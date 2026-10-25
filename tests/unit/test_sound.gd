extends GameTest
## Stage 12 sound: buses and options, loops, the voice cap, day/night/rain scene, campfires.

var _snd: SoundSystem
var _ear: Node3D


func _make() -> SoundSystem:
	_snd = SoundSystem.new()
	_snd.settings_path = "user://test_sound_settings_%d.cfg" % randi()
	add_child(_snd)
	_ear = Node3D.new()
	add_child(_ear)
	_snd.ear = _ear
	return _snd


func _done() -> void:
	_snd.queue_free()
	_ear.queue_free()


func test_buses_follow_the_options() -> void:
	var snd := _make()
	for bus in ["Music", "Effects", "Ambient"]:
		assert_true(AudioServer.get_bus_index(bus) >= 0, "%s bus" % bus)
	var s := Settings.new()
	s.music_volume = 0.5
	s.sfx_volume = 0.25
	s.music_on = false
	snd.apply_settings(s)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "music off")
	assert_near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Effects")), linear_to_db(0.25), 0.01)
	s.music_on = true
	snd.apply_settings(s)
	assert_true(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")))
	assert_near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), linear_to_db(0.5), 0.01)
	_done()


func test_loops_are_marked() -> void:
	var snd := _make()
	for name in ["campfire", "rain", "wind", "crickets", "music_day", "music_night"]:
		var st := snd.stream(name) as AudioStreamWAV
		assert_true(st != null and st.loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s loops" % name)
	var hit := snd.stream("hit") as AudioStreamWAV
	assert_true(hit != null and hit.loop_mode == AudioStreamWAV.LOOP_DISABLED, "a hit plays once")
	_done()


func test_never_more_than_the_voice_cap() -> void:
	var snd := _make()
	for i in 20:
		snd.play_at("chop", Vector3(i * 0.5, 0, 0))
	assert_true(snd.busy_voices() <= GameConstants.SOUND_VOICES, "at most %d voices (%d)" % [GameConstants.SOUND_VOICES, snd.busy_voices()])
	assert_true(not snd.play_at("chop", Vector3(GameConstants.SOUND_RANGE + 5.0, 0, 0)), "too far to hear")
	_done()


func test_scene_picks_music_and_ambience() -> void:
	var snd := _make()
	snd.set_scene(false, false)
	assert_eq(snd.music_target(), "music_day")
	assert_eq(snd.ambient_targets(), ["wind"])
	snd.set_scene(true, true)
	assert_eq(snd.music_target(), "music_night")
	assert_eq(snd.ambient_targets(), ["crickets", "rain"])
	_done()


func test_campfires_heard_are_the_nearest() -> void:
	var snd := _make()
	var fires: Array[Vector3] = []
	for d in [30.0, 4.0, 12.0, 8.0, 2.0]:
		fires.append(Vector3(d, 0, 0))
	snd.update_fires(fires)
	var heard := snd.fire_positions()
	assert_eq(heard.size(), GameConstants.SOUND_FIRE_VOICES)
	for p: Vector3 in heard:
		assert_true(p.x <= 8.0, "only the nearest fires crackle (%s)" % p)
	snd.update_fires([] as Array[Vector3])
	assert_eq(snd.fire_positions().size(), 0)
	_done()
