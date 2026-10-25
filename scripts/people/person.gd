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
var _rng := RandomNumberGenerator.new()
var _stuck_dist := INF
var _stuck_check_left := GameConstants.PERSON_STUCK_CHECK_SEC
var _stuck_for := 0.0
var _detour := Vector3.ZERO
var _detour_left := 0.0
var _goal_reach := 0.0 ## How close the goal needs us (work targets are prop or site centres).
var _library: ModelLibrary
var _carried: Node3D ## The body in this person's arms (stage 10).
var _tool: Node3D ## The shovel while digging.
var _tool_name := ""


func setup(rec: Dictionary, library: ModelLibrary, mgr: Node) -> void:
	record = rec
	manager = mgr
	_library = library
	name = "Person%d" % rec.id
	add_to_group("people")
	collision_layer = GameConstants.LAYER_PEOPLE
	collision_mask = GameConstants.LAYER_TERRAIN | GameConstants.LAYER_OBSTACLES
	global_position = rec.pos
	reset_physics_interpolation()
	_rng.seed = hash([rec.id, "idle"])
	var a := _rng.randf() * TAU
	_idle_offset = Vector3(sin(a), 0.0, cos(a)) * _rng.randf_range(1.5, GameConstants.PERSON_IDLE_RADIUS * 0.8)
	_brain_left = _rng.randf() * GameConstants.PERSON_BRAIN_TICK
	var h: float = rec.looks.height
	var scene := library.person_scene() if library else null
	if scene:
		_model = scene.instantiate() as Node3D
		_model.name = "Model"
		_model.scale = Vector3.ONE * body_scale(rec)
		add_child(_model)
		_recolor()
		if int(rec.profession) == GameConstants.Profession.GUARD:
			var holder := WeaponHolder.add(_model)
			var spear := library.weapon_scene(GameConstants.Weapon.SPEAR)
			if holder and spear:
				holder.add_child(spear.instantiate())
		var players := _model.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			_anim = players[0]
			for clip in GameConstants.LOOPED_CLIPS:
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
	if is_dead():
		collision_layer = 0 # a body lies on the ground, nobody bumps into it
		_play(GameConstants.ANIM_DEAD)


## A body lying where the person fell (stage 10): no thinking, no moving.
func is_dead() -> bool:
	return String(record.get("status", "")) == "dead"


## Walks to `pos` (or within `reach` of it) and stays there (tests and scripted moves): the brain is
## not consulted.
func walk_to(pos: Vector3, reach := 0.0) -> void:
	_goal_reach = reach
	_stuck_dist = INF
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
	if is_dead():
		return
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
		A.DEED:
			_stand(delta)
			var face: Variant = ((record.get("deed", {}) as Dictionary).get("data", {}) as Dictionary).get("face")
			_face(face if face is Vector3 else target_pos, delta) # talking: to the other person
			var clip := String((record.get("deed", {}) as Dictionary).get("anim", GameConstants.ANIM_WORK))
			_hold_tool("shovel" if clip == GameConstants.ANIM_DIG else "")
			_play(clip)
			if not _done:
				work_left -= delta
				if work_left <= 0.0:
					_done = true
					if manager:
						manager.finish_deed(self)
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
	_update_carried()
	if act != A.DEED:
		_hold_tool("")
	if _model:
		var s := body_scale(record)
		if absf(_model.scale.x - s) > 0.001: # children grow
			_model.scale = Vector3.ONE * s
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
	if (d.target_pos as Vector3).distance_to(target_pos) > 1.0:
		_stuck_dist = INF # a new destination
	target_pos = d.target_pos
	_goal_reach = float(work_target.get("reach", 0.0)) if goal == A.WORK else (float(me.deed.reach) if goal == A.DEED else 0.0)
	if goal != was_goal:
		_done = false
		_eval_left = GameConstants.PERSON_EVALUATE_SEC
	if act == A.WORK and (was_act != A.WORK or _done): # start (or repeat) one work action
		_done = false
		work_left = float(work_target.get("duration", _DEFAULT_WORK_SEC))
	if act == A.DEED and was_act != A.DEED:
		_done = false
		work_left = float((me.deed as Dictionary).get("work_sec", _DEFAULT_WORK_SEC))
	if act != A.ENTER and not visible:
		visible = true
		if manager:
			manager.exited(self)


