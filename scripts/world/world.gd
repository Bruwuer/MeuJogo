class_name World
extends Node3D
## Root of the main scene. Loads the save (or starts a new world with its own seed), then wires
## terrain/prop streaming, day/night, map-edge walls, player, camera, harvesting and HUD.
## The player stays frozen whenever the chunk under it has no collision yet.

signal world_ready
signal respawned(text: String)

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const _SPAWN_DROP := 0.5
const _RESPAWN_GAP := 1.5 ## Distance in front of the seat cabin door.
const _RESTORE_DROP := 0.2
const _WALL_THICKNESS := 1.0
const _SHADOW_DISTANCE := 90.0
const _PLAYER_CENTER := 0.9 ## Height of the point props fade around (prop occlusion shader).

## -1 = random spawn; any other value makes the spawn reproducible (new worlds only).
@export var spawn_seed := GameConstants.SPAWN_SEED
## -1 = new worlds get a random seed; ignored when a save is loaded.
@export var world_seed := -1
## Where the world is saved; "" disables saving and loading.
@export var save_path := GameConstants.SAVE_PATH

var _state: WorldState
var _gen: TerrainGenerator
var _streamer: ChunkStreamer
var _player: Player
var _camera: IsoCamera
var _day_night: DayNight
var _harvest: HarvestSystem
var _hud: Hud
var _build: BuildSystem
var _spawn: Vector3
var _scatter: PropScatter
var _pack_sim: PackSim
var _creatures: CreatureManager
var _village: VillageSim
var _people: PeopleManager
var _is_ready := false
var _autosave_left := GameConstants.AUTOSAVE_SEC


func _ready() -> void:
	_state = WorldState.load_from(save_path) if save_path != "" else null
	if _state == null and save_path != "" and WorldState.any_file_exists(save_path):
		_set_aside_unreadable_save()
	if _state == null:
		_state = WorldState.new()
		_state.seed = world_seed if world_seed >= 0 else randi()

	_gen = TerrainGenerator.new(_state.seed)
	var scatter := PropScatter.new(_gen, _state.seed)
	_scatter = scatter
	var library := ModelLibrary.new()
	library.name = "ModelLibrary"
	add_child(library)
	library.start_loading()
	_streamer = ChunkStreamer.new()
	_streamer.name = "Chunks"
	_streamer.setup(_gen, scatter, library, _state.removed_in, _state.buildings_in)
	add_child(_streamer)
	_add_environment()
	_add_edge_walls()

	var new_world := not _state.has_player_position
	if _state.has_player_position:
		# Terrain or props may have changed since the save: re-ground and step out of obstacles.
		_spawn = SpawnPicker.nearest_clear(_gen, scatter, _state.player_position) + Vector3.UP * (_RESTORE_DROP - _SPAWN_DROP)
	else:
		var rng := RandomNumberGenerator.new()
		if spawn_seed >= 0:
			rng.seed = spawn_seed
		else:
			rng.randomize()
		_spawn = SpawnPicker.pick(_gen, scatter, rng)

	_harvest = HarvestSystem.new()
	_harvest.name = "Harvest"
	_harvest.setup(_streamer.get_chunk, _state)
	add_child(_harvest)

	_player = PLAYER_SCENE.instantiate()
	_player.harvest = _harvest
	_player.state = _state
	_player.library = library
	_player.died.connect(_respawn)
	respawned.connect(func(text: String) -> void: _hud.add_message(text))
	add_child(_player)
	_player.global_position = _spawn + Vector3.UP * _SPAWN_DROP
	_player.reset_physics_interpolation()

	_camera = IsoCamera.new()
	_camera.target = _player
	add_child(_camera)
	_camera.make_current()
	_camera.snap_to_target()

	_hud = Hud.new()
	_hud.name = "Hud"
	add_child(_hud)
	_build = BuildSystem.new()
	_build.name = "Build"
	add_child(_build)
	_build.setup(_state, _gen, scatter, _streamer, library, _player, _camera)

	_hud.setup(_state, _harvest, _day_night, _player, _build)

	_add_creatures(scatter, library, new_world)
	_add_people(scatter, library)
	_streamer.chunk_loaded.connect(_on_chunk_loaded)
	_streamer.update_center(_spawn)


