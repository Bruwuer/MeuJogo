extends GameTest

const B := GameConstants.Building
const R := GameConstants.Res
const P := GameConstants.Profession

var state: WorldState
var gen: TerrainGenerator
var scatter: PropScatter
var lib: ModelLibrary
var streamer: ChunkStreamer
var packs: PackSim
var creatures: CreatureManager
var sim: VillageSim
var mgr: PeopleManager
var player: Node3D
var kingdom: Dictionary


## World with a kingdom at a flat clear spot (seat cabin); returns the kingdom center.
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
	packs = PackSim.new()
	add_child(packs)
	packs.setup(state, null)
	player = Node3D.new()
	add_child(player)
	var spot := TestSpots.flat_clear(gen, scatter, B.CABIN, 8.0, center)
	player.global_position = spot + Vector3(0, 0.5, -30)
	for c in ChunkMath.chunks_in_radius(ChunkMath.world_to_chunk(spot), 4):
		state.mark_visited(c) # no random creatures
	creatures = CreatureManager.new()
	add_child(creatures)
	creatures.setup(state, gen, scatter, streamer, lib, null, packs, player)
	var seat := state.add_building(B.CABIN, spot, 0)
	kingdom = state.add_kingdom("Teste", Color.RED, seat.pos, seat.id)
	kingdom.next_traveler_hour = 1e9 # no travelers unless a test wants them
	sim = VillageSim.new()
	add_child(sim)
	sim.setup(state, gen, scatter, null)
	sim.clock_hours = 8.0
	mgr = PeopleManager.new()
	add_child(mgr)
	mgr.setup(state, gen, scatter, streamer, lib, null, sim, player)
	return spot


func _resident(profession: int, pos: Vector3, seed_value := 1) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var p := state.add_person(PersonGen.generate(r, 0.0, profession), pos, kingdom.id)
	p.status = "resident"
	p.traits = [GameConstants.Trait.WORKER, GameConstants.Trait.BRAVE]
	kingdom.people_ever += 1
	return p


func _load_around(pos: Vector3) -> void:
	streamer.update_center(pos)
	for i in 900:
		await get_tree().process_frame
		if _all_loaded(pos) and lib.is_ready():
			break
	await wait_physics_frames(2)
	assert_true(_all_loaded(pos), "chunks never loaded around %s" % pos)
	for i in 120:
		if mgr.pending_spawns() == 0 and creatures.pending_spawns() == 0:
			break
		await get_tree().process_frame


func _all_loaded(pos: Vector3) -> bool:
	for c in ChunkMath.chunks_in_radius(ChunkMath.world_to_chunk(pos), GameConstants.LOAD_RADIUS):
		if ChunkMath.is_in_world(c) and not streamer.is_loaded(c):
			return false
	return true


## Runs physics (4x speed) until `done` is true or `frames` pass. Returns whether it got there.
func _run_until(done: Callable, frames: int) -> bool:
	Engine.time_scale = 4.0
	var ok := false
	for i in frames:
		await get_tree().physics_frame
		if done.call():
			ok = true
			break
	Engine.time_scale = 1.0
	return ok


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func test_spawns_people_in_loaded_chunks() -> void:
	var spot := _make()
	var a := _resident(P.BUILDER, spot + Vector3(3, 0.3, 5), 1)
	var far := _resident(P.BUILDER, spot + Vector3(300, 0.3, 300), 2)
	await _load_around(spot)
	assert_true(mgr.node_for(a.id) != null, "a person in a loaded chunk has a node")
	assert_true(mgr.node_for(far.id) == null, "far away: no node")
	assert_true(sim.has_node.call(a.id) and not sim.has_node.call(far.id), "the sim knows who is live")


