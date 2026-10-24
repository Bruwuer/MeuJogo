class_name Player
extends CharacterBody3D
## Player character: screen-relative WASD (Shift to run), E to harvest, gravity, faces its movement
## and switches idle/walk/run animations from the imported humanoid model.
## Combat is keyboard only: Space attacks where the character faces (no auto-aim), 1/2/3 pick a
## weapon and Q cycles, F makes arrows, H eats berries. The active weapon sits in the right hand.

signal died
signal attacked(weapon: int)
signal message(text: String)

const _IDLE_SPEED := 0.1
const _ANIM_BLEND := 0.15
const _FLOOR_SNAP := 0.5
const _HAND_BONE := "hand.R"
const _ARROW_FORWARD := 0.5 ## Arrows start this far in front of the body.

## While frozen the player ignores input and gravity (e.g. until its chunk has collision).
var frozen := true
## Set by World; E (interact) harvests through it.
var harvest: HarvestSystem
## False while build mode owns E.
var harvest_enabled := true
## False while build mode owns the number keys and Space.
var combat_enabled := true
## Set by World: resources (arrows, berries, wood) and the model library (weapon meshes).
var state: WorldState
var library: ModelLibrary
## func() -> Array of Creature nodes that can be hit (CreatureManager.active_creatures).
var creature_source := Callable()
var health := Health.new(GameConstants.PLAYER_HP)
var weapon: int = GameConstants.Weapon.SWORD

var _work_left := 0.0
var _attack_left := 0.0
var _hit_left := 0.0
var _since_hurt := 0.0
var _anim: AnimationPlayer
var _current_anim := ""
var _holder: Node3D
var _shown_weapon := -1

@onready var _model: Node3D = $Model


func _ready() -> void:
	floor_snap_length = _FLOOR_SNAP
	platform_floor_layers = GameConstants.LAYER_TERRAIN | GameConstants.LAYER_OBSTACLES # never ride creatures
	collision_mask = GameConstants.LAYER_TERRAIN | GameConstants.LAYER_OBSTACLES | GameConstants.LAYER_CREATURES
	add_to_group("player")
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_anim = players[0]
		for anim_name in [GameConstants.ANIM_IDLE, GameConstants.ANIM_WALK, GameConstants.ANIM_RUN]:
			if _anim.has_animation(anim_name):
				_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	play_anim(GameConstants.ANIM_IDLE)
	_add_weapon_holder()
	health.damaged.connect(func(_a: float, _s: Object) -> void: _since_hurt = 0.0)
	health.died.connect(func(_s: Object) -> void: died.emit())


func _process(_delta: float) -> void:
	if _shown_weapon != weapon and _holder and library and library.is_ready():
		_show_weapon()


func _unhandled_input(event: InputEvent) -> void:
	if frozen or not combat_enabled or health.is_dead():
		return
	for i in GameConstants.Weapon.size():
		if event.is_action_pressed("slot_%d" % (i + 1)):
			select_weapon(i)
	if event.is_action_pressed("weapon_next"):
		next_weapon()
	elif event.is_action_pressed("attack"):
		attack()
	elif event.is_action_pressed("craft_arrows"):
		craft_arrows()
	elif event.is_action_pressed("eat"):
		eat()


func _physics_process(delta: float) -> void:
	if frozen:
		return
	_work_left = maxf(0.0, _work_left - delta)
	_attack_left = maxf(0.0, _attack_left - delta)
	if _hit_left > 0.0:
		_hit_left -= delta
		if _hit_left <= 0.0:
			_resolve_hit()
	_since_hurt += delta
	if _since_hurt >= GameConstants.PLAYER_REGEN_DELAY:
		health.heal(GameConstants.PLAYER_REGEN_PER_SEC * delta)
	if not is_busy() and harvest and harvest_enabled and Input.is_action_just_pressed("interact"):
		_try_harvest()
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dir := IsoInput.to_world(input, GameConstants.CAM_YAW_DEG)
	if is_busy() or health.is_dead():
		dir = Vector3.ZERO
	var running := Input.is_action_pressed("run")
	var speed := GameConstants.RUN_SPEED if running else GameConstants.WALK_SPEED
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GameConstants.GRAVITY * delta
	move_and_slide()

	if dir.length_squared() > 0.0001:
		var target_yaw := atan2(dir.x, dir.z) # model front is +Z
		_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, clampf(GameConstants.TURN_SPEED * delta, 0.0, 1.0))

	var horizontal := Vector2(velocity.x, velocity.z).length()
	if is_busy():
		pass # the work or attack clip plays to the end
	elif horizontal < _IDLE_SPEED:
		play_anim(GameConstants.ANIM_IDLE)
	elif running:
		play_anim(GameConstants.ANIM_RUN)
	else:
		play_anim(GameConstants.ANIM_WALK)


## `restart` replays the clip from the start even if it is already playing.
func play_anim(anim_name: String, restart := false) -> void:
	if _anim == null or not _anim.has_animation(anim_name):
		return
	if _current_anim == anim_name and not restart:
		return
	_anim.play(anim_name, _ANIM_BLEND)
	if restart:
		_anim.seek(0.0, true)
	_current_anim = anim_name


