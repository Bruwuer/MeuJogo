class_name SocietyRules
extends RefCounted
## Pure social logic, no scene: how a meeting changes two people's relation, kinship, who may
## marry and have children, how a person's opinion of the player drifts each hour, and whether a
## person or family is the player's ally or enemy (with hysteresis so it does not flicker).

const T := GameConstants.Trait


static func is_adult(p: Dictionary) -> bool:
	return float(p.age) >= GameConstants.ADULT_AGE


## Parent and child, or sharing a parent.
static func is_kin(a: Dictionary, b: Dictionary) -> bool:
	var pa: Array = a.get("parents", [])
	var pb: Array = b.get("parents", [])
	if pa.has(b.id) or pb.has(a.id):
		return true
	return pa.any(func(id: int) -> bool: return pb.has(id))


## Change of a relation after one meeting: alike traits attract, opposite ones repel, sociable
## people warm up and loners cool down; `close` = same house or family.
static func meeting_delta(a: Dictionary, b: Dictionary, close: bool, rng: RandomNumberGenerator) -> float:
	var d := GameConstants.MEET_BASE
	for ta: int in a.traits:
		for tb: int in b.traits:
			if ta == tb:
				d += GameConstants.MEET_SAME_TRAIT
			elif PersonGen.pair_of(ta) == PersonGen.pair_of(tb):
				d += GameConstants.MEET_OPPOSITE_TRAIT
	for p in [a, b]:
		if PersonGen.has_trait(p, T.SOCIABLE):
			d += GameConstants.MEET_SOCIABLE
		if PersonGen.has_trait(p, T.LONER):
			d += GameConstants.MEET_LONER
	if close:
		d += GameConstants.MEET_CLOSE
	return d + rng.randf_range(-GameConstants.MEET_NOISE, GameConstants.MEET_NOISE)


static func can_marry(a: Dictionary, b: Dictionary, rel: float) -> bool:
	if a.id == b.id or rel < GameConstants.COUPLE_AT:
		return false
	for p in [a, b]:
		if float(p.age) < GameConstants.MARRY_MIN_AGE or int(p.spouse_id) >= 0:
			return false
	if absf(float(a.age) - float(b.age)) > GameConstants.COUPLE_MAX_AGE_GAP:
		return false
	return not is_kin(a, b)


## The partner who can carry a child (a woman of BIRTH_AGE with a man), or {}.
static func birth_mother(a: Dictionary, b: Dictionary) -> Dictionary:
	if bool(a.female) == bool(b.female):
		return {}
	var mother: Dictionary = a if a.female else b
	var age := float(mother.age)
	if age < GameConstants.BIRTH_AGE.x or age > GameConstants.BIRTH_AGE.y:
		return {}
	return mother


## Hourly change of a person's opinion of the player. `family_mean` = the family's adult mean (pass
## the person's own opinion when there is none); `ties` = [[relation, other's opinion], ...].
static func opinion_drift(p: Dictionary, family_mean: float, ties: Array) -> float:
	var op := float(p.opinion)
	var d := (float(p.contentment) - 0.5) * GameConstants.OPINION_CONTENT_RATE
	d += (family_mean - op) * GameConstants.OPINION_FAMILY_PULL
	for tie: Array in ties:
		var rel: float = tie[0]
		var other: float = tie[1]
		if rel >= GameConstants.FRIEND_AT:
			d += (other - op) * GameConstants.OPINION_FRIEND_PULL
		elif rel <= GameConstants.RIVAL_AT:
			d -= (other - op) * GameConstants.OPINION_RIVAL_PUSH
	return d


## "ally" | "enemy" | "": entering needs ALLY_AT / ENEMY_AT, leaving needs ALLY_EXIT / ENEMY_EXIT.
static func stance_for(opinion: float, current: String) -> String:
	if current == "ally" and opinion >= GameConstants.ALLY_EXIT:
		return "ally"
	if current == "enemy" and opinion <= GameConstants.ENEMY_EXIT:
		return "enemy"
	if opinion >= GameConstants.ALLY_AT:
		return "ally"
	if opinion <= GameConstants.ENEMY_AT:
		return "enemy"
	return ""


## Mean opinion of the adults in `members` (children do not count).
static func adult_mean(members: Array) -> Variant:
	var sum := 0.0
	var n := 0
	for p: Dictionary in members:
		if is_adult(p):
			sum += float(p.opinion)
			n += 1
	return sum / n if n > 0 else null


static func family_stance(members: Array, current: String) -> String:
	var mean: Variant = adult_mean(members)
	return "" if mean == null else stance_for(mean, current)


## "friend" | "rival" | "".
static func label(rel: float) -> String:
	if rel >= GameConstants.FRIEND_AT:
		return "friend"
	if rel <= GameConstants.RIVAL_AT:
		return "rival"
	return ""


## The per-hour chance that gives `per_day` over 24 hours.
static func hourly_chance(per_day: float) -> float:
	return 1.0 - pow(1.0 - per_day, 1.0 / 24.0)


## The player talks to `p` on game day `day`: the first talk of the day pleases a sociable person,
## annoys a loner and is mildly nice to anyone else. Returns whether it counted.
static func talk(p: Dictionary, day: int) -> bool:
	if int(p.get("talk_day", -1)) >= day:
		return false
	p.talk_day = day
	var key := "other"
	if PersonGen.has_trait(p, T.SOCIABLE):
		key = "sociable"
	elif PersonGen.has_trait(p, T.LONER):
		key = "loner"
	p.opinion = clampf(float(p.opinion) + GameConstants.TALK_OPINION[key], -1.0, 1.0)
	return true
