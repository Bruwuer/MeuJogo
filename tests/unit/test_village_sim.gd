extends GameTest

const B := GameConstants.Building
const R := GameConstants.Res
const T := GameConstants.Trait
const P := GameConstants.Profession

var _gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
var _scatter := PropScatter.new(_gen, GameConstants.WORLD_SEED)


func _setup(loaded := true) -> Array:
	var s := WorldState.new()
	s.seed = GameConstants.WORLD_SEED
	var center := TestSpots.flat_clear(_gen, _scatter, B.CABIN, 8.0, Vector2(200, 200))
	var seat := s.add_building(B.CABIN, center, 0)
	var k := s.add_kingdom("Teste", Color.RED, seat.pos, seat.id)
	var sim := VillageSim.new()
	add_child(sim)
	sim.setup(s, _gen, _scatter, null)
	sim.clock_hours = 8.0 # morning of day 0
	sim.is_kingdom_loaded = func(_k: Dictionary) -> bool: return loaded
	return [s, k, sim]


func _resident(s: WorldState, k: Dictionary, profession: int, seed := 1) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var p := s.add_person(PersonGen.generate(r, 0.0, profession), k.center + Vector3(2, 0, 4), k.id)
	p.status = "resident"
	p.traits = [T.WORKER, T.BRAVE]
	k.people_ever += 1
	return p


func _travelers(s: WorldState) -> Array[Dictionary]:
	return s.all_people().filter(func(p: Dictionary) -> bool: return p.status == "traveler")


func test_first_traveler_after_founding() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	sim.has_node = func(_id: int) -> bool: return true # keep the traveler walking (no auto-arrival)
	var spawned: Array = []
	sim.traveler_spawned.connect(func(rec: Dictionary) -> void: spawned.append(rec))
	sim.tick_hours(1.0)
	sim.tick_hours(GameConstants.TRAVELER_FIRST_HOURS)
	assert_eq(spawned.size(), 1, "one traveler soon after founding")
	if spawned.is_empty():
		return
	var p: Dictionary = spawned[0]
	assert_eq(p.status, "traveler")
	assert_eq(p.kingdom_id, k.id)
	var d := Vector2(p.pos.x - k.center.x, p.pos.z - k.center.z).length()
	assert_true(d >= GameConstants.TRAVELER_DISTANCE.x - 1.0 and d <= GameConstants.TRAVELER_DISTANCE.y + 1.0,
			"spawns 60-90 m away (%.1f)" % d)
	assert_eq(s.all_people().size(), 1)


func test_traveler_interval_and_cap() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	sim.has_node = func(_id: int) -> bool: return true
	var count := [0]
	sim.traveler_spawned.connect(func(_r: Dictionary) -> void: count[0] += 1)
	for i in 25:
		sim.tick_hours(1.0)
	var expected := 1 + int((24.0 - GameConstants.TRAVELER_FIRST_HOURS) / GameConstants.TRAVELER_INTERVAL_HOURS)
	assert_true(absi(count[0] - expected) <= 1, "about one every %d h (%d)" % [GameConstants.TRAVELER_INTERVAL_HOURS, count[0]])
	for p in s.all_people():
		s.remove_person(p.id)
	for i in GameConstants.KINGDOM_MAX_PEOPLE:
		_resident(s, k, P.WOODCUTTER, i + 10)
	count[0] = 0
	for i in 24:
		sim.tick_hours(1.0)
	assert_eq(count[0], 0, "a full kingdom gets no travelers")


func test_new_kingdom_grows() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	var opened := [0]
	sim.site_opened.connect(func(_r: Dictionary) -> void: opened[0] += 1)
	for i in 72:
		sim.tick_hours(1.0)
	assert_true(s.residents(k.id).size() >= 3, "three days: at least 3 residents (%d)" % s.residents(k.id).size())
	assert_true(opened[0] >= 1, "the villagers started building")


func test_hungry_people_leave_with_reason() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	sim.has_node = func(_id: int) -> bool: return true # no travelers arriving; residents' work is live
	k.next_traveler_hour = 1e9
	k.stock = {}
	var p := _resident(s, k, P.MERCHANT)
	var texts: Array[String] = []
	sim.message.connect(func(t: String) -> void: texts.append(t))
	var left: Array = []
	sim.person_left.connect(func(rec: Dictionary) -> void: left.append(rec))
	for i in 96:
		sim.tick_hours(1.0)
	assert_eq(left.size(), 1, "starving: leaves")
	assert_true(s.residents(k.id).is_empty())
	var found := false
	for t in texts:
		if t.contains(p.name) and t.contains(GameConstants.LEAVE_REASONS_PAST.hunger):
			found = true
	assert_true(found, "message says why: %s" % str(texts))