func test_woodcutter_cuts_real_tree_and_deposits() -> void:
	var spot := _make()
	kingdom.stock = { R.FOOD: 50 }
	var p := _resident(P.WOODCUTTER, spot + Vector3(2, 0.3, 5))
	await _load_around(spot)
	var ok: bool = await _run_until(func() -> bool: return state.stock_of(kingdom, R.WOOD) >= 3, 3600)
	assert_true(ok, "the woodcutter brought wood (job %s, act %d)" % [p.job, mgr.node_for(p.id).act if mgr.node_for(p.id) else -1])
	var removed := 0
	for c in ChunkMath.chunks_in_radius(ChunkMath.world_to_chunk(spot), 2):
		removed += state.removed_in(c).size()
	assert_true(removed >= 1, "a real tree was cut")
	assert_true((p.carrying as Dictionary).is_empty(), "deposited everything")


func test_builders_finish_site() -> void:
	var spot := _make()
	kingdom.stock = { R.WOOD: 100, R.FOOD: 50 }
	var place := VillageRules.pick_site(B.FARM, kingdom, state, gen, scatter, [], RandomNumberGenerator.new())
	assert_true(place.ok)
	var site := state.add_site(B.FARM, place.pos, place.rot, kingdom, 0.0)
	for i in 3:
		_resident(P.BUILDER, spot + Vector3(i, 0.3, 5), i + 1)
	await _load_around(spot)
	var chunk := streamer.get_chunk(ChunkMath.world_to_chunk(site.pos))
	assert_true(chunk.get_node_or_null("B_%d" % site.id).get_node_or_null("Scaffold") != null, "site shown")
	var ok: bool = await _run_until(func() -> bool: return not state.building(site.id).get("site", false), 4000)
	assert_true(ok, "builders finished the farm (progress %.2f)" % float(state.building(site.id).get("progress", 1.0)))
	var node := chunk.get_node_or_null("B_%d" % site.id)
	assert_true(node != null and node.get_node_or_null("Scaffold") == null, "the chunk shows the finished farm")


func test_house_gets_owner_and_resident() -> void:
	var spot := _make()
	kingdom.stock = { R.WOOD: 100, R.STONE: 50, R.FOOD: 50 }
	var place := VillageRules.pick_site(B.HOUSE, kingdom, state, gen, scatter, [], RandomNumberGenerator.new())
	var site := state.add_site(B.HOUSE, place.pos, place.rot, kingdom, 0.0)
	site.progress = 0.96
	var a := _resident(P.BUILDER, spot + Vector3(1, 0.3, 5), 1)
	var b := _resident(P.BUILDER, spot + Vector3(2, 0.3, 5), 2)
	var texts: Array[String] = []
	mgr.message.connect(func(t: String) -> void: texts.append(t))
	sim.is_kingdom_loaded = func(_k: Dictionary) -> bool: return true
	await _load_around(spot)
	var ok: bool = await _run_until(func() -> bool: return not state.building(site.id).get("site", false), 2400)
	assert_true(ok, "house finished")
	assert_eq(state.building(site.id).owner, a.id)
	assert_eq(a.home_id, site.id)
	assert_eq(b.home_id, site.id)
	assert_true(texts.any(func(t: String) -> bool: return t.contains(PersonGen.full_name(a))), "message: %s" % str(texts))


func test_unload_deposits_carried() -> void:
	var spot := _make()
	kingdom.stock = {}
	var p := _resident(P.MERCHANT, spot + Vector3(2, 0.3, 5))
	await _load_around(spot)
	assert_true(mgr.node_for(p.id) != null)
	p.carrying = { R.STONE: 2 }
	var far := spot + Vector3(400, 0, 400)
	player.global_position = far
	streamer.update_center(far)
	for i in 600:
		await get_tree().process_frame
		if mgr.node_for(p.id) == null:
			break
	assert_true(mgr.node_for(p.id) == null, "node freed with its chunk")
	assert_eq(state.stock_of(kingdom, R.STONE), 2, "what it carried went to the stock")
	assert_true((p.carrying as Dictionary).is_empty())


