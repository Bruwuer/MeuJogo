extends GameTest
## Life (stage 10): the dead lie where they fell until someone carries them to the cemetery, digs a
## grave and buries them; the family prays at the grave; grief, fear and joy come and go.

const B := GameConstants.Building
const T := GameConstants.Trait
const P := GameConstants.Profession

var s: WorldState
var society: SocietySim
var houses: HouseSim
var gov: GovSim
var life: LifeSim
var k: Dictionary


func _fresh() -> void:
	s = WorldState.new()
	s.seed = 10
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
	k = s.add_kingdom("Ravmia", Color.RED, seat.pos, seat.id)
	k.ruler_id = GameConstants.GOV_PLAYER


func _person(name: String, age := 30.0, female := false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var p := PersonGen.generate(rng)
	p.name = name
	p.age = age
	p.female = female
	p.traits = [T.WORKER]
	var rec := s.add_person(p, k.center + Vector3(5, 0, 0), k.id)
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


# --- The body ---

func test_the_dead_stay_where_they_fell() -> void:
	_fresh()
	var old := _person("Velho", 80.0)
	var wife := _person("Viúva", 75.0, true)
	old.spouse_id = wife.id
	wife.spouse_id = old.id
	var where: Vector3 = old.pos
	society.kill(k, old, "")
	var body := s.person(int(old.id))
	assert_true(not body.is_empty(), "the body is still there")
	assert_eq(String(body.status), "dead")
	assert_eq(body.pos, where)
	assert_true(not s.residents(k.id).has(body), "the dead are no residents")
	assert_eq(int(wife.spouse_id), -1)
	assert_true(wife.widowed)


func test_someone_carries_the_body_digs_and_buries_it() -> void:
	_fresh()
	var dead := _person("Defunto", 70.0)
	var son := _person("Filho", 30.0)
	son.parents = [dead.id]
	var stranger := _person("Estranho", 30.0)
	society.kill(k, dead, "")
	var h := _run(0.0, int(GameConstants.DEED_DAY.x)) # the errand waits for the morning
	var deed: Dictionary = son.get("deed", {})
	assert_eq(deed.get("kind", ""), "fetch_body", "the son goes for his father's body")
	assert_eq(deed.get("anim", ""), GameConstants.ANIM_PICKUP)
	assert_true((deed.pos as Vector3).distance_to(dead.pos) < 0.01)
	h = _run(h, 1)
	assert_eq(int(son.get("carrying_body", -1)), int(dead.id), "he carries the body")
	assert_eq((son.deed as Dictionary).get("kind", ""), "bury")
	assert_eq((son.deed as Dictionary).get("anim", ""), GameConstants.ANIM_DIG)
	_run(h, 12)
	assert_true(s.person(int(dead.id)).is_empty(), "buried: the body left the world")
	var graves := s.all_buildings().filter(func(b: Dictionary) -> bool: return int(b.type) == B.GRAVE)
	assert_eq(graves.size(), 1)
	assert_eq(String(graves[0].get("name", "")), PersonGen.full_name(dead))
	assert_eq(int(son.get("carrying_body", -1)), -1)
	assert_true(_logged("enterrou"))


func test_graves_line_up_in_the_cemetery() -> void:
	_fresh()
	_person("Coveiro", 30.0)
	for i in 3:
		society.kill(k, _person("Morto%d" % i, 70.0), "")
	_run(0.0, 24 * 3)
	var graves := s.all_buildings().filter(func(b: Dictionary) -> bool: return int(b.type) == B.GRAVE)
	assert_eq(graves.size(), 3)
	for i in graves.size():
		for j in range(i + 1, graves.size()):
			assert_true((graves[i].pos as Vector3).distance_to(graves[j].pos) >= GameConstants.GRAVE_SPACING * 0.9, "graves overlap")
	assert_true(Vector2(graves[0].pos.x - k.center.x, graves[0].pos.z - k.center.z).length() <= k.radius, "inside the kingdom")


func test_the_family_prays_at_the_grave() -> void:
	_fresh()
	var dead := _person("Avó", 75.0, true)
	var daughter := _person("Filha", 40.0, true)
	daughter.parents = [dead.id]
	var digger := _person("Coveiro", 30.0)
	society.kill(k, dead, "")
	assert_true(float(daughter.mood.grief) > 0.0, "grief for her mother")
	_run(0.0, 24 * 2)
	assert_true(_logged("rezou"), "the daughter prayed at the grave")
	assert_true(float(daughter.mood.grief) < GameConstants.GRIEF_KIN, "praying eases grief")


# --- Feelings ---

func test_grief_for_kin_and_friends() -> void:
	_fresh()
	var dead := _person("Amigo", 60.0)
	var kid := _person("Criança", 10.0)
	kid.parents = [dead.id]
	var friend := _person("Compadre", 50.0)
	s.set_relation(friend.id, dead.id, 0.8)
	var stranger := _person("Desconhecido", 50.0)
	society.kill(k, dead, "")
	assert_true(float(kid.mood.grief) >= GameConstants.GRIEF_KIN)
	assert_true(float(friend.mood.grief) >= GameConstants.GRIEF_FRIEND)
	assert_eq(float(stranger.mood.grief), 0.0)
	assert_eq(String(kid.mood.get("grief_for", "")), PersonGen.full_name(dead))


func test_moods_fade_and_weigh_on_contentment() -> void:
	_fresh()
	var p := _person("Triste", 40.0)
	LifeRules.add_mood(p, "grief", 0.8)
	var snap := VillageRules.snapshot(s, k, 0.0)
	var sad := VillageRules.hourly_contentment(p, snap, true)
	p.mood.grief = 0.0
	assert_true(sad < VillageRules.hourly_contentment(p, snap, true), "grief weighs on contentment")
	LifeRules.add_mood(p, "fear", 0.6)
	for i in 48:
		LifeRules.fade_moods(p, 1.0)
	assert_true(float(p.mood.fear) < 0.2, "fear fades in two days: %f" % p.mood.fear)


func test_an_unburied_body_frightens_the_kingdom() -> void:
	_fresh()
	var dead := _person("Esquecido", 70.0)
	var p := _person("Vizinho", 30.0)
	p.deed = Deeds.make("visit", k.center, 1.0, 1e6, 1e6 + 1, 5.0) # busy forever: nobody can bury
	society.kill(k, dead, "")
	var before := float(p.contentment)
	_run(0.0, int(GameConstants.BODY_UNBURIED_HOURS) + 6)
	assert_true(float(p.mood.fear) > 0.0, "a body lying around frightens")
	assert_true(float(p.contentment) < before)


func test_the_card_tells_the_strongest_feeling() -> void:
	_fresh()
	var p := _person("Enlutada", 40.0, true)
	LifeRules.add_mood(p, "grief", 0.7, "Ana Souto")
	assert_true(LifeRules.mood_text(p).contains("luto por Ana Souto"), LifeRules.mood_text(p))
	p.mood.grief = 0.0
	LifeRules.add_mood(p, "joy", 0.5)
	assert_true(LifeRules.mood_text(p).contains("feliz"), LifeRules.mood_text(p))


# --- Final review fixes ---

func _carrying(bearer: Dictionary, body: Dictionary) -> void:
	body.carrier_id = bearer.id
	bearer.carrying_body = body.id


func test_a_body_dropped_by_its_carrier_is_fetched_again() -> void:
	_fresh()
	var dead := _person("Largado", 70.0)
	var bearer := _person("Carregador", 30.0)
	var other := _person("Outro", 30.0)
	society.kill(k, dead, "")
	_carrying(bearer, dead)
	bearer.deed = {} # the bury errand was lost (window passed on screen, an exodus cleared it...)
	_run(0.0, int(GameConstants.DEED_DAY.x))
	assert_eq(int(dead.carrier_id), -1, "the body is free again")
	assert_eq(int(bearer.carrying_body), -1)
	var going := s.residents(k.id).filter(func(p: Dictionary) -> bool:
		return (p.get("deed", {}) as Dictionary).get("kind", "") == "fetch_body")
	assert_eq(going.size(), 1, "someone goes for it again")


func test_a_carrier_who_dies_drops_the_body() -> void:
	_fresh()
	var dead := _person("Primeiro", 70.0)
	var bearer := _person("Segundo", 75.0)
	_person("Terceiro", 30.0)
	society.kill(k, dead, "")
	_carrying(bearer, dead)
	society.kill(k, bearer, "")
	assert_eq(int(dead.carrier_id), -1, "the dead carrier lets go")
	_run(0.0, 24 * 2)
	assert_true(s.person(int(dead.id)).is_empty() and s.person(int(bearer.id)).is_empty(), "both were buried")


func test_killing_the_dead_does_nothing() -> void:
	_fresh()
	var p := _person("Uma vez", 70.0)
	var deaths := []
	society.person_died.connect(func(r: Dictionary) -> void: deaths.append(r.id))
	society.kill(k, p, "")
	society.kill(k, p, "")
	assert_eq(deaths.size(), 1)
