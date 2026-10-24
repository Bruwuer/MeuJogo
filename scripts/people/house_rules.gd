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


# --- Goals ----------------------------------------------------------------------------------

## Score of each goal for a House (0 = makes no sense now). ctx keys: members, adults,
## unmarried_adults, heirs, plots, wealth, house_level, has_house, rival_id, rival_gap, allies,
## partner_families, insulted_by, head_age.
static func goal_scores(family: Dictionary, ctx: Dictionary) -> Dictionary:
	var v: Dictionary = family.values
	var G := GameConstants.Goal
	var s := {}
	var wanted_plots := mini(int(ctx.adults) * GameConstants.PLOTS_PER_ADULT, GameConstants.PLOTS_MAX)
	if int(ctx.plots) < wanted_plots and float(ctx.wealth) >= GameConstants.PLOT_PRICE * 0.5:
		s[G.LAND] = v.land * minf(1.0, (wanted_plots - int(ctx.plots)) / 2.0) + 0.1
	var price := upgrade_price(int(ctx.house_level))
	if ctx.has_house and price > 0 and float(ctx.wealth) >= price * 0.6:
		s[G.UPGRADE] = v.prestige * 0.8 + 0.1
	if int(ctx.unmarried_adults) > 0 and not (ctx.partner_families as Array).is_empty():
		s[G.ALLIANCE] = v.prestige * 0.5 + v.wealth * 0.3
	if int(ctx.rival_id) >= 0 and float(ctx.rival_gap) > 0.0:
		s[G.SURPASS] = v.prestige * 0.7 + float(ctx.rival_gap) * 0.3
	if int(ctx.insulted_by) >= 0:
		s[G.REVENGE] = v.honor * 0.9
	if float(ctx.wealth) < GameConstants.WEALTH_POOR:
		s[G.WEALTH] = v.wealth * 0.8 + 0.2
	if int(ctx.heirs) == 0 and int(ctx.adults) > 0 and float(ctx.head_age) >= GameConstants.HEIR_AGE:
		s[G.HEIR] = 0.6
	if int(ctx.members) <= GameConstants.UNION_MAX_MEMBERS and int(ctx.heirs) == 0 and not (ctx.allies as Array).is_empty():
		s[G.UNION] = 0.9
	return s