func test_people_sleep_inside_at_night() -> void:
	var spot := _make()
	kingdom.stock = { R.FOOD: 50 }
	var house := state.add_building(B.HOUSE, spot + Vector3(12, 0, 0), 3, Color.WHITE, GameConstants.OWNER_KINGDOM)
	house.pos.y = gen.height_at(house.pos.x, house.pos.z)
	var p := _resident(P.MERCHANT, spot + Vector3(2, 0.3, 6))
	p.home_id = house.id
	var homeless := _resident(P.MERCHANT, spot + Vector3(-2, 0.3, 6), 2)
	sim.clock_hours = 22.0
	await _load_around(spot)
	var ok: bool = await _run_until(func() -> bool: return int(p.inside) == house.id, 2400)
	assert_true(ok, "went home to sleep")
	assert_true(mgr.node_for(p.id) != null and not mgr.node_for(p.id).visible, "inside: hidden")
	var n := mgr.node_for(homeless.id)
	assert_true(n != null and n.visible, "the homeless sleeps outside")
	sim.clock_hours = 31.0 # 7h next morning
	await _run_until(func() -> bool: return int(p.inside) == -1, 200)
	assert_eq(int(p.inside), -1, "wakes up and leaves the house")


func test_person_flees_wolf() -> void:
	var spot := _make()
	var p := _resident(P.MERCHANT, spot + Vector3(0, 0.3, 8))
	var pack := state.add_pack("lobo", spot + Vector3(40, 0, 40))
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var wolf := state.add_creature(Genome.random("lobo", r), spot + Vector3(4, 0.3, 8), pack.id)
	await _load_around(spot)
	var n := mgr.node_for(p.id)
	assert_true(n != null)
	if n == null:
		return
	var ok: bool = await _run_until(func() -> bool: return n.act == PersonBrain.Act.FLEE, 120)
	assert_true(ok, "flees from the wolf")
	await _run_until(func() -> bool: return false, 60)
	var w := creatures.node_for(wolf.id)
	if w:
		assert_true(_flat(n.global_position, spot + Vector3(4, 0, 8)) > 5.0, "ran away")


func test_herbivore_flees_person() -> void:
	var spot := _make()
	_resident(P.MERCHANT, spot + Vector3(0, 0.3, 8))
	var pack := state.add_pack("cervo", spot + Vector3(40, 0, 40))
	var r := RandomNumberGenerator.new()
	r.seed = 6
	var deer := state.add_creature(Genome.random("cervo", r), spot + Vector3(3, 0.3, 8), pack.id)
	await _load_around(spot)
	var c := creatures.node_for(deer.id)
	assert_true(c != null)
	if c == null:
		return
	var ok: bool = await _run_until(func() -> bool: return c.state == CreatureBrain.State.FLEE, 120)
	assert_true(ok, "the deer runs from a person")


func test_sites_not_raided() -> void:
	var spot := _make()
	kingdom.stock = { R.WOOD: 100, R.STONE: 50 }
	var place := VillageRules.pick_site(B.HOUSE, kingdom, state, gen, scatter, [], RandomNumberGenerator.new())
	var site := state.add_site(B.HOUSE, place.pos, place.rot, kingdom, 0.0)
	var pack := state.add_pack("lobo", spot + Vector3(30, 0, 30))
	var r := RandomNumberGenerator.new()
	r.seed = 7
	state.add_creature(Genome.random("lobo", r), pack.den, pack.id)
	pack.raid_kingdom = kingdom.id
	await _load_around(spot)
	var target := creatures._raid_target(pack, site.pos)
	assert_true(target.is_empty() or target.id != site.id, "raiders ignore sites")
	packs.resolve_offscreen_raid(pack, kingdom)
	assert_true(not state.building(site.id).is_empty() and state.building_hp(site.id) >= GameConstants.BUILD_HP[B.HOUSE],
			"offscreen raids skip sites")
	pack.raid_kingdom = -1
	pack.hunger = 1.0
	pack.next_raid_hour = -1.0
	packs.is_night_override = true
	packs.tick_hours(1.0)
	if pack.raid_kingdom == kingdom.id:
		assert_true(float(kingdom.last_raid_hour) > -1.0, "the kingdom remembers the raid")


