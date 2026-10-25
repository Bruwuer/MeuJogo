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
	await _people()
	await _society()
	await _houses()
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


## Stage 7, nothing staged: the kingdom lives on its own. First the player is away for HISTORY_DAYS
## (everything is summarized), then comes back and watches LIVE_DAYS at high speed; a shot is taken
## whenever someone is carrying out a House deed. The whole ADM log is saved next to the shots.
func _houses() -> void:
	const HISTORY_DAYS := 12
	const LIVE_DAYS := 3
	const LIVE_SPEED := 8.0
	const MAX_DEED_SHOTS := 10
	if _village_spot.x < 0.0 or _home().is_empty():
		print("SKIPPED houses: no village")
		return
	var state := _world.get_state()
	var day_night := _world.get_day_night()
	var mgr := _world.get_people_manager()
	var hud := _world.get_hud()
	var k: Dictionary = _home()
	var hour_sec := GameConstants.DAY_LENGTH_SEC / 24.0

	# 0) The founder governs (stage 8): a low tax and a guard of two, by the panel (P).
	await _teleport(_village_spot + Vector3(0, 0, 10))
	await _physics(10)
	hud.toggle_gov()
	hud.gov_change(1) # tax: none -> low
	hud.gov_move(2)
	hud.gov_change(3) # guard: free -> 2
	await _frames(5)
	await _shot("44_gov_panel")
	hud.toggle_gov()
	print("GOV decrees %s" % [k.decrees])

	# 1) Away: the player walks off to a far corner; the days pass without anyone watching.
	var far := Vector3(GameConstants.CHUNK_SIZE * 2.0, 0, GameConstants.CHUNK_SIZE * 2.0)
	if far.distance_to(k.center) < GameConstants.CHUNK_SIZE * 8.0:
		far = Vector3(GameConstants.CHUNK_SIZE * (GameConstants.MAP_CHUNKS - 2), 0, GameConstants.CHUNK_SIZE * (GameConstants.MAP_CHUNKS - 2))
	await _teleport(far)
	await _frames(30)
	for h in HISTORY_DAYS * 24:
		day_night.advance(hour_sec)
		await process_frame
	print("HISTORY: %d days, %d chronicle entries" % [HISTORY_DAYS, state.chronicle_all(-2, 100000).size()])
	print("GOV away: ruler=%s way=%s corrupt=%s decrees=%s" % [hud.gov_line(k), k.ruler_way, k.ruler_corrupt, k.decrees])

	# 2) Back home, watching: one shot per deed in progress (doer framed), at most one per kind.
	await _teleport(_village_spot + Vector3(0, 0, 10))
	var shot_kinds := {}
	var shots := 0
	var end_hours := day_night.total_hours() + LIVE_DAYS * 24.0
	Engine.time_scale = LIVE_SPEED
	while day_night.total_hours() < end_hours and shots < MAX_DEED_SHOTS:
		await _physics(8)
		for n in mgr.active_people():
			var deed: Dictionary = n.record.get("deed", {})
			if deed.is_empty() or n.act != PersonBrain.Act.DEED or shot_kinds.has(deed.kind):
				continue
			shot_kinds[deed.kind] = true
			Engine.time_scale = 1.0
			var p := _world.get_player()
			var spot := _clear_spot_near(n.global_position)
			p.global_position = Vector3(spot.x, _world.get_generator().height_at(spot.x, spot.z) + 0.3, spot.z)
			p.reset_physics_interpolation()
			p.face(n.global_position - spot)
			_world.get_camera().snap_to_target()
			await _physics(2)
			shots += 1
			var hod := fmod(day_night.total_hours(), 24.0)
			print("DEED %s by %s at %02dh" % [deed.kind, PersonGen.full_name(n.record), floori(hod)])
			await _shot("%d_deed_%s" % [28 + shots, deed.kind])
			Engine.time_scale = LIVE_SPEED
			break
	Engine.time_scale = 1.0
	print("LIVE: deeds seen %s" % [shot_kinds.keys()])
	print("GOV back: %s" % hud.gov_adm_line(k))
	await _teleport(_village_spot + Vector3(0, 0, 10))
	await _physics(10)
	hud.toggle_gov()
	await _frames(5)
	await _shot("45_gov_return")
	hud.toggle_gov()

	# 3) What the Houses made of their land and homes, by themselves.
	_set_time(DAY_TIME)
	var built := state.all_buildings().filter(func(b: Dictionary) -> bool:
		return (b.type == GameConstants.Building.HOUSE and int(b.get("house_level", 0)) > 0) or b.has("upgrade"))
	var stakes := state.all_buildings().filter(func(b: Dictionary) -> bool: return b.type == GameConstants.Building.STAKE)
	var focus: Array = built + stakes
	if not focus.is_empty():
		await _teleport((focus[0].pos as Vector3) + Vector3(0, 0, 9))
		await _physics(30)
		await _shot("40_land_and_homes")
	else:
		print("NO land or home changes in %d days" % (HISTORY_DAYS + LIVE_DAYS))

	# 4) The ADM panels (dev keys F9/F10) and the player's plain HUD.
	await _teleport(_village_spot + Vector3(0, 0, 10))
	await _physics(30)
	await _shot("41_player_hud_only")
	hud.toggle_chronicle()
	await _physics(5)
	await _shot("42_adm_log")
	hud.toggle_chronicle()
	hud.toggle_families()
	await _physics(5)
	await _shot("43_adm_houses")
	hud.toggle_families()

	var lines: PackedStringArray = []
	for e in state.chronicle_all(-2, 100000):
		lines.append(AdminLog.line(state, e))
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT_DIR.path_join("adm_log.txt")), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	print("ADM LOG: %d lines" % lines.size())


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


