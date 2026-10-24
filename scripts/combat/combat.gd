class_name Combat
extends RefCounted
## Melee geometry shared by the player and future fighters.


## Candidates (Node3D) whose body is within `reach` of `origin` (flat distance minus their body
## radius) and inside the arc of `arc_deg` degrees centered on `facing`.
static func melee_targets(origin: Vector3, facing: Vector3, reach: float, arc_deg: float, candidates: Array) -> Array:
	var out := []
	var f := Vector3(facing.x, 0.0, facing.z).normalized()
	var half := deg_to_rad(arc_deg) * 0.5
	for c in candidates:
		var n := c as Node3D
		if not is_instance_valid(n):
			continue
		var to := n.global_position - origin
		to.y = 0.0
		var d := to.length()
		if d - body_radius(n) > reach:
			continue
		if d < 0.001 or f.angle_to(to) <= half:
			out.append(n)
	return out


static func body_radius(n: Node3D) -> float:
	if n.has_meta("body_radius"):
		return n.get_meta("body_radius")
	if n.has_method("body_radius"):
		return n.body_radius()
	return 0.0
