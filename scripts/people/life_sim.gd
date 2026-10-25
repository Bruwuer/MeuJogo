class_name LifeSim
extends RefCounted
## The hourly life of a kingdom's people beyond work (stage 10), run by VillageSim after GovSim:
## the dead are fetched, carried to the cemetery and buried by someone who walks, kneels, carries
## and digs; the family prays at the grave; feelings come and fade; an unburied body frightens
## the kingdom. Every act is a deed with its animation (rule 17); everything goes to the ADM log.

const B := GameConstants.Building

## A body was buried (its node, lying or carried, must go).
signal body_removed(id: int)

var _state: WorldState
var _houses: HouseSim
var _gen: TerrainGenerator
var _scatter: PropScatter
var _hour := 0.0


func setup(state: WorldState, houses: HouseSim, society: SocietySim) -> void:
	_state = state
	_houses = houses
	houses.deed_handlers.append(complete_deed)
	if not society.person_died.is_connected(_mourn): # VillageSim may be set up again (tests)
		society.person_died.connect(_mourn)


## Terrain and props, so graves sit on the ground clear of trees (optional in tests).
func set_terrain(gen: TerrainGenerator, scatter: PropScatter) -> void:
	_gen = gen
	_scatter = scatter


func tick_hour(k: Dictionary, hour: float) -> void:
	_hour = hour
	for p in _state.residents(k.id):
		LifeRules.fade_moods(p, 1.0)
	_bodies(k)
	_needs(k)
	_wishes(k)


# --- Needs and wants ------------------------------------------------------------------------

## Company is missed by every adult (sociable more, loners less), faith by the devout. In the free
## evening hours whoever misses company goes to talk to a friend; at dusk the devout pray.
func _needs(k: Dictionary) -> void:
	var h := fmod(_hour, 24.0)
	for p in _state.residents(k.id):
		if not SocietyRules.is_adult(p):
			continue
		var needs: Dictionary = p.get("needs", {})
		if needs.is_empty():
			p.needs = {social = 0.0, faith = 0.0}
			needs = p.needs
		var rate := GameConstants.SOCIAL_PER_HOUR
		if PersonGen.has_trait(p, GameConstants.Trait.SOCIABLE):
			rate *= float(GameConstants.SOCIAL_TRAIT.sociable)
		elif PersonGen.has_trait(p, GameConstants.Trait.LONER):
			rate *= float(GameConstants.SOCIAL_TRAIT.loner)
		needs.social = minf(1.0, float(needs.get("social", 0.0)) + rate)
		if PersonGen.has_trait(p, GameConstants.Trait.DEVOUT):
			needs.faith = minf(1.0, float(needs.get("faith", 0.0)) + GameConstants.FAITH_PER_HOUR)
		if not (p.get("deed", {}) as Dictionary).is_empty():
			continue
		var talked := h >= GameConstants.TALK_HOURS.x and h < GameConstants.TALK_HOURS.y \
				and float(needs.social) >= GameConstants.SOCIAL_WANT and plan_talk(k, p, _hour)
		if not talked and int(h) == int(GameConstants.DEED_DUSK.x) - 1 and float(needs.get("faith", 0.0)) >= GameConstants.FAITH_WANT:
			_plan_prayer(k, p)


## `a` walks to meet a friend (or whom they love) halfway and they talk face to face. False when
## nobody is free to meet.
func plan_talk(k: Dictionary, a: Dictionary, hour: float) -> bool:
	_hour = hour
	var b := {}
	var target := int((a.get("desire", {}) as Dictionary).get("target_id", -1))
	var rels := _state.relations_of(a.id)
	var best := GameConstants.FRIEND_AT
	for other_id in rels:
		var o := _state.person(other_id)
		if o.is_empty() or o.status != "resident" or int(o.kingdom_id) != k.id or not SocietyRules.is_adult(o) \
				or not (o.get("deed", {}) as Dictionary).is_empty():
			continue
		var score := float(rels[other_id]) + (1.0 if o.id == target else 0.0) # whom one loves comes first
		if score >= best and (b.is_empty() or score > best or o.id < b.id):
			best = score
			b = o
	if b.is_empty():
		return false
	var mid: Vector3 = (a.pos + b.pos) * 0.5
	var dir: Vector3 = b.pos - a.pos
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.RIGHT
	var spots := [mid - dir * GameConstants.TALK_GAP * 0.5, mid + dir * GameConstants.TALK_GAP * 0.5]
	var people := [a, b]
	for i in 2:
		var other: Dictionary = people[1 - i]
		var deed := Deeds.make("talk", spots[i], GameConstants.PERSON_ARRIVE, _hour, _hour + GameConstants.TALK_WINDOW,
				GameConstants.TALK_SEC, {with = other.id, lead = i == 0, face = spots[1 - i]})
		deed.anim = GameConstants.ANIM_TALK
		_houses.plan_deed(people[i], deed)
	return true


