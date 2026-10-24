class_name Person
extends CharacterBody3D
## A villager or traveler in a loaded chunk. `record` is the person's dictionary in WorldState;
## the node only exists while its chunk is loaded. Every PERSON_BRAIN_TICK it asks PersonBrain
## what to do (with context from `manager`, a PeopleManager), then walks there straight over the
## terrain, turning around obstacles seen by short rays, and does it: work, deposit, enter the
## house (the node hides), sleep, look at the kingdom, leave.
## The humanoid's skin, hair, tunic and trousers materials are replaced by colored copies shared
## by everyone with the same color.

const A := PersonBrain.Act
const _AVOID_ANGLES := [0.0, 45.0, -45.0, 90.0, -90.0, 135.0, -135.0]
const _ANIM_BLEND := 0.2
const _RAY_HEIGHTS := [0.3, 1.0] ## Knee (stone bases of sites, low steps) and chest.
const _LOOK_KEYS := ["skin", "hair", "tunic", "trousers"]
const _DEFAULT_WORK_SEC := 3.0

static var _materials: Dictionary = {} # "slot/#color" -> StandardMaterial3D

var record: Dictionary
var manager: Node
var act: int = A.IDLE
var goal: int = A.IDLE
var target_pos := Vector3.ZERO
var work_left := 0.0
var work_target: Dictionary = {}

var _model: Node3D
var _anim: AnimationPlayer
var _current_anim := ""
var _overrides: Dictionary = {} # slot -> material
var _brain_left := 0.0
var _eval_left := GameConstants.PERSON_EVALUATE_SEC
var _commanded := false
var _avoid_sign := 1.0
var _idle_offset := Vector3.ZERO
var _done := false # the current goal's action already happened (work finished, deposited...)


func setup(rec: Dictionary, library: ModelLibrary, mgr: Node) -> void:
	record = rec
	manager = mgr
	name = "Person%d" % rec.id
	add_to_group("people")
	collision_layer = GameConstants.LAYER_PEOPLE
	collision_mask = GameConstants.LAYER_TERRAIN | GameConstants.LAYER_OBSTACLES
	global_position = rec.pos
	reset_physics_interpolation()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([rec.id, "idle"])
	var a := rng.randf() * TAU
	_idle_offset = Vector3(sin(a), 0.0, cos(a)) * rng.randf_range(1.5, GameConstants.PERSON_IDLE_RADIUS * 0.8)
	_brain_left = rng.randf() * GameConstants.PERSON_BRAIN_TICK
	var h: float = rec.looks.height
	var scene := library.person_scene() if library else null
	if scene:
		_model = scene.instantiate() as Node3D
		_model.name = "Model"
		_model.scale = Vector3.ONE * h
		add_child(_model)
		_recolor()
		var players := _model.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			_anim = players[0]
			for clip in [GameConstants.ANIM_IDLE, GameConstants.ANIM_WALK, GameConstants.ANIM_RUN, GameConstants.ANIM_WORK]:
				if _anim.has_animation(clip):
					_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = GameConstants.PERSON_RADIUS
	capsule.height = 1.8 * h
	shape.shape = capsule
	shape.position.y = 0.9 * h
	add_child(shape)
	_play(GameConstants.ANIM_IDLE)
	if int(rec.get("inside", -1)) >= 0:
		visible = false


## Walks to `pos` and stays there (tests and scripted moves): the brain is not consulted.
func walk_to(pos: Vector3) -> void:
	_commanded = true
	act = A.WALK
	goal = A.IDLE
	target_pos = pos


func material_for(slot: String) -> Material:
	return _overrides.get(slot)


func model_scale() -> float:
	return _model.scale.x if _model else 1.0


func is_inside() -> bool:
	return not visible


func sync_record() -> void:
	record.pos = global_position


func _physics_process(delta: float) -> void:
	if not _commanded:
		_brain_left -= delta
		if _brain_left <= 0.0:
			_brain_left = GameConstants.PERSON_BRAIN_TICK
			_think()
	match act:
		A.WALK, A.FLEE:
			_move(delta, GameConstants.PERSON_RUN_SPEED if act == A.FLEE else GameConstants.PERSON_WALK_SPEED)
		A.WORK:
			_stand(delta)
			_face(target_pos, delta)
			_play(GameConstants.ANIM_WORK)
			if not _done:
				work_left -= delta
				if work_left <= 0.0:
					_done = true
					if manager:
						manager.finish_work(self)
		A.EVALUATE:
			_stand(delta)
			_eval_left -= delta
			if _eval_left <= 0.0 and not _done:
				_done = true
				if manager:
					manager.evaluate(self)
		A.DEPOSIT:
			_stand(delta)
			if not _done:
				_done = true
				if manager:
					manager.deposit(self)
		A.ENTER:
			_stand(delta)
			if visible:
				visible = false
				if manager:
					manager.entered(self)
		A.LEAVE:
			_stand(delta)
			if not _done:
				_done = true
				if manager:
					manager.left_map(self)
		_:
			_stand(delta)


