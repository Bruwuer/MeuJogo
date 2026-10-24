extends GameTest

const B := GameConstants.Building
const T := GameConstants.Trait
const P := GameConstants.Profession

var _gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
var _scatter := PropScatter.new(_gen, GameConstants.WORLD_SEED)
var _said: Array[String] = []


## [state, kingdom, sim]; the kingdom gets no travelers and plenty of food.
func _setup() -> Array:
	_said = []
	var s := WorldState.new()
	s.seed = GameConstants.WORLD_SEED
	var center := TestSpots.flat_clear(_gen, _scatter, B.CABIN, 8.0, Vector2(200, 200))
	var seat := s.add_building(B.CABIN, center, 0)
	var k := s.add_kingdom("Teste", Color.RED, seat.pos, seat.id)
	k.next_traveler_hour = 1e9
	k.people_ever = 5
	s.add_stock(k, GameConstants.Res.FOOD, 500)
	var sim := VillageSim.new()
	add_child(sim)
	sim.setup(s, _gen, _scatter, null)
	sim.clock_hours = 8.0
	sim.is_kingdom_loaded = func(_k: Dictionary) -> bool: return true
	sim.message.connect(func(t: String) -> void: _said.append(t))
	return [s, k, sim]


func _person(s: WorldState, k: Dictionary, seed_value: int, age := 30.0, female := false, surname := "") -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var p := s.add_person(PersonGen.generate(r, 0.0, P.WOODCUTTER), k.center + Vector3(2, 0, 4), k.id)
	p.status = "resident"
	p.age = age
	p.female = female
	p.traits = [T.WORKER, T.BRAVE]
	if surname != "":
		p.surname = surname
	return p


func _house(s: WorldState, k: Dictionary, dx: float, owner := GameConstants.OWNER_KINGDOM) -> Dictionary:
	return s.add_building(B.HOUSE, k.center + Vector3(dx, 0, 12), 0, Color.WHITE, owner)


func _said_has(part: String) -> bool:
	return _said.any(func(t: String) -> bool: return t.contains(part))


func test_newcomer_founds_family_with_crest() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	var p := _person(s, k, 1, 30.0, false, "Ferreira")
	var q := _person(s, k, 2, 30.0, false, "Seixas")
	sim.tick_hours(1.0)
	var f := s.family(p.family_id)
	assert_true(not f.is_empty(), "has a family")
	assert_eq(f.surname, "Ferreira")
	assert_eq(f.head_id, p.id)
	assert_eq(f.kingdom_id, k.id)
	assert_true(f.crest.has("pattern"), "crest")
	var g := s.family(q.family_id)
	assert_true(not Crest.same(f.crest, g.crest), "different crests in one kingdom")
	assert_true(not _said_has("Casa"), "founding is silent")


func test_newcomer_joins_kin() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	var p := _person(s, k, 1, 40.0, false, "Ferreira")
	sim.tick_hours(1.0)
	var q := _person(s, k, 2, 20.0, true, "Ferreira")
	sim.tick_hours(1.0)
	assert_eq(q.family_id, p.family_id, "same surname = same family")
	assert_eq(s.families_of(k.id).size(), 1)
	assert_true(_said_has("juntou-se à Casa Ferreira"), str(_said))
	assert_true(s.relation(p.id, q.id) > 0.1, "kin start fond of each other")


func test_couple_forms_and_moves_in() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	var ana := _person(s, k, 1, 25.0, true, "Ferreira")
	var bento := _person(s, k, 2, 28.0, false, "do Vale")
	var rui := _person(s, k, 3, 33.0, false, "Couto")
	var h1 := _house(s, k, -6.0, ana.id)
	var h2 := _house(s, k, 6.0, bento.id)
	ana.home_id = h1.id
	bento.home_id = h2.id
	rui.home_id = h2.id
	sim.tick_hours(1.0) # families
	s.set_relation(ana.id, bento.id, 0.9)
	sim.tick_hours(1.0)
	assert_eq(ana.spouse_id, bento.id)
	assert_eq(bento.spouse_id, ana.id)
	assert_eq(ana.home_id, bento.home_id, "live together")
	assert_eq(ana.family_id, bento.family_id, "one family")
	assert_true(_said_has("Ana") and _said_has("se casaram") or _said_has("se casaram"), str(_said))
	assert_true(_said_has("uniu-se à Casa"), "the emptied family merged: %s" % str(_said))
	assert_eq(s.families_of(k.id).size(), 2, "Couto + the couple's")


