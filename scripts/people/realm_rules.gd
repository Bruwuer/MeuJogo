class_name RealmRules
extends RefCounted
## Pure rules between kingdoms (stage 9), no scene: how a relation drifts each day, who declares
## war, who accepts peace, how strong a kingdom is and how a battle ends.

const T := GameConstants.Trait


## The NPC ruling `k` ({} when the player rules or nobody does).
static func ruler_of(state: WorldState, k: Dictionary) -> Dictionary:
	return state.person(int(k.ruler_id)) if int(k.ruler_id) >= 0 else {}


static func guards(state: WorldState, k: Dictionary) -> Array[Dictionary]:
	return state.residents(k.id).filter(func(p: Dictionary) -> bool:
		return int(p.profession) == GameConstants.Profession.GUARD and SocietyRules.is_adult(p))


## Guards count fully; other adults help a little.
static func strength(state: WorldState, k: Dictionary) -> float:
	var adults := state.residents(k.id).filter(func(p: Dictionary) -> bool: return SocietyRules.is_adult(p)).size()
	var g := guards(state, k).size()
	return g + GameConstants.REALM_CIVIL_STRENGTH * (adults - g)


## The day's change of the relation between `a` and `b` (before the pull back to neutral).
static func daily_drift(state: WorldState, a: Dictionary, b: Dictionary) -> float:
	var d := Vector2(a.center.x - b.center.x, a.center.z - b.center.z).length()
	var drift := 0.0
	if d < GameConstants.REALM_BORDER: # close seats quarrel over land
		drift -= GameConstants.REALM_BORDER_RATE * (GameConstants.REALM_BORDER - d) / 100.0
	for k in [a, b]:
		var ruler := ruler_of(state, k)
		if ruler.is_empty():
			continue
		for t: int in [T.BRAVE, T.GREEDY]:
			if PersonGen.has_trait(ruler, t):
				drift -= GameConstants.REALM_TRAIT_RATE
		for t: int in [T.GENEROUS, T.SOCIABLE]:
			if PersonGen.has_trait(ruler, t):
				drift += GameConstants.REALM_TRAIT_RATE
		if k.get("ruler_corrupt", false):
			drift -= GameConstants.REALM_TRAIT_RATE
	# Toward a kingdom the player rules, the other ruler's view of the player counts.
	for pair in [[a, b], [b, a]]:
		if int(pair[0].ruler_id) == GameConstants.GOV_PLAYER:
			var other := ruler_of(state, pair[1])
			if not other.is_empty():
				drift += float(other.opinion) * GameConstants.REALM_OPINION_RATE
	if _has_market(state, a) and _has_market(state, b):
		drift += GameConstants.REALM_TRADE_RATE
	return clampf(drift, -GameConstants.REALM_DRIFT_MAX, GameConstants.REALM_DRIFT_MAX)


static func _has_market(state: WorldState, k: Dictionary) -> bool:
	return VillageRules.kingdom_buildings(state, k).any(func(b: Dictionary) -> bool:
		return int(b.type) == GameConstants.Building.MARKET and not b.get("site", false))


## Whether the NPC ruler of `a` declares war on `b` at `hour`: angry enough, strong enough, no
## truce, and `b` not ruled by the player (NPC kingdoms do not start wars on the player).
static func wants_war(state: WorldState, a: Dictionary, b: Dictionary, hour: float) -> bool:
	if ruler_of(state, a).is_empty() or int(b.ruler_id) == GameConstants.GOV_PLAYER:
		return false
	var r := state.realm(a.id, b.id)
	if r.war or hour < float(r.truce_until) or float(r.rel) >= GameConstants.REALM_WAR_AT:
		return false
	if guards(state, a).size() < GameConstants.REALM_WAR_MIN_GUARDS:
		return false
	return strength(state, a) >= GameConstants.REALM_WAR_RATIO * strength(state, b)


## Whether `k`, tired by `weary`, accepts a peace offer (the player's kingdoms always do: the
## founder does not fight wars in this stage).
static func accepts_peace(state: WorldState, k: Dictionary, weary: float) -> bool:
	if int(k.ruler_id) == GameConstants.GOV_PLAYER:
		return true
	var ruler := ruler_of(state, k)
	return weary >= GameConstants.REALM_PEACE_ACCEPT or (not ruler.is_empty() and PersonGen.has_trait(ruler, T.GENEROUS))


## A war party of `party` guards from `atk` at the gates of `def`: {attacker_wins, atk_loss, def_loss}.
static func battle(state: WorldState, atk: Dictionary, def: Dictionary, party: int, rng: RandomNumberGenerator) -> Dictionary:
	var def_guards := guards(state, def).size()
	var atk_s := float(party) * rng.randf_range(GameConstants.REALM_ROLL.x, GameConstants.REALM_ROLL.y)
	var def_s := strength(state, def) * GameConstants.REALM_DEFENSE_BONUS \
			* rng.randf_range(GameConstants.REALM_ROLL.x, GameConstants.REALM_ROLL.y)
	var wins := atk_s > def_s
	var loser_guards := def_guards if wins else party
	var loser_loss := 0 if loser_guards == 0 else maxi(1, ceili(0.5 * loser_guards))
	var ratio := minf(1.0, (def_s if wins else atk_s) / maxf(0.01, atk_s if wins else def_s))
	var winner_loss := floori(loser_loss * ratio)
	return {attacker_wins = wins, atk_loss = winner_loss if wins else loser_loss,
			def_loss = loser_loss if wins else winner_loss}


## Hours a person needs to walk between two points, with room to spare.
static func travel_hours(from: Vector3, to: Vector3) -> float:
	var d := Vector2(from.x - to.x, from.z - to.z).length()
	return d / GameConstants.REALM_WALK_M_PER_HOUR * GameConstants.REALM_TRAVEL_SLACK + GameConstants.REALM_TRAVEL_EXTRA
