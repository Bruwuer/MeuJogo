extends GameTest

const B := GameConstants.Building
const G := GameConstants.Goal
const T := GameConstants.Trait
const TR := GameConstants.Tradition
const R := GameConstants.Res

var s := WorldState.new()
var k: Dictionary
var house := HouseSim.new()
var society := SocietySim.new()
var said: Array[String] = []


func _init() -> void:
	s.seed = 21
	k = s.add_kingdom("Ravmia", Color.RED, Vector3(200, 0, 200), -1)
	society.setup(s, func(_k: Dictionary, t: String) -> void: said.append(t), func(_k: Dictionary) -> bool: return true,
			func(_k: Dictionary) -> Dictionary: return {})
	house.setup(s, func(_k: Dictionary, t: String) -> void: said.append(t), society)


func _person(name: String, female: bool, age := 25.0, traits := [T.WORKER, T.SOCIABLE]) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var p := PersonGen.generate(rng)
	p.name = name
	p.female = female
	p.age = age
	p.traits = traits
	var rec := s.add_person(p, k.center, k.id)
	rec.status = "resident"
	return rec


func _house(surname: String, head_traits := [T.WORKER, T.SOCIABLE], wealth := 100.0) -> Dictionary:
	var head := _person(surname + "-chefe", false, 50.0, head_traits)
	var f := s.add_family(surname, Crest.generate(RandomNumberGenerator.new(), []), k.id, head.id, 0.0)
	f.house_init = true
	f.tradition = TR.FARMERS
	f.wealth = wealth
	head.family_id = f.id
	return f


func _join(p: Dictionary, f: Dictionary) -> Dictionary:
	p.family_id = f.id
	p.surname = f.surname
	return p


func _public(text: String) -> bool:
	return s.chronicle(k.id, 200).any(func(e: Dictionary) -> bool: return (e.text as String).contains(text))


func test_arranged_marriage_dowry_and_alliance() -> void:
	var a := _house("Ferreira")
	var b := _house("Vale")
	var groom := _join(_person("Martim", false), a)
	var bride := _join(_person("Inês", true), b)
	a.goal = {kind = G.ALLIANCE, target_id = b.id, deadline_hour = 1000.0}
	house.arranged_marriage(k, a, groom, bride, "accept")
	assert_eq(groom.spouse_id, bride.id)
	assert_near(a.wealth, 100.0 - GameConstants.DOWRY, 0.001)
	assert_near(b.wealth, 100.0 + GameConstants.DOWRY, 0.001)
	assert_true(a.goal.get("done", false), "the alliance goal is met")
	assert_true(s.relation(a.head_id, b.head_id) > 0.0, "the Houses grow closer")


func test_resist_breeds_resentment() -> void:
	var a := _house("Ferreira")
	var b := _house("Vale")
	var groom := _join(_person("Martim", false), a)
	var bride := _join(_person("Inês", true), b)
	house.arranged_marriage(k, a, groom, bride, "resist")
	assert_eq(groom.spouse_id, -1)
	assert_true(groom.resentment > 0.0)
	assert_true(s.relation(groom.id, a.head_id) < 0.0)


func test_flee_with_lover() -> void:
	var a := _house("Ferreira")
	var b := _house("Vale")
	var c := _house("Souto")
	var groom := _join(_person("Martim", false, 22.0, [T.BRAVE, T.LONER]), a)
	var bride := _join(_person("Inês", true), b)
	var lover := _join(_person("Leonor", true, 21.0), c)
	s.set_relation(groom.id, lover.id, 0.9)
	house.arranged_marriage(k, a, groom, bride, "flee")
	assert_eq(groom.spouse_id, lover.id, "runs away and marries the one they love")
	assert_true(groom.family_id != a.id)
	assert_eq(lover.family_id, groom.family_id)
	assert_eq(groom.get("secret", {}).get("kind", ""), "runaway", "the family finds out the next day")


