extends GameTest
## Living world (stage 9): relations between kingdoms, envoys (war, peace, gifts), war parties and
## battles. Every act is a deed of a person who walks from one seat to the other.

const B := GameConstants.Building
const T := GameConstants.Trait
const P := GameConstants.Profession
const R := GameConstants.Res

var s: WorldState
var society: SocietySim
var houses: HouseSim
var gov: GovSim
var realms: RealmSim
var a: Dictionary
var b: Dictionary


func _fresh(gap := 200.0) -> void:
	s = WorldState.new()
	s.seed = 99
	society = SocietySim.new()
	houses = HouseSim.new()
	gov = GovSim.new()
	realms = RealmSim.new()
	society.setup(s, func(_k: Dictionary, _t: String) -> void: pass, func(_k: Dictionary) -> bool: return false,
			func(_k: Dictionary) -> Dictionary: return {})
	houses.setup(s, func(_k: Dictionary, _t: String) -> void: pass, society)
	gov.setup(s, houses, func(_k: Dictionary) -> bool: return false)
	realms.setup(s, houses, society, gov)
	a = _realm("Aldor", Vector3(150, 0, 150))
	b = _realm("Bruma", Vector3(150 + gap, 0, 150))


func _realm(name: String, at: Vector3) -> Dictionary:
	var seat := s.add_building(B.CABIN, at, 0, Color.WHITE, GameConstants.OWNER_KINGDOM)
	var k := s.add_kingdom(name, Color.RED, at, seat.id, "npc")
	var head := _person(k, name + "-rei", 45.0, P.FARMER)
	var f := s.add_family(name, Crest.generate(RandomNumberGenerator.new(), []), k.id, head.id, 0.0)
	f.house_init = true
	f.values = {wealth = 0.3, land = 0.5, prestige = 0.5, faith = 0.5, honor = 0.5}
	head.family_id = f.id
	k.ruler_id = head.id
	k.ruler_family = f.id
	k.ruler_way = ""
	k.decrees.guards = GameConstants.GOV_GUARDS_FREE
	return k


func _person(k: Dictionary, name: String, age := 30.0, prof := P.FARMER, traits := [T.WORKER]) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var p := PersonGen.generate(rng, 0.0, prof)
	p.name = name
	p.age = age
	p.traits = traits
	var rec := s.add_person(p, k.center, k.id)
	rec.status = "resident"
	rec.profession = prof
	return rec


func _guards(k: Dictionary, n: int) -> Array:
	var out := []
	for i in n:
		out.append(_person(k, "%s-guarda-%d" % [k.name, i], 25.0, P.GUARD))
	return out


func _run(from: float, hours: int) -> float:
	for i in hours:
		var h := from + i
		for k in s.kingdoms():
			houses.tick_hour(k, h)
			gov.tick_hour(k, h)
		realms.tick_hour(h)
	return from + hours


func _logged(k: Dictionary, part: String) -> bool:
	return s.chronicle_all(k.id, 500).any(func(e: Dictionary) -> bool: return (e.text as String).contains(part))


# --- Rules ---

func test_border_pressure_and_trade() -> void:
	_fresh(120.0)
	var close := RealmRules.daily_drift(s, a, b)
	assert_true(close < 0.0, "near seats strain the relation: %f" % close)
	_fresh(400.0)
	assert_eq(RealmRules.daily_drift(s, a, b), 0.0, "far apart: nothing")
	for k in [a, b]:
		s.add_building(B.MARKET, k.center + Vector3(8, 0, 0), 0, Color.WHITE, GameConstants.OWNER_KINGDOM)
	assert_true(RealmRules.daily_drift(s, a, b) > 0.0, "two markets trade")


func test_ruler_temper_moves_the_relation() -> void:
	_fresh(400.0)
	s.person(int(a.ruler_id)).traits = [T.BRAVE, T.GREEDY]
	assert_true(RealmRules.daily_drift(s, a, b) < 0.0)
	s.person(int(a.ruler_id)).traits = [T.GENEROUS, T.SOCIABLE]
	assert_true(RealmRules.daily_drift(s, a, b) > 0.0)
	assert_true(absf(RealmRules.daily_drift(s, a, b)) <= GameConstants.REALM_DRIFT_MAX)


func test_who_goes_to_war() -> void:
	_fresh()
	_guards(a, 3)
	_guards(b, 1)
	var r := s.realm(a.id, b.id)
	r.rel = GameConstants.REALM_WAR_AT + 0.1
	assert_true(not RealmRules.wants_war(s, a, b, 0.0), "not angry enough")
	r.rel = GameConstants.REALM_WAR_AT - 0.1
	assert_true(RealmRules.wants_war(s, a, b, 0.0))
	assert_true(not RealmRules.wants_war(s, b, a, 0.0), "the weaker side does not start it")
	r.truce_until = 100.0
	assert_true(not RealmRules.wants_war(s, a, b, 50.0), "truce")
	r.truce_until = -1.0
	b.ruler_id = GameConstants.GOV_PLAYER
	assert_true(not RealmRules.wants_war(s, a, b, 0.0), "no NPC war on a kingdom the player rules")


