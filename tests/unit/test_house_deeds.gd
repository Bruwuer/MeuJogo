extends GameTest
## House decisions become deeds: departures, land, building work, ceremonies and night deeds.

const B := GameConstants.Building
const G := GameConstants.Goal
const T := GameConstants.Trait
const P := GameConstants.Profession

var s := WorldState.new()
var k: Dictionary
var house := HouseSim.new()
var society := SocietySim.new()


func _init() -> void:
	s.seed = 31
	k = s.add_kingdom("Ravmia", Color.RED, Vector3(200, 0, 200), -1)
	society.setup(s, func(_k: Dictionary, _t: String) -> void: pass, func(_k: Dictionary) -> bool: return true,
			func(_k: Dictionary) -> Dictionary: return {})
	house.setup(s, func(_k: Dictionary, _t: String) -> void: pass, society)


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


## A House whose head lives in a house east of the center.
func _house(surname: String, wealth := 100.0, east := 10.0) -> Dictionary:
	var head := _person(surname + "-chefe", false, 50.0)
	var f := s.add_family(surname, Crest.generate(RandomNumberGenerator.new(), []), k.id, head.id, 0.0)
	f.house_init = true
	f.wealth = wealth
	head.family_id = f.id
	head.surname = surname
	var home := s.add_building(B.HOUSE, k.center + Vector3(east, 0, 0), 0, Color.WHITE, head.id)
	head.home_id = home.id
	return f


func _join(p: Dictionary, f: Dictionary) -> Dictionary:
	p.family_id = f.id
	p.surname = f.surname
	p.home_id = int(s.person(int(f.head_id)).home_id)
	return p


func _chronicle_has(part: String) -> bool:
	return s.chronicle(k.id, 200).any(func(e: Dictionary) -> bool: return (e.text as String).contains(part))


# --- Departures ---

func test_open_departure_is_a_farewell_at_the_head_door() -> void:
	var f := _house("Ferreira")
	var son := _join(_person("Martim", false, 20.0), f)
	house._hour = 8.0
	house.leave(k, f, son, {tone = "friendly", secret = false})
	assert_eq(son.family_id, f.id, "nothing changes until the farewell")
	assert_eq(son.deed.kind, "farewell")
	var door := PeopleManager.door_of(s.building(int(s.person(int(f.head_id)).home_id)))
	assert_true((son.deed.pos as Vector3).distance_to(door) < 0.01, "goes to the head's door")
	assert_eq(son.deed.start_hour, GameConstants.DEED_DAY.x, "by day")
	house.complete_deed(k, son, [])
	assert_true(son.family_id != f.id, "then leaves the House")


func test_runaway_waits_for_the_night_and_walks_to_the_edge() -> void:
	var f := _house("Souto")
	var son := _join(_person("Rui", false, 19.0), f)
	house._hour = 10.0
	house.leave(k, f, son, {tone = "hostile", secret = true})
	assert_eq(son.deed.kind, "runaway")
	assert_eq(son.deed.start_hour, GameConstants.DEED_NIGHT.x, "at night")
	var d := Vector2(son.deed.pos.x - k.center.x, son.deed.pos.z - k.center.z).length()
	assert_true(d > float(k.radius) * 0.7, "out to the edge of the territory (%.1f)" % d)
	assert_true(son.deed.data.secret)
	assert_eq(son.home_id, s.person(int(f.head_id)).home_id, "still sleeps at home until then")


func test_unseen_runaway_found_next_morning() -> void:
	var f := _house("Couto")
	var son := _join(_person("Davi", false, 19.0), f)
	house._hour = 10.0
	house.leave(k, f, son, {tone = "neutral", secret = true})
	house.complete_deed(k, son, [], 23.5)
	assert_true(son.family_id != f.id)
	assert_eq(son.secret.get("kind", ""), "runaway", "nobody saw: found out in the morning")


func test_seen_runaway_found_at_once() -> void:
	var f := _house("Mota")
	var son := _join(_person("Caio", false, 19.0), f)
	var guard := _person("Vigia", false, 30.0)
	house._hour = 10.0
	house.leave(k, f, son, {tone = "neutral", secret = true})
	house.complete_deed(k, son, [guard.id], 23.5)
	assert_eq(son.get("secret", {}), {}, "a witness tells at once")
	assert_true(_chronicle_has("Vigia"), "the ADM log names who saw it")
	assert_true(s.relation(son.id, f.head_id) < 0.0)


func test_flee_with_lover_is_a_night_escape() -> void:
	var a := _house("Ferreira", 100.0, 10.0)
	var b := _house("Vale", 100.0, -10.0)
	var groom := _join(_person("Tomé", false, 22.0, [T.BRAVE, T.LONER]), a)
	var bride := _join(_person("Inês", true), b)
	var lover := _person("Leonor", true, 21.0)
	s.set_relation(groom.id, lover.id, 0.9)
	house._hour = 10.0
	house.arranged_marriage(k, a, groom, bride, "flee")
	assert_eq(groom.spouse_id, -1, "not yet")
	assert_eq(groom.deed.kind, "runaway")
	assert_eq(lover.deed.kind, "runaway", "the lover goes along")
	assert_true((lover.deed.pos as Vector3).distance_to(groom.deed.pos) < 0.01, "to the same spot")
	house.complete_deed(k, groom, [], 23.5)
	assert_eq(groom.spouse_id, lover.id, "they marry once away")
	assert_eq(lover.family_id, groom.family_id)