func _physics_process(_delta: float) -> void:
	var pos := _player.global_position
	_streamer.update_center(pos)
	_player.frozen = not _streamer.is_loaded(ChunkMath.world_to_chunk(pos))


func _process(delta: float) -> void:
	var globals := shader_globals()
	for param in globals:
		RenderingServer.global_shader_parameter_set(param, globals[param])
	_flush_offscreen_messages()
	if not _is_ready or save_path == "":
		return
	_autosave_left -= delta
	if _autosave_left <= 0.0:
		_autosave_left = GameConstants.AUTOSAVE_SEC
		var err := save_now()
		if err != OK:
			push_warning("World: autosave failed (%s)" % error_string(err))


## Values for the project shader globals used by the prop occlusion shader. Interpolated
## transforms match what is drawn this frame (physics interpolation is on).
func shader_globals() -> Dictionary[StringName, Vector3]:
	return {
		&"player_world_pos": _player.get_global_transform_interpolated().origin + Vector3.UP * _PLAYER_CENTER,
		&"main_camera_pos": _camera.get_global_transform_interpolated().origin,
	}


## Keeps an unreadable save as `.corrupt` instead of silently overwriting it with a new world.
func _set_aside_unreadable_save() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(save_path + suffix):
			var corrupt := ProjectSettings.globalize_path(save_path + ".corrupt")
			if FileAccess.file_exists(save_path + ".corrupt"):
				DirAccess.remove_absolute(corrupt)
			DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path + suffix), corrupt)
			push_warning("World: save at %s was unreadable, kept as %s" % [save_path, corrupt])
			return


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _is_ready:
		save_now()


## Copies live values (player position, time of day) into the state and writes the save.
func save_now() -> Error:
	if save_path == "":
		return ERR_UNAVAILABLE
	_creatures.sync_all()
	_people.sync_all()
	_state.player_position = _player.global_position
	_state.has_player_position = true
	_state.time_of_day = _day_night.time_of_day
	_state.day = _day_night.day
	return _state.save_to(save_path)


## Packs (hourly motives, raids) and the creature nodes in loaded chunks. A new world gets its
## first wolf pack near the spawn.
func _add_creatures(scatter: PropScatter, library: ModelLibrary, new_world: bool) -> void:
	_pack_sim = PackSim.new()
	_pack_sim.name = "PackSim"
	add_child(_pack_sim)
	_pack_sim.setup(_state, _day_night)
	_pack_sim.player = _player
	_creatures = CreatureManager.new()
	_creatures.name = "Creatures"
	add_child(_creatures)
	_creatures.setup(_state, _gen, scatter, _streamer, library, _day_night, _pack_sim, _player)
	_creatures.message.connect(_hud.add_message)
	_creatures.creature_killed.connect(func(rec: Dictionary, by_player: bool) -> void:
		if by_player:
			_hud.add_message(GameConstants.KILL_MSG % Genome.display_name(rec.genome)))
	_player.creature_source = _creatures.active_creatures
	if new_world:
		_creatures.ensure_first_wolves(_spawn)


## Raids that happened while the player was away are told once the player is back in a kingdom.
func _flush_offscreen_messages() -> void:
	if _state.kingdom_at(_player.global_position).is_empty():
		return
	for text in _pack_sim.take_messages():
		_hud.add_message(text)
	if _village.pending_messages.is_empty():
		return
	# Village news are many: the latest few, and how many more happened.
	var news := _village.take_messages()
	var shown := mini(news.size(), GameConstants.VILLAGE_NEWS_SHOWN)
	var more := news.size() - shown + _village.take_dropped()
	if more > 0:
		_hud.add_message(GameConstants.VILLAGE_NEWS_MORE % more)
	for text in news.slice(news.size() - shown):
		_hud.add_message(text)


