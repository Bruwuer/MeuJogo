extends GameTest
## Government in motion (stage 8): absence and succession, the founder's return, taxes, the guard,
## the NPC ruler (corruption, cult, enmity) and deposition. Every act is a deed (rule 17).

const B := GameConstants.Building
const T := GameConstants.Trait
const P := GameConstants.Profession
const TR := GameConstants.Tradition
const R := GameConstants.Res

var s: WorldState
var k: Dictionary
var society: SocietySim
var houses: HouseSim
var gov: GovSim
var player_in := true
var seat: Dictionary


## A new world for each test (the runner keeps one instance for the whole file).
func _fresh() -> void:
	s = WorldState.new()
	society = SocietySim.new()
	houses = HouseSim.new()
	gov = GovSim.new()
	player_in = true
	s.seed = 88
	seat = s.add_building(B.CABIN, Vector3(300, 0, 300), 0)
	k = s.add_kingdom("Ravmia", Color.RED, seat.pos, seat.id)
	society.setup(s, func(_k: Dictionary, _t: String) -> void: pass, func(_k: Dictionary) -> bool: return player_in,
			func(_k: Dictionary) -> Dictionary: return {})
	houses.setup(s, func(_k: Dictionary, _t: String) -> void: pass, society)
	gov.setup(s, houses, func(_k: Dictionary) -> bool: return player_in)


func _person(name: String, age := 30.0, traits := [T.WORKER]) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var p := PersonGen.generate(rng)
	p.name = name
	p.age = age
	p.traits = traits
	p.opinion = 0.0
	var rec := s.add_person(p, k.center, k.id)
	rec.status = "resident"
	return rec


func _house(surname: String, prestige := 0.0, opinion := 0.0, traits := [T.WORKER]) -> Dictionary:
	var head := _person(surname + "-chefe", 45.0, traits)
	head.opinion = opinion
	var f := s.add_family(surname, Crest.generate(RandomNumberGenerator.new(), []), k.id, head.id, 0.0)
	f.house_init = true
	f.prestige = prestige
	f.wealth = 100.0
	f.tradition = TR.FARMERS
	f.values = {wealth = 0.3, land = 0.5, prestige = 0.5, faith = 0.5, honor = 0.5}
	head.family_id = f.id
	return f


## Runs `hours` simulated hours from `from` (each deed done offscreen when due).
func _run(from: float, hours: int) -> float:
	for i in hours:
		var h := from + i
		houses.tick_hour(k, h)
		gov.tick_hour(k, h)
	return from + hours


func _chronicle_has(part: String) -> bool:
	return s.chronicle_all(k.id, 500).any(func(e: Dictionary) -> bool: return (e.text as String).contains(part))


# --- Absence and succession ---

func test_a_regent_is_crowned_after_the_founder_is_away() -> void:
	_fresh()
	var f := _house("Forte", 3.0, 0.6)
	var head := s.person(int(f.head_id))
	player_in = false
	var h := _run(0.0, int(GameConstants.GOV_ABSENCE_HOURS) - 1)
	assert_eq(int(k.ruler_id), GameConstants.GOV_PLAYER, "not yet")
	h = _run(h, 2)
	assert_eq(head.deed.get("kind", ""), "crowning", "the regent goes to the seat to take power")
	assert_eq(int(k.ruler_id), GameConstants.GOV_PLAYER, "nothing changes before the ceremony")
	_run(h, 30)
	assert_eq(int(k.ruler_id), int(head.id))
	assert_eq(String(k.ruler_way), "leal")
	assert_true(_chronicle_has("assumiu o governo"))
	player_in = true


func test_returning_before_the_ceremony_cancels_it() -> void:
	_fresh()
	var f := _house("Breve", 3.0, 0.0)
	player_in = false
	var h := _run(0.0, int(GameConstants.GOV_ABSENCE_HOURS) + 1)
	assert_eq(s.person(int(f.head_id)).deed.get("kind", ""), "crowning")
	player_in = true
	_run(h, 30)
	assert_eq(int(k.ruler_id), GameConstants.GOV_PLAYER)
	assert_eq(float(k.away_hours), 0.0)
	assert_true((s.person(int(f.head_id)).deed as Dictionary).is_empty(), "the ceremony is called off")


func test_a_dead_ruler_is_succeeded_by_the_heir() -> void:
	_fresh()
	var f := _house("Coroa", 3.0, 0.0)
	var heir := _person("Herdeira", 30.0)
	heir.family_id = f.id
	k.ruler_id = f.head_id
	k.ruler_family = f.id
	k.ruler_way = "neutro"
	player_in = false
	s.remove_person(int(f.head_id))
	_run(0.0, 30)
	assert_eq(int(k.ruler_id), int(heir.id))
	assert_true(_chronicle_has("herdou o governo"))
	player_in = true