func test_battle_favors_the_stronger_and_the_defender() -> void:
	_fresh()
	_guards(b, 2)
	var wins := 0
	for i in 40:
		var rng := RandomNumberGenerator.new()
		rng.seed = i
		if RealmRules.battle(s, a, b, 2, rng).attacker_wins:
			wins += 1
	assert_true(wins < 20, "two attackers against two defenders at home win too often: %d/40" % wins)
	wins = 0
	for i in 40:
		var rng := RandomNumberGenerator.new()
		rng.seed = i
		if RealmRules.battle(s, a, b, 6, rng).attacker_wins:
			wins += 1
	assert_true(wins > 30, "six against two should win: %d/40" % wins)


# --- Envoys and war ---

func test_war_is_declared_by_an_envoy() -> void:
	_fresh()
	_guards(a, 3)
	s.realm(a.id, b.id).rel = -0.9
	var h := _run(0.0, int(GameConstants.REALM_HOUR) + 1)
	var envoy := s.residents(a.id).filter(func(p: Dictionary) -> bool:
		return (p.get("deed", {}) as Dictionary).get("kind", "") == "envoy")
	assert_eq(envoy.size(), 1, "an envoy sets out")
	assert_true(not s.at_war(a.id, b.id), "nothing before the envoy arrives")
	_run(h, 30)
	assert_true(s.at_war(a.id, b.id))
	assert_true(_logged(a, "declarou guerra") and _logged(b, "declarou guerra"))


func test_war_party_marches_and_fights() -> void:
	_fresh()
	_guards(a, 5)
	_guards(b, 1)
	s.add_stock(b, R.WOOD, 100)
	var hut := s.add_building(B.FARM, b.center + Vector3(10, 0, 0), 0, Color.WHITE, GameConstants.OWNER_KINGDOM)
	var burned := []
	realms.building_burned.connect(func(rec: Dictionary) -> void: burned.append(rec.id))
	var r := s.realm(a.id, b.id)
	r.war = true
	r.since = 0.0
	_run(0.0, 24 * 3)
	assert_true(_logged(a, "batalha") and _logged(b, "batalha"), "a battle was fought")
	assert_true(s.stock_of(a, R.WOOD) > 0, "the winner looted")
	assert_true(burned.has(hut.id) and s.building(hut.id).is_empty(), "a building burned")
	assert_true(not s.building(int(b.seat_id)).is_empty(), "never the seat")
	assert_true((float(r.weary_a) > 0.0 and float(r.weary_b) > 0.0) or _logged(a, "paz"), "the war wears both sides")


func test_battle_deaths_go_through_the_society() -> void:
	_fresh()
	var g: Array = _guards(b, 1)
	var died := []
	society.person_died.connect(func(rec: Dictionary) -> void: died.append(rec.id))
	realms._casualties(b, [g[0]], 1)
	assert_eq(died, [g[0].id])
	assert_eq(String(s.person(int(g[0].id)).status), "dead", "the fallen lie on the field until buried")


func test_weary_sides_make_peace_by_envoy() -> void:
	_fresh()
	var r := s.realm(a.id, b.id)
	r.war = true
	r.weary_a = GameConstants.REALM_PEACE_WEARY
	r.weary_b = GameConstants.REALM_PEACE_ACCEPT
	_run(0.0, 48)
	assert_true(not s.at_war(a.id, b.id), "peace was made")
	assert_true(float(r.truce_until) > 0.0)
	assert_true(float(r.rel) >= GameConstants.REALM_PEACE_REL)
	assert_true(_logged(a, "paz"))


func test_gift_raises_the_relation_on_arrival() -> void:
	_fresh()
	s.add_stock(a, R.WOOD, 100)
	assert_true(realms.send_envoy(a, b, "gift", 0.0), "someone free carries it")
	var rel := float(s.realm(a.id, b.id).rel)
	_run(0.0, 30)
	assert_true(float(s.realm(a.id, b.id).rel) > rel)
	assert_true(s.stock_of(b, R.WOOD) >= GameConstants.REALM_GIFT)


func test_npc_ruler_at_war_calls_up_the_guard() -> void:
	_fresh()
	s.realm(a.id, b.id).war = true
	_run(0.0, int(GameConstants.REALM_HOUR) + 1)
	assert_eq(int(a.decrees.guards), GameConstants.GOV_GUARDS_MAX)


# --- Exodus ---

func _rebel_house(k: Dictionary, wealth := 300.0) -> Dictionary:
	var head := _person(k, "Rebelde-chefe", 40.0)
	var f := s.add_family("Rebelde", Crest.generate(RandomNumberGenerator.new(), []), k.id, head.id, 0.0)
	f.house_init = true
	f.wealth = wealth
	head.family_id = f.id
	for i in GameConstants.REALM_EXODUS_ADULTS - 1:
		_person(k, "Rebelde-%d" % i, 25.0).family_id = f.id
	s.set_relation(head.id, int(k.ruler_id), -0.9)
	return f


