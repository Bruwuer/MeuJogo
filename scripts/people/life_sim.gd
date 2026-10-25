class_name LifeSim
extends RefCounted
## The hourly life of a kingdom's people beyond work (stage 10), run by VillageSim after GovSim:
## the dead are fetched, carried to the cemetery and buried by someone who walks, kneels, carries
## and digs; the family prays at the grave; feelings come and fade; an unburied body frightens
## the kingdom. Every act is a deed with its animation (rule 17); everything goes to the ADM log.

const B := GameConstants.Building

## A body was picked up or buried (its node lying on the ground must go).
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
	_everyday(k)
	_wishes(k)


# --- Everyday life (stage 11) ---------------------------------------------------------------

## Meals by the fire (people on screen only: offscreen meals are summarized by VillageSim), the
## evening at the fire and children at play (anyone; offscreen they are summarized like any deed),
## never out in the rain.
func _everyday(k: Dictionary) -> void:
	var h := float(int(fmod(_hour, 24.0)))
	var wet := _state.raining(_hour)
	for p in _state.residents(k.id):
		if not (p.get("deed", {}) as Dictionary).is_empty():
			continue
		var deed := {}
		if h in GameConstants.MEAL_HOURS and _houses.has_node.call(p.id) \
				and float(p.get("hunger", 0.0)) >= GameConstants.MEAL_HUNGER * LifeRules.ration_share(k):
			deed = Deeds.make("meal", _ring_spot(k, p, GameConstants.MEAL_RING), GameConstants.PERSON_ARRIVE, _hour,
					_hour + GameConstants.MEAL_WINDOW, GameConstants.MEAL_SEC, {})
			deed.anim = GameConstants.ANIM_EAT
		elif not wet and h == GameConstants.FIRESIDE_HOURS.x and SocietyRules.is_adult(p) \
				and float((p.get("needs", {}) as Dictionary).get("social", 0.0)) >= GameConstants.FIRESIDE_WANT:
			var w := Deeds.next_window(_hour, GameConstants.FIRESIDE_HOURS.x, GameConstants.FIRESIDE_HOURS.y)
			deed = Deeds.make("fireside", _ring_spot(k, p, GameConstants.FIRESIDE_RING), GameConstants.PERSON_ARRIVE, w.x, w.y,
					GameConstants.FIRESIDE_SEC, {})
			deed.anim = GameConstants.ANIM_SIT
		elif not wet and h in GameConstants.PLAY_HOURS and not SocietyRules.is_adult(p):
			deed = Deeds.make("play", _play_spot(k, p), GameConstants.PERSON_ARRIVE * GameConstants.GOV_REACH_MULT, _hour,
					_hour + GameConstants.MEAL_WINDOW, GameConstants.PLAY_SEC, {})
			deed.anim = GameConstants.ANIM_PLAY
		if not deed.is_empty():
			_houses.plan_deed(p, deed)


## A place in the ring around the kingdom's campfire (the seat's door when it has none).
func _ring_spot(k: Dictionary, p: Dictionary, ring: float) -> Vector3:
	var at: Vector3 = k.center
	var seat := _state.building(int(k.get("seat_id", -1)))
	if not seat.is_empty():
		at = PeopleManager.door_of(seat)
	for b in VillageRules.kingdom_buildings(_state, k):
		if int(b.type) == B.CAMPFIRE and not b.get("site", false):
			at = b.pos
			break
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_state.seed, "ring", p.id])
	return _free_around(at, ring, rng)


## Around the child's home door (or the seat's), a little different each time.
func _play_spot(k: Dictionary, p: Dictionary) -> Vector3:
	var home := _state.building(int(p.get("home_id", -1)))
	var at: Vector3 = PeopleManager.door_of(home) if not home.is_empty() else _ring_spot(k, p, GameConstants.PLAY_RADIUS)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_state.seed, "play", p.id, int(_hour)])
	return _free_around(at, rng.randf_range(1.0, GameConstants.PLAY_RADIUS), rng)


## A spot about `radius` from `at` that one can reach: outside every building and clear of trees and
## rocks (tries around the circle, a little nearer and farther). `at` itself when nothing is free.
func _free_around(at: Vector3, radius: float, rng: RandomNumberGenerator) -> Vector3:
	var start := rng.randf() * TAU
	for r in [radius, radius * 1.4, radius * 0.7, radius * 1.9]:
		for i in GameConstants.SPOT_TRIES:
			var spot: Vector3 = at + Vector3.FORWARD.rotated(Vector3.UP, start + TAU * i / GameConstants.SPOT_TRIES) * float(r)
			if _reachable(spot):
				return spot
	return at