## The best-scoring goal ({kind, target_id}), or {} when nothing makes sense.
static func pick_goal(family: Dictionary, ctx: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var scores := goal_scores(family, ctx)
	var best := -1
	var best_score := 0.0
	for kind in scores:
		var sc: float = scores[kind] + rng.randf_range(-GameConstants.GOAL_NOISE, GameConstants.GOAL_NOISE)
		if sc > best_score:
			best_score = sc
			best = kind
	if best < 0:
		return {}
	var G := GameConstants.Goal
	var target := -1
	match best:
		G.SURPASS:
			target = int(ctx.rival_id)
		G.REVENGE:
			target = int(ctx.insulted_by)
		G.ALLIANCE:
			target = int(ctx.partner_families[0])
		G.UNION:
			target = int(ctx.allies[0])
	return {kind = best, target_id = target}


# --- Marriages, corruption, infiltration, secret romance ------------------------------------

## Pairs one of `own` (unmarried adults of the House) with one of `partners` (another House):
## a man and a woman, not close kin, age gap allowed; the closest ages win. {person_id, partner_id} or {}.
static func arranged_match(own: Array, partners: Array, state: WorldState) -> Dictionary:
	var best := {}
	var best_gap := INF
	for a: Dictionary in own:
		for b: Dictionary in partners:
			if bool(a.female) == bool(b.female) or int(a.get("spouse_id", -1)) >= 0 or int(b.get("spouse_id", -1)) >= 0:
				continue
			if float(a.age) < GameConstants.MARRY_MIN_AGE or float(b.age) < GameConstants.MARRY_MIN_AGE:
				continue
			var gap := absf(float(a.age) - float(b.age))
			if gap > GameConstants.COUPLE_MAX_AGE_GAP or Kinship.is_close_kin(state, a, b):
				continue
			if gap < best_gap:
				best_gap = gap
				best = {person_id = a.id, partner_id = b.id}
	return best


## How someone takes an arranged marriage: "accept", "resist" or "flee" (with the one they love).
## `rel` = relation with the proposed partner; `love_rel` = with someone else they love (-1: no one).
static func arranged_response(person: Dictionary, rel: float, love_rel: float, rng: RandomNumberGenerator) -> String:
	if rel >= GameConstants.COUPLE_AT:
		return "accept"
	var traits: Array = person.get("traits", [])
	var in_love := love_rel >= GameConstants.COUPLE_AT
	var p_accept := 0.55 + rel * 0.4 - (0.3 if in_love else 0.0)
	if traits.has(T.FEARFUL):
		p_accept += 0.15
	if traits.has(T.BRAVE):
		p_accept -= 0.15
	var roll := rng.randf()
	if roll < clampf(p_accept, 0.05, 0.95):
		return "accept"
	if in_love and rng.randf() < 0.35 + (0.2 if traits.has(T.BRAVE) else 0.0):
		return "flee"
	return "resist"


## Chance per working day that a House skims from the kingdom stock (only greedy heads).
static func corruption_chance(family: Dictionary, head: Dictionary) -> float:
	if not (head.get("traits", []) as Array).has(T.GREEDY):
		return 0.0
	var goal: Dictionary = family.get("goal", {})
	var bonus := 0.1 if goal.get("kind", -1) == GameConstants.Goal.WEALTH else 0.0
	return GameConstants.CORRUPTION_BASE + float((family.get("values", {}) as Dictionary).get("wealth", 0.5)) * 0.15 + bonus


## Chance per day that a secret (skimming, a spy, a hidden romance) comes out, given how many
## honest/curious people watch.
static func discovery_chance(watchers: int) -> float:
	return minf(GameConstants.DISCOVERY_BASE + GameConstants.DISCOVERY_PER_WATCHER * watchers, GameConstants.DISCOVERY_MAX)


## A member the House could plant in its rival (never the head; prefers loners and the greedy),
## or {} when `rival` is not this House's rival.
static func spy_candidate(family: Dictionary, rival: Dictionary, members: Array) -> Dictionary:
	if rival.is_empty() or int(rival.id) == int(family.id) or int(family.get("rival_id", -1)) != int(rival.id):
		return {}
	var best := {}
	var best_score := -1.0
	for m: Dictionary in members:
		if int(m.id) == int(family.get("head_id", -1)) or float(m.get("age", 0.0)) < GameConstants.ADULT_AGE:
			continue
		var traits: Array = m.get("traits", [])
		var sc := 0.1 + (0.5 if traits.has(T.LONER) else 0.0) + (0.4 if traits.has(T.GREEDY) else 0.0)
		if sc > best_score:
			best_score = sc
			best = m
	return best


## Two adults of the same sex in love can only meet in secret (frowned upon, medieval custom).
static func secret_romance_possible(a: Dictionary, b: Dictionary, rel: float, kin: bool) -> bool:
	if kin or bool(a.female) != bool(b.female) or rel < GameConstants.COUPLE_AT:
		return false
	return float(a.age) >= GameConstants.MARRY_MIN_AGE and float(b.age) >= GameConstants.MARRY_MIN_AGE


## Trade of someone just grown up: the vocation when the House agrees (or there is no House), the
## House trade while a clash is unresolved, or what the kingdom needs when there is no vocation.
## {profession, conflict}.
static func grown_profession(person: Dictionary, family: Dictionary, needed: int) -> Dictionary:
	var v := int(person.get("vocation", -1))
	if v < 0:
		return {profession = needed, conflict = false}
	if conflicts(person, family):
		return {profession = expected_professions(family)[0], conflict = true}
	return {profession = v, conflict = false}