## A spot a few metres from `pos` on the camera's side (so the doer is not hidden behind the
## player or a house), away from buildings, so the player never lands on a roof.
func _clear_spot_near(pos: Vector3) -> Vector3:
	var yaw := deg_to_rad(GameConstants.CAM_YAW_DEG)
	var cam_dir := Vector3(sin(yaw), 0.0, cos(yaw))
	for step in 12:
		var turn := deg_to_rad(30.0 * floorf((step + 1) / 2.0) * (1.0 if step % 2 == 0 else -1.0))
		var spot := pos + cam_dir.rotated(Vector3.UP, turn) * 3.5
		var clear := _world.get_state().all_buildings().all(func(b: Dictionary) -> bool:
			return Vector2(b.pos.x - spot.x, b.pos.z - spot.z).length() > 5.0)
		if clear:
			return spot
	return pos + cam_dir * 3.5


## The player's own kingdom (the world also has NPC kingdoms), or {}.
func _home() -> Dictionary:
	for k in _world.get_state().kingdoms():
		if String(k.founder) == "player":
			return k
	return {}


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


## Stage 5: a traveler walking in, villagers at work, a site rising, a person's card and the
## village at night (people at home and by the campfire). Packs are kept from raiding meanwhile.
func _people() -> void:
	const B := GameConstants.Building
	const P := GameConstants.Profession
	if _village_spot.x < 0.0 or _home().is_empty():
		print("SKIPPED people: no village")
		return
	var state := _world.get_state()
	var gen := _world.get_generator()
	var sim := _world.get_village_sim()
	var mgr := _world.get_people_manager()
	var scatter := PropScatter.new(gen, state.seed)
	var k: Dictionary = _home()
	k.next_traveler_hour = 1e9 # this script brings its own people
	var raid_hours := {}
	for pk in state.all_packs():
		raid_hours[pk.id] = pk.next_raid_hour
		pk.next_raid_hour = 1e9
	_set_time(DAY_TIME)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var seat := state.building(k.seat_id)
	var front := PeopleManager.door_of(seat)
	await _teleport(front + Vector3(1.5, 0, 6.0))
	var traveler := state.add_person(PersonGen.generate(rng, 0.0, P.FARMER), _ground(gen, front + Vector3(1, 0, 17)), k.id,
			sim.now_hours() + 100.0)
	await _physics(170)
	await _shot("18_traveler_arrives")

	# Residents with trades, a house for three of them, a farm and a site.
	state.add_stock(k, GameConstants.Res.WOOD, 30)
	state.add_stock(k, GameConstants.Res.STONE, 20)
	state.add_stock(k, GameConstants.Res.FOOD, 40)
	var trades := [P.WOODCUTTER, P.MASON, P.BUILDER, P.BUILDER, P.GATHERER, P.FARMER, P.BUILDER]
	var people: Array[Dictionary] = []
	for i in trades.size():
		var rec := state.add_person(PersonGen.generate(rng, 0.2, trades[i]), _ground(gen, front + Vector3(i - 3.0, 0, 2.5)), k.id)
		rec.status = "resident"
		k.people_ever += 1
		people.append(rec)
	var house_spot := VillageRules.pick_site(B.HOUSE, k, state, gen, scatter, [], rng)
	if house_spot.ok:
		var house := state.add_building(B.HOUSE, house_spot.pos, house_spot.rot, Color.WHITE, people[0].id)
		for i in 3:
			people[i].home_id = house.id
		_show(house)
	var farm_spot := VillageRules.pick_site(B.FARM, k, state, gen, scatter, [], rng)
	if farm_spot.ok:
		_show(state.add_building(B.FARM, farm_spot.pos, farm_spot.rot, Color.WHITE, GameConstants.OWNER_KINGDOM))
	var site: Dictionary = state.building(k.site_id)
	if site.is_empty():
		var site_spot := VillageRules.pick_site(B.HOUSE, k, state, gen, scatter, [], rng)
		if site_spot.ok:
			state.add_stock(k, GameConstants.Res.WOOD, 40)
			state.add_stock(k, GameConstants.Res.STONE, 10)
			site = state.add_site(B.HOUSE, site_spot.pos, site_spot.rot, k, sim.now_hours())
	print("PEOPLE house=%s farm=%s site=%s" % [house_spot.ok, farm_spot.ok, not site.is_empty()])
	if not site.is_empty():
		site.progress = maxf(float(site.get("progress", 0.0)), 0.35)
		_show(site)
		_world.get_streamer().get_chunk(ChunkMath.world_to_chunk(site.pos)).update_site(site)
	await _physics(600)
	var look: Vector3 = (front + (site.pos if not site.is_empty() else front)) * 0.5
	await _teleport(look + Vector3(1.5, 0, 6.0))
	await _physics(240)
	await _shot("19_village_working")
	if not site.is_empty():
		await _teleport(site.pos + Vector3(3.6, 0, 3.6))
		await _physics(120)
		await _shot("20_site_rising")
	else:
		print("SKIPPED 20_site_rising: no place for a site")

	# Talk to someone.
	var p := _world.get_player()
	var who := mgr.node_for(people[4].id)
	if who:
		await _teleport(who.global_position + Vector3(1.2, 0, 1.2))
		who.walk_to(who.global_position)
		p.face(who.global_position - p.global_position)
		p.interact()
		await _frames(10)
		await _shot("21_person_card")
	else:
		print("SKIPPED 21_person_card: no node")

	# Night: the house owners sleep inside, the others by the campfire.
	_set_time(0.92)
	var fire := front
	for b in VillageRules.kingdom_buildings(state, k):
		if b.type == B.CAMPFIRE:
			fire = b.pos
	await _teleport(fire + Vector3(1.5, 0, 6.0))
	await _physics(900)
	await _shot("22_village_night")
	_set_time(DAY_TIME)
	print("PEOPLE traveler=%s inside=%d" % [traveler.status, people.filter(func(r: Dictionary) -> bool: return int(r.inside) >= 0).size()])
	for i in 3:
		var n := mgr.node_for(people[i].id)
		var h := state.building(people[i].home_id)
		print("PEOPLE owner %d home=%d node=%s pos=%s door=%s act=%s goal=%s target=%s" % [i, people[i].home_id, n != null, n.global_position if n else Vector3.ZERO, PeopleManager.door_of(h) if not h.is_empty() else Vector3.ZERO, n.act if n else -1, n.goal if n else -1, n.target_pos if n else Vector3.ZERO])
	for pk in state.all_packs():
		pk.next_raid_hour = raid_hours.get(pk.id, 0.0)