func test_unhappy_marriage_separates() -> void:
	var a := _house("Ferreira")
	var x := _join(_person("Gil", false), a)
	var y := _join(_person("Clara", true), a)
	x.spouse_id = y.id
	y.spouse_id = x.id
	x.unhappy_marriage = true
	y.unhappy_marriage = true
	s.set_relation(x.id, y.id, -0.9)
	house.tick_hour(k, 24.0 + GameConstants.DEED_HOUR)
	assert_eq(x.spouse_id, -1, "they separate")
	assert_eq(y.spouse_id, -1)
	assert_true(float(a.get("dishonor", 0.0)) > 0.0, "a scandal in medieval eyes")


func test_union_merges_houses() -> void:
	var big := _house("Ferreira", [T.WORKER, T.SOCIABLE], 200.0)
	var small := _house("Seixas", [T.WORKER, T.SOCIABLE], 50.0)
	small.plots = [Rect2(0, 0, 8, 8)]
	var member := _join(_person("Rui", false, 60.0), small)
	house.unite(k, small, big)
	assert_true(s.family(small.id).is_empty(), "the small House is absorbed")
	assert_eq(member.family_id, big.id)
	assert_eq(s.person(small.head_id).family_id, big.id)
	assert_near(big.wealth, 250.0, 0.001)
	assert_eq((big.plots as Array).size(), 1)
	assert_true(_public("uniu-se"))


func test_corruption_scandal() -> void:
	var f := _house("Barros", [T.GREEDY, T.WORKER], 10.0)
	s.add_stock(k, R.WOOD, 50)
	var before := s.stock_of(k, R.WOOD)
	house.skim(k, f)
	assert_true(s.stock_of(k, R.WOOD) < before, "skims the kingdom stock")
	assert_true(f.wealth > 10.0)
	assert_true(not _public("desviando"), "a secret until found out")
	house.expose(k, f, (f.secrets as Array)[0])
	assert_true(_public("desviando"))
	assert_true(float(f.dishonor) > 0.0)
	assert_true((f.secrets as Array).is_empty())


func test_infiltration_and_discovery() -> void:
	var a := _house("Ferreira")
	var b := _house("Vale")
	a.rival_id = b.id
	b.rival_id = a.id
	var spy := _join(_person("Sancho", false, 24.0, [T.LONER, T.GREEDY]), a)
	assert_true(house.plant_spy(k, a, b), "plants a member in the rival House")
	assert_eq(spy.family_id, b.id, "lives with the rival as a household member")
	assert_eq(spy.secret.kind, "spy")
	assert_true(not _public("espionava"))
	var w: float = b.wealth
	house.spy_day(k, spy)
	assert_true(b.wealth < w, "sabotage: the rival loses wealth")
	house.expose_spy(k, spy)
	assert_true(_public("espionava"))
	assert_eq(spy.family_id, a.id, "sent back home")
	assert_eq(int(b.insulted_by), a.id, "the rival wants revenge")
	assert_true(s.relation(a.head_id, b.head_id) < -0.3)


func test_revenge_goal_resolves() -> void:
	var a := _house("Ferreira")
	var b := _house("Vale")
	a.insulted_by = b.id
	a.goal = {kind = G.REVENGE, target_id = b.id, deadline_hour = 1000.0}
	house.take_revenge(k, a, b)
	assert_true(a.goal.get("done", false))
	assert_eq(int(a.get("insulted_by", -1)), -1)
	assert_true(float(b.get("dishonor", 0.0)) > 0.0)


func test_secret_romance_scandal() -> void:
	var a := _house("Ferreira")
	var b := _house("Vale")
	var x := _join(_person("Diogo", false, 24.0, [T.BRAVE, T.LONER]), a)
	var y := _join(_person("Simão", false, 26.0), b)
	s.set_relation(x.id, y.id, 0.9)
	assert_true(house.start_romance(k, x, y))
	assert_eq(x.secret.kind, "romance")
	assert_true(not _public("romance"))
	house.expose_romance(k, x)
	assert_true(_public("romance"), "discovered: a scandal")
	assert_true(float(a.get("dishonor", 0.0)) > 0.0 and float(b.get("dishonor", 0.0)) > 0.0)
	assert_eq(x.get("secret", {}), {})
	assert_true(x.spouse_id == -1 and y.spouse_id == -1, "they never marry")
	assert_true(x.resentment > 0.0 or x.family_id != a.id, "they give in or leave the House")
