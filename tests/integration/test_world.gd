extends GameTest

const MAIN_SCENE := "res://scenes/main.tscn"
const READY_TIMEOUT_FRAMES := 600


func _make_world() -> World:
	var w: World = load(MAIN_SCENE).instantiate()
	w.spawn_seed = 42
	add_child(w)
	for i in READY_TIMEOUT_FRAMES:
		if w.is_world_ready():
			return w
		await get_tree().process_frame
	failures.append("world not ready after %d frames" % READY_TIMEOUT_FRAMES)
	return w


func _ground_gap(w: World) -> float:
	var p := w.get_player().global_position
	return absf(p.y - w.get_generator().height_at(p.x, p.z))


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


func test_world_ready_and_chunks_loaded() -> void:
	var w: World = await _make_world()
	var c := ChunkMath.world_to_chunk(w.get_player().global_position)
	assert_true(w.get_streamer().is_loaded(c), "spawn chunk not loaded")
	assert_true(w.get_viewport().get_camera_3d() is IsoCamera, "active camera is not IsoCamera")


func test_player_rests_on_ground() -> void:
	var w: World = await _make_world()
	await wait_physics_frames(120)
	assert_true(_ground_gap(w) < 0.3, "gap to ground %f" % _ground_gap(w))


func test_w_moves_screen_up() -> void:
	var w: World = await _make_world()
	await wait_physics_frames(30)
	var start := _flat(w.get_player().global_position)
	Input.action_press("move_up")
	await wait_physics_frames(60)
	Input.action_release("move_up")
	var dir := (_flat(w.get_player().global_position) - start).normalized()
	assert_true(dir.dot(IsoInput.to_world(Vector2(0, -1), GameConstants.CAM_YAW_DEG)) > 0.95, "dir %s" % dir)


func test_edge_wall_blocks() -> void:
	var w: World = await _make_world()
	var p := w.get_player()
	var gen := w.get_generator()
	p.global_position = Vector3(2.0, gen.height_at(2.0, 128.0) + 0.5, 128.0)
	for i in 300: # wait for the new area to stream in
		await get_tree().physics_frame
		if w.get_streamer().is_loaded(ChunkMath.world_to_chunk(p.global_position)) and w.get_streamer().pending_count() == 0:
			break
	Input.action_press("move_left")
	Input.action_press("move_up") # together: straight toward -X
	await wait_physics_frames(120)
	Input.action_release("move_left")
	Input.action_release("move_up")
	assert_true(p.global_position.x >= 0.0, "crossed the edge: x=%f" % p.global_position.x)
	assert_true(_ground_gap(w) < 0.5, "fell through near the edge")


func test_streams_while_walking() -> void:
	var w: World = await _make_world()
	var p := w.get_player()
	var worst_ms := 0.0
	var last := Time.get_ticks_usec()
	var unloaded_frames := 0
	Input.action_press("move_down")
	Input.action_press("run")
	for i in 300:
		await get_tree().physics_frame
		var now := Time.get_ticks_usec()
		worst_ms = maxf(worst_ms, (now - last) / 1000.0)
		last = now
		if not w.get_streamer().is_loaded(ChunkMath.world_to_chunk(p.global_position)):
			unloaded_frames += 1
	Input.action_release("move_down")
	Input.action_release("run")
	assert_eq(unloaded_frames, 0, "frames standing on an unloaded chunk")
	assert_true(worst_ms < GameConstants.MAX_FRAME_MS, "worst frame %.1f ms" % worst_ms)
	assert_true(_ground_gap(w) < 0.5, "not on ground after running")


func test_player_frozen_over_unloaded_chunk() -> void:
	var w: World = await _make_world()
	var p := w.get_player()
	p.global_position = Vector3(250.0, 20.0, 250.0) # far corner, not streamed yet
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(p.frozen, "player must freeze while its chunk has no collision")


func test_physics_interpolation_enabled() -> void:
	# Player and camera move on physics ticks; without interpolation the image judders above 60 Hz.
	assert_true(ProjectSettings.get_setting("physics/common/physics_interpolation", false), "physics interpolation off")