func _show(rec: Dictionary) -> void:
	var chunk := _world.get_streamer().get_chunk(ChunkMath.world_to_chunk(rec.pos))
	if chunk:
		chunk.add_building(rec)


## Stage 6: a family (couple + children) by its house with the crest banner, the card of the
## mother, crests on several houses, the families panel (C), a member breaking away (new crest on
## his house) and the allies/enemies news (gift and theft).
func _society() -> void:
	const B := GameConstants.Building
	const P := GameConstants.Profession
	const T := GameConstants.Trait
	if _village_spot.x < 0.0 or _home().is_empty():
		print("SKIPPED society: no village")
		return
	var state := _world.get_state()
	var gen := _world.get_generator()
	var sim := _world.get_village_sim()
	var mgr := _world.get_people_manager()
	var hud := _world.get_hud()
	var p := _world.get_player()
	var scatter := PropScatter.new(gen, state.seed)
	var k: Dictionary = _home()
	k.next_traveler_hour = 1e9
	var raid_hours := {}
	for pk in state.all_packs():
		raid_hours[pk.id] = pk.next_raid_hour
		pk.next_raid_hour = 1e9
	_set_time(DAY_TIME)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	sim.society.tick_hour(k, sim.now_hours()) # every resident gets a family

	# The family: Ana and Bento, married, with two children, in their own house.
	var mom := state.add_person(PersonGen.generate(rng, 0.3, P.FARMER), _ground(gen, k.center), k.id)
	var dad := state.add_person(PersonGen.generate(rng, 0.3, P.BUILDER), _ground(gen, k.center), k.id)
	mom.merge({name = "Ana", surname = "Ferreira", female = true, age = 34.0, status = "resident",
			traits = [T.SOCIABLE, T.WORKER]}, true)
	dad.merge({name = "Bento", surname = "do Vale", female = false, age = 36.0, status = "resident",
			traits = [T.WORKER, T.BRAVE]}, true)
	var fam := state.add_family("Ferreira", Crest.generate(rng, []), k.id, mom.id, sim.now_hours())
	var kids: Array[Dictionary] = []
	for age in [7.0, 3.0]:
		var c := state.add_person(PersonGen.child(mom, dad, "Ferreira", rng, kids.map(func(x: Dictionary) -> String: return x.name)),
				_ground(gen, k.center), k.id)
		c.merge({status = "resident", age = age, parents = [mom.id, dad.id]}, true)
		kids.append(c)
	for x in [mom, dad] + kids:
		x.family_id = fam.id
	mom.spouse_id = dad.id
	dad.spouse_id = mom.id
	var spot := VillageRules.pick_site(B.HOUSE, k, state, gen, scatter, [p.global_position], rng)
	var house := {}
	if spot.ok:
		# The door faces the camera (it never turns) when the place allows it.
		var yaw := deg_to_rad(GameConstants.CAM_YAW_DEG)
		var rot := VillageRules._rot_facing(Vector3(sin(yaw), 0.0, cos(yaw)))
		if not BuildRules.check_site(B.HOUSE, spot.pos, rot, gen, scatter, state, [p.global_position]).ok:
			rot = spot.rot
		house = state.add_building(B.HOUSE, spot.pos, rot, Color.WHITE, mom.id)
		_show(house)
		for x in [mom, dad] + kids:
			x.home_id = house.id
	# A friend and a rival for Ana's card.
	var others := state.residents(k.id).filter(func(x: Dictionary) -> bool: return x.family_id != fam.id and SocietyRules.is_adult(x))
	if others.size() >= 2:
		state.set_relation(mom.id, others[0].id, 0.6)
		state.set_relation(mom.id, others[1].id, -0.6)
	mom.opinion = 0.7
	mom.stance = "ally"
	mgr.refresh_crests()
	print("SOCIETY house=%s families=%d" % [spot.ok, state.families_of(k.id).size()])
	await _physics(30)
	if not house.is_empty():
		var door := PeopleManager.door_of(house)
		var out: Vector3 = (door - house.pos).normalized()
		var side := out.cross(Vector3.UP)
		var people := [mom, dad] + kids
		var spots: Array[Vector3] = []
		for i in people.size():
			spots.append(_ground(gen, door + out * 1.2 + side * (i - 1.5) * 0.9))
			state.move_person(people[i].id, spots[i])
		await _teleport(door + out * 6.0 + side * 2.0)
		for f in 120: # the nodes appear where the records are
			if people.all(func(x: Dictionary) -> bool: return mgr.node_for(x.id) != null):
				break
			await _frames(1)
		for i in people.size():
			var n := mgr.node_for(people[i].id)
			if n:
				n.global_position = spots[i]
				n.reset_physics_interpolation()
				n.walk_to(spots[i])
				n.rotation.y = atan2(out.x, out.z)
		await _physics(40)
		await _shot("24_couple_children")
		var mn := mgr.node_for(mom.id)
		if mn:
			await _teleport(spots[0] + out * 1.4)
			p.face(spots[0] - p.global_position)
			p.interact()
			await _frames(10)
			await _shot("23_family_card")
			hud.hide_card()
	else:
		print("SKIPPED 23/24: no place for the family's house")

	# Crests on the houses of several families.
	var houses := VillageRules.kingdom_buildings(state, k).filter(func(b: Dictionary) -> bool:
		return b.type == B.HOUSE and not b.get("site", false))
	var center := Vector3.ZERO
	for b in houses:
		center += b.pos
		if int(b.owner) < 0 or state.person(b.owner).is_empty():
			var someone := state.residents(k.id).filter(func(x: Dictionary) -> bool: return SocietyRules.is_adult(x) and x.family_id != fam.id)
			if not someone.is_empty():
				b.owner = someone[0].id
				someone[0].home_id = b.id
	mgr.refresh_crests()
	if not houses.is_empty():
		# Frame the family's house with the house nearest to it (two crests side by side).
		var a: Dictionary = house if not house.is_empty() else houses[0]
		var b := a
		var best := INF
		for h in houses:
			var d := Vector2(h.pos.x - a.pos.x, h.pos.z - a.pos.z).length()
			if h.id != a.id and d < best:
				best = d
				b = h
		var yaw := deg_to_rad(GameConstants.CAM_YAW_DEG)
		await _teleport((a.pos + b.pos) * 0.5 + Vector3(sin(yaw), 0.0, cos(yaw)) * 2.0)
		await _physics(30)
		await _shot("25_house_crests")
	hud.toggle_families()
	await _frames(10)
	await _shot("26_families_panel")
	hud.toggle_families()

	# A rival of Ana breaks away from the Casa Ferreira and founds his own house.
	var other_house := {}
	for b in houses:
		if b.id != house.get("id", -1):
			other_house = b
	if not other_house.is_empty():
		var martim := state.add_person(PersonGen.generate(rng, 0.0, P.MASON), _ground(gen, PeopleManager.door_of(other_house)), k.id)
		martim.merge({name = "Martim", surname = "Ferreira", female = false, age = 24.0, status = "resident",
				family_id = fam.id, home_id = other_house.id, traits = [T.LAZY, T.GREEDY]}, true)
		other_house.owner = martim.id
		mgr.refresh_crests()
		var cam_dir := Vector3(sin(deg_to_rad(GameConstants.CAM_YAW_DEG)), 0.0, cos(deg_to_rad(GameConstants.CAM_YAW_DEG)))
		await _teleport(other_house.pos + cam_dir * 4.5)
		await _physics(30)
		state.set_relation(martim.id, mom.id, -0.9)
		fam.last_split_hour = -1e9
		sim.society.tick_hour(k, sim.now_hours())
		await _physics(30)
		print("SOCIETY split martim family=%s" % state.family(martim.family_id).get("surname", "?"))
		await _shot("27_family_split")
	else:
		print("SKIPPED 27_family_split: one house only")

	# Allies and enemies: a gift from the Casa Ferreira, a theft by an enemy.
	for x in state.family_members(fam.id):
		x.opinion = 0.8
	fam.stance = ""
	fam.deed_day = -1
	var foe := state.residents(k.id).filter(func(x: Dictionary) -> bool: return x.family_id != fam.id and SocietyRules.is_adult(x))
	if not foe.is_empty():
		foe[0].opinion = -0.9
		foe[0].stance = ""
		foe[0].deed_day = -1
	state.add_stock(k, GameConstants.Res.WOOD, 30)
	_set_time(0.45)
	sim.society.tick_hour(k, floorf(sim.now_hours()))
	await _frames(10)
	await _shot("28_allies_enemies")
	_set_time(DAY_TIME)
	for pk in state.all_packs():
		pk.next_raid_hour = raid_hours.get(pk.id, 0.0)