func test_opens_site_and_reserves_stock() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	k.next_traveler_hour = 1e9
	k.stock = { R.WOOD: 100, R.STONE: 50, R.FOOD: 50 }
	_resident(s, k, P.BUILDER)
	var opened: Array = []
	sim.site_opened.connect(func(r: Dictionary) -> void: opened.append(r))
	sim.tick_hours(1.0)
	assert_eq(opened.size(), 1)
	if opened.is_empty():
		return
	assert_eq(opened[0].type, B.HOUSE, "a homeless resident: a house")
	assert_eq(k.site_id, opened[0].id)
	assert_eq(s.stock_of(k, R.WOOD), 100 - GameConstants.BUILD_COST[B.HOUSE][R.WOOD], "cost reserved")
	assert_true(s.building(opened[0].id).get("site", false))
	sim.tick_hours(1.0)
	assert_eq(opened.size(), 1, "one site at a time")


func test_offscreen_work_builds_site() -> void:
	var a := _setup(false)
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	k.next_traveler_hour = 1e9
	k.stock = { R.WOOD: 100, R.STONE: 50, R.FOOD: 50 }
	var p1 := _resident(s, k, P.BUILDER, 1)
	var p2 := _resident(s, k, P.BUILDER, 2)
	var finished: Array = []
	sim.site_finished.connect(func(r: Dictionary) -> void: finished.append(r))
	for i in 10:
		sim.tick_hours(1.0)
	assert_true(finished.size() >= 1 and finished[0].type == B.HOUSE, "two builders finish a house in 4 work hours")
	if finished.is_empty():
		return
	var house := s.building(finished[0].id)
	assert_true(not house.get("site", false))
	assert_eq(house.owner, p1.id, "the first homeless signs it")
	assert_eq(p1.home_id, house.id)
	assert_eq(p2.home_id, house.id, "room for three")
	var texts := s.chronicle(k.id, 50).map(func(e: Dictionary) -> String: return e.text)
	assert_true(texts.any(func(t: String) -> bool: return t.contains(PersonGen.full_name(p1))), "the log names the owner")


func test_offscreen_only_for_nodeless() -> void:
	var a := _setup(false)
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	k.next_traveler_hour = 1e9
	k.stock = { R.WOOD: 100, R.STONE: 50, R.FOOD: 50 }
	var p := _resident(s, k, P.BUILDER)
	sim.has_node = func(id: int) -> bool: return id == p.id
	sim.tick_hours(1.0)
	var site := s.building(k.site_id)
	assert_true(not site.is_empty())
	for i in 5:
		sim.tick_hours(1.0)
	assert_near(float(s.building(k.site_id).progress), 0.0, 0.0001, "a person with a node works for real, not here")


func test_offscreen_harvest_removes_props() -> void:
	var a := _setup(false)
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	k.next_traveler_hour = 1e9
	k.stock = { R.FOOD: 50 }
	_resident(s, k, P.WOODCUTTER)
	var removed: Array = []
	sim.prop_removed.connect(func(c: Vector2i, id: int) -> void: removed.append([c, id]))
	for i in 6:
		sim.tick_hours(1.0)
	assert_true(s.stock_of(k, R.WOOD) >= 9, "about 2 wood an hour (%d)" % s.stock_of(k, R.WOOD))
	assert_true(removed.size() >= 3, "real trees were cut")
	if removed.is_empty():
		return
	assert_true(s.removed_in(removed[0][0]).has(removed[0][1]), "cut trees go to the save")
	var prop := {}
	for pr in _scatter.props_near(k.center, GameConstants.VILLAGE_HARVEST_RADIUS):
		if pr.id == removed[0][1] and ChunkMath.world_to_chunk(pr.pos) == removed[0][0]:
			prop = pr
	assert_true(not prop.is_empty() and prop.type in [GameConstants.Prop.OAK, GameConstants.Prop.PINE], "a tree near the kingdom")


func test_news_logged_when_unloaded() -> void:
	var a := _setup(false)
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	for i in 3:
		sim.tick_hours(1.0)
	assert_true(not s.chronicle(k.id, 10).is_empty(), "the traveler's decision is in the ADM log even far away")
	assert_eq(s.residents(k.id).size(), 1, "the founder stayed")


func test_stalled_site_abandoned() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	k.next_traveler_hour = 1e9
	k.stock = { R.WOOD: 100, R.STONE: 50, R.FOOD: 500 }
	var p := _resident(s, k, P.BUILDER)
	sim.has_node = func(_id: int) -> bool: return true # live, but nobody works on it
	sim.tick_hours(1.0)
	var id: int = k.site_id
	assert_true(id >= 0)
	for i in int(GameConstants.SITE_STALL_HOURS) + 1:
		sim.tick_hours(1.0)
		if k.site_id != id:
			break
	assert_true(s.building(id).is_empty(), "abandoned")
	assert_eq(s.stock_of(k, R.WOOD), 100, "cost back to the stock")
	assert_true(p.id > 0)


