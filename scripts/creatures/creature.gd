class_name Creature
extends CharacterBody3D
## A live creature in a loaded chunk. `record` is its persistent dictionary in WorldState
## ({id, genome, pos, hp, age, pack_id, hunger, ...}); the node only exists while its chunk is
## loaded. Every BRAIN_TICK it asks CreatureBrain what to do, then steers there each physics
## frame: straight over the terrain, turning around obstacles seen by a short ray.
## `manager` (CreatureManager, optional) adds pack knowledge: leader, den, mate, raid target,
## night, and hostility to the player.

signal died(creature: Creature, source: Object)

const S := CreatureBrain.State
const _FLOOR_SNAP := 0.6
const _AVOID_ANGLES := [0.0, 45.0, -45.0, 90.0, -90.0, 135.0, -135.0]
const _PROVOKED_SEC := 20.0
const _RAID_SPEED := 0.7 ## Share of top speed while marching on the kingdom.
const _RUN_RATIO := 1.5

var record: Dictionary
var genome: Dictionary ## Genome scaled by growth (cubs are smaller).
var health: Health
var body: CreatureBody
var manager: Node
var state: int = S.WANDER
var target_pos := Vector3.ZERO
var target_id := -1
var stamina := 1.0
## Used when there is no manager (tests).
var is_night_override := false

var _target_node: Node3D
var _commanded := false
var _brain_left := 0.0
var _attack_left := 0.0
var _provoked_left := 0.0
var _wander_pos := Vector3.ZERO
var _avoid_sign := 1.0
var _dead := false
var _raid_radius := 0.0 ## Footprint radius of the building being raided.
var _push := Vector3.ZERO ## Knockback velocity, decays quickly.
var _rng := RandomNumberGenerator.new()


func setup(rec: Dictionary, library: ModelLibrary, mgr: Node) -> void:
	record = rec
	manager = mgr
	if not record.has("hunger"):
		record.hunger = 0.0
	_rng.seed = hash(record.id)
	genome = (record.genome as Dictionary).duplicate()
	genome.size = float(genome.size) * growth_factor()
	name = "Creature%d" % record.id
	global_position = record.pos # before the collision shape exists: never spawn inside others
	reset_physics_interpolation()
	body = CreatureBody.new()
	body.name = "CreatureBody"
	add_child(body)
	body.build(genome, library)
	_add_collision()
	collision_layer = GameConstants.LAYER_CREATURES
	collision_mask = GameConstants.LAYER_TERRAIN | GameConstants.LAYER_OBSTACLES
	floor_snap_length = _FLOOR_SNAP
	platform_floor_layers = GameConstants.LAYER_TERRAIN | GameConstants.LAYER_OBSTACLES
	health = Health.new(float(genome.max_hp), float(record.get("hp", genome.max_hp)))
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	add_to_group("creatures")
	_wander_pos = record.pos
	_brain_left = _rng.randf() * GameConstants.BRAIN_TICK


## CUB_SIZE..1 from newborn to adult, by record.age (0..1).
func growth_factor() -> float:
	return lerpf(GameConstants.CUB_SIZE, 1.0, clampf(float(record.get("age", 1.0)), 0.0, 1.0))


func is_cub() -> bool:
	return float(record.get("age", 1.0)) < 1.0


## Rough horizontal body radius, for melee reach.
func body_radius() -> float:
	return float(genome.size) * 0.45


func knockback(v: Vector3) -> void:
	_push += v


func is_dead() -> bool:
	return _dead


## Locks the creature into a state and target (tests, scripted scenes). The brain stops deciding.
func command(new_state: int, pos: Vector3, target: Node3D = null) -> void:
	_commanded = true
	state = new_state
	target_pos = pos
	_target_node = target
	target_id = -1


func release_command() -> void:
	_commanded = false


func provoked_by_player() -> bool:
	return _provoked_left > 0.0


## Copies live values back into the persistent record.
func sync_record() -> void:
	record.pos = global_position
	record.hp = health.hp


