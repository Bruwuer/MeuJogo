extends GameTest

const B := GameConstants.Building
const T := GameConstants.Trait
const P := GameConstants.Profession

var _gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
var _scatter := PropScatter.new(_gen, GameConstants.WORLD_SEED)
var _said: Array[String] = []


func _setup() -> Array:
	_said = []
	var s := WorldState.new()
	s.seed = GameConstants.WORLD_SEED
	var center := TestSpots.flat_clear(_gen, _scatter, B.CABIN, 8.0, Vector2(200, 200))
	var seat := s.add_building(B.CABIN, center, 0)
	var k := s.add_kingdom("Teste", Color.RED, seat.pos, seat.id)
	k.next_traveler_hour = 1e9
	k.people_ever = 5
	s.add_stock(k, GameConstants.Res.FOOD, 2000)
	var sim := VillageSim.new()
	add_child(sim)
	sim.setup(s, _gen, _scatter, null)
	sim.clock_hours = 8.0
	sim.is_kingdom_loaded = func(_k: Dictionary) -> bool: return true
	sim.message.connect(func(t: String) -> void: _said.append(t))
	return [s, k, sim]


func _person(s: WorldState, k: Dictionary, seed_value: int, age := 30.0, female := false, surname := "Ferreira") -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var p := s.add_person(PersonGen.generate(r, 0.0, P.WOODCUTTER), k.center + Vector3(2, 0, 4), k.id)
	p.status = "resident"
	p.age = age
	p.female = female
	p.traits = [T.WORKER, T.BRAVE]
	p.surname = surname
	p.contentment = 0.9
	return p


func _house(s: WorldState, k: Dictionary, dx: float, owner := GameConstants.OWNER_KINGDOM) -> Dictionary:
	return s.add_building(B.HOUSE, k.center + Vector3(dx, 0, 12), 0, Color.WHITE, owner)


func _couple(s: WorldState, k: Dictionary, h: Dictionary) -> Array:
	var mom := _person(s, k, 1, 25.0, true)
	var dad := _person(s, k, 2, 27.0, false)
	mom.spouse_id = dad.id
	dad.spouse_id = mom.id
	mom.home_id = h.id
	dad.home_id = h.id
	return [mom, dad]


func _said_has(part: String) -> bool:
	return _said.any(func(t: String) -> bool: return t.contains(part))


func _children_of(s: WorldState, id: int) -> Array[Dictionary]:
	return s.all_people().filter(func(p: Dictionary) -> bool: return (p.parents as Array).has(id))


func test_couple_has_child() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	var h := _house(s, k, 0.0)
	var c := _couple(s, k, h)
	var born: Array = []
	sim.person_born.connect(func(r: Dictionary) -> void: born.append(r))
	for i in 24 * 15:
		sim.tick_hours(1.0)
		if not born.is_empty():
			break
	assert_eq(born.size(), 1, "a child within 15 days")
	if born.is_empty():
		return
	var kid: Dictionary = born[0]
	assert_eq(kid.parents, [c[0].id, c[1].id])
	assert_eq(kid.home_id, h.id)
	assert_eq(kid.family_id, c[0].family_id)
	assert_eq(kid.status, "resident")
	assert_eq(kid.surname, s.family(kid.family_id).surname)
	assert_true(float(kid.age) < 1.0, "a baby")
	assert_true(_said_has("Nasceu %s" % kid.name), str(_said))


func test_no_birth_without_bed_or_at_cap() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	var h := _house(s, k, 0.0)
	var c := _couple(s, k, h)
	for i in GameConstants.HOUSE_CAPACITY[B.HOUSE] - 2:
		_person(s, k, 10 + i, 40.0).home_id = h.id
	for i in 24 * 10:
		sim.tick_hours(1.0)
	assert_true(_children_of(s, c[0].id).is_empty(), "no free bed: no child")
	_house(s, k, 10.0) # beds now, but the kingdom is at the birth cap

	s.person(c[0].id).home_id = -1
	s.person(c[1].id).home_id = -1
	while s.residents(k.id).size() < GameConstants.KINGDOM_BIRTH_CAP:
		_person(s, k, 100 + s.residents(k.id).size(), 40.0)
	for i in 24 * 10:
		sim.tick_hours(1.0)
	assert_true(_children_of(s, c[0].id).is_empty(), "at the cap: no child")


