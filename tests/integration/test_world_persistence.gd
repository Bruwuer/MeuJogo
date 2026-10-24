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
