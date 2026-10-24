class_name PersonGen
extends RefCounted
## Makes people as plain Dictionaries (easy to save): name, sex, age, two traits from different
## pairs, a profession, looks (colors for the humanoid's materials and a height) and an initial
## opinion of the player. The same rng state always gives the same person.

const P := GameConstants.Profession


## `fame` is the player's reputation (-1..1); `profession` >= 0 forces the trade.
static func generate(rng: RandomNumberGenerator, fame := 0.0, profession := -1) -> Dictionary:
	var female := rng.randf() < 0.5
	var names: Array = GameConstants.FEMALE_NAMES if female else GameConstants.MALE_NAMES
	var p := {
		name = names[rng.randi() % names.size()],
		surname = GameConstants.SURNAMES[rng.randi() % GameConstants.SURNAMES.size()],
		female = female,
		age = rng.randi_range(GameConstants.PERSON_AGE.x, GameConstants.PERSON_AGE.y),
		traits = _traits(rng),
		profession = rng.randi() % P.size(),
		looks = {
			skin = _pick(GameConstants.SKIN_COLORS, rng),
			hair = _pick(GameConstants.HAIR_COLORS, rng),
			tunic = _pick(GameConstants.TUNIC_COLORS, rng),
			trousers = _pick(GameConstants.TROUSER_COLORS, rng),
			height = rng.randf_range(GameConstants.PERSON_HEIGHT.x, GameConstants.PERSON_HEIGHT.y),
		},
	}
	if profession >= 0:
		p.profession = profession
	var opinion := rng.randf_range(-GameConstants.OPINION_JITTER, GameConstants.OPINION_JITTER)
	for t: int in p.traits:
		opinion += GameConstants.TRAIT_OPINION[t]
	p.opinion = clampf(opinion + fame * GameConstants.FAME_OPINION_SHARE, -1.0, 1.0)
	return p


static func full_name(p: Dictionary) -> String:
	return "%s %s" % [p.name, p.surname]


static func has_trait(p: Dictionary, t: int) -> bool:
	return (p.traits as Array).has(t)


## Index of the opposite-pair a trait belongs to.
static func pair_of(t: int) -> int:
	for i in GameConstants.TRAIT_PAIRS.size():
		if (GameConstants.TRAIT_PAIRS[i] as Array).has(t):
			return i
	return -1


static func trait_name(p: Dictionary, t: int) -> String:
	return GameConstants.TRAIT_NAMES[t][1 if p.female else 0]


static func profession_name(p: Dictionary) -> String:
	return GameConstants.PROFESSION_NAMES[p.profession][1 if p.female else 0]


static func _traits(rng: RandomNumberGenerator) -> Array[int]:
	var pairs: Array = range(GameConstants.TRAIT_PAIRS.size())
	var first: int = pairs.pop_at(rng.randi() % pairs.size())
	var second: int = pairs[rng.randi() % pairs.size()]
	var out: Array[int] = []
	for i in [first, second]:
		out.append(GameConstants.TRAIT_PAIRS[i][rng.randi() % 2])
	return out


static func _pick(colors: Array, rng: RandomNumberGenerator) -> Color:
	return colors[rng.randi() % colors.size()]
