extends GameTest

const B := GameConstants.Building


func _instance(type: int) -> Node3D:
	var path: String = GameConstants.BUILD_SCENES[type]
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


func test_building_glbs_exist() -> void:
	for type in GameConstants.BUILD_SCENES:
		var n := _instance(type)
		if n:
			assert_true(n.find_children("*", "MeshInstance3D", true, false).size() >= 1, "no mesh in %d" % type)


func test_building_sizes_match_footprint() -> void:
	for type in GameConstants.BUILDABLE:
		var n := _instance(type)
		if n == null:
			continue
		var box := _aabb(n)
		var fp: Vector2 = GameConstants.BUILD_FOOTPRINT[type]
		var name: String = GameConstants.BUILD_NAMES[type]
		assert_near(box.size.x, fp.x, 0.6, "%s width" % name)
		assert_near(box.size.z, fp.y, 0.6, "%s depth" % name)
		assert_near(box.position.y, 0.0, 0.05, "%s base" % name)
		assert_near(box.get_center().x, 0.0, 0.3, "%s not centered on X" % name)
		assert_near(box.get_center().z, 0.0, 0.3, "%s not centered on Z" % name)


func test_cabin_door_faces_plus_z() -> void:
	# The door is a thin dark box on the front wall; the front must be at +Z (Godot) like characters.
	var n := _instance(B.CABIN)
	if n == null:
		return
	var mesh: Mesh = (n.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	var found := false
	for s in mesh.get_surface_count():
		if mesh.surface_get_material(s).resource_name == "door":
			var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			var zsum := 0.0
			for v in verts:
				zsum += v.z
			assert_true(zsum / verts.size() > 2.0, "door at z=%.2f" % (zsum / verts.size()))
			found = true
	assert_true(found, "cabin has no 'door' material")


func test_flag_has_banner_material() -> void:
	var n := _instance(B.FLAG)
	if n == null:
		return
	var names := []
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			names.append(mi.mesh.surface_get_material(s).resource_name)
	assert_true(names.has("banner"), "materials: %s" % [names])


func test_library_scenes_for_buildings() -> void:
	var lib := ModelLibrary.new()
	add_child(lib)
	lib.start_loading()
	for i in 600:
		if lib.is_ready():
			break
		await get_tree().process_frame
	assert_true(lib.is_ready(), "library not ready")
	for type in GameConstants.BUILD_SCENES:
		var scene := lib.scene_for(type)
		assert_true(scene != null, "no scene for %d" % type)
		if scene:
			var inst := scene.instantiate()
			for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
				for s in mi.mesh.get_surface_count():
					assert_true(mi.mesh.surface_get_material(s) is ShaderMaterial, "building %d surface not converted" % type)
			inst.free()
