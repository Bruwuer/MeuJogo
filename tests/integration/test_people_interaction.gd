extends GameTest

const B := GameConstants.Building
const R := GameConstants.Res
const P := GameConstants.Profession

var state: WorldState
var gen: TerrainGenerator
var scatter: PropScatter
var lib: ModelLibrary
var streamer: ChunkStreamer
var harvest: HarvestSystem
var day_night: DayNight
var sim: VillageSim
var mgr: PeopleManager
var player: Player
var hud: Hud
var kingdom: Dictionary


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
	harvest = HarvestSystem.new()
	harvest.setup(streamer.get_chunk, state)
	add_child(harvest)
	day_night = DayNight.new()
	var sun := DirectionalLight3D.new()
	add_child(sun)
	day_night.setup(sun, Environment.new(), ProceduralSkyMaterial.new())
	add_child(day_night)
	day_night.set_process(false)
	day_night.time_of_day = 0.5
	var spot := TestSpots.flat_clear(gen, scatter, B.CABIN, 8.0, center)
	var seat := state.add_building(B.CABIN, spot, 0)
	kingdom = state.add_kingdom("Teste", Color.RED, seat.pos, seat.id)
	kingdom.next_traveler_hour = 1e9
	kingdom.stock = {}
	player = load("res://scenes/player.tscn").instantiate()
	player.harvest = harvest
	player.state = state
	add_child(player)
	player.global_position = spot + Vector3(0, 0.3, 6)
	sim = VillageSim.new()
	add_child(sim)
	sim.setup(state, gen, scatter, day_night)
	sim.set_process(false)
	mgr = PeopleManager.new()
	add_child(mgr)
	mgr.setup(state, gen, scatter, streamer, lib, day_night, sim, player)
	player.talk_target = mgr.nearest_person
	player.donate_handler = mgr.donate
	hud = Hud.new()
	add_child(hud)
	hud.setup(state, harvest, day_night, player)
	hud.set_people(mgr)
	return spot


func _resident(profession: int, pos: Vector3, seed_value := 1) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var p := state.add_person(PersonGen.generate(r, 0.0, profession), pos, kingdom.id)
	p.status = "resident"
	p.opinion = 0.0
	kingdom.people_ever += 1
	return p


func _load_around(pos: Vector3) -> void:
	streamer.update_center(pos)
	for i in 900:
		await get_tree().process_frame
		if lib.is_ready() and streamer.pending_count() == 0 and streamer.is_loaded(ChunkMath.world_to_chunk(pos)):
			break
	player.frozen = false
	for i in 120:
		await get_tree().process_frame
		if mgr.pending_spawns() == 0:
			break
	await wait_physics_frames(3)


## Keeps a person still next to the player (no brain).
func _hold(id: int, at: Vector3) -> Person:
	var n := mgr.node_for(id)
	if n:
		n.global_position = at
		n.walk_to(at)
	return n


func test_talk_shows_card() -> void:
	var spot := _make()
	var p := _resident(P.FARMER, spot + Vector3(1.2, 0.3, 6))
	await _load_around(spot)
	_hold(p.id, player.global_position + Vector3(1.2, 0, 0))
	await wait_physics_frames(2)
	assert_true(hud.prompt_text().contains(p.name), "prompt names the person: %s" % hud.prompt_text())
	var heard: Array = []
	player.talked.connect(func(n: Person) -> void: heard.append(n))
	player.interact()
	assert_eq(heard.size(), 1, "talked")
	assert_true(hud.card_visible(), "card shown")
	var text := hud.card_text()
	assert_true(text.contains(PersonGen.full_name(p)) and text.contains("%d anos" % p.age), text)
	assert_true(text.contains(PersonGen.profession_name(p).capitalize()) or text.contains(PersonGen.profession_name(p)), text)
	for t in p.traits:
		assert_true(text.contains(PersonGen.trait_name(p, t)), "trait in the card: %s" % text)
	assert_true(text.contains(GameConstants.OPINION_TEXTS[2]), "neutral opinion line: %s" % text)
	await get_tree().create_timer(GameConstants.PERSON_CARD_SEC + 0.3).timeout
	assert_true(not hud.card_visible(), "card goes away")