func _think() -> void:
	var me := {
		pos = global_position, status = record.status, job = record.get("job", ""),
		carrying = record.get("carrying", {}), home_pos = null, door_pos = null, is_work_time = false,
		is_sleep_time = false, raid = false, threat_pos = null, idle_offset = _idle_offset,
	}
	var ctx := {work_target = {}, deposit_pos = record.pos, seat_pos = record.pos, campfire_pos = null,
			exit_pos = record.pos}
	if manager:
		var extra: Dictionary = manager.person_context(self)
		me.merge(extra.me, true)
		ctx.merge(extra.ctx, true)
	work_target = ctx.work_target
	var d := PersonBrain.decide(me, ctx)
	var was_goal := goal
	var was_act := act
	act = d.act
	goal = d.goal
	target_pos = d.target_pos
	if goal != was_goal:
		_done = false
		_eval_left = GameConstants.PERSON_EVALUATE_SEC
	if act == A.WORK and (was_act != A.WORK or _done): # start (or repeat) one work action
		_done = false
		work_left = float(work_target.get("duration", _DEFAULT_WORK_SEC))
	if act != A.ENTER and not visible:
		visible = true
		if manager:
			manager.exited(self)


func _stand(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_apply_gravity(delta)
	move_and_slide()
	if act != A.WORK:
		_play(GameConstants.ANIM_IDLE)


func _move(delta: float, speed: float) -> void:
	var to := target_pos - global_position
	to.y = 0.0
	var dist := to.length()
	var dir := Vector3.ZERO
	var stop := GameConstants.PERSON_ARRIVE * 0.5
	if dist > stop:
		# The last stretch goes straight: rays would see the door wall or the trunk being worked.
		dir = to / dist if dist < GameConstants.PERSON_AVOID_RAY else _avoid(to / dist)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_apply_gravity(delta)
	move_and_slide()
	if dir != Vector3.ZERO:
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), clampf(GameConstants.TURN_SPEED * delta, 0.0, 1.0))
		_play(GameConstants.ANIM_RUN if speed > GameConstants.PERSON_WALK_SPEED else GameConstants.ANIM_WALK)
	else:
		_play(GameConstants.ANIM_IDLE)


func _face(pos: Vector3, delta: float) -> void:
	var to := pos - global_position
	to.y = 0.0
	if to.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), clampf(GameConstants.TURN_SPEED * delta, 0.0, 1.0))


## First clear direction around the wanted one (keeps turning the same way while blocked). Rays at
## knee and chest height: a site only has its low stone base as collision.
func _avoid(want: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	for a: float in _AVOID_ANGLES:
		var d := want.rotated(Vector3.UP, deg_to_rad(a) * _avoid_sign)
		var clear := true
		for h: float in _RAY_HEIGHTS:
			var from := global_position + Vector3.UP * h
			var q := PhysicsRayQueryParameters3D.create(from, from + d * GameConstants.PERSON_AVOID_RAY, GameConstants.LAYER_OBSTACLES)
			if not space.intersect_ray(q).is_empty():
				clear = false
				break
		if clear:
			if a != 0.0:
				_avoid_sign = signf(a) * _avoid_sign
			return d
	return want


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GameConstants.GRAVITY * delta


func _play(clip: String) -> void:
	if _anim == null or _current_anim == clip or not _anim.has_animation(clip):
		return
	_anim.play(clip, _ANIM_BLEND)
	_current_anim = clip


func _recolor() -> void:
	var looks: Dictionary = record.looks
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			if src == null or not (src.resource_name in _LOOK_KEYS):
				continue
			var slot := src.resource_name
			var color: Color = looks[slot]
			var key := "%s/%s" % [slot, color.to_html()]
			if not _materials.has(key):
				var mat := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
				mat.albedo_color = color
				_materials[key] = mat
			mi.set_surface_override_material(s, _materials[key])
			_overrides[slot] = _materials[key]