func _stand(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_apply_gravity(delta)
	move_and_slide()
	if act != A.WORK and act != A.DEED:
		_play(_idle_clip())


func _move(delta: float, speed: float) -> void:
	var to := target_pos - global_position
	to.y = 0.0
	var dist := to.length()
	var dir := Vector3.ZERO
	var stop := maxf(GameConstants.PERSON_ARRIVE * 0.5, _goal_reach * 0.9)
	if dist > stop:
		if _detour_left > 0.0:
			_detour_left -= delta
			dir = _detour
		else:
			# The last stretch goes straight: rays would see the door wall or the trunk being worked.
			dir = to / dist if dist < GameConstants.PERSON_AVOID_RAY else _avoid(to / dist)
		if act == A.WALK:
			_watch_stuck(delta, to / dist)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_apply_gravity(delta)
	move_and_slide()
	if dir != Vector3.ZERO:
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), clampf(GameConstants.TURN_SPEED * delta, 0.0, 1.0))
		if int(record.get("carrying_body", -1)) >= 0:
			_play(GameConstants.ANIM_CARRY) # slow steps, the body in the arms
		else:
			_play(GameConstants.ANIM_RUN if speed > GameConstants.PERSON_WALK_SPEED else GameConstants.ANIM_WALK)
	else:
		_play(_idle_clip())


## Failsafe for corners and steps the rays miss: no progress for a while -> a short sidestep;
## stuck for long -> placed at the target's approach point (on the ground).
func _watch_stuck(delta: float, want: Vector3) -> void:
	_stuck_check_left -= delta
	if _stuck_check_left > 0.0:
		return
	_stuck_check_left = GameConstants.PERSON_STUCK_CHECK_SEC
	var left := Vector2(target_pos.x - global_position.x, target_pos.z - global_position.z).length()
	var moved := _stuck_dist - left # progress toward the target, not wandering
	_stuck_dist = left
	if moved >= GameConstants.PERSON_STUCK_MOVE:
		_stuck_for = 0.0
		return
	_stuck_for += GameConstants.PERSON_STUCK_CHECK_SEC
	if _stuck_for >= GameConstants.PERSON_STUCK_TELEPORT_SEC:
		_stuck_for = 0.0
		_detour_left = 0.0
		# The approach point on our side, not the centre (a prop or a site would swallow us).
		var back := global_position - target_pos
		back.y = 0.0
		if back.length() < 0.01:
			back = Vector3.BACK
		var spot := target_pos + back.normalized() * _goal_reach * 0.9
		global_position = _ground_at(spot) + Vector3.UP * 0.3
		reset_physics_interpolation()
		return
	_detour = want.rotated(Vector3.UP, PI * 0.5 * (1.0 if _rng.randf() < 0.5 else -1.0))
	_detour_left = GameConstants.PERSON_DETOUR_SEC


func _ground_at(pos: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 50.0, pos + Vector3.DOWN * 50.0, GameConstants.LAYER_TERRAIN)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else pos


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


## Standing still: head down in mourning when the grief runs deep.
func _idle_clip() -> String:
	var grief := float((record.get("mood", {}) as Dictionary).get("grief", 0.0))
	return GameConstants.ANIM_MOURN if grief >= GameConstants.MOOD_MOURN_AT else GameConstants.ANIM_IDLE


## Shows (or drops) the body this person carries: a villager lying across the arms.
func _update_carried() -> void:
	var carrying := int(record.get("carrying_body", -1)) >= 0
	if carrying and _carried == null and _library and _model:
		var scene := _library.person_scene()
		if scene == null:
			return
		_carried = scene.instantiate() as Node3D
		_carried.name = "CarriedBody"
		_carried.position = GameConstants.CARRY_OFFSET
		_carried.rotation_degrees = GameConstants.CARRY_ROTATION
		_carried.scale = Vector3.ONE * GameConstants.CARRY_SCALE
		_model.add_child(_carried)
		var players := _carried.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			(players[0] as AnimationPlayer).play(GameConstants.ANIM_DEAD)
	elif not carrying and _carried:
		_carried.queue_free()
		_carried = null


## Puts a tool ("shovel") in the right hand, or empties it ("").
func _hold_tool(tool_name: String) -> void:
	if tool_name == _tool_name:
		return
	if _tool:
		_tool.get_parent().get_parent().queue_free() # the hand attachment made for it
		_tool = null
	_tool_name = tool_name
	if tool_name == "" or _library == null or _model == null:
		return
	var scene := _library.tool_scene(tool_name)
	var holder := WeaponHolder.add(_model)
	if scene and holder:
		_tool = scene.instantiate() as Node3D
		holder.add_child(_tool)


func carried_body() -> Node3D:
	return _carried


func held_tool() -> String:
	return _tool_name


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


## Model scale: the adult height, smaller for children (growing with age).
static func body_scale(rec: Dictionary) -> float:
	var grown := clampf(float(rec.age) / GameConstants.ADULT_AGE, 0.0, 1.0)
	return float(rec.looks.height) * lerpf(GameConstants.CHILD_MIN_SCALE, 1.0, grown)
