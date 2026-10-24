extends GameTest

const T := GameConstants.Trait


func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func test_generates_all_fields() -> void:
	var p := PersonGen.generate(_rng(1))
	for key in ["name", "surname", "female", "age", "traits", "profession", "looks", "opinion"]:
		assert_true(p.has(key), "missing %s" % key)
	assert_eq(p.traits.size(), 2)
	assert_true(p.age >= GameConstants.PERSON_AGE.x and p.age <= GameConstants.PERSON_AGE.y, "age %d" % p.age)
	assert_true(p.profession >= 0 and p.profession < GameConstants.Profession.size())
	for key in ["skin", "hair", "tunic", "trousers"]:
		assert_true(p.looks[key] is Color, "looks.%s" % key)
	assert_true(p.looks.height >= GameConstants.PERSON_HEIGHT.x and p.looks.height <= GameConstants.PERSON_HEIGHT.y)
	assert_true(p.opinion >= -1.0 and p.opinion <= 1.0)


func test_traits_not_opposite() -> void:
	for s in 200:
		var p := PersonGen.generate(_rng(s))
		var a: int = p.traits[0]
		var b: int = p.traits[1]
		assert_true(a != b, "same trait twice")
		assert_true(PersonGen.pair_of(a) != PersonGen.pair_of(b), "traits %d and %d are from the same pair" % [a, b])


func test_deterministic() -> void:
	assert_eq(PersonGen.generate(_rng(42)), PersonGen.generate(_rng(42)))
	assert_true(PersonGen.generate(_rng(42)) != PersonGen.generate(_rng(43)))


func test_names_from_lists() -> void:
	var seen_female := false
	var seen_male := false
	for s in 60:
		var p := PersonGen.generate(_rng(s))
		var names: Array = GameConstants.FEMALE_NAMES if p.female else GameConstants.MALE_NAMES
		assert_true(names.has(p.name), "%s not in list" % p.name)
		assert_true(GameConstants.SURNAMES.has(p.surname), "%s not a surname" % p.surname)
		assert_eq(PersonGen.full_name(p), "%s %s" % [p.name, p.surname])
		seen_female = seen_female or p.female
		seen_male = seen_male or not p.female
	assert_true(seen_female and seen_male, "both sexes appear")


func test_profession_forced() -> void:
	for s in 10:
		var p := PersonGen.generate(_rng(s), 0.0, GameConstants.Profession.FARMER)
		assert_eq(p.profession, GameConstants.Profession.FARMER)


func test_opinion_bias_from_traits_and_fame() -> void:
	var avg_plain := 0.0
	var avg_famous := 0.0
	for s in 100:
		avg_plain += PersonGen.generate(_rng(s), 0.0).opinion
		avg_famous += PersonGen.generate(_rng(s), 0.8).opinion
	assert_near(avg_famous / 100.0 - avg_plain / 100.0, 0.8 * GameConstants.FAME_OPINION_SHARE, 0.05)
	# Same seed: a generous person thinks better of the player than a greedy one with the same jitter.
	assert_true(GameConstants.TRAIT_OPINION[T.GENEROUS] > GameConstants.TRAIT_OPINION[T.GREEDY])


func test_female_forms() -> void:
	var p := { female = true, traits = [T.WORKER, T.BRAVE], profession = GameConstants.Profession.WOODCUTTER }
	assert_eq(PersonGen.trait_name(p, T.WORKER), "trabalhadora")
	assert_eq(PersonGen.profession_name(p), "lenhadora")
	p.female = false
	assert_eq(PersonGen.trait_name(p, T.WORKER), "trabalhador")
	assert_eq(PersonGen.profession_name(p), "lenhador")
	assert_true(PersonGen.has_trait(p, T.BRAVE))
	assert_true(not PersonGen.has_trait(p, T.FEARFUL))
