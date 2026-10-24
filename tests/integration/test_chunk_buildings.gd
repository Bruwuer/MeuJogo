extends GameTest

const B := GameConstants.Building

var _gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
var _scatter := PropScatter.new(_gen, GameConstants.WORLD_SEED)
var _state := WorldState.new()


func _make_streamer() -> ChunkStreamer:
	var lib := ModelLibrary.new()
	add_child(lib)
	lib.start_loading()
	var s := ChunkStreamer.new()
	s.setup(_gen, _scatter, lib, _state.removed_in, _state.buildings_in)
	add_child(s)
	return s


func _settle(s: ChunkStreamer) -> void:
	for i in 900:
		await get_tree().process_frame
		if s.pending_count() == 0:
			await get_tree().process_frame
			return
	failures.append("streamer did not settle")


func _place(type: int, pos: Vector3, rot := 0) -> Dictionary:
	var r := BuildRules.check(type, pos, rot, _gen, _scatter, _state)
	return _state.add_building(type, Vector3(pos.x, r.y, pos.z), rot)


func test_chunk_instances_buildings() -> void:
	var spot := TestSpots.flat_clear(_gen, _scatter, B.CABIN)
	var rec := _place(B.CABIN, spot)
	var s := _make_streamer()
	s.update_center(spot)
	await _settle(s)
	var chunk := s.get_chunk(ChunkMath.world_to_chunk(spot))
	assert_true(chunk.has_building(rec.id))
	var node := chunk.get_node_or_null("B_%d" % rec.id) as Node3D
	assert_true(node != null, "building node missing")
	if node:
		assert_true(node.find_children("*", "MeshInstance3D", true, false).size() >= 2, "model or foundation missing")
		assert_true(node.global_position.distance_to(rec.pos) < 0.01)


func test_building_survives_chunk_reload() -> void:
	var spot := TestSpots.flat_clear(_gen, _scatter, B.WELL)
	var rec := _place(B.WELL, spot)
	var c := ChunkMath.world_to_chunk(spot)
	var s := _make_streamer()
	s.update_center(spot)
	await _settle(s)
	s.update_center(ChunkMath.chunk_origin(Vector2i(c.x + 8 if c.x < 12 else c.x - 8, c.y)))
	await _settle(s)
	assert_true(s.get_chunk(c) == null)
	s.update_center(spot)
	await _settle(s)
	assert_true(s.get_chunk(c).has_building(rec.id), "building gone after reload")


func test_add_and_remove_live() -> void:
	var spot := TestSpots.flat_clear(_gen, _scatter, B.STORAGE)
	var s := _make_streamer()
	s.update_center(spot)
	await _settle(s)
	var chunk := s.get_chunk(ChunkMath.world_to_chunk(spot))
	var rec := _place(B.STORAGE, spot)
	chunk.add_building(rec)
	assert_true(chunk.has_building(rec.id))
	chunk.remove_building(rec.id)
	await get_tree().process_frame
	assert_true(not chunk.has_building(rec.id))
	assert_true(chunk.get_node_or_null("B_%d" % rec.id) == null)


func test_building_blocks_player() -> void:
	var spot := TestSpots.flat_clear(_gen, _scatter, B.CABIN, 6.0)
	assert_true(spot.x >= 0.0, "no flat clear spot found")
	_place(B.CABIN, spot)
	var s := _make_streamer()
	s.update_center(spot)
	await _settle(s)
	var player: Player = load("res://scenes/player.tscn").instantiate()
	add_child(player)
	var start := spot + Vector3(-5.0, 0, 0)
	player.global_position = Vector3(start.x, _gen.height_at(start.x, start.z) + 0.3, start.z)
	player.reset_physics_interpolation()
	player.frozen = false
	await wait_physics_frames(5)
	# With the 45° camera, right+down together walk straight toward +X (into the cabin's west wall).
	Input.action_press("move_right")
	Input.action_press("move_down")
	await wait_physics_frames(150)
	Input.action_release("move_right")
	Input.action_release("move_down")
	assert_true(player.global_position.x <= spot.x - 2.0 + 0.05, "walked into the cabin: x=%.2f, wall at %.2f" % [player.global_position.x, spot.x - 2.0])