func test_frame_budget_people_and_creatures() -> void:
	var spot := _make()
	kingdom.stock = { R.FOOD: 500 }
	for i in GameConstants.PEOPLE_MAX_ACTIVE + 5:
		_resident(i % P.size(), spot + Vector3((i % 6) * 2.0 - 6.0, 0.3, 6.0 + (i / 6) * 2.0), i + 1)
	var pack := state.add_pack("cervo", spot + Vector3(0, 0, -20))
	for i in GameConstants.CREATURE_MAX_ACTIVE:
		var r := RandomNumberGenerator.new()
		r.seed = 100 + i
		state.add_creature(Genome.random("cervo", r), spot + Vector3((i % 8) * 3.0 - 12.0, 0.3, -20.0 - (i / 8) * 3.0), pack.id)
	await _load_around(spot)
	await wait_frames(30)
	assert_eq(mgr.active_count(), GameConstants.PEOPLE_MAX_ACTIVE, "people cap")
	var t0 := Time.get_ticks_usec()
	await wait_physics_frames(60)
	var avg_ms := (Time.get_ticks_usec() - t0) / 60.0 / 1000.0
	assert_true(avg_ms < GameConstants.MAX_FRAME_MS, "%.1f ms per physics frame with %d people and %d creatures"
			% [avg_ms, mgr.active_count(), creatures.active_count()])


func test_person_gets_around_seat_corner() -> void:
	# Seen in the captures: people wedged at the seat cabin's front corner, next to the flag.
	var spot := _make()
	var seat := state.building(kingdom.seat_id)
	state.add_building(B.FLAG, seat.pos + GameConstants.FLAG_OFFSET, 0, Color.RED)
	await _load_around(spot)
	var r := RandomNumberGenerator.new()
	r.seed = 4
	var rec := PersonGen.generate(r)
	rec.merge({id = 999, pos = seat.pos + Vector3(1.95, 0.3, 2.8), status = "resident", carrying = {}, home_id = -1,
			inside = -1, job = ""}, true)
	var p := Person.new()
	add_child(p)
	p.setup(rec, lib, null)
	var goal: Vector3 = seat.pos + Vector3(4.5, 0, -8.55)
	p.walk_to(goal)
	var ok: bool = await _run_until(func() -> bool: return _flat(p.global_position, goal) < GameConstants.PERSON_ARRIVE, 1200)
	assert_true(ok, "stuck at %s" % str(p.global_position - seat.pos))
	p.queue_free()


func test_finished_site_pushes_people_out() -> void:
	var spot := _make()
	kingdom.stock = { R.WOOD: 100, R.STONE: 50, R.FOOD: 50 }
	var place := VillageRules.pick_site(B.HOUSE, kingdom, state, gen, scatter, [], RandomNumberGenerator.new())
	var site := state.add_site(B.HOUSE, place.pos, place.rot, kingdom, 0.0)
	var p := _resident(P.MERCHANT, place.pos + Vector3(0.5, 0.6, 0.5))
	await _load_around(spot)
	var n := mgr.node_for(p.id)
	assert_true(n != null)
	if n == null:
		return
	n.walk_to(n.global_position)
	await wait_physics_frames(5)
	sim.work_on_site(site.id, 100.0)
	await wait_physics_frames(3)
	var rect := BuildRules.footprint_rect(B.HOUSE, site.pos, site.rot)
	assert_true(not BuildRules.circle_hits_rect(Vector2(n.global_position.x, n.global_position.z), GameConstants.PERSON_RADIUS, rect),
			"stepped out of the finished house (%s)" % str(n.global_position))
