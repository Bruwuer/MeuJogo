extends GameTest

const T := GameConstants.Trait


func _p(id: int, traits: Array, age := 30.0, female := false) -> Dictionary:
	var p := {id = id, traits = traits, age = age, female = female, opinion = 0.0, contentment = 0.6,
			status = "resident"}
	WorldState.person_defaults(p)
	return p


func _rng(s := 1) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func _mean_delta(a: Dictionary, b: Dictionary, close := false) -> float:
	var r := _rng()
	var sum := 0.0
	for i in 200:
		sum += SocietyRules.meeting_delta(a, b, close, r)
	return sum / 200.0


func test_same_traits_attract_opposites_repel() -> void:
	var worker := _p(1, [T.WORKER, T.BRAVE])
	var worker2 := _p(2, [T.WORKER, T.BRAVE])
	var lazy := _p(3, [T.LAZY, T.FEARFUL])
	assert_true(_mean_delta(worker, worker2) > 0.05, "alike get closer")
	assert_true(_mean_delta(worker, lazy) < -0.05, "opposites drift apart")
	assert_true(_mean_delta(worker, lazy, true) > _mean_delta(worker, lazy), "living together helps")
	var social := _p(4, [T.SOCIABLE, T.DEVOUT])
	var loner := _p(5, [T.LONER, T.SKEPTIC])
	var neutral := _p(6, [T.GENEROUS, T.WORKER])
	assert_true(_mean_delta(social, neutral) > _mean_delta(loner, neutral), "sociable warmer than loner")


func test_kin_cannot_marry() -> void:
	var mom := _p(1, [T.WORKER, T.BRAVE], 40.0, true)
	var son := _p(2, [T.WORKER, T.BRAVE], 20.0)
	son.parents = [1, 9]
	var daughter := _p(3, [T.WORKER, T.BRAVE], 20.0, true)
	daughter.parents = [9, 7]
	assert_true(SocietyRules.is_kin(mom, son), "parent")
	assert_true(SocietyRules.is_kin(son, daughter), "siblings share a parent")
	assert_true(not SocietyRules.can_marry(son, daughter, 1.0), "siblings never marry")
	assert_true(not SocietyRules.is_kin(mom, daughter), "unrelated")


func test_marry_needs_adults_and_love() -> void:
	var a := _p(1, [T.WORKER, T.BRAVE], 25.0, true)
	var b := _p(2, [T.WORKER, T.BRAVE], 30.0)
	assert_true(SocietyRules.can_marry(a, b, GameConstants.COUPLE_AT), "in love")
	assert_true(not SocietyRules.can_marry(a, b, GameConstants.COUPLE_AT - 0.01), "not enough")
	var kid := _p(3, [T.WORKER, T.BRAVE], 15.0)
	assert_true(not SocietyRules.can_marry(a, kid, 1.0), "never a minor")
	var old := _p(4, [T.WORKER, T.BRAVE], 50.0)
	assert_true(not SocietyRules.can_marry(a, old, 1.0), "age gap over 15")
	b.spouse_id = 7
	assert_true(not SocietyRules.can_marry(a, b, 1.0), "already married")
	var c := _p(5, [T.WORKER, T.BRAVE], 26.0, true)
	assert_true(SocietyRules.can_marry(a, c, 1.0), "any two adults")


func test_birth_mother() -> void:
	var w := _p(1, [T.WORKER, T.BRAVE], 30.0, true)
	var m := _p(2, [T.WORKER, T.BRAVE], 32.0)
	assert_eq(SocietyRules.birth_mother(w, m).get("id", -1), 1)
	assert_eq(SocietyRules.birth_mother(m, w).get("id", -1), 1)
	var w2 := _p(3, [T.WORKER, T.BRAVE], 30.0, true)
	assert_true(SocietyRules.birth_mother(w, w2).is_empty(), "two women: no child")
	w.age = 46.0
	assert_true(SocietyRules.birth_mother(w, m).is_empty(), "past 45")