## Death never costs buildings or resources: the player wakes up in front of the seat cabin of
## its first kingdom (or at the spawn point) with full health.
func _respawn() -> void:
	var pos := _spawn
	var text := GameConstants.RESPAWN_MSG_SPAWN
	if not _state.kingdoms().is_empty():
		var seat := _state.building(_state.kingdoms()[0].seat_id)
		if not seat.is_empty():
			var depth: float = GameConstants.BUILD_FOOTPRINT[GameConstants.Building.CABIN].y
			var front := Vector3(0, 0, depth * 0.5 + _RESPAWN_GAP).rotated(Vector3.UP, seat.rot * PI * 0.5)
			pos = SpawnPicker.nearest_clear(_gen, _scatter, seat.pos + front)
			text = GameConstants.RESPAWN_MSG_SEAT
	_player.global_position = pos + Vector3.UP * _SPAWN_DROP
	_player.reset_physics_interpolation()
	_player.revive()
	respawned.emit(text)


func _on_chunk_loaded(c: Vector2i) -> void:
	if not _is_ready and c == ChunkMath.world_to_chunk(_spawn):
		_is_ready = true
		world_ready.emit()


func is_world_ready() -> bool:
	return _is_ready


func get_player() -> Player:
	return _player


func get_camera() -> IsoCamera:
	return _camera


func get_streamer() -> ChunkStreamer:
	return _streamer


func get_generator() -> TerrainGenerator:
	return _gen


func get_state() -> WorldState:
	return _state


func get_harvest() -> HarvestSystem:
	return _harvest


func get_day_night() -> DayNight:
	return _day_night


func get_hud() -> Hud:
	return _hud


func get_build() -> BuildSystem:
	return _build


func _add_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = _SHADOW_DISTANCE
	add_child(sun)

	_day_night = DayNight.new()
	_day_night.name = "DayNight"
	_day_night.time_of_day = _state.time_of_day
	_day_night.day = _state.day
	add_child(_day_night)
	_day_night.setup(sun, env, sky_mat)


## Invisible walls just outside the playable square, tall enough for the highest terrain.
func _add_edge_walls() -> void:
	var size := ChunkMath.playable_size()
	var max_h := GameConstants.TERRAIN_HEIGHT * (1.0 + GameConstants.ROCKY_HEIGHT_BOOST)
	var height := max_h * 3.0
	var y := max_h * 0.5
	var half_t := _WALL_THICKNESS * 0.5
	var walls := [
		[Vector3(-half_t, y, size * 0.5), Vector3(_WALL_THICKNESS, height, size)],
		[Vector3(size + half_t, y, size * 0.5), Vector3(_WALL_THICKNESS, height, size)],
		[Vector3(size * 0.5, y, -half_t), Vector3(size, height, _WALL_THICKNESS)],
		[Vector3(size * 0.5, y, size + half_t), Vector3(size, height, _WALL_THICKNESS)],
	]
	for w in walls:
		var body := StaticBody3D.new()
		body.name = "EdgeWall"
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = w[1]
		shape.shape = box
		body.add_child(shape)
		body.position = w[0]
		add_child(body)


func get_creature_manager() -> CreatureManager:
	return _creatures


func get_pack_sim() -> PackSim:
	return _pack_sim


func get_village_sim() -> VillageSim:
	return _village


func get_people_manager() -> PeopleManager:
	return _people


## Villages: the hourly VillageSim for every kingdom and the person nodes in loaded chunks.
func _add_people(scatter: PropScatter, library: ModelLibrary) -> void:
	_village = VillageSim.new()
	_village.name = "VillageSim"
	add_child(_village)
	_village.setup(_state, _gen, scatter, _day_night)
	_village.is_player_in = func(k: Dictionary) -> bool:
		return _state.kingdom_at(_player.global_position).get("id", -1) == k.id
	_people = PeopleManager.new()
	_people.name = "People"
	add_child(_people)
	_people.setup(_state, _gen, scatter, _streamer, library, _day_night, _village, _player)
	_people.message.connect(_hud.add_message)
	_creatures.creature_killed.connect(_people.on_creature_killed)
	_player.talk_target = _people.nearest_person
	_player.donate_handler = _people.donate
	_hud.set_people(_people)
	_village.player_pos = func() -> Variant: return _player.global_position
	_build.extra_blockers = func() -> Array:
		return _people.active_people().filter(func(n: Person) -> bool: return n.visible).map(
				func(n: Person) -> Vector3: return n.global_position)