func _reachable(spot: Vector3) -> bool:
	for b in _state.all_buildings():
		if Vector2(b.pos.x - spot.x, b.pos.z - spot.z).length() > GameConstants.SPOT_NEAR:
			continue
		var rect := BuildRules.footprint_rect(int(b.type), b.pos, int(b.rot))
		if rect.grow(GameConstants.SPOT_CLEARANCE).has_point(Vector2(spot.x, spot.z)):
			return false
	if _scatter:
		for prop in _scatter.props_near(spot, GameConstants.SPOT_CLEARANCE * 2.0):
			if not _state.removed_in(ChunkMath.world_to_chunk(prop.pos)).has(prop.id):
				return false
	return true


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
			LifeRules.add_mood(p, "joy", GameConstants.WISH_JOY)
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
		if body.status != "dead" or care_of(body).get("id", -1) != k.id:
			continue
		if int(body.get("carrier_id", -1)) >= 0:
			if _still_carried(body):
				continue
			release(body) # the carrier died, left, or lost the errand: someone else must come
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


## Whether `body`'s carrier is still a resident holding it on the way to bury it.
func _still_carried(body: Dictionary) -> bool:
	var c := _state.person(int(body.carrier_id))
	if c.is_empty() or c.status != "resident" or int(c.get("carrying_body", -1)) != body.id:
		return false
	var deed: Dictionary = c.get("deed", {})
	return deed.get("kind", "") == "bury" and int((deed.get("data", {}) as Dictionary).get("body_id", -1)) == body.id


## The body is put down (where its carrier stood) and waits for another bearer.
func release(body: Dictionary) -> void:
	var c := _state.person(int(body.get("carrier_id", -1)))
	if not c.is_empty():
		if int(c.get("carrying_body", -1)) == body.id:
			c.carrying_body = -1
		_state.move_person(body.id, c.pos)
	body.carrier_id = -1
	body.bearer_id = -1


## Grief of the living for `dead` (called when anyone dies).
func _mourn(dead: Dictionary) -> void:
	var held := _state.person(int(dead.get("carried_before", -1)))
	if not held.is_empty() and held.status == "dead":
		release(held) # a carrier who dies drops the body
	for p in _state.residents(int(dead.kingdom_id)):
		var g := LifeRules.grief_for(_state, p, dead)
		if g > 0.0:
			LifeRules.add_mood(p, "grief", g, PersonGen.full_name(dead))


## The next free grave slot of `k`'s cemetery (chosen the first time, out toward the edge).
func _grave_spot(k: Dictionary) -> Vector3:
	if not k.has("cemetery"):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([_state.seed, "cemetery", k.id])
		var start := rng.randf() * TAU
		var dir := Vector3.FORWARD.rotated(Vector3.UP, start)
		k.cemetery = k.center + dir * float(k.radius) * GameConstants.CEMETERY_SHARE
		# Flat, free ground: the first whole row of graves must fit (never a rocky slope).
		for i in GameConstants.CEMETERY_TRIES:
			var d := Vector3.FORWARD.rotated(Vector3.UP, start + TAU * i / GameConstants.CEMETERY_TRIES)
			var base: Vector3 = k.center + d * float(k.radius) * GameConstants.CEMETERY_SHARE
			if _gen == null or _row_fits(k, base):
				k.cemetery = base
				break
		k.graves = 0
	var base: Vector3 = k.cemetery
	var inward := Vector3(k.center.x - base.x, 0.0, k.center.z - base.z).normalized() # new rows grow toward the center
	var side := inward.cross(Vector3.UP)
	for t in GameConstants.GRAVE_TRIES:
		var n := int(k.graves) + t
		var col := (n % GameConstants.GRAVE_COLS) - (GameConstants.GRAVE_COLS - 1) * 0.5
		var pos := base + side * col * GameConstants.GRAVE_SPACING + inward * (n / GameConstants.GRAVE_COLS) * GameConstants.GRAVE_ROW
		if _gen:
			pos.y = _gen.height_at(pos.x, pos.z)
			if not BuildRules.check_site(B.GRAVE, pos, 0, _gen, _scatter, _state, []).ok:
				continue
		k.graves = n + 1
		return pos
	k.graves = int(k.graves) + 1
	return base


## Talking, `p` hears what `other` thinks: of the founder, and of whom `other` can't stand.
func _gossip(p: Dictionary, other: Dictionary) -> void:
	p.opinion = clampf(float(p.opinion) + (float(other.opinion) - float(p.opinion)) * GameConstants.GOSSIP_PULL, -1.0, 1.0)
	var rels := _state.relations_of(other.id)
	var worst := -1
	var worst_v := GameConstants.RIVAL_AT
	for id in rels:
		var o := _state.person(id)
		if id == p.id or o.is_empty() or int(p.get("spouse_id", -1)) == id or Kinship.is_close_kin(_state, p, o):
			continue # gossip does not turn one against one's own
		if float(rels[id]) <= worst_v:
			worst = id
			worst_v = float(rels[id])
	if worst >= 0:
		_state.add_relation(p.id, worst, -GameConstants.GOSSIP_RIVAL)


