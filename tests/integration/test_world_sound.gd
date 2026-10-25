extends GameTest
## Stage 12: the world plays its sounds through the Sound autoload.

const MAIN_SCENE := "res://scenes/main.tscn"


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
	while w.get_streamer().pending_count() > 0:
		await get_tree().process_frame
	return w


func _count(names: Array) -> int:
	var n := 0
	for name in names:
		n += int(Sound.played.get(name, 0))
	return n


func test_the_player_is_the_listener() -> void:
	var w: World = await _world()
	var listener := w.get_player().find_child("Listener", true, false) as AudioListener3D
	assert_true(listener != null, "a listener on the player")
	assert_eq(Sound.ear, w.get_player())
	w.free()


func test_footsteps_when_walking() -> void:
	var w: World = await _world()
	var before := _count(["step_1", "step_2"])
	Input.action_press("move_up")
	await wait_physics_frames(120)
	Input.action_release("move_up")
	assert_true(_count(["step_1", "step_2"]) > before, "walking makes footsteps")
	w.free()


func test_a_swing_sounds() -> void:
	var w: World = await _world()
	var before := _count(["swing"])
	assert_true(w.get_player().attack())
	assert_eq(_count(["swing"]), before + 1)
	w.free()


func test_night_changes_the_music() -> void:
	var w: World = await _world()
	w.get_day_night().time_of_day = 0.02 # deep night
	w.get_day_night().apply()
	await wait_frames(3)
	assert_eq(Sound.music_target(), "music_night")
	w.get_day_night().time_of_day = 0.5
	w.get_day_night().apply()
	await wait_frames(3)
	assert_eq(Sound.music_target(), "music_day")
	w.free()


func test_a_campfire_nearby_crackles() -> void:
	var w: World = await _world()
	var p := w.get_player().global_position
	w.get_state().add_building(GameConstants.Building.CAMPFIRE, p + Vector3(4, 0, 0), 0)
	await get_tree().create_timer(1.0).timeout # fires are looked up twice a second
	assert_true(Sound.fire_positions().size() >= 1, "the fire 4 m away is heard")
	w.free()
	Sound.update_fires([] as Array[Vector3])


func test_work_sounds_by_trade() -> void:
	assert_eq(Person.work_sound("wood", GameConstants.ANIM_WORK), "chop")
	assert_eq(Person.work_sound("stone", GameConstants.ANIM_WORK), "pick")
	assert_eq(Person.work_sound("farm", GameConstants.ANIM_WORK), "dig")
	assert_eq(Person.work_sound("", GameConstants.ANIM_DIG), "dig", "digging a grave")
	assert_eq(Person.work_sound("rest", GameConstants.ANIM_MOURN), "", "mourning is silent")
