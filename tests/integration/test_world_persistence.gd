extends GameTest

const MAIN_SCENE := "res://scenes/main.tscn"
const READY_TIMEOUT_FRAMES := 900

var _path := "user://test_persist_%d.bin" % randi()


func _exit_tree() -> void:
	for p in [_path, _path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _make_world(world_seed: int, save_path: String) -> World:
	var w: World = load(MAIN_SCENE).instantiate()
	w.world_seed = world_seed
	w.spawn_seed = 42
	w.save_path = save_path
	add_child(w)
	for i in READY_TIMEOUT_FRAMES:
		if w.is_world_ready():
			break
		await get_tree().process_frame
	assert_true(w.is_world_ready(), "world not ready")
	while w.get_streamer().pending_count() > 0:
		await get_tree().process_frame
	return w


func test_new_world_random_seed_differs() -> void:
	var a: World = await _make_world(-1, "")
	var seed_a := a.get_state().seed
	a.free()
	var b: World = await _make_world(-1, "")
	var seed_b := b.get_state().seed
	if seed_a == seed_b: # astronomically unlikely; retry once
		b.free()
		b = await _make_world(-1, "")
		seed_b = b.get_state().seed
	assert_true(seed_a != seed_b, "two new worlds got seed %d" % seed_a)


func test_world_seed_drives_terrain() -> void:
	var w: World = await _make_world(1337, "")
	assert_eq(w.get_state().seed, 1337)
	assert_eq(w.get_generator().height_at(100, 100), TerrainGenerator.new(1337).height_at(100, 100))


func test_harvest_persists_across_save_and_reload() -> void:
	var a: World = await _make_world(1337, _path)
	var target := {}
	for c in a.get_streamer().loaded_coords():
		var chunk := a.get_streamer().get_chunk(c)
		for id in chunk.prop_ids():
			if chunk.get_prop(id).type == GameConstants.Prop.BUSH:
				target = {chunk = chunk, prop = chunk.get_prop(id)}
				break
		if not target.is_empty():
			break
	assert_true(not target.is_empty(), "no bush near spawn")
	if target.is_empty():
		return
	var coord: Vector2i = target.chunk.coord
	var id: int = target.prop.id
	assert_true(a.get_harvest().hit(target))
	var pos := a.get_player().global_position
	assert_eq(a.save_now(), OK)
	a.free()

	var b: World = await _make_world(-1, _path) # seed must come from the save, not -1
	assert_eq(b.get_state().seed, 1337)
	assert_eq(b.get_state().get_resource(GameConstants.Res.BERRIES), 2)
	assert_true(b.get_state().removed_in(coord).has(id), "removal not saved")
	var chunk := b.get_streamer().get_chunk(coord)
	assert_true(chunk != null and not chunk.has_prop(id), "harvested bush is back")
	assert_true(b.get_player().global_position.distance_to(pos) < 1.0, "player position not restored")


func test_no_save_when_path_empty() -> void:
	var w: World = await _make_world(1337, "")
	assert_true(w.save_now() != OK)


func test_restored_position_snaps_to_ground() -> void:
	var s := WorldState.new()
	s.seed = 1337
	s.player_position = Vector3(300, -80, 300) # far below the terrain
	s.has_player_position = true
	s.save_to(_path)
	var w: World = await _make_world(-1, _path)
	await wait_physics_frames(60)
	var p := w.get_player().global_position
	assert_true(absf(p.y - w.get_generator().height_at(p.x, p.z)) < 0.5, "player at y=%.1f, ground %.1f" % [p.y, w.get_generator().height_at(p.x, p.z)])


func test_unreadable_save_is_moved_aside() -> void:
	var f := FileAccess.open(_path, FileAccess.WRITE)
	f.store_buffer("MJSVgarbage-that-is-not-a-variant".to_ascii_buffer())
	f.close()
	var w: World = await _make_world(-1, _path)
	assert_true(FileAccess.file_exists(_path + ".corrupt"), "unreadable save was not preserved")
	assert_true(w.is_world_ready())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path + ".corrupt"))


func test_shader_globals_follow_player_and_camera() -> void:
	var w: World = await _make_world(1337, "")
	await wait_frames(3)
	# The dummy renderer cannot read globals back, so check the values World pushes each frame.
	var g := w.shader_globals()
	assert_true(g[&"main_camera_pos"].distance_to(w.get_camera().global_position) < 1.0, "main_camera_pos wrong")
	assert_true(g[&"player_world_pos"].distance_to(w.get_player().global_position) < 1.5, "player_world_pos wrong")
	for param in g:
		assert_true(RenderingServer.global_shader_parameter_get_list().has(param), "%s not registered" % param)


func test_buildings_persist_across_save_and_reload() -> void:
	var a: World = await _make_world(1337, _path)
	var gen := a.get_generator()
	var scatter := PropScatter.new(gen, 1337)
	var spot := TestSpots.flat_clear(gen, scatter, GameConstants.Building.CABIN, 8.0)
	var p := a.get_player()
	p.global_position = Vector3(spot.x, gen.height_at(spot.x, spot.z) + 0.3, spot.z - GameConstants.BUILD_GHOST_DISTANCE)
	p.reset_physics_interpolation()
	for i in 600:
		await get_tree().physics_frame
		if a.get_streamer().pending_count() == 0 and a.get_streamer().is_loaded(ChunkMath.world_to_chunk(spot)):
			break
	a.get_state().add_resource(GameConstants.Res.WOOD, 100)
	a.get_state().add_resource(GameConstants.Res.STONE, 100)
	var build := a.get_build()
	build.use_mouse = false
	build.select(GameConstants.Building.CABIN)
	assert_true(build.try_place(), "cabin: %s" % build.preview().reason)
	assert_eq(a.save_now(), OK)
	var ids := a.get_state().all_buildings().map(func(b: Dictionary) -> int: return b.id)
	a.free()

	var b: World = await _make_world(-1, _path)
	assert_eq(b.get_state().all_buildings().map(func(r: Dictionary) -> int: return r.id), ids)
	assert_eq(b.get_state().kingdoms().size(), 1)
	for i in 600:
		if b.get_streamer().is_loaded(ChunkMath.world_to_chunk(spot)):
			break
		await get_tree().process_frame
	var chunk := b.get_streamer().get_chunk(ChunkMath.world_to_chunk(spot))
	for id in ids:
		var rec := b.get_state().building(id)
		var c := b.get_streamer().get_chunk(ChunkMath.world_to_chunk(rec.pos))
		assert_true(c != null and c.has_building(id), "building %d missing after reload" % id)
	assert_true(chunk != null)
