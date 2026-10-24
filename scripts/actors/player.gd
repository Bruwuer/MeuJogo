class_name Player
extends CharacterBody3D
## Player character: screen-relative WASD (Shift to run), E to harvest, gravity, faces its movement
## and switches idle/walk/run animations from the imported humanoid model.

const _IDLE_SPEED := 0.1
const _ANIM_BLEND := 0.15
const _FLOOR_SNAP := 0.5

## While frozen the player ignores input and gravity (e.g. until its chunk has collision).
var frozen := true
## Set by World; E (interact) harvests through it.
var harvest: HarvestSystem

var _work_left := 0.0
var _anim: AnimationPlayer
var _current_anim := ""

@onready var _model: Node3D = $Model


func _ready() -> void:
	floor_snap_length = _FLOOR_SNAP
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_anim = players[0]
		for anim_name in [GameConstants.ANIM_IDLE, GameConstants.ANIM_WALK, GameConstants.ANIM_RUN]:
			if _anim.has_animation(anim_name):
				_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	play_anim(GameConstants.ANIM_IDLE)


func _physics_process(delta: float) -> void:
	if frozen:
		return
	_work_left = maxf(0.0, _work_left - delta)
	if _work_left == 0.0 and harvest and Input.is_action_just_pressed("interact"):
		_try_harvest()
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dir := IsoInput.to_world(input, GameConstants.CAM_YAW_DEG)
	if is_working():
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
	if is_working():
		pass # the work clip plays to the end
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


func _try_harvest() -> void:
	var target := harvest.find_target(global_position)
	if target.is_empty():
		return
	var to_prop: Vector3 = target.prop.pos - global_position
	_model.rotation.y = atan2(to_prop.x, to_prop.z)
	_work_left = GameConstants.HARVEST_HIT_TIME
	play_anim(GameConstants.ANIM_WORK, true)
	harvest.hit(target)