func _plan_prayer(k: Dictionary, p: Dictionary) -> void:
	var at: Vector3 = k.center
	for b in VillageRules.kingdom_buildings(_state, k):
		if int(b.type) == B.FLAG:
			at = b.pos + GameConstants.GOV_FLAG_OFFSET
			break
	var w := Deeds.next_window(_hour, GameConstants.DEED_DUSK.x, GameConstants.DEED_DUSK.y)
	var deed := Deeds.make("prayer", at, GameConstants.PERSON_ARRIVE * GameConstants.GOV_REACH_MULT, w.x, w.y,
			GameConstants.DEED_CEREMONY_SEC, {})
	deed.anim = GameConstants.ANIM_PRAY
	_houses.plan_deed(p, deed)


## Adults with no want find one once a day; a want come true is a joy.
func _wishes(k: Dictionary) -> void:
	var D := GameConstants.Desire
	var daily := int(fmod(_hour, 24.0)) == int(GameConstants.DEED_HOUR)
	for p in _state.residents(k.id):
		if not SocietyRules.is_adult(p):
			continue
		var want: Dictionary = p.get("desire", {})
		var kind := int(want.get("kind", D.NONE))
		var done := false
		match kind:
			D.LOVE:
				done = int(p.get("spouse_id", -1)) >= 0 and int(p.spouse_id) == int(want.get("target_id", -2))
			D.RICH:
				done = float(_state.family(int(p.get("family_id", -1))).get("wealth", 0.0)) >= GameConstants.WEALTH_COMFORT
		if done:
			LifeRules.add_mood(p, "joy", GameConstants.TALK_JOY * 3.0)
			var text: String = GameConstants.DESIRE_TEXTS[kind]
			if text.contains("%s"):
				text = text % PersonGen.full_name(_state.person(int(want.get("target_id", -1))))
			_log(k, GameConstants.LIFE_MSG_WISH % [PersonGen.full_name(p), text])
			p.desire = {kind = D.NONE, target_id = -1}
		elif kind == D.NONE and daily:
			p.desire = LifeRules.pick_desire(_state, p)


# --- Bodies ----------------------------------------------------------------------------------

## The kingdom whose territory holds the body (or the dead's own kingdom when it lies outside any).
func care_of(body: Dictionary) -> Dictionary:
	var here := _state.kingdom_at(body.pos)
	return here if not here.is_empty() else _state.kingdom(int(body.kingdom_id))


func _bodies(k: Dictionary) -> void:
	for body in _state.all_people():
		if body.status != "dead" or care_of(body).get("id", -1) != k.id or int(body.get("carrier_id", -1)) >= 0:
			continue
		if _hour - float(body.get("died_hour", _hour)) > GameConstants.BODY_UNBURIED_HOURS:
			for p in _state.residents(k.id): # a body left lying frightens everyone
				LifeRules.add_mood(p, "fear", GameConstants.BODY_FEAR_PER_HOUR)
				p.contentment = clampf(float(p.contentment) + GameConstants.BODY_CONTENT_PER_HOUR, 0.0, 1.0)
		var bearer := _state.person(int(body.get("bearer_id", -1)))
		if not bearer.is_empty() and (bearer.get("deed", {}) as Dictionary).get("kind", "") == "fetch_body":
			continue # someone is on the way
		bearer = LifeRules.bearer_for(_state, _state.residents(k.id), body)
		if bearer.is_empty():
			continue
		var w := Deeds.next_window(_hour, GameConstants.DEED_DAY.x, GameConstants.DEED_DAY.y)
		var deed := Deeds.make("fetch_body", body.pos, GameConstants.PERSON_ARRIVE, w.x, w.y, GameConstants.PICKUP_SEC,
				{body_id = body.id, kingdom_id = k.id})
		deed.anim = GameConstants.ANIM_PICKUP
		_houses.plan_deed(bearer, deed)
		body.bearer_id = bearer.id
		_log(k, GameConstants.LIFE_MSG_FETCH % [PersonGen.full_name(bearer), PersonGen.full_name(body)])


## Grief of the living for `dead` (called when anyone dies).
func _mourn(dead: Dictionary) -> void:
	for p in _state.residents(int(dead.kingdom_id)):
		var g := LifeRules.grief_for(_state, p, dead)
		if g > 0.0:
			LifeRules.add_mood(p, "grief", g, PersonGen.full_name(dead))