# --- The founder's return ---

func test_a_loyal_regent_hands_the_kingdom_back() -> void:
	_fresh()
	var f := _house("Fiel", 3.0, 0.8)
	k.ruler_id = f.head_id
	k.ruler_way = "leal"
	player_in = true
	_run(0.0, 30)
	assert_eq(int(k.ruler_id), GameConstants.GOV_PLAYER)
	assert_true(_chronicle_has("devolveu o governo"))


func test_an_enemy_ruler_keeps_it_and_the_founder_is_a_stranger() -> void:
	_fresh()
	var f := _house("Hostil", 3.0, -0.8)
	k.ruler_id = f.head_id
	k.ruler_way = "inimigo"
	player_in = true
	_run(0.0, 30)
	assert_eq(int(k.ruler_id), int(f.head_id))
	assert_true(not gov.player_may_act(k), "the founder cannot build or donate here")
	assert_eq(gov.refusal(k), GameConstants.GOV_NOT_YOURS % ["Ravmia", PersonGen.full_name(s.person(int(f.head_id)))])
	assert_true(_chronicle_has("não devolve o governo"))
	k.ruler_id = GameConstants.GOV_PLAYER
	assert_true(gov.player_may_act(k))


# --- Decrees: tax and the guard ---

func test_tax_is_carried_to_the_seat() -> void:
	_fresh()
	var f := _house("Pagante", 1.0)
	f.wealth = 200.0
	k.decrees.tax = "high"
	var stock_before := 0
	for r in [R.WOOD, R.STONE, R.FOOD]:
		stock_before += s.stock_of(k, r)
	_run(0.0, int(GameConstants.DEED_HOUR) + 1)
	var head := s.person(int(f.head_id))
	assert_eq(head.deed.get("kind", ""), "tax", "the head takes the tax to the seat")
	assert_eq(float(f.wealth), 200.0, "nothing paid before the walk")
	_run(GameConstants.DEED_HOUR + 1.0, 24)
	assert_true(float(f.wealth) < 200.0)
	var stock_after := 0
	for r in [R.WOOD, R.STONE, R.FOOD]:
		stock_after += s.stock_of(k, r)
	assert_true(stock_after > stock_before, "the kingdom stock grew")
	assert_true(_chronicle_has("pagou o imposto"))
	k.decrees.tax = "none"


func test_poor_houses_pay_no_tax() -> void:
	_fresh()
	var f := _house("Pobre", 1.0)
	f.wealth = GameConstants.GOV_TAX_FLOOR - 1.0
	k.decrees.tax = "high"
	_run(0.0, 30)
	assert_eq(float(f.wealth), GameConstants.GOV_TAX_FLOOR - 1.0)
	k.decrees.tax = "none"


func test_tax_never_replaces_another_deed() -> void:
	_fresh()
	var f := _house("Ocupada", 1.0)
	f.wealth = 200.0
	var head := s.person(int(f.head_id))
	head.deed = Deeds.make("skim", k.center, 1.0, 1000.0, 1004.0, 5.0, {family_id = f.id})
	k.decrees.tax = "low"
	_run(0.0, int(GameConstants.DEED_HOUR) + 1)
	assert_eq(head.deed.kind, "skim", "the head's own errand is kept")
	k.decrees.tax = "none"


func test_muster_and_dismissal() -> void:
	_fresh()
	var w := _house("Lanceiros", 1.0)
	w.tradition = TR.WARRIORS
	var son := _person("Soldado", 20.0)
	son.family_id = w.id
	son.profession = P.FARMER
	k.decrees.guards = 1
	_run(0.0, 30)
	var guards := s.residents(k.id).filter(func(p: Dictionary) -> bool: return int(p.profession) == P.GUARD)
	assert_eq(guards.size(), 1, "one guard was mustered")
	assert_true(_chronicle_has("convocado para a guarda"))
	k.decrees.guards = 0
	_run(30.0, 30)
	guards = s.residents(k.id).filter(func(p: Dictionary) -> bool: return int(p.profession) == P.GUARD)
	assert_eq(guards.size(), 0)
	assert_true(_chronicle_has("dispensado da guarda"))
	k.decrees.guards = GameConstants.GOV_GUARDS_FREE


# --- The NPC ruler ---

func test_corrupt_ruler_skims_at_night() -> void:
	_fresh()
	var f := _house("Ganancia", 3.0, 0.0, [T.GREEDY])
	s.add_stock(k, R.WOOD, 100)
	k.ruler_id = f.head_id
	k.ruler_way = "neutro"
	k.ruler_corrupt = true
	k.ruler_since = 0.0
	player_in = false
	var wealth := float(f.wealth)
	_run(0.0, 24 * 6)
	assert_true(int(k.ruler_skimmed) > 0, "a corrupt ruler took from the stock")
	assert_true(float(f.wealth) > wealth, "and his House got richer")
	player_in = true