## Whether a whole row of graves fits at `base` (on flat, free ground).
func _row_fits(k: Dictionary, base: Vector3) -> bool:
	var inward := Vector3(k.center.x - base.x, 0.0, k.center.z - base.z).normalized()
	var side := inward.cross(Vector3.UP)
	for c in GameConstants.GRAVE_COLS:
		var pos := base + side * (c - (GameConstants.GRAVE_COLS - 1) * 0.5) * GameConstants.GRAVE_SPACING
		pos.y = _gen.height_at(pos.x, pos.z)
		var check := BuildRules.check_site(B.GRAVE, pos, 0, _gen, _scatter, _state, [])
		if not check.ok or _gen.biome_at(pos.x, pos.z) == GameConstants.Biome.ROCKY:
			return false
	return true


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
			body_removed.emit(body.id) # off the ground: from now on it is drawn in the bearer's arms
			var care := _state.kingdom(int(data.get("kingdom_id", k.id)))
			var spot := _grave_spot(care)
			var bury := Deeds.make("bury", spot, GameConstants.PERSON_ARRIVE, _hour, _hour + GameConstants.BURY_HOURS,
					GameConstants.DIG_SEC, {body_id = body.id, kingdom_id = care.id})
			bury.anim = GameConstants.ANIM_DIG
			_houses.plan_deed(p, bury)
			_procession(care, body, spot)
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
			p.needs = p.get("needs", {social = 0.0, faith = 0.0})
			p.needs.social = 0.0
			LifeRules.add_mood(p, "joy", GameConstants.TALK_JOY)
			if not other.is_empty():
				_gossip(p, other)
				_state.add_relation(p.id, other.id, GameConstants.TALK_REL / 2.0) # each side adds half

		"meal":
			LifeRules.meal(p, k, _state)
		"procession":
			pass # they walked behind the body and stood by the grave: the funeral comes next
		"fireside":
			p.needs = p.get("needs", {social = 0.0, faith = 0.0})
			p.needs.social = maxf(0.0, float(p.needs.get("social", 0.0)) - GameConstants.FIRESIDE_SOCIAL)
			LifeRules.add_mood(p, "joy", GameConstants.PRAY_JOY)
		"play":
			LifeRules.add_mood(p, "joy", GameConstants.PLAY_JOY)
		"prayer":
			p.needs.faith = 0.0
			LifeRules.add_mood(p, "joy", GameConstants.PRAY_JOY)
		"funeral":
			LifeRules.add_mood(p, "grief", 0.0)
			p.mood.grief = float(p.mood.grief) * GameConstants.FUNERAL_GRIEF_KEEP
			_log(k, GameConstants.LIFE_MSG_PRAYED % [PersonGen.full_name(p), String(data.get("dead_name", ""))])
		_:
			return false
	return true


## The close family walks behind the body to the grave and waits there with the head bowed.
func _procession(k: Dictionary, body: Dictionary, grave_at: Vector3) -> void:
	var kin := _state.residents(k.id).filter(func(o: Dictionary) -> bool:
		return (SocietyRules.is_adult(o) and (o.get("deed", {}) as Dictionary).is_empty()
				and LifeRules.grief_for(_state, o, body) >= GameConstants.GRIEF_KIN))
	for i in kin.size():
		var a := TAU * (i + 0.5) / maxf(1.0, kin.size())
		var deed := Deeds.make("procession", grave_at + Vector3(cos(a), 0.0, sin(a)) * GameConstants.PROCESSION_RING,
				GameConstants.PERSON_ARRIVE, _hour, _hour + GameConstants.BURY_HOURS, GameConstants.PROCESSION_SEC, {body_id = body.id})
		deed.anim = GameConstants.ANIM_MOURN
		_houses.plan_deed(kin[i], deed)


## The family kneels and prays at the new grave at dusk (each one free goes; nobody is forced).
func _funeral(k: Dictionary, grave: Dictionary, mourners: Array) -> void:
	var w := Deeds.next_window(_hour, GameConstants.DEED_CEREMONY.x, GameConstants.DEED_CEREMONY.y) # a ceremony, by daylight
	for i in mourners.size():
		var m: Dictionary = mourners[i]
		if not (m.get("deed", {}) as Dictionary).is_empty():
			continue
		var a := PI * (GameConstants.FUNERAL_ARC.x + GameConstants.FUNERAL_ARC.y * i / maxf(1.0, mourners.size()))
		var spot: Vector3 = grave.pos + Vector3(cos(a), 0.0, -sin(a)) * GameConstants.FUNERAL_OFFSET
		var deed := Deeds.make("funeral", spot, GameConstants.PERSON_ARRIVE, w.x, w.y, GameConstants.DEED_CEREMONY_SEC,
				{grave_id = grave.id, dead_name = grave.name})
		deed.anim = GameConstants.ANIM_PRAY
		_houses.plan_deed(m, deed)


func _log(k: Dictionary, text: String) -> void:
	_state.chronicle_add(_hour, text, k.id)
