extends GameTest
## Life (stage 10): needs beyond food and sleep (company, faith) met by real acts — two friends walk
## to each other and talk, the devout pray at the flag — and the wants each adult carries.

const B := GameConstants.Building
const T := GameConstants.Trait
const D := GameConstants.Desire

var s: WorldState
var society: SocietySim
var houses: HouseSim
var gov: GovSim
var life: LifeSim
var k: Dictionary


func _fresh() -> void:
	s = WorldState.new()
	s.seed = 12
	society = SocietySim.new()
	houses = HouseSim.new()
	gov = GovSim.new()
	life = LifeSim.new()
	society.setup(s, func(_k: Dictionary, _t: String) -> void: pass, func(_k: Dictionary) -> bool: return false,
			func(_k: Dictionary) -> Dictionary: return {})
	houses.setup(s, func(_k: Dictionary, _t: String) -> void: pass, society)
	gov.setup(s, houses, func(_k: Dictionary) -> bool: return false)
	life.setup(s, houses, society)
	var seat := s.add_building(B.CABIN, Vector3(300, 0, 300), 0, Color.WHITE, GameConstants.OWNER_KINGDOM)
	s.add_building(B.FLAG, seat.pos + Vector3(2, 0, 2), 0)
	k = s.add_kingdom("Ravmia", Color.RED, seat.pos, seat.id)


func _person(name: String, age := 30.0, traits := [T.WORKER], female := false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var p := PersonGen.generate(rng)
	p.name = name
	p.age = age
	p.traits = traits
	p.female = female
	var rec := s.add_person(p, k.center + Vector3(6, 0, 0), k.id)
	rec.status = "resident"
	return rec


func _run(from: float, hours: int) -> float:
	for i in hours:
		var h := from + i
		houses.tick_hour(k, h)
		gov.tick_hour(k, h)
		life.tick_hour(k, h)
	return from + hours


func _logged(part: String) -> bool:
	return s.chronicle_all(k.id, 500).any(func(e: Dictionary) -> bool: return (e.text as String).contains(part))


func test_company_need_grows_and_two_friends_meet_to_talk() -> void:
	_fresh()
	var a := _person("Joana", 30.0, [T.SOCIABLE], true)
	var b := _person("Teresa", 32.0, [T.WORKER], true)
	s.set_relation(a.id, b.id, 0.6)
	_run(0.0, 30)
	assert_true(float(a.needs.social) > 0.0 or _logged("conversaram"), "company is missed over time")
	_run(30.0, 24 * 2)
	assert_true(_logged("conversaram"), "the friends met and talked")
	assert_true(s.relation(a.id, b.id) > 0.6, "talking brings them closer")


func test_talk_is_a_meeting_of_both() -> void:
	_fresh()
	var a := _person("Rui", 30.0, [T.SOCIABLE])
	var b := _person("Gil", 30.0)
	s.set_relation(a.id, b.id, 0.7)
	a.needs = {social = 1.0, faith = 0.0}
	assert_true(life.plan_talk(k, a, GameConstants.TALK_HOURS.x))
	assert_eq(a.deed.get("kind", ""), "talk")
	assert_eq(b.deed.get("kind", ""), "talk", "the friend comes too")
	assert_eq(a.deed.get("anim", ""), GameConstants.ANIM_TALK)
	assert_true((a.deed.pos as Vector3).distance_to(b.deed.pos) < GameConstants.TALK_GAP + 0.01, "face to face")


func test_the_devout_pray_at_the_flag() -> void:
	_fresh()
	var p := _person("Beata", 50.0, [T.DEVOUT], true)
	var skeptic := _person("Cético", 50.0, [T.SKEPTIC])
	_run(0.0, 24 * 3)
	assert_true(_logged("rezou junto à bandeira"), "faith is kept by praying")
	assert_eq(float(skeptic.needs.get("faith", 0.0)), 0.0, "only the devout feel the need")


func test_unmet_needs_weigh_on_contentment() -> void:
	_fresh()
	var p := _person("Só", 30.0)
	var snap := VillageRules.snapshot(s, k, 0.0)
	p.needs = {social = 0.0, faith = 0.0}
	var fine := VillageRules.hourly_contentment(p, snap, true)
	p.needs = {social = 1.0, faith = 1.0}
	assert_true(VillageRules.hourly_contentment(p, snap, true) < fine)


func test_adults_carry_wants() -> void:
	_fresh()
	var greedy := _person("Avarento", 30.0, [T.GREEDY])
	var lover := _person("Romeu", 22.0, [T.SOCIABLE])
	var beloved := _person("Julieta", 21.0, [T.WORKER], true)
	s.set_relation(lover.id, beloved.id, 0.8)
	var kid := _person("Menino", 8.0)
	_run(0.0, 30)
	assert_eq(int(greedy.desire.kind), D.RICH)
	assert_eq(int(lover.desire.kind), D.LOVE)
	assert_eq(int(lover.desire.target_id), int(beloved.id))
	assert_eq(int(kid.desire.kind), D.NONE, "children only dream later")


func test_a_want_fulfilled_is_a_joy() -> void:
	_fresh()
	var lover := _person("Tomé", 25.0, [T.SOCIABLE])
	var beloved := _person("Inês", 24.0, [T.WORKER], true)
	lover.desire = {kind = D.LOVE, target_id = beloved.id}
	lover.spouse_id = beloved.id
	beloved.spouse_id = lover.id
	_run(0.0, 2)
	assert_eq(int(lover.desire.kind), D.NONE, "married to whom he loved")
	assert_true(float(lover.mood.joy) > 0.0)
	assert_true(_logged("realizou"))