func test_cult_prayers_raise_the_founder() -> void:
	_fresh()
	var f := _house("Devota", 3.0, 0.9, [T.DEVOUT])
	var pious := _person("Beata", 50.0, [T.DEVOUT])
	pious.opinion = 0.2
	s.add_building(B.FLAG, seat.pos + Vector3(3, 0, 0), 0)
	k.ruler_id = f.head_id
	k.ruler_way = "culto"
	player_in = false
	_run(0.0, 24 * 3)
	assert_true(float(pious.opinion) > 0.2, "she prays to the founder at dusk")
	assert_true(_chronicle_has("rezou ao fundador"))
	player_in = true


func test_away_opinion_drifts_by_the_ruler_way() -> void:
	_fresh()
	k.ruler_id = 999
	k.ruler_way = "inimigo"
	assert_eq(GovRules.away_target(k), GameConstants.GOV_ENEMY_TARGET)
	k.ruler_way = "culto"
	assert_eq(GovRules.away_target(k), GameConstants.GOV_CULT_TARGET)
	k.ruler_id = GameConstants.GOV_PLAYER
	assert_eq(GovRules.away_target(k), 0.0)


func test_hated_ruler_is_deposed_by_the_heads() -> void:
	_fresh()
	var tyrant := _house("Tirano", 3.0, 0.0)
	var a := _house("Rebelde", 1.0, 0.0)
	var b := _house("Revolta", 1.0, 0.0)
	for f in [a, b]:
		s.set_relation(int(f.head_id), int(tyrant.head_id), -0.9)
	k.ruler_id = tyrant.head_id
	k.ruler_way = "neutro"
	k.ruler_since = 0.0
	player_in = false
	_run(GameConstants.GOV_MIN_REIGN_HOURS, 48)
	assert_true(int(k.ruler_id) != int(tyrant.head_id), "the hated ruler fell")
	assert_true(_chronicle_has("foi deposto"))
	player_in = true


# --- The founder's decrees ---

func test_founder_decree_moves_opinions() -> void:
	_fresh()
	var rich := _house("Rica", 1.0)
	rich.values.wealth = 0.9
	var head := s.person(int(rich.head_id))
	head.opinion = 0.2
	assert_true(gov.set_decree(k, "tax", "high"))
	assert_true(float(head.opinion) < 0.2)
	assert_true(_chronicle_has("Decreto"))
	assert_true(gov.set_decree(k, "tax", "none"))
	k.ruler_id = tyrant_id()
	assert_true(not gov.set_decree(k, "tax", "high"), "only the ruler decrees")
	k.ruler_id = GameConstants.GOV_PLAYER


func tyrant_id() -> int:
	return 12345


# --- Final review fixes ---

func test_deposition_with_the_founder_present_but_disliked_crowns_a_regent() -> void:
	_fresh()
	var tyrant := _house("Odioso", 3.0, 0.0)
	var a := _house("Contra", 2.0, -0.5)
	var b := _house("Oposto", 1.0, -0.5)
	for f in [a, b]:
		s.set_relation(int(f.head_id), int(tyrant.head_id), -0.9)
	k.ruler_id = tyrant.head_id
	k.ruler_family = tyrant.id
	k.ruler_way = "inimigo"
	k.ruler_since = 0.0
	player_in = true # the founder is here, but the people do not want him back
	_run(GameConstants.GOV_MIN_REIGN_HOURS, 72)
	assert_true(int(k.ruler_id) >= 0 and int(k.ruler_id) != int(tyrant.head_id), "ruler: %d" % int(k.ruler_id))


func test_heir_is_crowned_even_with_the_founder_present() -> void:
	_fresh()
	var f := _house("Dinastia", 3.0, -0.8)
	var heir := _person("Filho", 30.0)
	heir.family_id = f.id
	heir.opinion = -0.8
	k.ruler_id = f.head_id
	k.ruler_family = f.id
	k.ruler_way = "inimigo"
	player_in = true
	s.remove_person(int(f.head_id))
	_run(0.0, 30)
	assert_eq(int(k.ruler_id), int(heir.id), "the heir takes the throne, not the founder")


func test_nobody_rules_until_someone_grows_up() -> void:
	_fresh()
	var kid := _person("Criança", 10.0)
	k.ruler_id = GameConstants.GOV_NOBODY
	player_in = false
	_run(0.0, 5)
	assert_eq(int(k.ruler_id), GameConstants.GOV_NOBODY)
	kid.age = 30.0
	_run(5.0, 40)
	assert_eq(int(k.ruler_id), int(kid.id), "an adult at last: crowned")


