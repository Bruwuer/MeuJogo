extends GameTest

const T := GameConstants.Trait
const P := GameConstants.Profession
const TR := GameConstants.Tradition


func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func _person(traits: Array, profession := P.FARMER, female := false) -> Dictionary:
	var p := PersonGen.generate(_rng(hash(traits) + profession))
	p.traits = traits
	p.profession = profession
	p.female = female
	p.id = 1
	p.resentment = 0.0
	p.vocation = -1
	return p


func _family(tradition: int) -> Dictionary:
	return {id = 1, tradition = tradition, values = (GameConstants.TRADITION_VALUES[tradition] as Dictionary).duplicate()}


func test_tradition_follows_head_trade() -> void:
	var counts := {}
	for s in 200:
		var t := HouseRules.tradition_for(_person([T.WORKER, T.SOCIABLE], P.FARMER), _rng(s))
		counts[t] = counts.get(t, 0) + 1
	assert_true(counts.get(TR.FARMERS, 0) > 120, "farmer heads mostly found Lavradores: %s" % counts)
	var brave := 0
	for s in 200:
		if HouseRules.tradition_for(_person([T.BRAVE, T.WORKER], P.FARMER), _rng(s)) == TR.WARRIORS:
			brave += 1
	assert_true(brave > 10, "brave heads sometimes found warrior Houses (%d)" % brave)


func test_values_near_tradition() -> void:
	var v := HouseRules.values_for(TR.MERCHANTS, _rng(3))
	for key in ["wealth", "land", "prestige", "faith", "honor"]:
		assert_true(v[key] >= 0.0 and v[key] <= 1.0)
		assert_near(v[key], GameConstants.TRADITION_VALUES[TR.MERCHANTS][key], GameConstants.VALUE_NOISE + 0.001)


func test_vocation_distribution() -> void:
	var fam := _family(TR.WARRIORS)
	var follow := 0
	for s in 400:
		var v := HouseRules.vocation_for(_person([T.LAZY, T.LONER]), fam, _rng(s))
		assert_true(GameConstants.PROFESSION_NAMES.has(v))
		if v == P.GUARD:
			follow += 1
	var share := follow / 400.0
	assert_true(share > 0.45 and share < 0.8, "share following the tradition %.2f" % share)


func test_conflict_only_outside_expected_trades() -> void:
	var fam := _family(TR.BUILDERS)
	var p := _person([T.WORKER, T.BRAVE])
	p.vocation = P.MASON
	assert_true(not HouseRules.conflicts(p, fam))
	p.vocation = P.GUARD
	assert_true(HouseRules.conflicts(p, fam))
	p.vocation = -1
	assert_true(not HouseRules.conflicts(p, fam), "children without vocation have no conflict")


func test_conflict_outcome_leans_with_resentment_and_relation() -> void:
	var fam := _family(TR.WARRIORS)
	var calm := _person([T.FEARFUL, T.SOCIABLE])
	var angry := _person([T.BRAVE, T.LONER])
	angry.resentment = 1.0
	var leave_calm := 0
	var leave_angry := 0
	for s in 300:
		if HouseRules.conflict_outcome(calm, fam, 0.8, _rng(s)) == "leave":
			leave_calm += 1
		if HouseRules.conflict_outcome(angry, fam, -0.6, _rng(s)) == "leave":
			leave_angry += 1
	assert_true(leave_angry > leave_calm * 2, "angry %d vs calm %d" % [leave_angry, leave_calm])
	var outcomes := {}
	for s in 300:
		outcomes[HouseRules.conflict_outcome(_person([T.WORKER, T.GENEROUS]), fam, 0.0, _rng(s))] = true
	assert_true(outcomes.has("conform") and outcomes.has("negotiate") and outcomes.has("leave"), "all outcomes happen: %s" % [outcomes.keys()])


func test_departure_tone_and_secrecy() -> void:
	var fam := _family(TR.FARMERS)
	assert_eq(HouseRules.departure_style(_person([T.WORKER, T.SOCIABLE]), fam, 0.9, _rng(1)).tone, "friendly")
	assert_eq(HouseRules.departure_style(_person([T.WORKER, T.SOCIABLE]), fam, -0.9, _rng(1)).tone, "hostile")
	assert_eq(HouseRules.departure_style(_person([T.WORKER, T.SOCIABLE]), fam, 0.0, _rng(1)).tone, "neutral")
	var secret_fearful := 0
	var secret_brave := 0
	for s in 300:
		if HouseRules.departure_style(_person([T.FEARFUL, T.LONER]), fam, -0.5, _rng(s)).secret:
			secret_fearful += 1
		if HouseRules.departure_style(_person([T.BRAVE, T.SOCIABLE]), fam, 0.5, _rng(s)).secret:
			secret_brave += 1
	assert_true(secret_fearful > secret_brave * 2, "fearful %d vs brave %d" % [secret_fearful, secret_brave])


func test_skill_bonus_monotonic_and_capped() -> void:
	var last := -1.0
	for h in [0.0, 10.0, 50.0, 150.0, 200.0, 1000.0]:
		var b := HouseRules.skill_bonus(h)
		assert_true(b >= last)
		last = b
	assert_near(HouseRules.skill_bonus(0.0), 0.0, 0.0001)
	assert_near(HouseRules.skill_bonus(10000.0), GameConstants.SKILL_MAX_BONUS, 0.0001)
	assert_true(HouseRules.work_wealth(P.FARMER, 200.0) > HouseRules.work_wealth(P.FARMER, 0.0))


func test_house_levels() -> void:
	assert_eq(HouseRules.capacity(0), 4)
	assert_eq(HouseRules.capacity(2), 8)
	assert_eq(HouseRules.upgrade_price(0), GameConstants.UPGRADE_PRICE[0])
	assert_eq(HouseRules.upgrade_price(2), -1, "a manor cannot be upgraded")
