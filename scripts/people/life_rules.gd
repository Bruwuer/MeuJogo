class_name LifeRules
extends RefCounted
## Pure rules of life (stage 10), no scene: feelings (joy, grief, fear, anger) that come and fade,
## what the card says about them, who mourns a death and who goes for a body.


## Adds `amount` of feeling `kind` to `p` (capped at 1); `about` names who it is about (grief).
static func add_mood(p: Dictionary, kind: String, amount: float, about := "") -> void:
	if not p.has("mood"):
		p.mood = {joy = 0.0, grief = 0.0, fear = 0.0, anger = 0.0}
	p.mood[kind] = clampf(float(p.mood.get(kind, 0.0)) + amount, 0.0, 1.0)
	if about != "":
		p.mood[kind + "_for"] = about


## Feelings fade a little every `hours` (grief slowest).
static func fade_moods(p: Dictionary, hours: float) -> void:
	var mood: Dictionary = p.get("mood", {})
	for kind: String in GameConstants.MOOD_FADE:
		mood[kind] = float(mood.get(kind, 0.0)) * pow(float(GameConstants.MOOD_FADE[kind]), hours)


## The strongest feeling worth telling ("" when none): "de luto por Ana Souto", "com medo"...
static func mood_text(p: Dictionary) -> String:
	var mood: Dictionary = p.get("mood", {})
	var best := ""
	var best_v := GameConstants.MOOD_SHOW_AT
	for kind: String in GameConstants.MOOD_TEXTS:
		if float(mood.get(kind, 0.0)) >= best_v:
			best = kind
			best_v = float(mood[kind])
	if best == "":
		return ""
	if best == "grief" and String(mood.get("grief_for", "")) != "":
		return GameConstants.MOOD_GRIEF_FOR % mood.grief_for
	return GameConstants.MOOD_TEXTS[best]


## How much `p` grieves the death of `dead`: kin and spouse most, friends less, others not.
static func grief_for(state: WorldState, p: Dictionary, dead: Dictionary) -> float:
	if p.id == dead.id:
		return 0.0
	if int(dead.get("spouse_id", -1)) == p.id or Kinship.is_close_kin(state, p, dead):
		return GameConstants.GRIEF_KIN
	if state.relation(p.id, dead.id) >= GameConstants.FRIEND_AT:
		return GameConstants.GRIEF_FRIEND
	return 0.0


## What an adult wishes for, from who they are and whom they love: {kind, target_id}.
static func pick_desire(state: WorldState, p: Dictionary) -> Dictionary:
	var D := GameConstants.Desire
	if int(p.get("spouse_id", -1)) < 0:
		var beloved := {}
		var best := GameConstants.LOVE_AT
		var rels := state.relations_of(p.id)
		for other_id in rels:
			var o := state.person(other_id)
			if o.is_empty() or o.status != "resident" or bool(o.female) == bool(p.female) or not SocietyRules.is_adult(o) \
					or int(o.get("spouse_id", -1)) >= 0 or Kinship.is_close_kin(state, p, o):
				continue
			if float(rels[other_id]) >= best:
				best = float(rels[other_id])
				beloved = o
		if not beloved.is_empty():
			return {kind = D.LOVE, target_id = beloved.id}
	if PersonGen.has_trait(p, GameConstants.Trait.GREEDY):
		return {kind = D.RICH, target_id = -1}
	if float(p.get("resentment", 0.0)) >= 0.5:
		return {kind = D.LEAVE, target_id = -1}
	if PersonGen.has_trait(p, GameConstants.Trait.BRAVE):
		for c in state.residents(int(p.kingdom_id)):
			if not SocietyRules.is_adult(c) and Kinship.is_close_kin(state, p, c):
				return {kind = D.PROTECT, target_id = -1}
	if PersonGen.has_trait(p, GameConstants.Trait.WORKER):
		for parent_id in (p.parents as Array):
			var parent := state.person(int(parent_id))
			if not parent.is_empty() and parent.status == "resident" and int(parent.profession) == int(p.profession):
				return {kind = D.SURPASS_PARENT, target_id = parent.id}
	return {kind = D.NONE, target_id = -1}


## Who of `people` goes for the body of `dead`: a free adult, kin first, then the lowest id.
static func bearer_for(state: WorldState, people: Array, dead: Dictionary) -> Dictionary:
	var best := {}
	var best_rank := 2
	for p: Dictionary in people:
		if p.status != "resident" or not SocietyRules.is_adult(p) or not (p.get("deed", {}) as Dictionary).is_empty() \
				or int(p.get("carrying_body", -1)) >= 0:
			continue
		var rank := 0 if grief_for(state, p, dead) >= GameConstants.GRIEF_KIN else 1
		if best.is_empty() or rank < best_rank or (rank == best_rank and p.id < best.id):
			best = p
			best_rank = rank
	return best
