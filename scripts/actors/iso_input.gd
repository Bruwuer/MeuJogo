class_name IsoInput
extends RefCounted
## Converts a screen-space input vector into a world direction on the XZ plane.


## `input` follows Input.get_vector("move_left", "move_right", "move_up", "move_down"):
## W gives (0, -1). Screen-up is the camera forward flattened onto XZ.
static func to_world(input: Vector2, cam_yaw_deg: float) -> Vector3:
	var yaw := deg_to_rad(cam_yaw_deg)
	var up := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var dir := right * input.x - up * input.y
	return dir.normalized() if dir.length() > 1.0 else dir
