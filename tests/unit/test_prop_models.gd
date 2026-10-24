extends GameTest

const SIZES := {
	GameConstants.Prop.OAK: Vector2(3.5, 5.5),
	GameConstants.Prop.PINE: Vector2(4.5, 6.5),
	GameConstants.Prop.ROCK: Vector2(0.7, 1.6),
	GameConstants.Prop.BUSH: Vector2(0.5, 1.1),
}


func _meshes(type: int) -> Array:
	var path: String = GameConstants.PROP_SCENES[type]
	if not ResourceLoader.exists(path):
		failures.append("%s missing: run tools/build_models.ps1" % path)
		return []
	var node: Node = load(path).instantiate()
	add_child(node)
	return node.find_children("*", "MeshInstance3D", true, false)


func test_prop_glbs_exist_with_one_mesh() -> void:
	for type in GameConstants.PROP_SCENES:
		assert_eq(_meshes(type).size(), 1, "mesh count for %s" % GameConstants.PROP_SCENES[type])


func test_prop_sizes() -> void:
	for type in SIZES:
		var meshes := _meshes(type)
		if meshes.is_empty():
			continue
		var mi: MeshInstance3D = meshes[0]
		var box := mi.global_transform * mi.mesh.get_aabb()
		var limits: Vector2 = SIZES[type]
		assert_true(box.size.y >= limits.x and box.size.y <= limits.y, "%s height %.2f" % [GameConstants.PROP_SCENES[type], box.size.y])
		assert_near(box.position.y, 0.0, 0.1, "%s base" % GameConstants.PROP_SCENES[type])


func test_library_loads_async() -> void:
	var lib := ModelLibrary.new()
	add_child(lib)
	lib.start_loading()
	assert_true(not lib.is_ready(), "must not load synchronously")
	for i in 300:
		if lib.is_ready():
			break
		await get_tree().process_frame
	assert_true(lib.is_ready(), "library not ready in 300 frames")
	for type in GameConstants.PROP_SCENES:
		assert_true(lib.mesh_for(type) != null, "no mesh for %d" % type)


func test_library_meshes_use_occlusion_shader() -> void:
	var lib := ModelLibrary.new()
	add_child(lib)
	lib.start_loading()
	while not lib.is_ready():
		await get_tree().process_frame
	for type in GameConstants.PROP_SCENES:
		var mesh := lib.mesh_for(type)
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			assert_true(mat is ShaderMaterial and (mat as ShaderMaterial).shader.resource_path == ModelLibrary.OCCLUSION_SHADER,
					"type %d surface %d not using the occlusion shader" % [type, s])


func test_occlusion_global_exists() -> void:
	assert_true(RenderingServer.global_shader_parameter_get_list().has(&"player_world_pos"), "missing shader global player_world_pos")
