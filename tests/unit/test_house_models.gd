extends GameTest

const B := GameConstants.Building


func _aabb(path: String) -> AABB:
	if not ResourceLoader.exists(path):
		failures.append("%s missing: run tools/build_models.ps1" % path)
		return AABB()
	var n: Node3D = load(path).instantiate()
	add_child(n)
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var b := mi.global_transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func test_house_levels_exist_and_fit_the_footprint() -> void:
	var fp: Vector2 = GameConstants.BUILD_FOOTPRINT[B.HOUSE]
	var heights := []
	for path in GameConstants.HOUSE_LEVEL_SCENES:
		var box := _aabb(path)
		assert_near(box.size.x, fp.x, 0.7, "%s width" % path)
		assert_near(box.size.z, fp.y, 0.7, "%s depth" % path)
		assert_near(box.position.y, 0.0, 0.05, "%s base" % path)
		heights.append(box.size.y)
	assert_true(heights[1] > heights[0] and heights[2] > heights[1], "each level is grander: %s" % [heights])


func test_library_has_house_levels() -> void:
	var lib := ModelLibrary.new()
	add_child(lib)
	lib.start_loading()
	while not lib.is_ready():
		await get_tree().process_frame
	for level in GameConstants.HOUSE_LEVEL_SCENES.size():
		assert_true(lib.house_scene(level) != null, "no scene for level %d" % level)
