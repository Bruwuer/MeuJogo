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
var _village_spot := Vector3(-1, -1, -1)


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

	await _village(scatter)
	await _creatures(scatter)
	print("WORST_FRAME_MS %.1f" % _worst_ms)
	print("WOOD %d" % _world.get_state().get_resource(GameConstants.Res.WOOD))
	quit(0)


## Stage 3: ghost previews, founding a kingdom and a small village by day and night.
func _village(scatter: PropScatter) -> void:
	const B := GameConstants.Building
	var gen := _world.get_generator()
	var state := _world.get_state()
	var build := _world.get_build()
	build.use_mouse = false
	state.add_resource(GameConstants.Res.WOOD, 400)
	state.add_resource(GameConstants.Res.STONE, 400)
	var spot := _flat_area(gen, 9.0)
	_village_spot = spot
	if spot.x < 0.0:
		print("SKIPPED village: no flat area")
		return
	_set_time(DAY_TIME)
	await _teleport(spot + Vector3(0, 0, -3))
	_clear_area(scatter, spot, 13.0) # the player cleared the land first
	_world.get_player().face(Vector3(0, 0, 1)) # axis-aligned ghost in front of the player
	await _ghost_at(spot)
	build.select(B.CABIN)
	await _frames(10)
	await _shot("09_ghost_ok")
	build.try_place()
	await _frames(10)
	await _shot("10_ghost_blocked")
	var layout := [
		[B.STORAGE, Vector3(7.0, 0, 0.5), 0],
		[B.WELL, Vector3(-5.5, 0, 3.5), 0],
		[B.CAMPFIRE, Vector3(0.0, 0, 6.0), 0],
		[B.FENCE, Vector3(-7.5, 0, -2.0), 1],
		[B.FENCE, Vector3(-7.5, 0, -5.0), 1],
		[B.FENCE, Vector3(-6.0, 0, -6.5), 0],
		[B.FENCE, Vector3(-3.0, 0, -6.5), 0],
	]
	for item in layout:
		build.select(item[0])
		build.rot = item[2]
		await _ghost_at(spot + item[1])
		if not build.try_place():
			print("SKIPPED %s: %s" % [GameConstants.BUILD_NAMES[item[0]], build.preview().reason])
	build.rot = 0
	build.toggle()
	await _teleport(spot + Vector3(2.5, 0, 9.0))
	await _frames(20)
	await _shot("11_village_day")
	_set_time(0.03)
	await _frames(20)
	await _shot("12_village_night")
	_set_time(DAY_TIME)


