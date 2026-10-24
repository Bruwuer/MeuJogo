extends GameTest

const B := GameConstants.Building
const P := GameConstants.Profession

var state: WorldState
var gen: TerrainGenerator
var scatter: PropScatter
var lib: ModelLibrary
var streamer: ChunkStreamer
var sim: VillageSim
var mgr: PeopleManager
var player: Node3D
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
	player = Node3D.new()
	add_child(player)
	var spot := TestSpots.flat_clear(gen, scatter, B.CABIN, 8.0, center)
	player.global_position = spot + Vector3(0, 0.5, -30)
	var seat := state.add_building(B.CABIN, spot, 0)
	kingdom = state.add_kingdom("Teste", Color.RED, seat.pos, seat.id)
	kingdom.next_traveler_hour = 1e9
	sim = VillageSim.new()
	add_child(sim)
	sim.setup(state, gen, scatter, null)
	sim.set_process(false)
	sim.clock_hours = 12.0
	mgr = PeopleManager.new()
	add_child(mgr)
	mgr.setup(state, gen, scatter, streamer, lib, null, sim, player)
	return spot


func _resident(pos: Vector3, seed_value: int, age := 30.0) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var p := state.add_person(PersonGen.generate(r, 0.0, P.MERCHANT), pos, kingdom.id)
	p.status = "resident"
	p.age = age
	return p


func _family(p: Dictionary, crest_seed: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = crest_seed
	var f := state.add_family(p.surname, Crest.generate(r, []), kingdom.id, p.id, 0.0)
	p.family_id = f.id
	return f


func _load_around(pos: Vector3) -> void:
	streamer.update_center(pos)
	for i in 900:
		await get_tree().process_frame
		if lib.is_ready() and streamer.pending_count() == 0 and streamer.is_loaded(ChunkMath.world_to_chunk(pos)):
			break
	for i in 120:
		await get_tree().process_frame
		if mgr.pending_spawns() == 0:
			break


func _banner_material(rec: Dictionary) -> Material:
	var chunk := streamer.get_chunk(ChunkMath.world_to_chunk(rec.pos))
	var node := chunk.building_node(rec.id) if chunk else null
	var banner := node.get_node_or_null("Crest") if node else null
	if banner == null:
		return null
	for mi: MeshInstance3D in banner.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_material(s).resource_name == "crest":
				return mi.get_surface_override_material(s)
	return null


func test_banner_on_owned_house() -> void:
	var spot := _make()
	var p := _resident(spot + Vector3(0, 0, 6), 1)
	var f := _family(p, 5)
	var house := state.add_building(B.HOUSE, spot + Vector3(12, 0, 0), 0, Color.WHITE, p.id)
	await _load_around(spot)
	mgr.refresh_crests()
	assert_eq(_banner_material(house), Crest.material(f.crest), "the owner's family crest")
	var chunk := streamer.get_chunk(ChunkMath.world_to_chunk(house.pos))
	var banner: Node3D = chunk.building_node(house.id).get_node("Crest")
	var fp: Vector2 = GameConstants.BUILD_FOOTPRINT[B.HOUSE]
	assert_true(banner.position.x > fp.x * 0.5 and banner.position.z > 0.0, "beside the front corner, outside the walls")


func test_banner_follows_owner_family() -> void:
	var spot := _make()
	var p := _resident(spot + Vector3(0, 0, 6), 1)
	_family(p, 5)
	var house := state.add_building(B.HOUSE, spot + Vector3(12, 0, 0), 0, Color.WHITE, p.id)
	await _load_around(spot)
	mgr.refresh_crests()
	var g := _family(p, 6) # the owner broke away
	sim.families_changed.emit()
	assert_eq(_banner_material(house), Crest.material(g.crest), "new crest")
	house.owner = GameConstants.OWNER_KINGDOM
	await get_tree().create_timer(GameConstants.PEOPLE_SYNC_SEC + 0.3).timeout
	assert_eq(_banner_material(house), null, "no owner, no banner (refreshed by the sync)")


func test_child_node_smaller() -> void:
	var spot := _make()
	var adult := _resident(spot + Vector3(1, 0, 6), 1)
	var kid := _resident(spot + Vector3(-1, 0, 6), 2, 4.0)
	await _load_around(spot)
	var na := mgr.node_for(adult.id)
	var nk := mgr.node_for(kid.id)
	assert_true(na != null and nk != null, "both have nodes")
	if na == null or nk == null:
		return
	assert_near(nk.model_scale(), Person.body_scale(kid), 0.001)
	assert_true(nk.model_scale() < na.model_scale() * 0.8, "a child is small")
	kid.age = GameConstants.ADULT_AGE
	await get_tree().create_timer(GameConstants.PERSON_BRAIN_TICK * 2.0).timeout
	assert_near(nk.model_scale(), float(kid.looks.height), 0.001, "grown up")


func test_birth_spawns_node_and_death_frees_it() -> void:
	var spot := _make()
	var mom := _resident(spot + Vector3(1, 0, 6), 1)
	await _load_around(spot)
	var baby := state.add_person(PersonGen.child(mom, mom, mom.surname, RandomNumberGenerator.new(), []),
			mom.pos, kingdom.id)
	baby.status = "resident"
	sim.person_born.emit(baby)
	for i in 30:
		await get_tree().process_frame
		if mgr.node_for(baby.id):
			break
	assert_true(mgr.node_for(baby.id) != null, "the newborn appears")
	var n := mgr.node_for(mom.id)
	sim.person_died.emit(mom)
	state.remove_person(mom.id)
	await get_tree().process_frame
	assert_true(not is_instance_valid(n) or n.is_queued_for_deletion(), "the dead person's node goes")
	assert_eq(mgr.node_for(mom.id), null)
