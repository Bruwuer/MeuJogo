extends GameTest

var _path := "user://test_world_state_%d.bin" % randi()


func _exit_tree() -> void:
	for p in [_path, _path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _filled() -> WorldState:
	var s := WorldState.new()
	s.seed = 4242
	s.time_of_day = 0.73
	s.day = 3
	s.player_position = Vector3(10.5, 3.25, 99.0)
	s.has_player_position = true
	s.mark_removed(Vector2i(1, 2), 5)
	s.mark_removed(Vector2i(1, 2), 9)
	s.mark_removed(Vector2i(-1, 0), 0)
	s.add_resource(GameConstants.Res.WOOD, 6)
	s.add_resource(GameConstants.Res.BERRIES, 2)
	return s


func test_roundtrip() -> void:
	var a := _filled()
	assert_eq(a.save_to(_path), OK)
	var b := WorldState.load_from(_path)
	assert_true(b != null, "load failed")
	if b == null:
		return
	assert_eq(b.seed, 4242)
	assert_near(b.time_of_day, 0.73, 0.0001)
	assert_eq(b.day, 3)
	assert_eq(b.player_position, Vector3(10.5, 3.25, 99.0))
	assert_true(b.has_player_position)
	assert_eq(b.removed_in(Vector2i(1, 2)), PackedInt32Array([5, 9]))
	assert_eq(b.removed_in(Vector2i(-1, 0)), PackedInt32Array([0]))
	assert_eq(b.removed_in(Vector2i(7, 7)), PackedInt32Array())
	assert_eq(b.get_resource(GameConstants.Res.WOOD), 6)
	assert_eq(b.get_resource(GameConstants.Res.STONE), 0)
	assert_eq(b.get_resource(GameConstants.Res.BERRIES), 2)


func test_missing_file_returns_null() -> void:
	assert_true(WorldState.load_from("user://does_not_exist_%d.bin" % randi()) == null)


func test_corrupt_file_returns_null() -> void:
	var f := FileAccess.open(_path, FileAccess.WRITE)
	f.store_buffer(PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]))
	f.close()
	assert_true(WorldState.load_from(_path) == null)


func test_version_mismatch_drops_removed_only() -> void:
	_filled().save_to(_path)
	var data: Dictionary = WorldState.read_payload(_path)
	data.version = GameConstants.WORLDGEN_VERSION - 1
	WorldState.write_payload(_path, data)
	var s := WorldState.load_from(_path)
	assert_true(s != null)
	if s == null:
		return
	assert_eq(s.removed_in(Vector2i(1, 2)), PackedInt32Array())
	assert_eq(s.seed, 4242)
	assert_eq(s.get_resource(GameConstants.Res.WOOD), 6)
	assert_eq(s.player_position, Vector3(10.5, 3.25, 99.0))


func test_mark_removed_no_duplicates() -> void:
	var s := WorldState.new()
	s.mark_removed(Vector2i(0, 0), 3)
	s.mark_removed(Vector2i(0, 0), 3)
	assert_eq(s.removed_in(Vector2i(0, 0)), PackedInt32Array([3]))


func test_save_overwrites_existing() -> void:
	_filled().save_to(_path)
	var s := WorldState.new()
	s.seed = 1
	assert_eq(s.save_to(_path), OK)
	assert_eq(WorldState.load_from(_path).seed, 1)


func test_load_falls_back_to_tmp_when_main_missing() -> void:
	# Simulates a crash after the old save was removed but before the new one was renamed in.
	_filled().save_to(_path)
	DirAccess.rename_absolute(ProjectSettings.globalize_path(_path), ProjectSettings.globalize_path(_path + ".tmp"))
	var s := WorldState.load_from(_path)
	assert_true(s != null and s.seed == 4242, "save lost when only .tmp survived")


func test_load_falls_back_to_bak() -> void:
	_filled().save_to(_path)
	DirAccess.rename_absolute(ProjectSettings.globalize_path(_path), ProjectSettings.globalize_path(_path + ".bak"))
	var s := WorldState.load_from(_path)
	assert_true(s != null and s.seed == 4242, "save lost when only .bak survived")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path + ".bak"))


func test_save_leaves_no_side_files() -> void:
	_filled().save_to(_path)
	_filled().save_to(_path)
	assert_true(FileAccess.file_exists(_path))
	assert_true(not FileAccess.file_exists(_path + ".tmp") and not FileAccess.file_exists(_path + ".bak"))
