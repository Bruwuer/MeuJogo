extends GameTest
## Finishing (stage 12): three save slots with a summary, the old single save moved into slot 1,
## and a new game that truly starts over.

var _dir := "user://test_slots_%d/" % randi()


func _slots() -> SaveSlots:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	return SaveSlots.new(_dir)


func _exit_tree() -> void:
	var abs_dir := ProjectSettings.globalize_path(_dir)
	if DirAccess.dir_exists_absolute(abs_dir):
		for f in DirAccess.get_files_at(abs_dir):
			DirAccess.remove_absolute(abs_dir.path_join(f))
		DirAccess.remove_absolute(abs_dir)


func _write(path: String, text := "x") -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_slot_paths_and_emptiness() -> void:
	var slots := _slots()
	assert_eq(slots.path(1), _dir + "save_1.bin")
	assert_true(not slots.used(1))
	_write(slots.path(2) + ".bak") # only a backup left: still a saved game
	assert_true(slots.used(2))


func test_summary_after_a_save() -> void:
	var slots := _slots()
	var s := WorldState.new()
	var cabin := s.add_building(GameConstants.Building.CABIN, Vector3.ZERO, 0)
	s.add_kingdom("Valdemar", Color.RED, Vector3.ZERO, cabin.id)
	s.day = 7
	assert_eq(s.save_to(slots.path(1)), OK)
	slots.write_summary(1, s, 1700000000)
	var m := slots.summary(1)
	assert_eq(String(m.kingdom), "Valdemar")
	assert_eq(int(m.day), 7)
	assert_eq(int(m.saved_unix), 1700000000)
	assert_true(slots.label(1).contains("Valdemar") and slots.label(1).contains("dia 7"), slots.label(1))
	assert_eq(slots.label(2), GameConstants.SLOT_EMPTY)


func test_latest_slot_is_the_last_saved() -> void:
	var slots := _slots()
	var s := WorldState.new()
	for i in [1, 3]:
		s.save_to(slots.path(i))
	slots.write_summary(1, s, 100)
	slots.write_summary(3, s, 300)
	assert_eq(slots.latest(), 3)
	assert_eq(_slots_empty().latest(), -1)


func _slots_empty() -> SaveSlots:
	var other := "user://test_slots_empty_%d/" % randi()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(other))
	return SaveSlots.new(other)


func test_new_game_clears_every_trace() -> void:
	var slots := _slots()
	for ext in ["", ".bak", ".tmp", ".corrupt"]:
		_write(slots.path(2) + ext)
	_write(slots.summary_path(2))
	slots.clear(2)
	assert_true(not slots.used(2), "the old world must not come back from a backup")
	assert_true(not FileAccess.file_exists(slots.summary_path(2)))


func test_old_single_save_moves_into_slot_1() -> void:
	var slots := _slots()
	_write(slots.legacy_path(), "old")
	_write(slots.legacy_path() + ".bak", "old bak")
	slots.migrate_legacy()
	assert_true(slots.used(1))
	assert_true(FileAccess.file_exists(slots.path(1) + ".bak"))
	assert_true(not FileAccess.file_exists(slots.legacy_path()))
	_write(slots.legacy_path(), "again")
	slots.migrate_legacy()
	assert_eq(FileAccess.get_file_as_string(slots.path(1)), "old", "never over a used slot 1")
