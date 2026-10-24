extends GameTest

var state: WorldState
var gen: TerrainGenerator
var scatter: PropScatter
var lib: ModelLibrary
var streamer: ChunkStreamer
var sim: PackSim
var mgr: CreatureManager
var player: Node3D


func _make(center := Vector2(200, 200)) -> Vector3:
	state = WorldState.new()
	state.seed = GameConstants.WORLD_SEED
	gen = TerrainGenerator.new(state.seed)
	scatter = PropScatter.new(gen, state.seed)
	lib = ModelLibrary.new()
	add_child(lib)
	lib.start_loading()
	streamer = ChunkStreamer.new()
	streamer.setup(gen, scatter, lib, state.removed_in, state.buildings_in)
	add_child(streamer)
	sim = PackSim.new()
	add_child(sim)
	sim.setup(state, null)
	player = Node3D.new()
	add_child(player)
	var spot := TestSpots.flat_clear(gen, scatter, GameConstants.Building.FENCE, 6.0, center)
	player.global_position = spot + Vector3(0, 0.5, 0)
	mgr = CreatureManager.new()
	add_child(mgr)
	mgr.setup(state, gen, scatter, streamer, lib, null, sim, player)
	return spot


func _load_around(pos: Vector3) -> void:
	streamer.update_center(pos)
	for i in 900:
		await get_tree().process_frame
		if _all_loaded(pos):
			break
	await wait_physics_frames(2)
	assert_true(_all_loaded(pos), "chunks never loaded around %s" % pos)
	await wait_frames(2)
	for i in 120:
		if mgr.pending_spawns() == 0:
			break
		await get_tree().process_frame


func _all_loaded(pos: Vector3) -> bool:
	for c in ChunkMath.chunks_in_radius(ChunkMath.world_to_chunk(pos), GameConstants.LOAD_RADIUS):
		if ChunkMath.is_in_world(c) and not streamer.is_loaded(c):
			return false
	return true


