class_name HouseRules
extends RefCounted
## Pure rules of the Houses (stage 7): tradition and values, vocations and the clash between what
## a person wants and what the House expects, how people leave, and the House economy.

const T := GameConstants.Trait
const TR := GameConstants.Tradition


## Tradition of a new House: the head's trade, sometimes pulled by a trait (brave -> warriors,
## greedy/sociable -> merchants...).
static func tradition_for(head: Dictionary, rng: RandomNumberGenerator) -> int:
	var t := WorldState.tradition_of_profession(int(head.get("profession", -1)))
	if rng.randf() < GameConstants.TRADITION_TRAIT_NUDGE:
		for trait_id: int in head.get("traits", []):
			if GameConstants.TRAIT_VOCATIONS.has(trait_id):
				return WorldState.tradition_of_profession(GameConstants.TRAIT_VOCATIONS[trait_id][0])
	return t


static func values_for(tradition: int, rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	var base: Dictionary = GameConstants.TRADITION_VALUES[tradition]
	for key in base:
		out[key] = clampf(base[key] + rng.randf_range(-GameConstants.VALUE_NOISE, GameConstants.VALUE_NOISE), 0.0, 1.0)
	return out


static func expected_professions(family: Dictionary) -> Array:
	return GameConstants.TRADITION_PROFESSIONS[int(family.tradition)]


## The trade a young person wants: the House's, one pulled by a trait, or any.
static func vocation_for(person: Dictionary, family: Dictionary, rng: RandomNumberGenerator) -> int:
	var roll := rng.randf()
	if roll < GameConstants.VOCATION_FOLLOW_TRADITION and not family.is_empty():
		var own := expected_professions(family)
		return own[rng.randi() % own.size()]
	if roll < GameConstants.VOCATION_FOLLOW_TRADITION + GameConstants.VOCATION_FROM_TRAIT:
		for trait_id: int in person.get("traits", []):
			if GameConstants.TRAIT_VOCATIONS.has(trait_id):
				var opts: Array = GameConstants.TRAIT_VOCATIONS[trait_id]
				return opts[rng.randi() % opts.size()]
	var all: Array = GameConstants.PROFESSION_NAMES.keys()
	return all[rng.randi() % all.size()]


static func conflicts(person: Dictionary, family: Dictionary) -> bool:
	var v := int(person.get("vocation", -1))
	return v >= 0 and not family.is_empty() and not expected_professions(family).has(v)


## How a vocation clash ends: "conform" (follows the House trade, keeps resenting), "negotiate"
## (the House accepts) or "leave".
static func conflict_outcome(person: Dictionary, family: Dictionary, relation_with_head: float,
		rng: RandomNumberGenerator) -> String:
	var traits: Array = person.get("traits", [])
	var p_leave := 0.2 + float(person.get("resentment", 0.0)) * 0.6 - relation_with_head * 0.3
	if traits.has(T.BRAVE) or traits.has(T.LONER):
		p_leave += 0.15
	if traits.has(T.FEARFUL):
		p_leave -= 0.1
	p_leave = clampf(p_leave, 0.05, 0.9)
	var honor := float((family.get("values", {}) as Dictionary).get("honor", 0.5))
	var p_negotiate := clampf(0.35 - honor * 0.2 + relation_with_head * 0.15, 0.05, 0.6)
	var roll := rng.randf()
	if roll < p_leave:
		return "leave"
	if roll < p_leave + p_negotiate:
		return "negotiate"
	return "conform"


## {tone: "friendly" | "neutral" | "hostile", secret: bool}: in good terms people leave openly with a
## blessing; in bad terms they break away, and the fearful slip away at night.
static func departure_style(person: Dictionary, _family: Dictionary, relation_with_head: float,
		rng: RandomNumberGenerator) -> Dictionary:
	var rel := relation_with_head + rng.randf_range(-0.05, 0.05)
	var tone := "neutral"
	if rel > GameConstants.DEPART_FRIENDLY_AT:
		tone = "friendly"
	elif rel < GameConstants.DEPART_HOSTILE_AT:
		tone = "hostile"
	var traits: Array = person.get("traits", [])
	var p_secret := 0.15
	if traits.has(T.FEARFUL):
		p_secret += 0.35
	if traits.has(T.BRAVE):
		p_secret -= 0.12
	if tone == "hostile":
		p_secret += 0.25
	elif tone == "friendly":
		p_secret -= 0.1
	return {tone = tone, secret = rng.randf() < clampf(p_secret, 0.02, 0.9)}


static func skill_bonus(skill_hours: float) -> float:
	return GameConstants.SKILL_MAX_BONUS * clampf(skill_hours / GameConstants.SKILL_HOURS_FOR_MAX, 0.0, 1.0)


## Wealth one working member brings to the House in an hour.
static func work_wealth(_profession: int, skill_hours: float) -> float:
	return GameConstants.WEALTH_PER_WORK_HOUR * (1.0 + skill_bonus(skill_hours))


static func capacity(level: int) -> int:
	return GameConstants.HOUSE_LEVEL_CAPACITY[clampi(level, 0, GameConstants.HOUSE_LEVEL_CAPACITY.size() - 1)]


## Price to go up from `level`, or -1 at the top level.
static func upgrade_price(level: int) -> int:
	return GameConstants.UPGRADE_PRICE[level] if level < GameConstants.UPGRADE_PRICE.size() else -1