func _physics_process(delta: float) -> void:
	if _dead:
		_apply_gravity(delta)
		move_and_slide()
		return
	record.hunger = minf(1.0, float(record.hunger) + GameConstants.CREATURE_HUNGER_PER_SEC * delta)
	_attack_left = maxf(0.0, _attack_left - delta)
	_provoked_left = maxf(0.0, _provoked_left - delta)
	if not _commanded:
		_brain_left -= delta
		if _brain_left <= 0.0:
			_brain_left = GameConstants.BRAIN_TICK
			_think()
	if is_instance_valid(_target_node):
		target_pos = _target_node.global_position
	if state == S.GRAZE:
		record.hunger = maxf(0.0, float(record.hunger) - GameConstants.GRAZE_RATE * delta)
	_move(delta)
	_try_attack()


func _think() -> void:
	var me := {
		id = record.id, genome = genome, pos = global_position, hp_ratio = health.ratio(),
		hunger = record.hunger, is_night = is_night_override, pack_leader_pos = null,
		den_pos = record.get("den", record.pos), mate = {}, raid_target = {},
		hostile_to_player = provoked_by_player() and (genome.diet == GameConstants.Diet.CARNIVORE
				or genome.aggression >= GameConstants.PLAYER_DEFENSE_AGGRESSION),
	}
	if manager:
		me.merge(manager.brain_extras(self), true)
	if global_position.distance_to(_wander_pos) < GameConstants.CREATURE_ARRIVE * 2.0 or _rng.randf() < 0.01:
		var den: Vector3 = me.den_pos
		var a := _rng.randf() * TAU
		var r := _rng.randf() * GameConstants.WANDER_RADIUS
		_wander_pos = den + Vector3(cos(a) * r, 0.0, sin(a) * r)
	me.wander_pos = _wander_pos
	var d := CreatureBrain.decide(me, { nearby = _sense() })
	state = d.state
	target_pos = d.target_pos
	target_id = d.target_id
	_target_node = null
	_raid_radius = float(me.raid_target.get("radius", 0.0)) if state == S.RAID else 0.0
	if state in [S.HUNT, S.ATTACK, S.MATE]:
		_target_node = _find(target_id)


func _sense() -> Array:
	var out := []
	var reach: float = genome.perception
	for n in get_tree().get_nodes_in_group("creatures"):
		var c := n as Creature
		if c == self or c.is_dead() or c.record.is_empty():
			continue
		if c.global_position.distance_to(global_position) > reach:
			continue
		out.append({ id = c.record.id, kind = "creature", pos = c.global_position, diet = c.genome.diet,
				species = c.genome.species, is_cub = c.is_cub() })
	for n in get_tree().get_nodes_in_group("people"):
		var person := n as Node3D
		if person is Person and (person as Person).is_dead():
			continue # bodies are not prey
		if person.visible and person.global_position.distance_to(global_position) <= reach:
			out.append({ id = person.get_instance_id(), kind = "person", pos = person.global_position,
					diet = GameConstants.Diet.HERBIVORE, species = "", is_cub = false })
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Node3D
		if p.global_position.distance_to(global_position) <= reach:
			out.append({ id = p.get_instance_id(), kind = "player", pos = p.global_position,
					diet = GameConstants.Diet.CARNIVORE, species = "", is_cub = false })
	return out


func _find(id: int) -> Node3D:
	for n in get_tree().get_nodes_in_group("creatures"):
		if (n as Creature).record.get("id") == id:
			return n
	for n in get_tree().get_nodes_in_group("player"):
		if n.get_instance_id() == id:
			return n
	return null