func test_refusal_with_a_vanished_ruler_does_not_crash() -> void:
	_fresh()
	var f := _house("Sumido", 3.0, -0.8)
	k.ruler_id = f.head_id
	k.ruler_way = "inimigo"
	s.remove_person(int(f.head_id))
	assert_true(gov.player_may_act(k), "nobody to keep the founder out")
	assert_true(gov.refusal(k) != "")


func test_deposition_only_hits_the_ruler_it_was_meant_for() -> void:
	_fresh()
	var old := _house("Antigo", 3.0)
	var leader := _house("Chefe", 1.0)
	var heir := _person("Novo", 30.0)
	k.ruler_id = heir.id
	k.ruler_way = "neutro"
	var deed := Deeds.make("depose", k.center, 1.0, 0.0, 4.0, 5.0, {kingdom_id = k.id, ruler_id = old.head_id})
	assert_true(gov.complete_deed(k, s.person(int(leader.head_id)), deed, [], 1.0))
	assert_eq(int(k.ruler_id), int(heir.id), "a plot against the old ruler does not topple the new one")


func test_handover_needs_the_founder_there() -> void:
	_fresh()
	var f := _house("Leal", 3.0, 0.8)
	k.ruler_id = f.head_id
	k.ruler_way = "leal"
	player_in = false
	var deed := Deeds.make("handover", k.center, 1.0, 0.0, 4.0, 5.0, {kingdom_id = k.id})
	gov.complete_deed(k, s.person(int(f.head_id)), deed, [], 1.0)
	assert_eq(int(k.ruler_id), int(f.head_id), "the founder left before the handover")
	player_in = true


func test_ruler_house_is_the_live_one() -> void:
	_fresh()
	var f := _house("Viva", 3.0)
	var other := _house("Outra", 1.0)
	other.wealth = 200.0
	f.wealth = 200.0
	k.ruler_id = f.head_id
	k.ruler_family = 9999 # stale: the House was absorbed by a union
	k.ruler_way = "neutro"
	k.decrees.tax = "high"
	player_in = false
	_run(0.0, 30)
	assert_eq(float(f.wealth), 200.0, "the ruler's own House pays no tax")
	assert_true(float(other.wealth) < 200.0)
	player_in = true


func test_lost_tax_deed_is_tried_again() -> void:
	_fresh()
	var f := _house("Teimosa", 1.0)
	f.wealth = 200.0
	k.decrees.tax = "low"
	_run(0.0, int(GameConstants.DEED_HOUR) + 1)
	var head := s.person(int(f.head_id))
	assert_eq(head.deed.get("kind", ""), "tax")
	head.deed = {} # lost (replaced or dropped)
	_run(GameConstants.DEED_HOUR + 1.0, 26)
	assert_true(float(f.wealth) < 200.0, "the House pays the next day")


# --- Stage 9: kingdoms founded by NPCs ---

func test_npc_kingdom_crowns_its_own_even_with_the_player_there() -> void:
	_fresh()
	k.founder = "npc"
	k.ruler_id = GameConstants.GOV_NOBODY
	var f := _house("Nativa", 3.0, 0.9, [T.DEVOUT])
	player_in = true
	_run(0.0, 30)
	assert_eq(int(k.ruler_id), int(f.head_id), "a visitor never takes over")
	assert_eq(String(k.ruler_way), "", "an NPC kingdom's ruler has no stance toward the visitor")
	assert_true(not gov.player_may_build(k))
	assert_true(gov.player_may_donate(k), "a gift to the people is welcome")


func test_npc_ruler_never_hands_over_to_the_visitor() -> void:
	_fresh()
	k.founder = "npc"
	var f := _house("Dona", 3.0, 0.9)
	k.ruler_id = f.head_id
	k.ruler_way = "leal"
	player_in = true
	_run(0.0, 30)
	assert_eq(int(k.ruler_id), int(f.head_id))
	assert_true((s.person(int(f.head_id)).deed as Dictionary).is_empty(), "no walk to hand anything over")


func test_npc_houses_give_no_gifts_to_the_visitor() -> void:
	_fresh()
	k.founder = "npc"
	var f := _house("Amiga", 1.0, 0.9)
	f.stance = "ally"
	f.deed_day = -1
	s.add_stock(k, R.WOOD, 50)
	var before := s.get_resource(R.WOOD)
	society._hour = GameConstants.DEED_HOUR
	society._deeds(k)
	assert_eq(s.get_resource(R.WOOD), before)