func _genome(species: String, s: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return Genome.random(species, r)


## A pack placed by hand (no random spawn) next to `pos`; returns its records.
func _pack_at(species: String, pos: Vector3, count: int, seed_base := 100) -> Dictionary:
	var p := state.add_pack(species, pos)
	for i in count:
		var rec := state.add_creature(_genome(species, seed_base + i), pos + Vector3(i * 1.5, 0.3, 0), p.id)
		if i == 0:
			p.leader_id = rec.id
	return p


func _ids() -> Array:
	var ids := state.all_creatures().map(func(c: Dictionary) -> int: return c.id)
	ids.sort()
	return ids


func test_spawns_on_first_visit_only() -> void:
	var spot := _make()
	await _load_around(spot)
	var c := ChunkMath.world_to_chunk(spot)
	assert_true(state.visited(c), "loaded chunk not marked visited")
	var first := _ids()
	assert_true(first.size() > 0, "no creature spawned around %s" % spot)
	var far := spot + Vector3(300, 0, 0)
	await _load_around(far)
	var after_far := state.all_creatures().filter(func(r: Dictionary) -> bool:
		return first.has(r.id)).size()
	assert_eq(after_far, first.size(), "creatures lost while away")
	await _load_around(spot)
	var again := state.all_creatures().filter(func(r: Dictionary) -> bool:
		return ChunkMath.world_to_chunk(r.pos).distance_to(c) <= 2).size()
	assert_true(again <= first.size() + 2, "chunks respawned their packs on the second visit")


func test_creatures_survive_chunk_reload() -> void:
	var spot := _make()
	state.mark_visited(ChunkMath.world_to_chunk(spot)) # only the hand-placed pack in this chunk
	for c in ChunkMath.chunks_in_radius(ChunkMath.world_to_chunk(spot), 4):
		state.mark_visited(c)
	var p := _pack_at("lobo", spot, 3)
	await _load_around(spot)
	assert_eq(mgr.active_count(), 3)
	var node := mgr.node_for(state.pack_members(p.id)[0].id)
	assert_true(node != null, "no node for a record in a loaded chunk")
	await wait_physics_frames(30)
	await _load_around(spot + Vector3(400, 0, 0))
	await wait_frames(5)
	assert_eq(mgr.active_count(), 0, "nodes kept for unloaded chunks")
	assert_eq(state.pack_members(p.id).size(), 3, "records lost on unload")
	await _load_around(spot)
	assert_eq(mgr.active_count(), 3, "creatures did not come back")
	for rec in state.pack_members(p.id):
		var n := mgr.node_for(rec.id)
		assert_true(n != null)
		if n:
			assert_true(absf(n.global_position.y - gen.height_at(n.global_position.x, n.global_position.z)) < 1.0,
					"creature not on the ground after reload")


func test_first_wolves_near_spawn() -> void:
	var spot := _make()
	while not lib.is_ready(): # never leave a threaded load running
		await get_tree().process_frame
	var p := mgr.ensure_first_wolves(spot)
	assert_eq(p.species, "lobo")
	var d := Vector2(p.den.x - spot.x, p.den.z - spot.z).length()
	assert_true(d >= GameConstants.FIRST_WOLVES_DISTANCE.x - 0.1 and d <= GameConstants.FIRST_WOLVES_DISTANCE.y + 0.1, "wolves at %f m" % d)
	assert_true(state.pack_members(p.id).size() >= 3)
	assert_eq(p.hunger, 0.0)
	assert_eq(p.grudge, 0.0)


func test_breeding_makes_cub_with_parent_parts() -> void:
	var spot := _make()
	for c in ChunkMath.chunks_in_radius(ChunkMath.world_to_chunk(spot), 4):
		state.mark_visited(c)
	var p := state.add_pack("lobo", spot)
	var a := state.add_creature(_genome("lobo", 1), spot + Vector3(0, 0.3, 0), p.id)
	var b := state.add_creature(_genome("uivante", 2), spot + Vector3(1.0, 0.3, 0), p.id)
	await _load_around(spot)
	var cub := {}
	for i in 200:
		var made := mgr.breed_tick()
		if not made.is_empty():
			cub = made[0]
			break
	assert_true(not cub.is_empty(), "two calm adults never bred")
	if cub.is_empty():
		return
	assert_eq(cub.age, 0.0)
	assert_eq(cub.pack_id, p.id)
	assert_eq(Genome.display_name(cub.genome), "Lobo-uivante")
	for gene in Genome.PART_GENES:
		var from_parent: bool = cub.genome[gene] == a.genome[gene] or cub.genome[gene] == b.genome[gene]
		assert_true(from_parent or cub.genome.generation == 1, "gene %s" % gene)
	await wait_physics_frames(2)
	var n := mgr.node_for(cub.id)
	assert_true(n != null and n.is_cub(), "cub has no node")
	assert_true(mgr.breed_tick().is_empty(), "parents bred again right away")


func test_population_cap() -> void:
	var spot := _make()
	for c in ChunkMath.chunks_in_radius(ChunkMath.world_to_chunk(spot), 4):
		state.mark_visited(c)
	var cap := GameConstants.POPULATION_CAP_PER_CHUNK * 9
	var p := state.add_pack("cervo", spot)
	for i in cap:
		state.add_creature(_genome("cervo", i), spot + Vector3((i % 6) * 1.2, 0.3, (i / 6) * 1.2), p.id)
	await _load_around(spot)
	for i in 100:
		mgr.breed_tick()
	assert_eq(state.all_creatures().size(), cap, "bred past the population cap")


func test_kill_raises_grudge() -> void:
	var spot := _make()
	for c in ChunkMath.chunks_in_radius(ChunkMath.world_to_chunk(spot), 4):
		state.mark_visited(c)
	player.add_to_group("player")
	var p := _pack_at("lobo", spot + Vector3(30, 0, 0), 3)
	await _load_around(spot)
	var kills := []
	mgr.creature_killed.connect(func(rec: Dictionary, by_player: bool) -> void: kills.append(by_player))
	var victim := state.pack_members(p.id)[1]
	var node := mgr.node_for(victim.id)
	node.health.damage(1000.0, player)
	assert_eq(kills, [true])
	assert_true(p.grudge > 0.0, "killing a wolf should anger the pack")
	assert_eq(state.creature(victim.id), {}, "dead record kept")


func test_live_raid_damages_building() -> void:
	var spot := _make()
	for c in ChunkMath.chunks_in_radius(ChunkMath.world_to_chunk(spot), 4):
		state.mark_visited(c)
	var cabin := state.add_building(GameConstants.Building.CABIN, spot + Vector3(-12, 0, 0), 0)
	var fence := state.add_building(GameConstants.Building.FENCE, spot, 0)
	state.add_kingdom("Valdemar", Color.RED, cabin.pos, cabin.id)
	var p := _pack_at("lobo", spot + Vector3(0, 0, 14), 4)
	p.hunger = 1.0
	player.global_position = spot + Vector3(-60, 0, 0) # far from the wolves
	await _load_around(spot)
	var texts := []
	mgr.message.connect(func(t: String) -> void: texts.append(t))
	sim.is_night_override = true
	mgr.is_night_override = true
	sim.tick_hours(1.0)
	assert_eq(p.raid_kingdom, 1, "starving wolves did not raid the loaded kingdom")
	assert_true(texts.size() > 0 and (texts[0] as String).contains("famintos"), "no raid message: %s" % [texts])
	Engine.time_scale = 4.0
	for i in 1800:
		await get_tree().physics_frame
		if state.building(fence.id).is_empty():
			break
	Engine.time_scale = 1.0
	assert_true(state.building(fence.id).is_empty() or state.building_hp(fence.id) < GameConstants.BUILD_HP[GameConstants.Building.FENCE],
			"raiders never hurt the fence")
	assert_true(not state.building(cabin.id).is_empty(), "the seat fell")


func test_active_cap_and_frame_budget() -> void:
	var spot := _make()
	for c in ChunkMath.chunks_in_radius(ChunkMath.world_to_chunk(spot), 4):
		state.mark_visited(c)
	var p := state.add_pack("cervo", spot)
	for i in GameConstants.CREATURE_MAX_ACTIVE + 15:
		state.add_creature(_genome("cervo", i), spot + Vector3((i % 8) * 3.0 - 12.0, 0.3, (i / 8) * 3.0 - 12.0), p.id)
	await _load_around(spot)
	await wait_frames(10)
	assert_eq(mgr.active_count(), GameConstants.CREATURE_MAX_ACTIVE)
	var t0 := Time.get_ticks_usec()
	await wait_physics_frames(60)
	var avg_ms := (Time.get_ticks_usec() - t0) / 60.0 / 1000.0
	assert_true(avg_ms < GameConstants.MAX_FRAME_MS, "%.1f ms per physics frame with %d creatures" % [avg_ms, mgr.active_count()])


func test_node_freed_elsewhere_is_recreated() -> void:
	var spot := _make()
	for c in ChunkMath.chunks_in_radius(ChunkMath.world_to_chunk(spot), 4):
		state.mark_visited(c)
	var p := _pack_at("cervo", spot, 2)
	await _load_around(spot)
	var rec := state.pack_members(p.id)[0]
	mgr.node_for(rec.id).free()
	await get_tree().create_timer(0.8).timeout
	await wait_frames(5)
	assert_true(not state.creature(rec.id).is_empty(), "record lost")
	assert_true(is_instance_valid(mgr.node_for(rec.id)), "node not recreated: active %d pending %d chunk loaded %s pos %s" % [mgr.active_count(), mgr.pending_spawns(), streamer.is_loaded(ChunkMath.world_to_chunk(state.creature(rec.id).pos)), state.creature(rec.id).pos])
