class_name SoundSystem
extends Node
## Autoload `Sound` (stage 12). Buses Music, Effects and Ambient; music and ambience for day, night
## and rain with crossfades; a cap of 3D voices for sounds in the world (nothing beyond SOUND_RANGE
## of the listener); the nearest campfires crackle; footsteps, strikes and menu clicks in 2D.
## Options come from Settings (user://settings.cfg). Missing files are skipped silently.

var settings_path := Settings.DEFAULT_PATH
## Where the listener is (the player). Sounds are measured from it.
var ear: Node3D
## Plays per sound name (for tests and the ADM).
var played: Dictionary = {}

var _streams: Dictionary = {}
var _music: Dictionary = {} # name -> AudioStreamPlayer
var _ambient: Dictionary = {}
var _music_target := ""
var _ambient_targets: Array[String] = []
var _voices: Array[AudioStreamPlayer3D] = []
var _next_voice := 0
var _oneshots: Array[AudioStreamPlayer] = []
var _next_oneshot := 0
var _fires: Array[AudioStreamPlayer3D] = []
var _step_left := 0
var _night := false
var _birds_left := 10.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Music", "Effects", "Ambient"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	for name in ["music_day", "music_night"]:
		_music[name] = _player_2d(name, "Music")
	for name in ["wind", "crickets", "rain"]:
		_ambient[name] = _player_2d(name, "Ambient")
	for i in GameConstants.SOUND_ONESHOT_2D:
		_oneshots.append(_player_2d("", "Effects"))
	for i in GameConstants.SOUND_VOICES:
		_voices.append(_player_3d("", "Effects"))
	for i in GameConstants.SOUND_FIRE_VOICES:
		_fires.append(_player_3d("campfire", "Ambient"))
	apply_settings(Settings.load_from(settings_path))


## The sound file `name` (looping ones marked as loops), or null when it does not exist.
func stream(name: String) -> AudioStream:
	if _streams.has(name):
		return _streams[name]
	var path := GameConstants.SOUND_DIR + name + ".wav"
	var st: AudioStream = load(path) if ResourceLoader.exists(path) else null
	var wav := st as AudioStreamWAV
	if wav and GameConstants.SOUND_LOOPS.has(name):
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = wav.data.size() / (2 * (2 if wav.stereo else 1))
	_streams[name] = st
	return st


func apply_settings(s: Settings) -> void:
	var music := AudioServer.get_bus_index("Music")
	AudioServer.set_bus_volume_db(music, linear_to_db(maxf(s.music_volume, 0.0001)))
	AudioServer.set_bus_mute(music, not s.music_on)
	for bus in ["Effects", "Ambient"]:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus), linear_to_db(maxf(s.sfx_volume, 0.0001)))


## Puts the listener on `node` (the player).
func attach_listener(node: Node3D) -> void:
	var listener := AudioListener3D.new()
	listener.name = "Listener"
	node.add_child(listener)
	listener.make_current()
	ear = node


# --- What plays ---

## Day or night, rain or not: the music and ambience fade to match.
func set_scene(night: bool, raining: bool) -> void:
	_night = night
	_music_target = "music_night" if night else "music_day"
	_ambient_targets.clear()
	_ambient_targets.append("crickets" if night else "wind")
	if raining:
		_ambient_targets.append("rain")


func music_target() -> String:
	return _music_target


func ambient_targets() -> Array[String]:
	return _ambient_targets


## A one-shot sound without a place (the player's own steps and strikes, menu clicks).
func play(name: String) -> void:
	var st := stream(name)
	played[name] = int(played.get(name, 0)) + 1
	if st == null:
		return
	var p := _oneshots[_next_oneshot]
	_next_oneshot = (_next_oneshot + 1) % _oneshots.size()
	p.stream = st
	p.play()


## A sound at a place in the world; false when it is too far from the listener to be heard.
func play_at(name: String, pos: Vector3) -> bool:
	if ear and is_instance_valid(ear) and ear.global_position.distance_to(pos) > GameConstants.SOUND_RANGE:
		return false
	var st := stream(name)
	played[name] = int(played.get(name, 0)) + 1
	if st == null:
		return true
	var v := _voices[_next_voice] # the oldest voice is reused: never more than SOUND_VOICES
	_next_voice = (_next_voice + 1) % _voices.size()
	v.stream = st
	v.global_position = pos
	v.play()
	return true


func busy_voices() -> int:
	return _voices.filter(func(v: AudioStreamPlayer3D) -> bool: return v.playing).size()


## One footstep of the player (alternating feet).
func step() -> void:
	_step_left = 1 - _step_left
	play("step_%d" % (_step_left + 1))


func ui() -> void:
	play("ui_move")


## The nearest campfires within range crackle (at most SOUND_FIRE_VOICES).
func update_fires(positions: Array[Vector3]) -> void:
	var near: Array[Vector3] = []
	var from: Vector3 = ear.global_position if ear and is_instance_valid(ear) else Vector3.ZERO
	for p in positions:
		if from.distance_to(p) <= GameConstants.SOUND_RANGE:
			near.append(p)
	near.sort_custom(func(a: Vector3, b: Vector3) -> bool: return from.distance_to(a) < from.distance_to(b))
	for i in _fires.size():
		var f := _fires[i]
		if i < near.size():
			f.global_position = near[i]
			if not f.playing and f.stream:
				f.play()
			f.set_meta("on", true)
		else:
			f.stop()
			f.set_meta("on", false)


func fire_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for f in _fires:
		if f.get_meta("on", false):
			out.append(f.global_position)
	return out


func _process(delta: float) -> void:
	var step_db := 60.0 * delta / GameConstants.SOUND_FADE_SEC
	for name: String in _music:
		_fade(_music[name], name == _music_target, step_db)
	for name: String in _ambient:
		_fade(_ambient[name], _ambient_targets.has(name), step_db)
	if _music_target != "" and not _night and not get_tree().paused:
		_birds_left -= delta
		if _birds_left <= 0.0:
			_birds_left = randf_range(GameConstants.SOUND_BIRDS_EVERY.x, GameConstants.SOUND_BIRDS_EVERY.y)
			play("birds")


## Fades a looping player toward full (on) or silent (off), starting and stopping it as needed.
func _fade(p: AudioStreamPlayer, on: bool, step_db: float) -> void:
	if p.stream == null:
		return
	if on and not p.playing:
		p.volume_db = -60.0
		p.play()
	if not p.playing:
		return
	p.volume_db = minf(0.0, p.volume_db + step_db) if on else p.volume_db - step_db
	if not on and p.volume_db <= -60.0:
		p.stop()


func _player_2d(name: String, bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	if name != "":
		p.stream = stream(name)
	add_child(p)
	return p


func _player_3d(name: String, bus: String) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = bus
	p.max_distance = GameConstants.SOUND_RANGE
	p.unit_size = 4.0
	if name != "":
		p.stream = stream(name)
	add_child(p)
	return p