func test_a_house_that_hates_the_ruler_founds_a_kingdom() -> void:
	_fresh(400.0)
	var gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
	realms.set_terrain(gen, PropScatter.new(gen, GameConstants.WORLD_SEED))
	var f := _rebel_house(a)
	var head := s.person(int(f.head_id))
	var h := _run(0.0, int(GameConstants.REALM_HOUR) + 1)
	assert_eq(head.deed.get("kind", ""), "exodus", "the head sets out to found a kingdom")
	assert_eq(s.kingdoms().size(), 2, "nothing before the head arrives")
	_run(h, 30)
	assert_eq(s.kingdoms().size(), 3)
	var nk: Dictionary = s.kingdoms()[2]
	assert_eq(String(nk.founder), "npc")
	assert_eq(int(nk.ruler_id), int(head.id), "the head rules the new kingdom")
	assert_true(s.family_members(f.id).all(func(p: Dictionary) -> bool: return int(p.kingdom_id) == nk.id))
	assert_eq(int(f.kingdom_id), nk.id)
	assert_true(float(f.wealth) < 300.0, "the House paid for the settlement")
	for o in s.kingdoms():
		if o.id != nk.id:
			assert_true(PackSim._flat_dist(o.center, nk.center) >= GameConstants.REALM_MIN_GAP)
	assert_true(float(s.realm(a.id, nk.id).rel) < 0.0, "they left in anger")
	assert_true(_logged(a, "fundou o Reino"))


func test_no_exodus_without_means_or_anger() -> void:
	_fresh(400.0)
	var gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
	realms.set_terrain(gen, PropScatter.new(gen, GameConstants.WORLD_SEED))
	var poor := _rebel_house(a, GameConstants.REALM_EXODUS_WEALTH - 1.0)
	_run(0.0, 40)
	assert_eq(s.kingdoms().size(), 2, "too poor to found a kingdom")
	poor.wealth = 300.0
	s.set_relation(int(poor.head_id), int(a.ruler_id), 0.5)
	_run(40.0, 40)
	assert_eq(s.kingdoms().size(), 2, "content Houses stay")


# --- Final review fixes ---

func test_exodus_takes_spouses_and_children_from_other_houses() -> void:
	_fresh(400.0)
	var gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
	realms.set_terrain(gen, PropScatter.new(gen, GameConstants.WORLD_SEED))
	var f := _rebel_house(a)
	var head := s.person(int(f.head_id))
	var wife := _person(a, "Esposa", 38.0)
	wife.female = true
	wife.family_id = int(s.person(int(a.ruler_id)).family_id) # married in from the ruler's House
	head.spouse_id = wife.id
	wife.spouse_id = head.id
	var kid := _person(a, "Filho", 8.0)
	kid.parents = [head.id, wife.id]
	kid.family_id = wife.family_id
	_run(0.0, 40)
	assert_eq(s.kingdoms().size(), 3)
	var nk: Dictionary = s.kingdoms()[2]
	assert_eq(int(wife.kingdom_id), nk.id, "the wife goes with her husband")
	assert_eq(int(kid.kingdom_id), nk.id, "and their child")
	assert_eq(int(wife.family_id), f.id)


func test_war_envoy_checks_again_on_arrival() -> void:
	_fresh()
	_guards(a, 3)
	var deed := Deeds.make("envoy", b.center, 1.0, 0.0, 10.0, 5.0, {kingdom_id = a.id, target_id = b.id, act = "war"})
	b.ruler_id = GameConstants.GOV_PLAYER # the founder came back while the envoy walked
	realms.complete_deed(a, s.person(int(a.ruler_id)), deed, [], 5.0)
	assert_true(not s.at_war(a.id, b.id), "no NPC war on a kingdom the player rules")
	b.ruler_id = -5
	s.realm(a.id, b.id).truce_until = 100.0 # a peace was made meanwhile
	realms.complete_deed(a, s.person(int(a.ruler_id)), deed, [], 50.0)
	assert_true(not s.at_war(a.id, b.id), "the truce holds")


func test_war_guard_lets_go_when_the_player_rules() -> void:
	_fresh()
	s.realm(a.id, b.id).war = true
	_run(0.0, int(GameConstants.REALM_HOUR) + 1)
	assert_true(a.war_guard)
	a.ruler_id = GameConstants.GOV_PLAYER
	a.decrees.guards = 1 # the founder's own choice
	_run(GameConstants.REALM_HOUR + 1.0, 24)
	assert_true(not a.get("war_guard", false), "the regent's call-up is forgotten")
	assert_eq(int(a.decrees.guards), 1, "the founder's decree stands")


func test_exodus_site_is_checked_again_when_the_head_arrives() -> void:
	_fresh(400.0)
	var gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
	realms.set_terrain(gen, PropScatter.new(gen, GameConstants.WORLD_SEED))
	var f := _rebel_house(a)
	var head := s.person(int(f.head_id))
	_run(0.0, int(GameConstants.REALM_HOUR) + 1)
	var site: Vector3 = head.deed.data.site
	s.add_building(B.HOUSE, site, 0) # someone built there meanwhile
	_run(GameConstants.REALM_HOUR + 1.0, 30)
	assert_eq(s.kingdoms().size(), 2, "no kingdom on top of a house")
	assert_eq(int(head.kingdom_id), a.id)
