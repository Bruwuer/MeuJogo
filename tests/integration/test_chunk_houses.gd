extends GameTest

const B := GameConstants.Building

var _gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
var _scatter := PropScatter.new(_gen, GameConstants.WORLD_SEED)
var _state := WorldState.new()


func _height(node: Node) -> float:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mi.name == "Foundation":
			continue
		var b := mi.global_transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box.end.y - (node as Node3D).global_position.y


func test_chunk_uses_the_house_level_model() -> void:
	var spot := TestSpots.flat_clear(_gen, _scatter, B.HOUSE)
	var lib := ModelLibrary.new()
	add_child(lib)
	lib.start_loading()
	var s := ChunkStreamer.new()
	s.setup(_gen, _scatter, lib, _state.removed_in, _state.buildings_in)
	add_child(s)
	var simple := _state.add_building(B.HOUSE, spot, 0)
	var manor := _state.add_building(B.HOUSE, spot + Vector3(9, 0, 0), 0)
	manor.house_level = 2
	s.update_center(spot)
	for i in 900:
		await get_tree().process_frame
		if s.pending_count() == 0 and lib.is_ready():
			break
	await get_tree().process_frame
	var chunk := s.get_chunk(ChunkMath.world_to_chunk(spot))
	var a := chunk.get_node("B_%d" % simple.id)
	var b := s.get_chunk(ChunkMath.world_to_chunk(manor.pos)).get_node("B_%d" % manor.id)
	assert_true(_height(b) > _height(a) + 1.0, "the manor is taller than a simple house (%.1f vs %.1f)" % [_height(b), _height(a)])
	assert_eq(HouseRules.beds(manor), 8)


func test_stake_is_flat_and_colored() -> void:
	var spot := TestSpots.flat_clear(_gen, _scatter, B.WELL)
	var lib := ModelLibrary.new()
	add_child(lib)
	lib.start_loading()
	var s := ChunkStreamer.new()
	s.setup(_gen, _scatter, lib, _state.removed_in, _state.buildings_in)
	add_child(s)
	var stake := _state.add_building(B.STAKE, spot, 0, Color(0.1, 0.2, 0.9), GameConstants.OWNER_KINGDOM)
	s.update_center(spot)
	for i in 900:
		await get_tree().process_frame
		if s.pending_count() == 0 and lib.is_ready():
			break
	await get_tree().process_frame
	var node := s.get_chunk(ChunkMath.world_to_chunk(spot)).get_node("B_%d" % stake.id)
	assert_eq(node.find_children("*", "StaticBody3D", true, false).size(), 0, "walk-through")
	var colored := false
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		for i in mi.get_surface_override_material_count():
			var m := mi.get_surface_override_material(i) as ShaderMaterial
			if m and m.get_shader_parameter("albedo") == Color(0.1, 0.2, 0.9):
				colored = true
	assert_true(colored, "painted in the House color")
