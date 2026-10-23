class_name Player
extends CharacterBody3D
## Player character: screen-relative WASD (Shift to run), gravity, faces its movement
## and switches idle/walk/run animations from the imported humanoid model.

const _IDLE_SPEED := 0.1
const _ANIM_BLEND := 0.15
const _FLOOR_SNAP := 0.5

## While frozen the player ignores input and gravity (e.g. until its chunk has collision).
var frozen := true

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
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dir := IsoInput.to_world(input, GameConstants.CAM_YAW_DEG)
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
	if horizontal < _IDLE_SPEED:
		play_anim(GameConstants.ANIM_IDLE)
	elif running:
		play_anim(GameConstants.ANIM_RUN)
	else:
		play_anim(GameConstants.ANIM_WALK)


func play_anim(anim_name: String) -> void:
	if _anim == null or not _anim.has_animation(anim_name) or _current_anim == anim_name:
		return
	_anim.play(anim_name, _ANIM_BLEND)
	_current_anim = anim_name


func current_anim() -> String:
	return _current_anim
