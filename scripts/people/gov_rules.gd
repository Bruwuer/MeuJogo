class_name GovRules
extends RefCounted
## Pure government logic (stage 8), no scene: who takes over a kingdom (support, heirs), how a ruler
## behaves (way and corruption), which decrees a ruler keeps, when the Houses depose a ruler and how a
## change of decree moves a person's opinion of the founder.

const T := GameConstants.Trait


static func default_decrees() -> Dictionary:
	return {tax = "none", ration = "normal", guards = GameConstants.GOV_GUARDS_FREE, build = GameConstants.GOV_BUILD_FREE}


## A House head's claim to rule: prestige, adult members and how the other heads like the head.
static func support(state: WorldState, f: Dictionary) -> float:
	var adults := state.family_members(f.id).filter(func(p: Dictionary) -> bool:
		return SocietyRules.is_adult(p) and p.status == "resident").size()
	var rel := 0.0
	var n := 0
	for other in state.families_of(int(f.kingdom_id)):
		if other.id != f.id and int(other.head_id) >= 0:
			rel += state.relation(int(other.head_id), int(f.head_id))
			n += 1
	var mean := rel / n if n > 0 else 0.0
	return float(f.get("prestige", 0.0)) + adults * GameConstants.GOV_SUPPORT_MEMBER \
			+ mean * GameConstants.GOV_SUPPORT_RELATION


## The person who takes over `k` (-1 when nobody can): the House head with most support, else the
## oldest adult resident. Ties go to the lowest id. `except_id` cannot be chosen.
static func choose_regent(state: WorldState, k: Dictionary, except_id := -2) -> int:
	var best := -1
	var best_score := -INF
	for f in state.families_of(k.id):
		var head := state.person(int(f.head_id))
		if head.is_empty() or head.id == except_id or head.status != "resident" or not SocietyRules.is_adult(head):
			continue
		var sc := support(state, f)
		if sc > best_score or (sc == best_score and head.id < best):
			best = head.id
			best_score = sc
	if best >= 0:
		return best
	var oldest := -1
	var oldest_age := -1.0
	for p in state.residents(k.id):
		if p.id == except_id or not SocietyRules.is_adult(p):
			continue
		if float(p.age) > oldest_age or (float(p.age) == oldest_age and p.id < oldest):
			oldest = p.id
			oldest_age = float(p.age)
	return oldest


## The oldest adult resident of House `family_id` other than `except_id` (-1 when none).
static func heir_of(state: WorldState, k: Dictionary, family_id: int, except_id: int) -> int:
	var best := -1
	var best_age := -1.0
	for p in state.family_members(family_id):
		if p.id == except_id or p.status != "resident" or int(p.kingdom_id) != k.id or not SocietyRules.is_adult(p):
			continue
		if float(p.age) > best_age or (float(p.age) == best_age and p.id < best):
			best = p.id
			best_age = float(p.age)
	return best


## "leal", "culto", "neutro" or "inimigo", from the ruler's own opinion of the founder.
static func ruler_way(p: Dictionary) -> String:
	var op := float(p.opinion)
	if op >= GameConstants.ALLY_AT:
		if PersonGen.has_trait(p, T.DEVOUT) and op >= GameConstants.GOV_CULT_OPINION:
			return "culto"
		return "leal"
	if op <= GameConstants.ENEMY_AT:
		return "inimigo"
	return "neutro"


## Greedy rulers, or rulers of a House that values wealth above all, enrich themselves.
static func is_corrupt(p: Dictionary, f: Dictionary) -> bool:
	if PersonGen.has_trait(p, T.GREEDY):
		return true
	return float((f.get("values", {}) as Dictionary).get("wealth", 0.0)) >= GameConstants.GOV_CORRUPT_WEALTH


## Whether a ruler of this way hands the kingdom back to the returning founder.
static func gives_back(way: String, mean_opinion: float) -> bool:
	match way:
		"leal", "culto":
			return true
		"neutro":
			return mean_opinion >= 0.0
	return false


## The decrees an NPC ruler keeps or sets.
static func npc_decrees(way: String, corrupt: bool, current: Dictionary) -> Dictionary:
	var d := current.duplicate()
	if way == "inimigo":
		d.tax = "low"
		d.ration = "normal"
	if corrupt:
		d.tax = "high"
	return d


## Whether the House heads depose the NPC ruler of `k` at `hour`: they hate the ruler (mean
## relation below GOV_DEPOSE_AT) and the reign is old enough.
static func wants_deposition(state: WorldState, k: Dictionary, hour: float) -> bool:
	var ruler_id := int(k.ruler_id)
	if ruler_id == GameConstants.GOV_PLAYER or hour - float(k.ruler_since) < GameConstants.GOV_MIN_REIGN_HOURS:
		return false
	var ruler := state.person(ruler_id)
	if ruler.is_empty():
		return false
	var sum := 0.0
	var n := 0
	for f in state.families_of(k.id):
		var head := state.person(int(f.head_id))
		if head.is_empty() or head.id == ruler_id or f.id == int(ruler.get("family_id", -2)):
			continue
		sum += state.relation(head.id, ruler_id)
		n += 1
	return n > 0 and sum / n < GameConstants.GOV_DEPOSE_AT


## Opinion change of `p` (of House `f`, maybe {}) when decree `key` goes from `old` to `new`.
static func decree_opinion(p: Dictionary, f: Dictionary, key: String, old: Variant, new: Variant) -> float:
	var step := GameConstants.GOV_OPINION_STEP
	match key:
		"tax":
			var levels: Array = GameConstants.GOV_TAX_LEVELS
			var up := levels.find(new) - levels.find(old)
			var greed := 1.0 + float((f.get("values", {}) as Dictionary).get("wealth", 0.0))
			return -up * step * greed
		"ration":
			var levels: Array = GameConstants.GOV_RATION_LEVELS
			return (levels.find(new) - levels.find(old)) * step
		"guards":
			if int(f.get("tradition", -1)) != GameConstants.Tradition.WARRIORS and not PersonGen.has_trait(p, T.BRAVE):
				return 0.0
			var a := maxi(0, int(old))
			var b := maxi(0, int(new))
			return signf(b - a) * step
	return 0.0