func _move(delta: float) -> void:
	var to := target_pos - global_position
	to.y = 0.0
	var dist := to.length()
	var top: float = genome.speed
	var share := 0.0
	match state:
		S.WANDER, S.FOLLOW, S.MATE, S.RETURN:
			share = GameConstants.CREATURE_WANDER_SPEED
		S.RAID:
			share = _RAID_SPEED
		S.HUNT, S.FLEE:
			share = 1.0
		S.ATTACK:
			share = 1.0 if dist > CreatureBrain.attack_reach(genome) * 0.8 else 0.0
	var sprint := share >= 1.0 and dist > GameConstants.CREATURE_ARRIVE
	if sprint:
		stamina = maxf(0.0, stamina - GameConstants.STAMINA_DRAIN[genome.diet] * delta)
		if stamina == 0.0:
			share = GameConstants.EXHAUSTED_SPEED
	else:
		stamina = minf(1.0, stamina + GameConstants.STAMINA_REGEN * delta)
	var dir := Vector3.ZERO
	if dist > GameConstants.CREATURE_ARRIVE and share > 0.0:
		# Near the raided building the building itself is the goal, not an obstacle.
		var at_target := state == S.RAID and dist <= _raid_radius + GameConstants.AVOID_RAY * float(genome.size)
		dir = to / dist if at_target else _avoid(to / dist)
		if state == S.RAID and dist <= _raid_radius + CreatureBrain.attack_reach(genome) * 0.6:
			dir = Vector3.ZERO
	velocity.x = dir.x * top * share + _push.x
	velocity.z = dir.z * top * share + _push.z
	_push = _push.move_toward(Vector3.ZERO, GameConstants.KNOCKBACK_DECAY * _push.length() * delta + 0.01)
	_apply_gravity(delta)
	move_and_slide()

	var face := dir
	if face == Vector3.ZERO and state == S.ATTACK and dist > 0.01:
		face = to / dist
	if face != Vector3.ZERO:
		rotation.y = lerp_angle(rotation.y, atan2(face.x, face.z), clampf(GameConstants.TURN_SPEED * delta, 0.0, 1.0))
	var h := Vector2(velocity.x, velocity.z).length()
	var walk_speed: float = top * GameConstants.CREATURE_WANDER_SPEED
	var ratio := 0.0
	if h >= 0.05:
		ratio = _RUN_RATIO if h > walk_speed * 1.3 else h / walk_speed
	body.animate(delta, ratio)


## First clear direction around the wanted one (keeps turning the same way while blocked).
func _avoid(want: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * body.standing_height()
	var reach := GameConstants.AVOID_RAY * maxf(float(genome.size), 0.6)
	for a: float in _AVOID_ANGLES:
		var d := want.rotated(Vector3.UP, deg_to_rad(a) * _avoid_sign)
		var q := PhysicsRayQueryParameters3D.create(from, from + d * reach, GameConstants.LAYER_OBSTACLES)
		if space.intersect_ray(q).is_empty():
			if a != 0.0:
				_avoid_sign = signf(a) * _avoid_sign
			return d
	return want


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GameConstants.GRAVITY * delta


func _try_attack() -> void:
	if _attack_left > 0.0:
		return
	if state == S.RAID:
		_try_raid_bite()
		return
	if state != S.ATTACK:
		return
	var target := _target_node
	if not is_instance_valid(target):
		return
	if target.global_position.distance_to(global_position) > CreatureBrain.attack_reach(genome):
		return
	var h = target.get("health")
	if h == null or (h as Health).is_dead():
		return
	_attack_left = GameConstants.CREATURE_ATTACK_COOLDOWN
	body.play_attack()
	var killed := (h as Health).damage(float(genome.damage), self)
	if killed and target is Creature and genome.diet == GameConstants.Diet.CARNIVORE:
		record.hunger = 0.0 # it eats the prey


func _try_raid_bite() -> void:
	if manager == null or target_id < 0:
		return
	var to := target_pos - global_position
	to.y = 0.0
	if to.length() > _raid_radius + CreatureBrain.attack_reach(genome):
		return
	_attack_left = GameConstants.CREATURE_ATTACK_COOLDOWN
	rotation.y = atan2(to.x, to.z)
	body.play_attack()
	manager.damage_building(target_id, float(genome.damage), self)


## Rescales the body after the record aged (cubs grow up).
func refresh_growth() -> void:
	genome.size = float(record.genome.size) * growth_factor()
	body.scale = Vector3.ONE * float(genome.size)


func _on_damaged(_amount: float, source: Object) -> void:
	if _dead:
		return
	body.play_hurt()
	if source is Node and (source as Node).is_in_group("player"):
		_provoked_left = _PROVOKED_SEC
	_brain_left = 0.0


func _on_died(source: Object) -> void:
	_dead = true
	collision_layer = 0
	velocity = Vector3.ZERO
	body.play_death()
	sync_record()
	died.emit(self, source)
	var tw := create_tween()
	tw.tween_interval(GameConstants.CORPSE_SEC)
	tw.tween_callback(queue_free)


## One sphere around the torso: cheap against the terrain trimesh. Creatures do not collide with
## each other (the player still bumps into them); obstacles are steered around by rays.
func _add_collision() -> void:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(0.15, body.standing_height() * 0.5)
	shape.shape = sphere
	shape.position.y = sphere.radius
	add_child(shape)
