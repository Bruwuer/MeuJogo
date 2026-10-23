class_name IsoCamera
extends Camera3D
## Fixed-angle orthographic isometric camera that smoothly follows `target`.
## Follows in _physics_process so it stays in step with the CharacterBody3D it tracks.

const _NEAR := 0.1
const _FAR := 200.0

@export var target: Node3D


func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	size = GameConstants.CAM_ORTHO_SIZE
	near = _NEAR
	far = _FAR
	rotation_degrees = Vector3(GameConstants.CAM_PITCH_DEG, GameConstants.CAM_YAW_DEG, 0.0)
	snap_to_target()


## Camera position relative to the target when at rest.
func rest_offset() -> Vector3:
	var basis := Basis.from_euler(Vector3(deg_to_rad(GameConstants.CAM_PITCH_DEG), deg_to_rad(GameConstants.CAM_YAW_DEG), 0.0))
	return basis.z * GameConstants.CAM_DISTANCE


func snap_to_target() -> void:
	if target:
		global_position = target.global_position + rest_offset()
		reset_physics_interpolation() # no smoothing across a teleport


func _physics_process(delta: float) -> void:
	if target:
		var goal := target.global_position + rest_offset()
		global_position = global_position.lerp(goal, clampf(GameConstants.CAM_FOLLOW_SMOOTH * delta, 0.0, 1.0))
