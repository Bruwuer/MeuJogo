extends GameTest

const G := GameConstants.Goal
const T := GameConstants.Trait
const TR := GameConstants.Tradition


func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func _fam(tradition := TR.FARMERS) -> Dictionary:
	return {id = 1, tradition = tradition, values = (GameConstants.TRADITION_VALUES[tradition] as Dictionary).duplicate(),
			wealth = 0.0, plots = [], house_level = 0, prestige = 0.0}


func _ctx(over := {}) -> Dictionary:
	var c := {members = 4, adults = 2, unmarried_adults = 0, heirs = 1, plots = 2, wealth = 60.0, house_level = 0,
			has_house = true, rival_id = -1, rival_gap = 0.0, allies = [], partner_families = [], insulted_by = -1,
			head_age = 35.0}
	c.merge(over, true)
	return c


func _kinds(fam: Dictionary, ctx: Dictionary) -> Dictionary:
	var out := {}
	for s in 60:
		var g := HouseRules.pick_goal(fam, ctx, _rng(s))
		if not g.is_empty():
			out[g.kind] = true
	return out


func test_goals_are_coherent() -> void:
	var fam := _fam(TR.MERCHANTS)
	assert_true(not _kinds(fam, _ctx({wealth = 900.0})).has(G.WEALTH), "a rich House never 'gathers wealth'")
	assert_true(not _kinds(fam, _ctx({unmarried_adults = 0, partner_families = [7]})).has(G.ALLIANCE), "no one to marry")
	assert_true(not _kinds(fam, _ctx({unmarried_adults = 1, partner_families = []})).has(G.ALLIANCE), "no partner House")
	assert_true(not _kinds(fam, _ctx({plots = 2, adults = 2})).has(G.LAND), "enough land")
	assert_true(not _kinds(fam, _ctx({house_level = 2, wealth = 900.0})).has(G.UPGRADE), "already a manor")
	assert_true(not _kinds(fam, _ctx({has_house = false, wealth = 900.0})).has(G.UPGRADE), "no house to upgrade")
	assert_true(not _kinds(fam, _ctx({rival_id = -1})).has(G.SURPASS))
	assert_true(not _kinds(fam, _ctx({insulted_by = -1})).has(G.REVENGE))
	assert_true(not _kinds(fam, _ctx({members = 5, heirs = 2, allies = [3]})).has(G.UNION), "a big House does not merge")


func test_goal_changes_with_situation() -> void:
	var fam := _fam(TR.FARMERS)
	var poor := _kinds(fam, _ctx({wealth = 10.0, adults = 4, plots = 0, members = 6}))
	assert_true(poor.has(G.WEALTH) or poor.has(G.LAND), "a poor crowded House wants wealth or land: %s" % [poor.keys()])
	var settled := _kinds(fam, _ctx({wealth = 400.0, adults = 2, plots = 2, unmarried_adults = 1, partner_families = [5]}))
	assert_true(settled.has(G.UPGRADE) or settled.has(G.ALLIANCE), "a settled rich House aims higher: %s" % [settled.keys()])
	assert_true(not settled.has(G.WEALTH))


func test_targets_are_set() -> void:
	var g := HouseRules.pick_goal(_fam(TR.WARRIORS), _ctx({rival_id = 9, rival_gap = 0.8, wealth = 900.0}), _rng(1))
	if g.kind == G.SURPASS:
		assert_eq(g.target_id, 9)
	var u := HouseRules.pick_goal(_fam(), _ctx({members = 1, adults = 1, heirs = 0, allies = [4], wealth = 900.0, plots = 1}), _rng(2))
	assert_eq(u.kind, G.UNION, "a lone heirless member with an ally seeks a union")
	assert_eq(u.target_id, 4)


func _person(s: WorldState, name: String, female: bool, age: float, parents := []) -> Dictionary:
	var p := PersonGen.generate(_rng(hash(name)))
	p.name = name
	p.female = female
	p.age = age
	var rec := s.add_person(p, Vector3.ZERO, 1)
	rec.status = "resident"
	rec.parents = parents
	return rec


func test_no_kin_marriage() -> void:
	var s := WorldState.new()
	var g := _person(s, "Avô", false, 70.0)
	var a := _person(s, "Pai", false, 45.0, [g.id])
	var b := _person(s, "Tia", true, 44.0, [g.id])
	var son := _person(s, "Martim", false, 22.0, [a.id])
	var cousin := _person(s, "Joana", true, 21.0, [b.id])
	var stranger := _person(s, "Inês", true, 23.0)
	var m := HouseRules.arranged_match([son], [cousin, stranger], s)
	assert_eq(m.partner_id, stranger.id, "never a cousin")
	assert_true(HouseRules.arranged_match([son], [cousin], s).is_empty())
	var man := _person(s, "Rui", false, 24.0)
	assert_true(HouseRules.arranged_match([son], [man], s).is_empty(), "only a man and a woman")


func test_arranged_response() -> void:
	var p := {traits = [T.WORKER, T.SOCIABLE]}
	var accept_love := 0
	var flee := 0
	for s in 300:
		if HouseRules.arranged_response(p, 0.8, -1.0, _rng(s)) == "accept":
			accept_love += 1
		if HouseRules.arranged_response({traits = [T.BRAVE, T.LONER]}, -0.2, 0.9, _rng(s)) == "flee":
			flee += 1
	assert_eq(accept_love, 300, "already fond of the partner: always accepts")
	assert_true(flee > 60, "in love with someone else, the brave often flee (%d)" % flee)


func test_corruption_only_greedy() -> void:
	var fam := _fam(TR.MERCHANTS)
	assert_eq(HouseRules.corruption_chance(fam, {traits = [T.GENEROUS, T.WORKER]}), 0.0)
	assert_true(HouseRules.corruption_chance(fam, {traits = [T.GREEDY, T.WORKER]}) > 0.0)
	assert_true(HouseRules.discovery_chance(4) > HouseRules.discovery_chance(0))
	assert_true(HouseRules.discovery_chance(100) <= 0.4)


func test_spy_targets_rival_only() -> void:
	var s := WorldState.new()
	var head := _person(s, "Chefe", false, 50.0)
	var kid := _person(s, "Sancho", false, 20.0, [head.id])
	kid.traits = [T.LONER, T.GREEDY]
	var mine := {id = 1, head_id = head.id, rival_id = 2}
	assert_true(HouseRules.spy_candidate(mine, {id = 3}, [head, kid]).is_empty(), "only against the rival House")
	assert_true(HouseRules.spy_candidate(mine, {id = 1}, [head, kid]).is_empty(), "never against itself")
	assert_eq(HouseRules.spy_candidate(mine, {id = 2}, [head, kid]).id, kid.id, "the head never goes as a spy")


func test_secret_romance_rules() -> void:
	var a := {id = 1, female = false, age = 25.0}
	var b := {id = 2, female = false, age = 27.0}
	var c := {id = 3, female = true, age = 26.0}
	assert_true(HouseRules.secret_romance_possible(a, b, GameConstants.COUPLE_AT, false))
	assert_true(not HouseRules.secret_romance_possible(a, c, 1.0, false), "a man and a woman can simply marry")
	assert_true(not HouseRules.secret_romance_possible(a, b, 0.1, false), "needs love")
	assert_true(not HouseRules.secret_romance_possible(a, b, 1.0, true), "never kin")
