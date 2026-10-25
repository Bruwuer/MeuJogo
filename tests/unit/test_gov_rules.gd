extends GameTest
## Government (stage 8): who rules, how a ruler behaves, decrees and their effect on the village.

const B := GameConstants.Building
const T := GameConstants.Trait
const TR := GameConstants.Tradition

var s := WorldState.new()
var k: Dictionary


func _init() -> void:
	s.seed = 8
	k = s.add_kingdom("Ravmia", Color.RED, Vector3(100, 0, 100), -1)


func _person(name: String, age := 30.0, traits := [T.WORKER]) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var p := PersonGen.generate(rng)
	p.name = name
	p.age = age
	p.traits = traits
	var rec := s.add_person(p, k.center, k.id)
	rec.status = "resident"
	return rec


func _house(surname: String, prestige := 0.0, members := 0) -> Dictionary:
	var head := _person(surname + "-chefe", 45.0)
	var f := s.add_family(surname, Crest.generate(RandomNumberGenerator.new(), []), k.id, head.id, 0.0)
	f.prestige = prestige
	f.values = {wealth = 0.3, land = 0.5, prestige = 0.5, faith = 0.5, honor = 0.5}
	head.family_id = f.id
	for i in members:
		_person("%s-%d" % [surname, i], 25.0).family_id = f.id
	return f


# --- Task 1: kingdom fields ---

func test_new_kingdom_is_ruled_by_the_player_with_default_decrees() -> void:
	assert_eq(int(k.ruler_id), GameConstants.GOV_PLAYER)
	assert_eq(k.decrees, GovRules.default_decrees())
	assert_eq(float(k.away_hours), 0.0)
	assert_eq(String(k.ruler_way), "")


func test_old_save_kingdom_gets_the_defaults() -> void:
	var old := {id = 1, name = "Velho", color = Color.RED, center = Vector3.ZERO, radius = 40.0, seat_id = -1}
	WorldState._kingdom_defaults(old)
	assert_eq(int(old.ruler_id), GameConstants.GOV_PLAYER)
	assert_eq(old.decrees, GovRules.default_decrees())
	var other := {}
	WorldState._kingdom_defaults(other)
	(other.decrees as Dictionary).tax = "high"
	assert_eq(String(old.decrees.tax), "none", "decrees are not shared between kingdoms")


# --- Task 2: rules ---

func test_regent_is_the_head_with_most_support() -> void:
	var small := _house("Pobre", 0.5, 0)
	var big := _house("Forte", 2.0, 3)
	var friend := _house("Amigo", 0.5, 0)
	s.set_relation(int(friend.head_id), int(small.head_id), 0.9) # friends do not outweigh a strong House
	assert_eq(GovRules.choose_regent(s, k), int(big.head_id))
	assert_true(GovRules.support(s, big) > GovRules.support(s, small))


func test_regent_without_houses_is_the_oldest_adult() -> void:
	var s2 := WorldState.new()
	var k2 := s2.add_kingdom("Ermo", Color.BLUE, Vector3.ZERO, -1)
	assert_eq(GovRules.choose_regent(s2, k2), -1, "nobody to rule")
	var young := s2.add_person(PersonGen.generate(RandomNumberGenerator.new()), Vector3.ZERO, k2.id)
	young.merge({status = "resident", age = 20.0}, true)
	var old := s2.add_person(PersonGen.generate(RandomNumberGenerator.new()), Vector3.ZERO, k2.id)
	old.merge({status = "resident", age = 50.0}, true)
	var kid := s2.add_person(PersonGen.generate(RandomNumberGenerator.new()), Vector3.ZERO, k2.id)
	kid.merge({status = "resident", age = 10.0}, true) # children never rule
	assert_eq(GovRules.choose_regent(s2, k2), int(old.id))


func test_heir_is_the_oldest_adult_of_the_house() -> void:
	var f := _house("Linhagem", 1.0, 0)
	var a := _person("Velho", 40.0)
	var b := _person("Novo", 22.0)
	var c := _person("Menino", 9.0)
	for p in [a, b, c]:
		p.family_id = f.id
	assert_eq(GovRules.heir_of(s, k, f.id, int(f.head_id)), int(a.id))


func test_ruler_way_from_opinion_and_faith() -> void:
	var p := _person("Regente", 40.0, [T.WORKER])
	p.opinion = GameConstants.ALLY_AT
	assert_eq(GovRules.ruler_way(p), "leal")
	p.opinion = GameConstants.GOV_CULT_OPINION
	p.traits = [T.DEVOUT]
	assert_eq(GovRules.ruler_way(p), "culto")
	p.opinion = 0.0
	assert_eq(GovRules.ruler_way(p), "neutro")
	p.opinion = GameConstants.ENEMY_AT
	assert_eq(GovRules.ruler_way(p), "inimigo")


func test_corruption_from_greed_or_house_values() -> void:
	var f := _house("Moeda")
	var p := _person("Avaro", 40.0, [T.WORKER])
	assert_true(not GovRules.is_corrupt(p, f))
	p.traits = [T.GREEDY]
	assert_true(GovRules.is_corrupt(p, f))
	p.traits = [T.WORKER]
	f.values.wealth = GameConstants.GOV_CORRUPT_WEALTH
	assert_true(GovRules.is_corrupt(p, f))
	assert_true(not GovRules.is_corrupt(p, {}), "no House, only the trait counts")


