extends GameTest
## Stage 12: the start menu (slots, options) and the pause menu, keyboard only.

const MAIN_SCENE := "res://scenes/main.tscn"

var _dir := "user://test_menu_%d/" % randi()
var _opened: Array[int] = []
var _quit := 0


func _slots() -> SaveSlots:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	return SaveSlots.new(_dir)


func _exit_tree() -> void:
	var slots := SaveSlots.new(_dir)
	for i in range(1, GameConstants.SAVE_SLOTS + 1):
		slots.clear(i)
	for f in ["settings.cfg"]:
		if FileAccess.file_exists(_dir + f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(_dir + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_dir))


## A fake save in slot `i`, saved at unix time `t`.
func _fake_save(slots: SaveSlots, i: int, t: int) -> void:
	var s := WorldState.new()
	s.add_kingdom("Valdemar", Color.RED, Vector3.ZERO, -1)
	assert_eq(s.save_to(slots.path(i)), OK)
	slots.write_summary(i, s, t)


func _menu(slots: SaveSlots) -> MainMenu:
	_opened.clear()
	_quit = 0
	var m := MainMenu.new()
	m.slots = slots
	m.settings_path = _dir + "settings.cfg"
	m.open_world = func(slot: int) -> void: _opened.append(slot)
	m.quit = func() -> void: _quit += 1
	add_child(m)
	return m


func _choose(m: MainMenu, text: String) -> void:
	var i := m.items().find(text)
	assert_true(i >= 0, "'%s' not in %s" % [text, m.items()])
	m.select(i)
	m.confirm()


func test_first_run_has_no_continue() -> void:
	var m := _menu(_slots())
	assert_eq(m.items(), [GameConstants.MENU_NEW, GameConstants.MENU_OPTIONS, GameConstants.MENU_QUIT])
	_choose(m, GameConstants.MENU_QUIT)
	assert_eq(_quit, 1)
	m.queue_free()


func test_continue_opens_the_latest_save() -> void:
	var slots := _slots()
	_fake_save(slots, 1, 1000)
	_fake_save(slots, 3, 2000)
	var m := _menu(slots)
	assert_eq(m.items(), [GameConstants.MENU_CONTINUE, GameConstants.MENU_NEW, GameConstants.MENU_LOAD,
			GameConstants.MENU_OPTIONS, GameConstants.MENU_QUIT])
	_choose(m, GameConstants.MENU_CONTINUE)
	assert_eq(_opened, [3], "the slot saved last")
	assert_eq(Session.slot, 3)
	Session.slot = 0
	m.queue_free()


func test_new_game_in_an_empty_slot() -> void:
	var m := _menu(_slots())
	_choose(m, GameConstants.MENU_NEW)
	assert_eq(m.items().size(), GameConstants.SAVE_SLOTS + 1, "three slots and Back")
	assert_true((m.items()[1] as String).contains(GameConstants.SLOT_EMPTY), m.items()[1])
	m.select(1)
	m.confirm()
	assert_eq(_opened, [2])
	Session.slot = 0
	m.queue_free()


func test_new_game_over_a_save_asks_first() -> void:
	var slots := _slots()
	_fake_save(slots, 1, 1000)
	var m := _menu(slots)
	_choose(m, GameConstants.MENU_NEW)
	m.select(0)
	m.confirm()
	assert_eq(_opened, [], "asks before throwing a world away")
	assert_true(m.title_text().contains(GameConstants.MENU_CONFIRM_NEW % 1), m.title_text())
	_choose(m, GameConstants.MENU_NO)
	assert_true(slots.used(1), "No keeps it")
	m.select(0)
	m.confirm()
	_choose(m, GameConstants.MENU_YES)
	assert_true(not slots.used(1), "Yes clears every trace of it")
	assert_eq(_opened, [1])
	Session.slot = 0
	m.queue_free()


func test_load_lists_only_saved_slots() -> void:
	var slots := _slots()
	_fake_save(slots, 2, 1000)
	var m := _menu(slots)
	_choose(m, GameConstants.MENU_LOAD)
	assert_eq(m.items().size(), 2, "slot 2 and Back")
	assert_true((m.items()[0] as String).contains("Reino de Valdemar"), m.items()[0])
	m.confirm()
	assert_eq(_opened, [2])
	Session.slot = 0
	m.queue_free()


func test_esc_goes_back() -> void:
	var m := _menu(_slots())
	_choose(m, GameConstants.MENU_NEW)
	m.back()
	assert_eq(m.items()[0], GameConstants.MENU_NEW, "back on the first page")
	m.queue_free()


func test_options_change_and_are_kept() -> void:
	var m := _menu(_slots())
	_choose(m, GameConstants.MENU_OPTIONS)
	var before := Settings.load_from(_dir + "settings.cfg").music_volume
	m.select(0)
	m.change(-1)
	var after := Settings.load_from(_dir + "settings.cfg").music_volume
	assert_true(after < before, "music volume down and saved (%s -> %s)" % [before, after])
	assert_true((m.items()[0] as String).contains("%d%%" % roundi(after * 100.0)), m.items()[0])
	m.select(2)
	m.confirm()
	assert_true(not Settings.load_from(_dir + "settings.cfg").music_on, "music off")
	m.queue_free()


func test_menu_is_the_main_scene() -> void:
	assert_eq(ProjectSettings.get_setting("application/run/main_scene"), "res://scenes/menu.tscn")


# --- Pause menu ---

func _world() -> World:
	var w: World = load(MAIN_SCENE).instantiate()
	w.spawn_seed = 42
	w.world_seed = GameConstants.WORLD_SEED
	w.save_path = ""
	add_child(w)
	for i in 900:
		if w.is_world_ready():
			break
		await get_tree().process_frame
	return w


func test_pause_stops_the_world_and_resumes() -> void:
	var w: World = await _world()
	var pause := w.get_pause_menu()
	var clock := w.get_day_night().total_hours()
	pause.open()
	assert_true(get_tree().paused and pause.is_open())
	await wait_frames(30)
	assert_near(w.get_day_night().total_hours(), clock, 0.0001, "time stands still")
	pause.select(0)
	pause.confirm()
	assert_true(not get_tree().paused and not pause.is_open(), "Continue")
	w.free()


func test_pause_needs_esc_free() -> void:
	var w: World = await _world()
	var pause := w.get_pause_menu()
	w.get_build().toggle()
	pause.on_esc()
	assert_true(not pause.is_open(), "building keeps its Esc")
	w.get_build().toggle()
	pause.on_esc()
	assert_true(pause.is_open())
	pause.on_esc()
	assert_true(not pause.is_open() and not get_tree().paused, "Esc again closes it")
	w.free()


func test_leaving_without_a_good_save_stays() -> void:
	var w: World = await _world() # save_path "": saving is not possible
	var pause := w.get_pause_menu()
	var left := []
	pause.open_menu = func() -> void: left.append(1)
	pause.open()
	pause.select(pause.items().find(GameConstants.PAUSE_TO_MENU))
	pause.confirm()
	assert_eq(left, [], "the game is never lost to a failed save")
	assert_true(pause.message_text().contains(GameConstants.PAUSE_SAVE_FAILED), pause.message_text())
	pause.close()
	w.free()