func test_stance_hysteresis() -> void:
	assert_eq(SocietyRules.stance_for(0.5, ""), "ally")
	assert_eq(SocietyRules.stance_for(0.45, ""), "")
	assert_eq(SocietyRules.stance_for(0.45, "ally"), "ally", "keeps it until below 0.4")
	assert_eq(SocietyRules.stance_for(0.39, "ally"), "")
	assert_eq(SocietyRules.stance_for(-0.4, ""), "enemy")
	assert_eq(SocietyRules.stance_for(-0.35, "enemy"), "enemy")
	assert_eq(SocietyRules.stance_for(-0.29, "enemy"), "")
	assert_eq(SocietyRules.stance_for(-0.6, "ally"), "enemy")
	var fam := [_p(1, [], 30.0), _p(2, [], 30.0), _p(3, [], 5.0)]
	fam[0].opinion = 0.6
	fam[1].opinion = 0.5
	fam[2].opinion = -1.0 # a child does not count
	assert_eq(SocietyRules.family_stance(fam, ""), "ally")


func test_opinion_drift_parts() -> void:
	var p := _p(1, [])
	p.contentment = 1.0
	assert_near(SocietyRules.opinion_drift(p, 0.0, []), 0.5 * GameConstants.OPINION_CONTENT_RATE, 0.0001, "happy")
	p.contentment = 0.5
	assert_near(SocietyRules.opinion_drift(p, 0.5, []), 0.5 * GameConstants.OPINION_FAMILY_PULL, 0.0001, "family")
	var friend := SocietyRules.opinion_drift(p, 0.0, [[0.5, 1.0]])
	assert_near(friend, GameConstants.OPINION_FRIEND_PULL, 0.0001, "friend pulls")
	var rival := SocietyRules.opinion_drift(p, 0.0, [[-0.5, 1.0]])
	assert_near(rival, -GameConstants.OPINION_RIVAL_PUSH, 0.0001, "rival pushes away")
	assert_near(SocietyRules.opinion_drift(p, 0.0, [[0.1, 1.0]]), 0.0, 0.0001, "acquaintance does nothing")


func test_child_inherits() -> void:
	var r := _rng(3)
	var mom := PersonGen.generate(r)
	var dad := PersonGen.generate(r)
	mom.traits = [T.WORKER, T.BRAVE]
	dad.traits = [T.WORKER, T.FEARFUL]
	mom.opinion = 0.4
	dad.opinion = 0.0
	for i in 20:
		var c := PersonGen.child(mom, dad, "Ferreira", r, [])
		assert_eq(c.surname, "Ferreira")
		assert_near(float(c.age), 0.0, 0.001)
		assert_eq(c.profession, -1)
		assert_near(c.opinion, 0.2, 0.001)
		assert_eq(c.traits.size(), 2)
		assert_true(PersonGen.pair_of(c.traits[0]) != PersonGen.pair_of(c.traits[1]), "traits from two pairs")
		assert_true([mom.looks.skin, dad.looks.skin].has(c.looks.skin), "skin of a parent")
		assert_true([mom.looks.hair, dad.looks.hair].has(c.looks.hair), "hair of a parent")
		var h := (float(mom.looks.height) + float(dad.looks.height)) * 0.5
		assert_true(absf(float(c.looks.height) - h) <= GameConstants.CHILD_HEIGHT_JITTER + 0.001, "height")
	assert_eq(PersonGen.profession_name({profession = -1, female = false}), GameConstants.CHILD_PROFESSION_NAME)
	var named := PersonGen.child(mom, dad, "Ferreira", _rng(1), [])
	for i in 10:
		var sib := PersonGen.child(mom, dad, "Ferreira", _rng(1), [named.name])
		assert_true(sib.name != named.name, "no sibling with the same name")


func test_hourly_chance() -> void:
	var p := SocietyRules.hourly_chance(0.35)
	assert_near(1.0 - pow(1.0 - p, 24.0), 0.35, 0.0001)
