extends GameTest
## Living world (stage 9): the NPC kingdoms a new world starts with.

const B := GameConstants.Building
const P := GameConstants.Profession

var gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
var scatter := PropScatter.new(gen, GameConstants.WORLD_SEED)


func _seeded(avoid: Vector3) -> WorldState:
	var s := WorldState.new()
	s.seed = GameConstants.WORLD_SEED
	NpcRealms.seed(s, gen, scatter, [avoid])
	return s


func test_npc_kingdoms_are_placed_apart() -> void:
	var spawn := Vector3(380, 0, 380)
	var s := _seeded(spawn)
	assert_eq(s.kingdoms().size(), GameConstants.REALM_NPC_START)
	assert_true(s.realms_seeded)
	for k in s.kingdoms():
		assert_eq(String(k.founder), "npc")
		assert_true(PackSim._flat_dist(k.center, spawn) >= GameConstants.REALM_MIN_GAP, "too close to the player")
		var margin := GameConstants.KINGDOM_RADIUS
		assert_true(k.center.x >= margin and k.center.z >= margin and k.center.x <= ChunkMath.playable_size() - margin
				and k.center.z <= ChunkMath.playable_size() - margin, "off the map edge: %s" % k.center)
		for o in s.kingdoms():
			if o.id != k.id:
				assert_true(PackSim._flat_dist(k.center, o.center) >= GameConstants.REALM_MIN_GAP)


func test_npc_kingdom_has_a_village_and_people() -> void:
	var s := _seeded(Vector3(380, 0, 380))
	var k: Dictionary = s.kingdoms()[0]
	var seat := s.building(int(k.seat_id))
	assert_eq(int(seat.type), B.CABIN)
	assert_eq(int(seat.owner), GameConstants.OWNER_KINGDOM, "the player may not tear it down")
	var types := VillageRules.kingdom_buildings(s, k).map(func(b: Dictionary) -> int: return int(b.type))
	for t in [B.FLAG, B.CAMPFIRE, B.FARM, B.HOUSE]:
		assert_true(types.has(t), "missing %s" % GameConstants.BUILD_NAMES[t])
	var people := s.residents(k.id)
	assert_eq(people.size(), GameConstants.REALM_NPC_PEOPLE)
	assert_true(people.filter(func(p: Dictionary) -> bool: return int(p.home_id) >= 0).size() == people.size(),
			"everyone has a home")
	assert_true(people.filter(func(p: Dictionary) -> bool: return int(p.profession) == P.GUARD).size() >= 1)
	assert_eq(int(k.ruler_id), GameConstants.GOV_NOBODY, "the realm crowns its first ruler itself")
	assert_eq(int(k.people_ever), people.size())


func test_seeding_happens_once() -> void:
	var s := _seeded(Vector3(380, 0, 380))
	var n := s.kingdoms().size()
	NpcRealms.seed(s, gen, scatter, [])
	assert_eq(s.kingdoms().size(), n)


func test_npc_kingdom_crowns_a_ruler_on_its_own() -> void:
	var s := _seeded(Vector3(380, 0, 380))
	var sim := VillageSim.new()
	sim.setup(s, gen, scatter, null)
	sim.tick_hours(40.0)
	for k in s.kingdoms():
		assert_true(int(k.ruler_id) >= 0, "%s has no ruler after 40 h" % k.name)
	sim.free()


func test_names_match_who_they_are() -> void:
	var s := _seeded(Vector3(380, 0, 380))
	for p in s.all_people():
		var names: Array = GameConstants.FEMALE_NAMES if p.female else GameConstants.MALE_NAMES
		assert_true(names.has(p.name), "%s is %s" % [p.name, "a woman" if p.female else "a man"])