func test_opinion_drifts_when_away() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	k.next_traveler_hour = 1e9
	k.stock = { R.FOOD: 500 }
	var p := _resident(s, k, P.MERCHANT)
	p.opinion = 0.5
	var c0: float = p.contentment
	sim.is_player_in = func(_k: Dictionary) -> bool: return true
	for i in 24:
		sim.tick_hours(1.0)
	var near: float = p.opinion # stage 6: contentment moves it too, the same way in both runs
	p.opinion = 0.5
	p.contentment = c0
	sim.is_player_in = func(_k: Dictionary) -> bool: return false
	for i in 24:
		sim.tick_hours(1.0)
	assert_near(near - p.opinion, GameConstants.AWAY_OPINION_PER_DAY, 0.01, "a day away: toward neutral")
	assert_near(s.fame, p.opinion, 0.0001, "fame is the residents' average opinion")


func test_travelers_differ_after_reload() -> void:
	# A new session (fresh VillageSim on the same state) must not replay the first travelers.
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	sim.has_node = func(_id: int) -> bool: return true
	var first: Array = []
	sim.traveler_spawned.connect(func(r: Dictionary) -> void: first.append(PersonGen.full_name(r) + str(r.looks)))
	for i in 3:
		sim.tick_hours(1.0)
	var again := VillageSim.new()
	add_child(again)
	again.setup(s, _gen, _scatter, null)
	again.clock_hours = sim.clock_hours
	again.has_node = sim.has_node
	var second: Array = []
	again.traveler_spawned.connect(func(r: Dictionary) -> void: second.append(PersonGen.full_name(r) + str(r.looks)))
	k.next_traveler_hour = again.clock_hours + 1.0
	again.tick_hours(1.0)
	assert_eq(first.size(), 1)
	assert_eq(second.size(), 1)
	if first.size() == 1 and second.size() == 1:
		assert_true(first[0] != second[0], "a different person: %s" % second[0])


func test_masons_build_when_rocks_are_gone() -> void:
	var a := _setup(false)
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	k.next_traveler_hour = 1e9
	k.stock = { R.WOOD: 100, R.STONE: 10, R.FOOD: 100 }
	for pr in _scatter.props_near(k.center, GameConstants.VILLAGE_HARVEST_RADIUS + 1.0):
		if pr.type == GameConstants.Prop.ROCK:
			s.mark_removed(ChunkMath.world_to_chunk(pr.pos), pr.id)
	_resident(s, k, P.MASON)
	sim.tick_hours(1.0) # opens a house site (stone 10 covers it)
	var id: int = k.site_id
	assert_true(id >= 0, "a site is open")
	for i in 3:
		sim.tick_hours(1.0)
	assert_true(float(s.building(id).get("progress", 1.0)) > 0.0, "the mason helps instead of looking for rocks")


func test_site_not_opened_on_the_player() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	k.next_traveler_hour = 1e9
	k.stock = { R.WOOD: 100, R.STONE: 50, R.FOOD: 50 }
	_resident(s, k, P.BUILDER)
	sim.has_node = func(_id: int) -> bool: return true
	sim.tick_hours(1.0)
	var first := s.building(k.site_id)
	assert_true(not first.is_empty())
	var where: Vector3 = first.pos
	s.remove_building(first.id) # same hour again, with the player standing there
	sim.clock_hours -= 1.0
	sim.player_pos = func() -> Variant: return where
	sim.tick_hours(1.0)
	var second := s.building(k.site_id)
	assert_true(not second.is_empty(), "opened elsewhere")
	if not second.is_empty():
		var rect := BuildRules.footprint_rect(second.type, second.pos, second.rot)
		assert_true(not BuildRules.circle_hits_rect(Vector2(where.x, where.z), GameConstants.BUILD_PLAYER_RADIUS, rect),
				"not on top of the player")


func test_live_farm_food_before_any_offscreen_hour() -> void:
	var a := _setup()
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	k.erase("work_frac")
	k.stock = {}
	sim.add_fraction(k, "food", R.FOOD, 1.5)
	assert_eq((a[0] as WorldState).stock_of(k, R.FOOD), 1, "whole units go to the stock")
	sim.add_fraction(k, "food", R.FOOD, 0.5)
	assert_eq((a[0] as WorldState).stock_of(k, R.FOOD), 2, "fractions add up")
