extends GameTest

const P := GameConstants.Profession
const T := GameConstants.Trait
const TR := GameConstants.Tradition

var s := WorldState.new()
var k: Dictionary
var house := HouseSim.new()
var society := SocietySim.new()
var said: Array[String] = []


func _init() -> void:
	s.seed = 11
	k = s.add_kingdom("Ravmia", Color.RED, Vector3(100, 0, 100), -1)
	society.setup(s, func(_k: Dictionary, t: String) -> void: said.append(t), func(_k: Dictionary) -> bool: return true,
			func(_k: Dictionary) -> Dictionary: return {})
	house.setup(s, func(_k: Dictionary, t: String) -> void: said.append(t), society)


func _person(name: String, female: bool, age: float, profession := P.FARMER, traits := [T.WORKER, T.SOCIABLE]) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var p := PersonGen.generate(rng)
	p.name = name
	p.female = female
	p.age = age
	p.profession = profession
	p.traits = traits
	var rec := s.add_person(p, Vector3(100, 0, 100), k.id)
	rec.status = "resident"
	return rec


func _family(head: Dictionary, tradition := TR.FARMERS) -> Dictionary:
	var f := s.add_family(head.surname, Crest.generate(RandomNumberGenerator.new(), []), k.id, head.id, 0.0)
	f.tradition = tradition
	f.house_init = true
	head.family_id = f.id
	return f


func _work_hour(day := 0) -> float:
	return day * 24.0 + 10.0


func test_wealth_grows_with_work() -> void:
	var a := _person("Ana", true, 30.0)
	var f := _family(a)
	a.job = "farm"
	house.tick_hour(k, _work_hour())
	assert_true(f.wealth > 0.0, "working members bring wealth home")
	assert_true(f.skill.get(P.FARMER, 0.0) > 0.0, "and the House gets better at the trade")
	var w: float = f.wealth
	house.tick_hour(k, 2.0) # night
	assert_near(f.wealth, w, 0.0001, "no wealth at night")


func test_new_house_gets_tradition_from_head() -> void:
	var a := _person("Bento", false, 40.0, P.MERCHANT, [T.GREEDY, T.SOCIABLE])
	var f := s.add_family("Bento", Crest.generate(RandomNumberGenerator.new(), []), k.id, a.id, 0.0)
	a.family_id = f.id
	house.tick_hour(k, _work_hour())
	assert_true(f.house_init)
	assert_eq(f.tradition, TR.MERCHANTS)


func test_grown_profession_follows_vocation_or_starts_conflict() -> void:
	var head := _person("Vasco", false, 45.0, P.GUARD, [T.BRAVE, T.WORKER])
	var f := _family(head, TR.WARRIORS)
	var kid := _person("Nuno", false, 15.9, P.FARMER)
	kid.family_id = f.id
	kid.vocation = P.FARMER
	var r := HouseRules.grown_profession(kid, f, P.MASON)
	assert_eq(r.profession, P.GUARD, "while unsure, the young work the House trade")
	assert_true(r.conflict)
	kid.vocation = P.GUARD
	r = HouseRules.grown_profession(kid, f, P.MASON)
	assert_eq(r.profession, P.GUARD)
	assert_true(not r.conflict)
	kid.vocation = -1
	assert_eq(HouseRules.grown_profession(kid, f, P.MASON).profession, P.MASON, "no vocation: what the kingdom needs")


func _leave(style: Dictionary) -> Array:
	var head := _person("Pai", false, 50.0, P.GUARD)
	var f := _family(head, TR.WARRIORS)
	f.wealth = 100.0
	f.skill = {P.FARMER: 100.0}
	var son := _person("Martim", false, 20.0, P.FARMER)
	son.family_id = f.id
	son.parents = [head.id]
	son.home_id = 77
	house.depart(k, f, son, style, _work_hour())
	return [f, son]


func test_friendly_departure_blessing() -> void:
	var r := _leave({tone = "friendly", secret = false})
	var f: Dictionary = r[0]
	var son: Dictionary = r[1]
	var nf := s.family(son.family_id)
	assert_true(nf.id != f.id)
	assert_true(nf.wealth > 0.0 and f.wealth < 100.0, "leaves with a gift")
	assert_near(nf.wealth + f.wealth, 100.0, 0.001, "the gift comes out of the old House")
	assert_near(float(nf.skill.get(P.FARMER, 0.0)), 100.0 * GameConstants.SKILL_INHERIT, 0.001, "takes the craft along")
	assert_true(f.rival_id != nf.id)


func test_hostile_departure_rivals() -> void:
	var r := _leave({tone = "hostile", secret = false})
	var f: Dictionary = r[0]
	var nf := s.family(r[1].family_id)
	assert_eq(f.rival_id, nf.id)
	assert_eq(nf.rival_id, f.id)
	assert_near(nf.wealth, 0.0, 0.001, "no blessing, no gift")
	assert_true(s.relation(r[1].id, f.head_id) < 0.0)


func test_runaway_leaves_house_and_bed() -> void:
	var r := _leave({tone = "neutral", secret = true})
	var f: Dictionary = r[0]
	var son: Dictionary = r[1]
	assert_true(son.family_id != f.id)
	assert_eq(son.home_id, -1)
	assert_true(not s.family_members(f.id).any(func(m: Dictionary) -> bool: return m.id == son.id))


func test_secret_discovered_next_day() -> void:
	said.clear()
	var r := _leave({tone = "neutral", secret = true})
	var f: Dictionary = r[0]
	assert_true(not s.chronicle(k.id, 50).any(func(e: Dictionary) -> bool: return (e.text as String).contains("fugiu")),
			"a secret departure is not public at once")
	house.tick_hour(k, _work_hour(1) - 3.0) # next morning
	assert_true(s.chronicle(k.id, 50).any(func(e: Dictionary) -> bool: return (e.text as String).contains("fugiu")),
			"the family finds out the next day")
	assert_true(s.chronicle(k.id, 50).any(func(e: Dictionary) -> bool: return (e.text as String).contains(f.surname)))
	assert_true(said.is_empty(), "nothing is announced to the player")


func test_orphan_adopted() -> void:
	var w := _person("Maria", true, 35.0)
	var h := _person("Gil", false, 37.0)
	w.spouse_id = h.id
	h.spouse_id = w.id
	var fam := _family(w)
	h.family_id = fam.id
	w.home_id = 5
	h.home_id = 5
	var orphan := _person("Rui", false, 6.0)
	orphan.parents = [999] # parent gone
	house.tick_hour(k, _work_hour())
	assert_eq(orphan.adopted_by, [w.id, h.id])
	assert_eq(orphan.family_id, fam.id)
	assert_eq(orphan.home_id, 5)


func test_wealth_never_negative() -> void:
	var r := _leave({tone = "friendly", secret = false})
	var f: Dictionary = r[0]
	f.wealth = 0.0
	var other := _person("Luzia", true, 22.0)
	other.family_id = f.id
	house.depart(k, f, other, {tone = "friendly", secret = false}, _work_hour())
	assert_true(f.wealth >= 0.0)
	assert_true(s.family(other.family_id).wealth >= 0.0)