## Stage 4: the first wolves, a hybrid with its parents, sword and bow, and a raid with a motive.
func _creatures(scatter: PropScatter) -> void:
	var state := _world.get_state()
	var mgr := _world.get_creature_manager()
	var p := _world.get_player()
	_set_time(DAY_TIME)
	var wolves := state.pack(1)
	if not wolves.is_empty() and wolves.species == "lobo":
		await _teleport(wolves.den + Vector3(-5, 0, -5))
		await _frames(60)
		await _shot("13_first_wolves")

	# A hybrid cub between its parents, in a cleared plain away from the village.
	var gen := _world.get_generator()
	var spot := _village_spot + Vector3(0, 0, 40)
	_clear_area(scatter, spot, 10.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pack := state.add_pack("lobo", spot)
	var dad := Genome.random("lobo", rng)
	var mom := Genome.random("uivante", rng)
	var cub := Genome.cross(dad, mom, rng)
	var recs := [
		state.add_creature(dad, _ground(gen, spot + Vector3(-2.2, 0, 0)), pack.id),
		state.add_creature(mom, _ground(gen, spot + Vector3(2.2, 0, 0)), pack.id),
		state.add_creature(cub, _ground(gen, spot + Vector3(0, 0, 1.2)), pack.id, 0.5),
	]
	await _teleport(spot + Vector3(0, 0, -4))
	await _frames(30)
	for r in recs:
		var n := mgr.node_for(r.id)
		if n:
			n.command(CreatureBrain.State.SLEEP, n.global_position)
			n.rotation.y = PI
	await _frames(10)
	await _shot("14_hybrid_family")
	for r in recs:
		var n := mgr.node_for(r.id)
		if n:
			n.queue_free()
		state.remove_creature(r.id)

	# Sword swing at a wolf, then an arrow in flight.
	var foe := state.add_creature(Genome.random("lobo", rng), _ground(gen, spot + Vector3(0, 0, 1.8)), pack.id)
	await _teleport(spot)
	p.face(Vector3(0, 0, 1))
	await _frames(20)
	var wolf := mgr.node_for(foe.id)
	if wolf:
		wolf.command(CreatureBrain.State.SLEEP, wolf.global_position)
		wolf.rotation.y = PI
	p.select_weapon(GameConstants.Weapon.SWORD)
	p.attack()
	await _physics(int(GameConstants.WEAPONS[GameConstants.Weapon.SWORD].hit_time * Engine.physics_ticks_per_second * 0.6))
	await _shot("15_sword_swing")
	await _physics(40)
	p.select_weapon(GameConstants.Weapon.BOW)
	state.add_resource(GameConstants.Res.ARROWS, 5)
	p.face(Vector3(1, 0, 0))
	await _frames(5)
	p.attack()
	await _physics(int((GameConstants.WEAPONS[GameConstants.Weapon.BOW].hit_time + 0.12) * Engine.physics_ticks_per_second))
	await _shot("16_arrow_flight")
	await _physics(60)
	p.select_weapon(GameConstants.Weapon.SWORD)

	# Starving wolves raid the village at night; the HUD tells why.
	if _village_spot.x < 0.0:
		print("SKIPPED raid: no village")
		return
	var raiders := state.add_pack("lobo", _village_spot + Vector3(0, 0, 26))
	for i in 4:
		state.add_creature(Genome.random("lobo", rng), _ground(gen, raiders.den + Vector3(i * 1.5, 0, 0)), raiders.id)
	raiders.hunger = 1.0
	await _teleport(_village_spot + Vector3(2.5, 0, 9.0))
	_set_time(0.03)
	await _frames(30)
	var sim := _world.get_pack_sim()
	sim.tick_hours(1.0)
	await _physics(240)
	await _shot("17_raid_night")
	_set_time(DAY_TIME)


func _ground(gen: TerrainGenerator, pos: Vector3) -> Vector3:
	return Vector3(pos.x, gen.height_at(pos.x, pos.z) + 0.3, pos.z)


## Center of a square of half-size `half` whose ground varies less than 1 m, or (-1,-1,-1).
func _flat_area(gen: TerrainGenerator, half: float) -> Vector3:
	for z in range(60, 700, 8):
		for x in range(60, 700, 8):
			var lo := INF
			var hi := -INF
			for dz in [-half, -half * 0.5, 0.0, half * 0.5, half]:
				for dx in [-half, -half * 0.5, 0.0, half * 0.5, half]:
					var h := gen.height_at(x + dx, z + dz)
					lo = minf(lo, h)
					hi = maxf(hi, h)
			if hi - lo < 1.0 and gen.biome_at(x, z) == GameConstants.Biome.PLAINS:
				return Vector3(x, gen.height_at(x, z), z)
	return Vector3(-1, -1, -1)


func _clear_area(scatter: PropScatter, center: Vector3, radius: float) -> void:
	for p in scatter.props_near(center, radius):
		var c := ChunkMath.world_to_chunk(p.pos)
		_world.get_state().mark_removed(c, p.id)
		var chunk := _world.get_streamer().get_chunk(c)
		if chunk:
			chunk.remove_prop(p.id)


func _ghost_at(target: Vector3) -> void:
	var p := _world.get_player()
	await _teleport(target - p.facing() * GameConstants.BUILD_GHOST_DISTANCE)


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