func test_child_grows_and_gets_trade() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	_person(s, k, 1, 40.0)
	var kid := _person(s, k, 3, GameConstants.ADULT_AGE - 0.1, true)
	kid.profession = -1
	assert_eq(VillageRules.choose_job(kid, sim.snapshot(k)), "child")
	for i in 3:
		sim.tick_hours(1.0)
	assert_true(SocietyRules.is_adult(kid), "grown up")
	assert_true(int(kid.profession) >= 0, "has a trade")
	assert_true(_said_has("cresceu e agora é"), str(_said))
	assert_true(VillageRules.choose_job(kid, sim.snapshot(k)) != "child")


func test_old_person_dies_and_spouse_widowed() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	var h := _house(s, k, 0.0)
	var old := _person(s, k, 1, 85.0)
	var wife := _person(s, k, 2, 60.0, true)
	old.spouse_id = wife.id
	wife.spouse_id = old.id
	h.owner = old.id
	old.home_id = h.id
	wife.home_id = h.id
	var died: Array = []
	sim.person_died.connect(func(r: Dictionary) -> void: died.append(r))
	for i in 24 * 40:
		sim.tick_hours(1.0)
		if not died.is_empty():
			break
	assert_eq(died.size(), 1, "the old man dies")
	assert_eq(String(s.person(old.id).get("status", "")), "dead", "a body lies there until buried (stage 10)")
	assert_eq(wife.spouse_id, -1)
	assert_true(wife.widowed, "widowed")
	assert_eq(h.owner, wife.id, "the widow keeps the house")
	assert_true(_said_has("Morreu"), str(_said))


func test_rival_of_head_breaks_away() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	var head := _person(s, k, 1, 50.0)
	var son := _person(s, k, 2, 25.0)
	var wife := _person(s, k, 3, 24.0, true, "Couto")
	var grandkid := _person(s, k, 4, 3.0)
	son.parents = [head.id]
	grandkid.parents = [son.id, wife.id]
	son.spouse_id = wife.id
	wife.spouse_id = son.id
	sim.tick_hours(1.0)
	var old := s.family(head.family_id)
	wife.family_id = old.id
	grandkid.family_id = old.id
	old.last_split_hour = -1e9
	s.set_relation(son.id, head.id, -0.9)
	sim.tick_hours(1.0)
	var nf := s.family(son.family_id)
	assert_true(nf.id != old.id, "son has his own house")
	assert_eq(nf.origin, "rival")
	assert_eq(nf.parent_id, old.id)
	assert_eq(nf.head_id, son.id)
	assert_true(nf.surname != "Ferreira", "a new name")
	assert_eq(son.surname, nf.surname)
	assert_eq(grandkid.family_id, nf.id, "the child goes along")
	assert_eq(grandkid.surname, nf.surname)
	assert_eq(wife.family_id, nf.id, "the wife goes along")
	assert_eq(wife.surname, "Couto", "keeps her own name")
	assert_eq(head.family_id, old.id)
	assert_true(not Crest.same(nf.crest, old.crest))
	assert_true(_said_has("rompeu com a Casa Ferreira e fundou a Casa %s" % nf.surname), str(_said))


func test_big_family_branches() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	var h1 := _house(s, k, -6.0)
	var h2 := _house(s, k, 6.0)
	var head := _person(s, k, 1, 55.0)
	head.home_id = h1.id
	for i in 3:
		_person(s, k, 10 + i, 30.0 + i).home_id = h1.id
	var x := _person(s, k, 20, 28.0)
	var y := _person(s, k, 21, 27.0, true)
	x.spouse_id = y.id
	y.spouse_id = x.id
	x.home_id = h2.id
	y.home_id = h2.id
	sim.tick_hours(1.0)
	var old := s.family(head.family_id)
	old.last_split_hour = -1e9
	assert_eq(s.family_members(old.id).size(), 6)
	var branch := {}
	for i in 24 * 15:
		sim.tick_hours(1.0)
		for f in s.families_of(k.id):
			if f.origin == "branch":
				branch = f
		if not branch.is_empty():
			break
	assert_true(not branch.is_empty(), "a household branched off")
	if branch.is_empty():
		return
	assert_eq(branch.parent_id, old.id)
	assert_eq(branch.crest.pattern, old.crest.pattern, "derived crest")
	assert_eq(branch.crest.field, old.crest.field)
	assert_true(_said_has("em paz"), str(_said))


func test_children_do_not_work_or_marry() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	var c1 := _person(s, k, 1, 12.0)
	var c2 := _person(s, k, 2, 12.0, true, "Couto")
	s.set_relation(c1.id, c2.id, 1.0)
	sim.tick_hours(1.0)
	assert_eq(c1.spouse_id, -1)
	assert_eq(c1.job, "child", "summarized work skips children")