func test_who_gives_power_back() -> void:
	assert_true(GovRules.gives_back("leal", -0.5))
	assert_true(GovRules.gives_back("culto", -0.5))
	assert_true(GovRules.gives_back("neutro", 0.1))
	assert_true(not GovRules.gives_back("neutro", -0.1))
	assert_true(not GovRules.gives_back("inimigo", 0.9))


func test_npc_decrees_follow_the_ruler() -> void:
	var mine := GovRules.default_decrees()
	mine.ration = "farta"
	assert_eq(GovRules.npc_decrees("leal", false, mine), mine, "a loyal ruler keeps the founder's decrees")
	assert_eq(String(GovRules.npc_decrees("leal", true, mine).tax), "high", "a corrupt one raises the tax")
	var foe := GovRules.npc_decrees("inimigo", false, mine)
	assert_eq(String(foe.tax), "low")
	assert_eq(String(foe.ration), "normal", "the enemy undoes the founder's generosity")


func test_deposition_needs_hatred_and_time() -> void:
	var ruler_house := _house("Trono", 1.0)
	var a := _house("Rancor", 1.0)
	var b := _house("Raiva", 1.0)
	k.ruler_id = ruler_house.head_id
	k.ruler_since = 0.0
	for f in [a, b]:
		s.set_relation(int(f.head_id), int(ruler_house.head_id), GameConstants.GOV_DEPOSE_AT - 0.1)
	assert_true(not GovRules.wants_deposition(s, k, GameConstants.GOV_MIN_REIGN_HOURS - 1.0), "too soon")
	assert_true(GovRules.wants_deposition(s, k, GameConstants.GOV_MIN_REIGN_HOURS))
	s.set_relation(int(a.head_id), int(ruler_house.head_id), 0.9)
	assert_true(not GovRules.wants_deposition(s, k, GameConstants.GOV_MIN_REIGN_HOURS), "not hated enough")
	k.ruler_id = GameConstants.GOV_PLAYER
	assert_true(not GovRules.wants_deposition(s, k, 1e6), "the player is never deposed this way")


func test_decree_opinion_effects() -> void:
	var rich := _house("Rica")
	rich.values.wealth = 0.9
	var head := s.person(int(rich.head_id))
	assert_true(GovRules.decree_opinion(head, rich, "tax", "none", "high") < 0.0, "taxes anger")
	assert_true(GovRules.decree_opinion(head, rich, "tax", "high", "low") > 0.0, "lower taxes please")
	assert_true(GovRules.decree_opinion(head, rich, "ration", "normal", "curta") < 0.0)
	var warriors := _house("Lança")
	warriors.tradition = TR.WARRIORS
	var w := s.person(int(warriors.head_id))
	assert_true(GovRules.decree_opinion(w, warriors, "guards", 1, 3) > 0.0, "warriors like a bigger guard")
	assert_eq(GovRules.decree_opinion(head, rich, "guards", 1, 3), 0.0)


# --- Task 3: decrees in the village ---

func test_ration_changes_how_often_people_eat() -> void:
	s.add_stock(k, GameConstants.Res.FOOD, 100)
	var meals := {}
	for ration in ["curta", "normal", "farta"]:
		k.decrees.ration = ration
		var p := _person("Comilão-" + ration)
		var before := s.stock_of(k, GameConstants.Res.FOOD)
		for h in 72:
			p.hunger = minf(1.0, float(p.hunger) + GameConstants.HUNGER_PER_HOUR)
			VillageRules.eat(p, k, s)
		meals[ration] = before - s.stock_of(k, GameConstants.Res.FOOD)
	assert_true(meals.curta < meals.normal and meals.normal < meals.farta, "meals in 3 days: %s" % meals)
	k.decrees.ration = "normal"


func test_contentment_feels_tax_and_ration() -> void:
	var p := _person("Sentido")
	var snap := VillageRules.snapshot(s, k, 0.0)
	var base := VillageRules.hourly_contentment(p, snap, true)
	snap.decrees = {tax = "high", ration = "curta", guards = -1, build = -1}
	assert_true(VillageRules.hourly_contentment(p, snap, true) < base)
	snap.decrees = {tax = "none", ration = "farta", guards = -1, build = -1}
	assert_true(VillageRules.hourly_contentment(p, snap, true) > base)


func test_build_preference_comes_first_when_affordable() -> void:
	var snap := VillageRules.snapshot(s, k, 0.0)
	snap.residents = 3
	snap.site = -1
	snap.decrees = {tax = "none", ration = "normal", guards = -1, build = B.WELL}
	snap.stock = {GameConstants.Res.WOOD: 100, GameConstants.Res.STONE: 100}
	assert_eq(VillageRules.next_project(snap), B.WELL)
	snap.stock = {}
	assert_true(VillageRules.next_project(snap) != B.WELL or snap.residents >= GameConstants.PROJECT_WELL_AT,
			"without stock the usual plan goes on")
	assert_eq(snap.decrees.build, B.WELL)


func test_build_decree_is_done_once_built() -> void:
	var sim := VillageSim.new()
	sim.setup(s, TerrainGenerator.new(GameConstants.WORLD_SEED), PropScatter.new(TerrainGenerator.new(GameConstants.WORLD_SEED), 8), null)
	k.decrees.build = B.WELL
	var well := s.add_building(B.WELL, k.center + Vector3(6, 0, 0), 0, Color.WHITE, GameConstants.OWNER_KINGDOM)
	well.kingdom_id = k.id
	sim.complete_site(well)
	assert_eq(int(k.decrees.build), GameConstants.GOV_BUILD_FREE, "the preferred work is done: back to the usual plan")
	sim.free()