## The next free grave slot of `k`'s cemetery (chosen the first time, out toward the edge).
func _grave_spot(k: Dictionary) -> Vector3:
	if not k.has("cemetery"):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([_state.seed, "cemetery", k.id])
		var dir := Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU)
		k.cemetery = k.center + dir * float(k.radius) * GameConstants.CEMETERY_SHARE
		k.graves = 0
	var base: Vector3 = k.cemetery
	for t in GameConstants.GRAVE_TRIES:
		var n := int(k.graves) + t
		var pos := base + Vector3((n % GameConstants.GRAVE_COLS) * GameConstants.GRAVE_SPACING, 0.0,
				(n / GameConstants.GRAVE_COLS) * GameConstants.GRAVE_ROW)
		if _gen:
			pos.y = _gen.height_at(pos.x, pos.z)
			if not BuildRules.check_site(B.GRAVE, pos, 0, _gen, _scatter, _state, []).ok:
				continue
		k.graves = n + 1
		return pos
	k.graves = int(k.graves) + 1
	return base


# --- Deeds ----------------------------------------------------------------------------------

func complete_deed(k: Dictionary, p: Dictionary, deed: Dictionary, _seen: Array, hour: float) -> bool:
	_hour = hour
	var data: Dictionary = deed.data
	match String(deed.kind):
		"fetch_body":
			var body := _state.person(int(data.get("body_id", -1)))
			if body.is_empty() or body.status != "dead" or int(body.get("carrier_id", -1)) >= 0:
				return true
			body.carrier_id = p.id
			p.carrying_body = body.id
			var care := _state.kingdom(int(data.get("kingdom_id", k.id)))
			var spot := _grave_spot(care)
			var bury := Deeds.make("bury", spot, GameConstants.PERSON_ARRIVE, _hour, _hour + GameConstants.BURY_HOURS,
					GameConstants.DIG_SEC, {body_id = body.id, kingdom_id = care.id})
			bury.anim = GameConstants.ANIM_DIG
			_houses.plan_deed(p, bury)
		"bury":
			var body := _state.person(int(data.get("body_id", -1)))
			p.carrying_body = -1
			if body.is_empty():
				return true
			var care := _state.kingdom(int(data.get("kingdom_id", k.id)))
			var grave := _state.add_building(B.GRAVE, deed.pos, 0, Color.WHITE, GameConstants.OWNER_KINGDOM)
			grave.kingdom_id = care.id
			grave.name = PersonGen.full_name(body)
			grave.died_hour = float(body.get("died_hour", _hour))
			var mourners := _state.residents(care.id).filter(func(o: Dictionary) -> bool:
				return LifeRules.grief_for(_state, o, body) >= GameConstants.GRIEF_KIN and SocietyRules.is_adult(o))
			_log(care, GameConstants.LIFE_MSG_BURIED % [PersonGen.full_name(p), PersonGen.full_name(body)])
			_state.remove_person(body.id)
			body_removed.emit(body.id)
			_houses.buildings_changed.emit([grave])
			_funeral(care, grave, mourners)
		"talk":
			var other := _state.person(int(data.get("with", -1)))
			p.needs.social = 0.0
			LifeRules.add_mood(p, "joy", GameConstants.TALK_JOY)
			if not other.is_empty():
				_state.add_relation(p.id, other.id, GameConstants.TALK_REL * 0.5)
				if data.get("lead", false):
					_log(k, GameConstants.LIFE_MSG_TALKED % [PersonGen.full_name(p), PersonGen.full_name(other)])
		"prayer":
			p.needs.faith = 0.0
			LifeRules.add_mood(p, "joy", GameConstants.PRAY_JOY)
			_log(k, GameConstants.LIFE_MSG_PRAYED_FLAG % PersonGen.full_name(p))
		"funeral":
			LifeRules.add_mood(p, "grief", 0.0)
			p.mood.grief = float(p.mood.grief) * GameConstants.FUNERAL_GRIEF_KEEP
			_log(k, GameConstants.LIFE_MSG_PRAYED % [PersonGen.full_name(p), String(data.get("dead_name", ""))])
		_:
			return false
	return true


## The family kneels and prays at the new grave at dusk (each one free goes; nobody is forced).
func _funeral(k: Dictionary, grave: Dictionary, mourners: Array) -> void:
	var w := Deeds.next_window(_hour, GameConstants.DEED_DUSK.x, GameConstants.DEED_DUSK.y)
	for i in mourners.size():
		var m: Dictionary = mourners[i]
		if not (m.get("deed", {}) as Dictionary).is_empty():
			continue
		var a := PI * (0.25 + 0.5 * i / maxf(1.0, mourners.size()))
		var spot: Vector3 = grave.pos + Vector3(cos(a), 0.0, -sin(a)) * GameConstants.FUNERAL_OFFSET
		var deed := Deeds.make("funeral", spot, GameConstants.PERSON_ARRIVE, w.x, w.y, GameConstants.DEED_CEREMONY_SEC,
				{grave_id = grave.id, dead_name = grave.name})
		deed.anim = GameConstants.ANIM_PRAY
		_houses.plan_deed(m, deed)


func _log(k: Dictionary, text: String) -> void:
	_state.chronicle_add(_hour, text, k.id)