func test_assign_home_prefers_spouse() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	var ana := _person(s, k, 1, 25.0, true)
	var bento := _person(s, k, 2, 28.0)
	_house(s, k, -6.0) # empty, listed first
	var h2 := _house(s, k, 6.0, bento.id)
	bento.home_id = h2.id
	ana.spouse_id = bento.id
	bento.spouse_id = ana.id
	sim.tick_hours(1.0)
	assert_eq(ana.home_id, h2.id, "moves in with the spouse")


func test_empty_family_dissolves() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	var p := _person(s, k, 1, 30.0, false, "Ferreira")
	_person(s, k, 2, 30.0, false, "Seixas")
	sim.tick_hours(1.0)
	var fid: int = p.family_id
	p.status = "leaving"
	sim.tick_hours(1.0)
	assert_true(s.family(fid).is_empty(), "gone")
	assert_true(_said_has("A Casa Ferreira se desfez"), str(_said))


func test_head_passes_to_oldest() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	var head := _person(s, k, 1, 30.0, false, "Ferreira")
	var young := _person(s, k, 2, 20.0, false, "Ferreira")
	var old := _person(s, k, 3, 50.0, false, "Ferreira")
	sim.tick_hours(1.0)
	var f := s.family(head.family_id)
	assert_eq(f.head_id, head.id, "founder heads it")
	assert_eq(young.family_id, f.id)
	s.remove_person(head.id)
	sim.tick_hours(1.0)
	assert_eq(f.head_id, old.id, "the oldest adult takes over")


func test_leaver_takes_family() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	k.stock = {} # hungry
	var dad := _person(s, k, 1, 35.0, false, "Ferreira")
	var mom := _person(s, k, 2, 33.0, true, "Ferreira")
	var kid := _person(s, k, 3, 5.0, true, "Ferreira")
	var lodger := _person(s, k, 4, 60.0, false, "Couto")
	kid.parents = [dad.id, mom.id]
	dad.spouse_id = mom.id
	mom.spouse_id = dad.id
	var h := _house(s, k, 0.0, dad.id)
	for p in [dad, mom, kid, lodger]:
		p.home_id = h.id
	for p in [dad, kid]:
		p.contentment = 0.0
		p.unhappy_hours = GameConstants.LEAVE_AFTER_HOURS
	lodger.contentment = 1.0
	mom.contentment = 1.0
	sim.tick_hours(1.0)
	for p in [dad, mom, kid]:
		assert_true(s.person(p.id).is_empty(), "%s left" % p.name)
	assert_true(not s.person(lodger.id).is_empty(), "the lodger stays")
	assert_true(_said_has("com a família"), str(_said))
	assert_eq(_said.filter(func(t: String) -> bool: return t.contains("deixou o Reino")).size(), 1, "one message")
	assert_eq(h.owner, lodger.id, "the house passes to the oldest adult living there")


func test_child_never_leaves_alone() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	_person(s, k, 1, 35.0)
	var kid := _person(s, k, 3, 5.0)
	kid.contentment = 0.0
	kid.unhappy_hours = GameConstants.LEAVE_AFTER_HOURS
	sim.tick_hours(1.0)
	assert_true(not s.person(kid.id).is_empty(), "a child stays")


func test_kin_helps_stay() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	var p := _person(s, k, 1, 30.0, false, "Ferreira")
	sim.tick_hours(1.0)
	var snap := sim.snapshot(k)
	assert_true((snap.surnames as Array).has("Ferreira"), "snapshot knows the family names")
	var traveler := p.duplicate(true)
	var r1 := RandomNumberGenerator.new()
	r1.seed = 3
	var with_kin := VillageRules.stay_decision(traveler, snap, r1)
	snap.surnames = []
	var r2 := RandomNumberGenerator.new()
	r2.seed = 3
	var without := VillageRules.stay_decision(traveler, snap, r2)
	assert_near(with_kin.score - without.score, GameConstants.STAY_KIN, 0.0001)