func test_talk_has_priority_over_harvest() -> void:
	var spot := _make()
	var p := _resident(P.FARMER, spot + Vector3(1.2, 0.3, 6))
	await _load_around(spot)
	# a tree right next to the player
	var tree := {}
	var best := INF
	for c in streamer.loaded_coords():
		var chunk := streamer.get_chunk(c)
		for id in chunk.prop_ids():
			var pr := chunk.get_prop(id)
			if pr.type in [GameConstants.Prop.OAK, GameConstants.Prop.PINE]:
				var d := Vector2(pr.pos.x - spot.x, pr.pos.z - spot.z).length()
				if d < best:
					best = d
					tree = pr
	assert_true(not tree.is_empty())
	var stand: Vector3 = tree.pos + Vector3(GameConstants.PROP_COLLISION_RADIUS[tree.type] * tree.scale + 0.8, 0, 0)
	stand.y = gen.height_at(stand.x, stand.z) + 0.2
	player.global_position = stand
	_hold(p.id, stand + Vector3(0, 0, 1.0))
	await wait_physics_frames(3)
	var target := harvest.find_target(player.global_position)
	assert_true(not target.is_empty(), "the tree is in reach")
	var heard: Array = []
	player.talked.connect(func(n: Person) -> void: heard.append(n))
	player.interact()
	assert_eq(heard.size(), 1, "talks instead of chopping")
	assert_eq(harvest.hits_on(target), 0, "no hit on the tree")


func test_donate_moves_resources_and_raises_opinion() -> void:
	var spot := _make()
	var near := _resident(P.FARMER, spot + Vector3(2, 0.3, 6), 1)
	var far := _resident(P.FARMER, spot + Vector3(30, 0.3, -30), 2)
	state.add_resource(R.WOOD, 30)
	state.add_resource(R.STONE, 4)
	await _load_around(spot)
	var texts: Array[String] = []
	player.message.connect(func(t: String) -> void: texts.append(t))
	player.donate()
	assert_eq(state.stock_of(kingdom, R.WOOD), GameConstants.DONATE_MAX)
	assert_eq(state.stock_of(kingdom, R.STONE), 4)
	assert_eq(state.get_resource(R.WOOD), 30 - GameConstants.DONATE_MAX)
	assert_eq(state.get_resource(R.STONE), 0)
	assert_near(near.opinion, GameConstants.DONATE_OPINION, 0.0001, "the people around saw it")
	assert_near(far.opinion, 0.0, 0.0001)
	assert_true(texts.size() == 1 and texts[0].contains("Teste"), "message: %s" % str(texts))
	player.global_position = spot + Vector3(300, 0, 300)
	player.donate()
	assert_eq(state.get_resource(R.WOOD), 30 - GameConstants.DONATE_MAX, "outside a kingdom nothing moves")


func test_village_line_in_hud() -> void:
	var spot := _make()
	_resident(P.FARMER, spot + Vector3(2, 0.3, 6))
	kingdom.stock = { R.WOOD: 12, R.FOOD: 8 }
	await _load_around(spot)
	await wait_physics_frames(2)
	assert_true(hud.village_visible())
	var text := hud.village_text()
	assert_true(text.contains("Moradores: 1") and text.contains("Madeira 12") and text.contains("Comida 8"), text)
	player.global_position = spot + Vector3(300, 50, 300)
	await wait_physics_frames(2)
	assert_true(not hud.village_visible(), "only inside a kingdom")


func test_protecting_raises_opinion() -> void:
	var spot := _make()
	var a := _resident(P.FARMER, spot + Vector3(30, 0.3, 30), 1)
	var pack := state.add_pack("lobo", spot + Vector3(60, 0, 60))
	pack.raid_kingdom = kingdom.id
	var r := RandomNumberGenerator.new()
	r.seed = 3
	var wolf := state.add_creature(Genome.random("lobo", r), spot + Vector3(5, 0, 5), pack.id)
	mgr.on_creature_killed(wolf, true)
	assert_near(a.opinion, GameConstants.PROTECT_OPINION, 0.0001, "everyone hears about it")
	mgr.on_creature_killed(wolf, false)
	assert_near(a.opinion, GameConstants.PROTECT_OPINION, 0.0001, "only the player's kills count")
