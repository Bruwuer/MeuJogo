extends GameTest


func _at(p: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = p
	return n


func test_melee_arc_and_range() -> void:
	var front := _at(Vector3(0, 0, 1.5))
	var side := _at(Vector3(1.5, 0, 0.2))
	var behind := _at(Vector3(0, 0, -1.5))
	var far := _at(Vector3(0, 0, 4.0))
	var all := [front, side, behind, far]
	var hit := Combat.melee_targets(Vector3.ZERO, Vector3(0, 0, 1), 2.0, 110.0, all)
	assert_eq(hit, [front])
	var wide := Combat.melee_targets(Vector3.ZERO, Vector3(0, 0, 1), 2.0, 200.0, all)
	assert_true(wide.has(front) and wide.has(side) and not wide.has(behind), "wide arc: %s" % [wide])
	var long := Combat.melee_targets(Vector3.ZERO, Vector3(0, 0, 1), 4.5, 40.0, all)
	assert_true(long.has(front) and long.has(far) and not long.has(side))


func test_melee_ignores_height_and_uses_body_radius() -> void:
	var up := _at(Vector3(0, 1.5, 1.5))
	assert_eq(Combat.melee_targets(Vector3.ZERO, Vector3(0, 0, 1), 2.0, 90.0, [up]), [up], "height should not matter")
	var edge := _at(Vector3(0, 0, 2.3))
	assert_eq(Combat.melee_targets(Vector3.ZERO, Vector3(0, 0, 1), 2.0, 90.0, [edge]), [], "too far without radius")
	edge.set_meta("body_radius", 0.5)
	assert_eq(Combat.melee_targets(Vector3.ZERO, Vector3(0, 0, 1), 2.0, 90.0, [edge]), [edge], "body radius ignored")
