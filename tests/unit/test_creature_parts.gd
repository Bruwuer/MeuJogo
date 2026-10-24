extends GameTest


func _instance(part: String) -> Node3D:
	var path := GameConstants.CREATURE_PART_PATH % part
	if not ResourceLoader.exists(path):
		failures.append("%s missing: run tools/build_models.ps1" % path)
		return null
	var n: Node3D = load(path).instantiate()
	add_child(n)
	return n


func _aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var b := mi.global_transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _materials(root: Node3D) -> Array:
	var names := []
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			names.append(mi.mesh.surface_get_material(s).resource_name)
	return names


func test_all_parts_exist() -> void:
	assert_eq(GameConstants.CREATURE_PARTS.size(), 21)
	for part in GameConstants.CREATURE_PARTS:
		_instance(part)


func test_leg_unit_length() -> void:
	for part in ["leg_thin", "leg_thick", "leg_clawed"]:
		var n := _instance(part)
		if n:
			var box := _aabb(n)
			assert_near(box.position.y, -1.0, 0.05, "%s bottom" % part)
			assert_near(box.end.y, 0.0, 0.08, "%s top" % part)


func test_heads_point_forward() -> void:
	for part in ["head_wolf", "head_bear", "head_boar", "head_deer", "head_lizard", "head_horned"]:
		var n := _instance(part)
		if n:
			assert_true(_aabb(n).get_center().z > 0.05, "%s should extend toward +Z (front)" % part)


func test_tails_point_back() -> void:
	for part in ["tail_bushy", "tail_stub", "tail_long", "tail_spiked"]:
		var n := _instance(part)
		if n:
			assert_true(_aabb(n).get_center().z < -0.02, "%s should extend toward -Z (back)" % part)


func test_parts_have_primary_material() -> void:
	for part in GameConstants.CREATURE_PARTS:
		if part.begins_with("extra_antlers") or part.begins_with("extra_horns") or part.begins_with("extra_spikes"):
			continue # bone-colored only
		var n := _instance(part)
		if n:
			var mats := _materials(n)
			assert_true(mats.has("primary") or mats.has("secondary"), "%s materials %s" % [part, mats])


func test_body_sockets_complete() -> void:
	for body in GameConstants.Body.values():
		var s: Dictionary = GameConstants.BODY_SOCKETS[body]
		assert_eq((s.legs as Array).size(), 4)
		assert_true(s.leg_length > 0.2)
		for key in ["head", "tail", "extra"]:
			assert_true(s.has(key))


func test_library_parts() -> void:
	var lib := ModelLibrary.new()
	add_child(lib)
	lib.start_loading()
	for i in 1200:
		if lib.is_ready():
			break
		await get_tree().process_frame
	assert_true(lib.is_ready())
	for part in GameConstants.CREATURE_PARTS:
		assert_true(lib.part_scene(part) != null, "no scene for %s" % part)