func current_anim() -> String:
	return _current_anim


func is_working() -> bool:
	return _work_left > 0.0


func is_attacking() -> bool:
	return _attack_left > 0.0


func is_busy() -> bool:
	return is_working() or is_attacking()


## Horizontal direction the character model faces.
func facing() -> Vector3:
	var f := _model.global_transform.basis.z
	return Vector3(f.x, 0.0, f.z).normalized()


## Turns the character at once (respawn, scripted scenes, tests).
func face(dir: Vector3) -> void:
	_model.rotation.y = atan2(dir.x, dir.z)


func select_weapon(w: int) -> void:
	if w >= 0 and w < GameConstants.Weapon.size():
		weapon = w


func next_weapon() -> void:
	select_weapon((weapon + 1) % GameConstants.Weapon.size())


func weapon_holder() -> Node3D:
	return _holder


## Starts a swing (or a shot) toward where the character faces. The damage lands at the
## weapon's hit_time. Returns false when busy, dead, or out of arrows.
func attack() -> bool:
	if is_busy() or health.is_dead():
		return false
	var data: Dictionary = GameConstants.WEAPONS[weapon]
	if weapon == GameConstants.Weapon.BOW:
		if state == null or not state.spend({ GameConstants.Res.ARROWS: 1 }):
			message.emit(GameConstants.NO_ARROWS_MSG)
			return false
	_attack_left = data.cooldown
	_hit_left = data.hit_time
	play_anim(data.clip, true)
	attacked.emit(weapon)
	return true


func craft_arrows() -> bool:
	if state == null or not state.spend(GameConstants.ARROW_CRAFT_COST):
		return false
	state.add_resource(GameConstants.Res.ARROWS, GameConstants.ARROWS_PER_CRAFT)
	return true


func eat() -> bool:
	if state == null or health.is_dead() or health.hp >= health.max_hp:
		return false
	if not state.spend(GameConstants.EAT_COST):
		return false
	health.heal(GameConstants.EAT_HEAL)
	return true


## Back to full health (World moves the player to the seat or spawn first).
func revive() -> void:
	health.hp = health.max_hp
	_since_hurt = 0.0
	_attack_left = 0.0
	_hit_left = 0.0
	play_anim(GameConstants.ANIM_IDLE, true)


func _resolve_hit() -> void:
	var data: Dictionary = GameConstants.WEAPONS[weapon]
	if weapon == GameConstants.Weapon.BOW:
		_shoot(data)
		return
	if not creature_source.is_valid():
		return
	var alive: Array = creature_source.call().filter(func(c: Node) -> bool:
		return is_instance_valid(c) and not (c as Creature).is_dead())
	var f := facing()
	for c: Creature in Combat.melee_targets(global_position, f, data.range, data.arc, alive):
		c.health.damage(data.damage, self)
		c.knockback(f * float(data.knockback))


func _shoot(data: Dictionary) -> void:
	var arrow := Arrow.new()
	arrow.name = "Arrow"
	get_parent().add_child(arrow)
	var f := facing()
	var start := global_position + Vector3.UP * GameConstants.ARROW_SPAWN_HEIGHT + f * _ARROW_FORWARD
	arrow.launch(start, f, GameConstants.ARROW_SPEED, data.damage, self, library.arrow_scene() if library else null)


## A BoneAttachment3D on the right hand with a holder turned so that a weapon's +Y axis points
## to the character's front (and +Z up) in the rest pose.
func _add_weapon_holder() -> void:
	var skels := _model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var skel: Skeleton3D = skels[0]
	var bone := skel.find_bone(_HAND_BONE)
	if bone < 0:
		return
	var attach := BoneAttachment3D.new()
	attach.name = "RightHand"
	attach.bone_name = _HAND_BONE
	skel.add_child(attach)
	_holder = Node3D.new()
	_holder.name = "Weapon"
	attach.add_child(_holder)
	var to_skel := skel.global_basis.orthonormalized().inverse()
	var fwd := (to_skel * _model.global_basis.z).normalized()
	var up := (to_skel * Vector3.UP).normalized()
	var wanted := Basis(fwd.cross(up), fwd, up)
	_holder.basis = skel.get_bone_global_rest(bone).basis.orthonormalized().inverse() * wanted


func _show_weapon() -> void:
	for child in _holder.get_children():
		_holder.remove_child(child)
		child.queue_free()
	var scene := library.weapon_scene(weapon)
	if scene:
		var m := scene.instantiate()
		m.name = GameConstants.WEAPONS[weapon].name
		_holder.add_child(m)
	_shown_weapon = weapon


func _try_harvest() -> void:
	var target := harvest.find_target(global_position)
	if target.is_empty():
		return
	var to_prop: Vector3 = target.prop.pos - global_position
	_model.rotation.y = atan2(to_prop.x, to_prop.z)
	_work_left = GameConstants.HARVEST_HIT_TIME
	play_anim(GameConstants.ANIM_WORK, true)
	harvest.hit(target)
