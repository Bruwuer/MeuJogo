extends SceneTree
## Windowed visual check: runs the main scene with a fixed world and spawn (no save), visits
## each biome, harvests a tree, shows night and dusk, and saves screenshots to captures/.
## Usage: tools/capture.ps1

const MAIN_SCENE := "res://scenes/main.tscn"
const OUT_DIR := "res://captures"
const SPAWN_SEED := 42
const DAY_TIME := 0.42

var _world: World
var _worst_ms := 0.0
var _segment_ms := 0.0
var _last_usec := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for f in DirAccess.get_files_at(OUT_DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OUT_DIR.path_join(f)))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_world = load(MAIN_SCENE).instantiate()
	_world.spawn_seed = SPAWN_SEED
	_world.world_seed = GameConstants.WORLD_SEED
	_world.save_path = ""
	root.add_child(_world)
	await _settle()
	_set_time(DAY_TIME)
	_last_usec = Time.get_ticks_usec()
	await _frames(30) # warm-up: first frames compile shaders
	_worst_ms = 0.0
	_segment_ms = 0.0
	await _shot("01_spawn")
	await _hold(["move_up"], 60)
	await _shot("02_walk")
	_release_all()

	var scatter := PropScatter.new(_world.get_generator(), _world.get_state().seed)
	var forest := _richest_chunk(scatter, [GameConstants.Prop.OAK, GameConstants.Prop.PINE])
	var oak := _first_prop(scatter, forest, GameConstants.Prop.OAK)
	await _teleport(oak.pos + Vector3(1.3, 0, 0.4))
	await _frames(20)
	await _shot("03_forest")
	for i in GameConstants.HARVEST_HITS[GameConstants.Prop.OAK]:
		Input.action_press("interact")
		await _physics(3)
		Input.action_release("interact")
		if i == 0:
			await _shot("04_harvest_swing")
		await _physics(int(GameConstants.HARVEST_HIT_TIME * Engine.physics_ticks_per_second) + 2)
	await _frames(20)
	await _shot("05_tree_cut")

	_set_time(0.02)
	await _frames(20)
	await _shot("06_night")

	var rocky := _richest_chunk(scatter, [GameConstants.Prop.ROCK])
	var rock := _first_prop(scatter, rocky, GameConstants.Prop.ROCK)
	_set_time(DAY_TIME)
	await _teleport(rock.pos + Vector3(2.2, 0, 1.0))
	await _frames(20)
	await _shot("07_rocky")
	_set_time(0.735)
	await _frames(20)
	await _shot("08_dusk")
	print("WORST_FRAME_MS %.1f" % _worst_ms)
	print("WOOD %d" % _world.get_state().get_resource(GameConstants.Res.WOOD))
	quit(0)


func _set_time(t: float) -> void:
	_world.get_day_night().time_of_day = t
	_world.get_day_night().apply()


func _settle() -> void:
	while not _world.is_world_ready() or _world.get_streamer().pending_count() > 0:
		await process_frame


func _teleport(pos: Vector3) -> void:
	var p := _world.get_player()
	p.global_position = Vector3(pos.x, _world.get_generator().height_at(pos.x, pos.z) + 0.3, pos.z)
	p.reset_physics_interpolation()
	_world.get_camera().snap_to_target()
	await _physics(2)
	await _settle()
	_last_usec = Time.get_ticks_usec() # teleport loads a whole new area at once; not gameplay


func _richest_chunk(scatter: PropScatter, types: Array) -> Vector2i:
	var best := Vector2i(GameConstants.MAP_CHUNKS / 2, GameConstants.MAP_CHUNKS / 2)
	var best_n := -1
	for cy in range(2, GameConstants.MAP_CHUNKS - 2):
		for cx in range(2, GameConstants.MAP_CHUNKS - 2):
			var n := scatter.build_chunk_props(Vector2i(cx, cy)).filter(
					func(p: Dictionary) -> bool: return types.has(p.type)).size()
			if n > best_n:
				best_n = n
				best = Vector2i(cx, cy)
	return best


func _first_prop(scatter: PropScatter, c: Vector2i, type: int) -> Dictionary:
	for p in scatter.build_chunk_props(c):
		if p.type == type:
			return p
	return scatter.build_chunk_props(c)[0]


func _hold(actions: Array, n: int) -> void:
	_release_all()
	for a in actions:
		Input.action_press(a)
	await _physics(n)


func _release_all() -> void:
	for a in ["move_up", "move_down", "move_left", "move_right", "run", "interact"]:
		Input.action_release(a)


func _physics(n: int) -> void:
	for i in n:
		await physics_frame
		_track()


func _frames(n: int) -> void:
	for i in n:
		await process_frame
		_track()


func _track() -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last_usec) / 1000.0
	_worst_ms = maxf(_worst_ms, ms)
	_segment_ms = maxf(_segment_ms, ms)
	_last_usec = now


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(OUT_DIR.path_join(shot_name + ".png"))
	root.get_texture().get_image().save_png(path)
	print("CAPTURED ", path, "  worst_since_last=%.1f ms" % _segment_ms)
	_segment_ms = 0.0
	_last_usec = Time.get_ticks_usec() # exclude readback + PNG encode from frame timing