func test_campfire_has_light() -> void:
	var spot := TestSpots.flat_clear(_gen, _scatter, B.CAMPFIRE)
	var rec := _place(B.CAMPFIRE, spot)
	var s := _make_streamer()
	s.update_center(spot)
	await _settle(s)
	var node := s.get_chunk(ChunkMath.world_to_chunk(spot)).get_node("B_%d" % rec.id)
	assert_eq(node.find_children("*", "OmniLight3D", true, false).size(), 1)


func test_flag_banner_colored() -> void:
	var spot := TestSpots.flat_clear(_gen, _scatter, B.FLAG)
	var color := Color(0.2, 0.3, 0.8)
	var rec := _state.add_building(B.FLAG, spot, 0, color)
	var s := _make_streamer()
	s.update_center(spot)
	await _settle(s)
	var node := s.get_chunk(ChunkMath.world_to_chunk(spot)).get_node("B_%d" % rec.id)
	var found := false
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		for i in mi.get_surface_override_material_count():
			var m := mi.get_surface_override_material(i) as ShaderMaterial
			if m and m.resource_name == "banner":
				assert_eq(m.get_shader_parameter("albedo"), color)
				found = true
	assert_true(found, "banner not recolored")


func test_obstacles_on_their_own_layer() -> void:
	var spot := TestSpots.flat_clear(_gen, _scatter, B.WELL)
	var rec := _place(B.WELL, spot)
	var s := _make_streamer()
	s.update_center(spot)
	await _settle(s)
	var chunk := s.get_chunk(ChunkMath.world_to_chunk(spot))
	var body := chunk.get_node("B_%d" % rec.id).find_children("*", "StaticBody3D", true, false)[0] as StaticBody3D
	assert_eq(body.collision_layer, GameConstants.LAYER_OBSTACLES)
	assert_eq((chunk.get_node("Terrain") as StaticBody3D).collision_layer, GameConstants.LAYER_TERRAIN)
	assert_eq((chunk.get_node("PropBodies") as StaticBody3D).collision_layer, GameConstants.LAYER_OBSTACLES)


func test_site_shows_scaffold_and_grows() -> void:
	var spot := TestSpots.flat_clear(_gen, _scatter, B.HOUSE)
	var seat := _state.add_building(B.CABIN, spot + Vector3(20, 0, 0), 0)
	var k := _state.add_kingdom("T", Color.RED, seat.pos, seat.id)
	_state.add_stock(k, GameConstants.Res.WOOD, 100)
	_state.add_stock(k, GameConstants.Res.STONE, 100)
	var r := BuildRules.check_site(B.HOUSE, spot, 0, _gen, _scatter, _state)
	var site := _state.add_site(B.HOUSE, Vector3(spot.x, r.y, spot.z), 0, k, 0.0)
	var s := _make_streamer()
	s.update_center(spot)
	await _settle(s)
	var chunk := s.get_chunk(ChunkMath.world_to_chunk(spot))
	var node := chunk.get_node_or_null("B_%d" % site.id) as Node3D
	assert_true(node != null, "site node missing")
	if node == null:
		return
	assert_true(node.get_node_or_null("Scaffold") != null, "no scaffold")
	var model := node.get_node_or_null("Model") as Node3D
	assert_true(model != null, "no model")
	if model == null:
		return
	var low := model.scale.y
	assert_true(low < 0.5, "a new site starts low (%.2f)" % low)
	_state.add_progress(site.id, 4.0, 1.0)
	chunk.update_site(site)
	assert_true(model.scale.y > low, "site grows with progress")
	_state.add_progress(site.id, 100.0, 2.0)
	chunk.update_site(site)
	var done := chunk.get_node_or_null("B_%d" % site.id) as Node3D
	assert_true(done != null and done.get_node_or_null("Scaffold") == null, "finished: scaffold gone")
	assert_true(done != null and done.find_children("*", "StaticBody3D", true, false).size() == 1, "finished: full collision")


func test_farm_has_no_collision() -> void:
	var spot := TestSpots.flat_clear(_gen, _scatter, B.FARM)
	var rec := _state.add_building(B.FARM, spot, 0, Color.WHITE, GameConstants.OWNER_KINGDOM)
	var s := _make_streamer()
	s.update_center(spot)
	await _settle(s)
	var node := s.get_chunk(ChunkMath.world_to_chunk(spot)).get_node_or_null("B_%d" % rec.id) as Node3D
	assert_true(node != null)
	if node:
		assert_eq(node.find_children("*", "StaticBody3D", true, false).size(), 0, "farm is walkable")
		assert_true(node.get_node_or_null("Foundation") == null, "no stone base under a field")
