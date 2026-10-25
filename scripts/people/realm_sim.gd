class_name RealmSim
extends RefCounted
## Life between kingdoms (stage 9), run by VillageSim once per hour after every kingdom: once a day
## the relations drift, NPC rulers declare war or seek peace by envoy, and kingdoms at war send war
## parties. Every act is a deed: the envoy walks to the other seat, the war party marches to the
## enemy's gates, and only then the war starts, the peace is made, the gift arrives or the battle is
## fought. Everything goes to the ADM chronicle. Randomness is seeded by (seed, tag, kingdoms, hour).

const R := GameConstants.Res
const B := GameConstants.Building

## A building burned in a battle (its node must go).
signal building_burned(rec: Dictionary)
## A bush under a new seat is gone (its node must go).
signal prop_removed(c: Vector2i, id: int)
## People moved between Houses or homes (banners may need a new crest).
signal families_changed

var _state: WorldState
var _houses: HouseSim
var _society: SocietySim
var _gen: TerrainGenerator
var _scatter: PropScatter
var _hour := 0.0


func setup(state: WorldState, houses: HouseSim, society: SocietySim, gov: GovSim) -> void:
	_state = state
	_houses = houses
	_society = society
	houses.deed_handlers.append(complete_deed)


## Terrain and props, to find where a House founds a new kingdom (no exodus without them).
func set_terrain(gen: TerrainGenerator, scatter: PropScatter) -> void:
	_gen = gen
	_scatter = scatter


func tick_hour(hour: float) -> void:
	_hour = hour
	if int(fmod(hour, 24.0)) == int(GameConstants.REALM_HOUR):
		_daily()


func _daily() -> void:
	var ks := _state.kingdoms()
	for i in ks.size():
		for j in range(i + 1, ks.size()):
			var r := _state.realm(ks[i].id, ks[j].id)
			r.rel = clampf((float(r.rel) + RealmRules.daily_drift(_state, ks[i], ks[j])) * GameConstants.REALM_DECAY, -1.0, 1.0)
			if r.war:
				r.weary_a = float(r.weary_a) + GameConstants.REALM_WEARY_DAY
				r.weary_b = float(r.weary_b) + GameConstants.REALM_WEARY_DAY
	for k in ks:
		if RealmRules.ruler_of(_state, k).is_empty():
			if int(k.ruler_id) == GameConstants.GOV_PLAYER:
				k.war_guard = false # a regent's call-up ends with the founder; the decrees are his now
			continue # the player decides for the own kingdoms; nobody decides in an interregnum
		var enemies := ks.filter(func(o: Dictionary) -> bool: return o.id != k.id and _state.at_war(k.id, o.id))
		var tense := ks.any(func(o: Dictionary) -> bool:
			return o.id != k.id and float(_state.realm(k.id, o.id).rel) < GameConstants.REALM_ARM_AT)
		_war_guard(k, not enemies.is_empty() or tense) # arming before a war, too
		for e: Dictionary in enemies:
			if weary(k, e) >= GameConstants.REALM_PEACE_WEARY:
				send_envoy(k, e, "peace", _hour)
			elif _hour >= float(k.get("next_march_hour", 0.0)):
				_march(k, e)
		for o in ks:
			if o.id != k.id and RealmRules.wants_war(_state, k, o, _hour):
				send_envoy(k, o, "war", _hour)
	for k in _state.kingdoms():
		_exodus(k)


## A House that cannot stand its kingdom sets out: the head walks to a free place and founds a
## kingdom there when he arrives. Only with the whole House offscreen (nobody vanishes on screen).
func _exodus(k: Dictionary) -> void:
	if _gen == null or _hour < float(k.get("next_exodus_hour", 0.0)):
		return
	if int(k.get("exodus_family", -1)) >= 0 and _hour <= float(k.get("exodus_until", 0.0)):
		return
	k.exodus_family = -1
	var f := RealmRules.exodus_house(_state, k)
	if f.is_empty():
		return
	if _settlers(k, f).any(func(p: Dictionary) -> bool: return _houses.has_node.call(p.id)):
		return
	var head := _state.person(int(f.head_id))
	if not (head.get("deed", {}) as Dictionary).is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_state.seed, "exodus", k.id, int(_hour)])
	var site := NpcRealms._place(_state, _gen, _scatter, [], rng, false)
	if site.x < 0.0:
		k.next_exodus_hour = _hour + GameConstants.REALM_EXODUS_RETRY_HOURS
		return
	var end := _hour + RealmRules.travel_hours(k.center, site)
	_houses.plan_deed(head, Deeds.make("exodus", site, GameConstants.PERSON_ARRIVE * GameConstants.REALM_MARCH_REACH,
			_hour, end, GameConstants.DEED_WORK_SEC, {kingdom_id = k.id, family_id = f.id, site = site}))
	k.exodus_family = f.id
	k.exodus_until = end
	k.next_exodus_hour = _hour + GameConstants.REALM_EXODUS_DAYS * 24.0
	_log(k, GameConstants.REALM_MSG_EXODUS % [f.surname, k.name])


## Who leaves with House `f` of `old`: its resident members, their spouses (even of another House)
## and the minor children of any of them.
func _settlers(old: Dictionary, f: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in _state.residents(old.id):
		if int(p.family_id) == f.id:
			out.append(p)
	for p in out.duplicate():
		var spouse := _state.person(int(p.get("spouse_id", -1)))
		if not spouse.is_empty() and spouse.status == "resident" and int(spouse.kingdom_id) == old.id and not out.has(spouse):
			out.append(spouse)
	for c in _state.residents(old.id):
		if not SocietyRules.is_adult(c) and not out.has(c) \
				and (c.parents as Array).any(func(id: int) -> bool: return out.any(func(o: Dictionary) -> bool: return o.id == id)):
			out.append(c)
	return out


## The head reached the place: the kingdom is founded and the whole household moves there (only if
## the place is still free and nobody of them is on screen).
func _found(old: Dictionary, head: Dictionary, f: Dictionary, site: Vector3) -> void:
	old.exodus_family = -1
	if f.is_empty() or head.status != "resident" or int(f.kingdom_id) != old.id \
			or _state.kingdoms().size() >= GameConstants.REALM_MAX \
			or _state.kingdoms().any(func(o: Dictionary) -> bool:
				return Vector2(o.center.x - site.x, o.center.z - site.z).length() < GameConstants.REALM_MIN_GAP):
		return
	var members := _settlers(old, f)
	if members.any(func(p: Dictionary) -> bool: return _houses.has_node.call(p.id) and p.id != head.id):
		return
	var check := BuildRules.check_site(B.CABIN, site, 0, _gen, _scatter, _state, [])
	if not check.ok: # someone built there meanwhile
		return
	for bush: Dictionary in check.bushes:
		_state.mark_removed(bush.chunk, bush.id)
		prop_removed.emit(bush.chunk, bush.id)
	var index := _state.kingdoms().size()
	var color := KingdomNames.color(_state.seed, index)
	var seat := _state.add_building(B.CABIN, site, 0, Color.WHITE, GameConstants.OWNER_KINGDOM)
	var flag_pos := site + GameConstants.FLAG_OFFSET
	var flag := _state.add_building(B.FLAG, Vector3(flag_pos.x, _gen.height_at(flag_pos.x, flag_pos.z), flag_pos.z), 0,
			color, GameConstants.OWNER_KINGDOM)
	var nk := _state.add_kingdom(KingdomNames.generate(_state.seed, index), color, site, seat.id, "npc")
	var ids := members.map(func(p: Dictionary) -> int: return p.id)
	for i in members.size():
		var m: Dictionary = members[i]
		SocietySim.transfer_houses(_state, m.id, ids)
		m.kingdom_id = nk.id
		m.family_id = f.id # spouses and children from other Houses join the household's House
		m.home_id = -1
		m.inside = -1
		m.deed = {}
		var a := TAU * i / maxf(1.0, members.size())
		_state.move_person(m.id, site + Vector3(cos(a), 0.0, sin(a)) * GameConstants.REALM_SETTLE_RING)
	f.kingdom_id = nk.id
	f.wealth = float(f.wealth) - GameConstants.REALM_EXODUS_WEALTH
	nk.ruler_id = head.id
	nk.ruler_family = f.id
	nk.ruler_way = ""
	nk.ruler_corrupt = GovRules.is_corrupt(head, f)
	nk.ruler_since = _hour
	nk.decrees.guards = GameConstants.REALM_NPC_GUARDS
	nk.people_ever = members.size()
	var angry := float(head.opinion) < 0.0 if int(old.ruler_id) < 0 else _state.relation(head.id, int(old.ruler_id)) < 0.0
	_state.realm(old.id, nk.id).rel = GameConstants.REALM_EXODUS_REL.angry if angry else GameConstants.REALM_EXODUS_REL.calm
	_houses.buildings_changed.emit([seat, flag])
	families_changed.emit()
	_log_both(old, nk, GameConstants.REALM_MSG_FOUNDED % [f.surname, old.name, nk.name])


## A ruler at war (or arming for one) calls up the whole guard; when it passes the usual guard comes back.
func _war_guard(k: Dictionary, at_war: bool) -> void:
	if at_war and not k.get("war_guard", false):
		k.war_guard = true
		k.peace_guards = int(k.decrees.guards)
		k.decrees.guards = GameConstants.GOV_GUARDS_MAX
	elif not at_war and k.get("war_guard", false):
		k.war_guard = false
		k.decrees.guards = int(k.get("peace_guards", GameConstants.GOV_GUARDS_FREE))


## How tired `k` is of the war with `other`.
func weary(k: Dictionary, other: Dictionary) -> float:
	var r := _state.realm(k.id, other.id)
	return float(r.weary_a) if k.id < other.id else float(r.weary_b)


func _add_weary(a: Dictionary, b: Dictionary, amount: float) -> void:
	var r := _state.realm(a.id, b.id)
	r.weary_a = float(r.weary_a) + amount
	r.weary_b = float(r.weary_b) + amount


## Sends a free adult of `from` to the seat of `to` with a declaration of war, a peace offer or a
## gift ("war", "peace", "gift"). False when one is already on the way or nobody is free.
func send_envoy(from: Dictionary, to: Dictionary, act: String, hour: float) -> bool:
	_hour = hour
	if float(from.get("envoy_until", -1.0)) > hour:
		return false
	var envoy := {}
	for p in _state.residents(from.id): # anyone free; the ruler goes only when nobody else can
		if not SocietyRules.is_adult(p) or not (p.get("deed", {}) as Dictionary).is_empty():
			continue
		var rank := 1 if p.id == int(from.ruler_id) else 0
		var best_rank := 1 if not envoy.is_empty() and envoy.id == int(from.ruler_id) else 0
		if envoy.is_empty() or rank < best_rank or (rank == best_rank and p.id < envoy.id):
			envoy = p
	if envoy.is_empty():
		return false
	var w := Deeds.next_window(hour, GameConstants.DEED_DAY.x, GameConstants.DEED_DAY.y)
	var end := w.x + RealmRules.travel_hours(from.center, to.center)
	_houses.plan_deed(envoy, Deeds.make("envoy", _seat_door(to), GameConstants.PERSON_ARRIVE * GameConstants.GOV_REACH_MULT,
			w.x, end, GameConstants.DEED_CEREMONY_SEC, {kingdom_id = from.id, target_id = to.id, act = act}))
	from.envoy_until = end
	return true


## The free guards (all but one, at least one) march to the enemy's gates.
func _march(k: Dictionary, enemy: Dictionary) -> void:
	var free := RealmRules.guards(_state, k).filter(func(p: Dictionary) -> bool:
		return (p.get("deed", {}) as Dictionary).is_empty() and p.id != int(k.ruler_id))
	if free.is_empty():
		return
	free.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.id < y.id)
	var n := mini(free.size(), maxi(1, RealmRules.guards(_state, k).size() - 1))
	var party: Array = free.slice(0, n)
	var ids := party.map(func(p: Dictionary) -> int: return p.id)
	var end := _hour + RealmRules.travel_hours(k.center, enemy.center)
	for i in party.size():
		var data := {kingdom_id = k.id, target_id = enemy.id}
		if i == 0:
			data.party = ids
		else:
			data.follow = ids[0]
		_houses.plan_deed(party[i], Deeds.make("march", _seat_door(enemy), GameConstants.PERSON_ARRIVE * GameConstants.REALM_MARCH_REACH, _hour, end,
				GameConstants.DEED_WORK_SEC, data))
	k.next_march_hour = _hour + GameConstants.REALM_MARCH_EVERY_HOURS
	_log(k, GameConstants.REALM_MSG_MARCH % [k.name, enemy.name])


# --- Deeds ----------------------------------------------------------------------------------

## Deeds handed over by GovSim. Returns whether the kind was one of these.
func complete_deed(_k: Dictionary, p: Dictionary, deed: Dictionary, _seen: Array, hour: float) -> bool:
	_hour = hour
	var data: Dictionary = deed.data
	var from := _state.kingdom(int(data.get("kingdom_id", -1)))
	var to := _state.kingdom(int(data.get("target_id", -1)))
	match String(deed.kind):
		"envoy":
			from.envoy_until = -1.0
			if not from.is_empty() and not to.is_empty():
				_envoy_arrived(from, to, String(data.act), p)
		"exodus":
			_found(from, p, _state.family(int(data.get("family_id", -1))), data.site)
		"march":
			if data.has("party") and not from.is_empty() and not to.is_empty() and _state.at_war(from.id, to.id):
				_battle(from, to, data.party)
		_:
			return false
	return true


func _envoy_arrived(from: Dictionary, to: Dictionary, act: String, envoy: Dictionary) -> void:
	var r := _state.realm(from.id, to.id)
	match act:
		"war":
			# Checked again on arrival: a truce, a founder back on the throne or a ruler gone end it.
			if not r.war and _hour >= float(r.truce_until) and int(to.ruler_id) != GameConstants.GOV_PLAYER \
					and not RealmRules.ruler_of(_state, from).is_empty():
				r.war = true
				r.since = _hour
				r.weary_a = 0.0
				r.weary_b = 0.0
				_log_both(from, to, GameConstants.REALM_MSG_WAR % [from.name, to.name])
		"peace":
			if not r.war:
				return
			if RealmRules.accepts_peace(_state, to, weary(to, from)):
				r.war = false
				r.truce_until = _hour + GameConstants.REALM_TRUCE_DAYS * 24.0
				r.rel = maxf(float(r.rel), GameConstants.REALM_PEACE_REL)
				r.weary_a = 0.0
				r.weary_b = 0.0
				_log_both(from, to, GameConstants.REALM_MSG_PEACE % [from.name, to.name])
			else:
				_log_both(from, to, GameConstants.REALM_MSG_PEACE_REFUSED % [to.name, from.name])
		"gift":
			var res := SocietySim._most([R.WOOD, R.STONE, R.FOOD], func(x: int) -> int: return _state.stock_of(from, x))
			var n := mini(GameConstants.REALM_GIFT, _state.stock_of(from, res))
			if n <= 0:
				return
			_state.add_stock(from, res, -n)
			_state.add_stock(to, res, n)
			r.rel = clampf(float(r.rel) + GameConstants.REALM_GIFT_REL, -1.0, 1.0)
			_log_both(from, to, GameConstants.REALM_MSG_GIFT % [from.name, n, SocietySim._res_name(res), to.name])


## The war party of `atk` (ids in `party`; the dead do not fight) at the gates of `def`.
func _battle(atk: Dictionary, def: Dictionary, party: Array) -> void:
	var alive := party.map(func(id: int) -> Dictionary: return _state.person(id)).filter(func(p: Dictionary) -> bool:
		return not p.is_empty() and p.status == "resident" and int(p.kingdom_id) == atk.id)
	if alive.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_state.seed, "battle", atk.id, def.id, int(_hour)])
	var res := RealmRules.battle(_state, atk, def, alive.size(), rng)
	_add_weary(atk, def, GameConstants.REALM_WEARY_BATTLE)
	if res.attacker_wins:
		var loot := _loot(atk, def)
		var burned := _burn(def)
		_log_both(atk, def, GameConstants.REALM_MSG_BATTLE_WIN % [def.name, atk.name, loot, burned])
	else:
		_log_both(atk, def, GameConstants.REALM_MSG_BATTLE_LOSE % [def.name, atk.name])
	_casualties(def, RealmRules.guards(_state, def), int(res.def_loss), rng)
	_casualties(atk, alive, int(res.atk_loss), rng)


## `n` of `people` die in battle, drawn by `rng` (through the society: homes pass on, nodes go).
func _casualties(k: Dictionary, people: Array, n: int, rng: RandomNumberGenerator = null) -> void:
	var order := people.duplicate()
	order.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.id < y.id)
	if rng:
		for i in range(order.size() - 1, 0, -1): # seeded shuffle: the leader is not always the first to fall
			var j := rng.randi() % (i + 1)
			var tmp: Dictionary = order[i]
			order[i] = order[j]
			order[j] = tmp
	for i in mini(n, order.size()):
		var p: Dictionary = order[i]
		if _state.person(int(p.id)).is_empty():
			continue
		_society.kill(k, p, GameConstants.REALM_MSG_FELL % PersonGen.full_name(p))


## The winner carries off a share of each resource. Returns what was taken, in words.
func _loot(atk: Dictionary, def: Dictionary) -> String:
	var parts: PackedStringArray = []
	for res in [R.WOOD, R.STONE, R.FOOD, R.BERRIES]:
		var n := floori(_state.stock_of(def, res) * GameConstants.REALM_LOOT_SHARE)
		if n > 0:
			_state.add_stock(def, res, -n)
			_state.add_stock(atk, res, n)
			parts.append("%d de %s" % [n, SocietySim._res_name(res)])
	return ", ".join(parts) if not parts.is_empty() else GameConstants.REALM_NOTHING


## One building of `def` burns (nearest to its center; never the seat, the flag, stakes or sites).
func _burn(def: Dictionary) -> String:
	var best := {}
	var best_d := INF
	for b in VillageRules.kingdom_buildings(_state, def):
		if b.id == int(def.seat_id) or int(b.type) in [B.FLAG, B.STAKE] or b.get("site", false):
			continue
		var d := Vector2(b.pos.x - def.center.x, b.pos.z - def.center.z).length()
		if d < best_d:
			best_d = d
			best = b
	if best.is_empty():
		return GameConstants.REALM_NOTHING
	_state.remove_building(best.id)
	building_burned.emit(best)
	return (GameConstants.BUILD_NAMES[int(best.type)] as String).to_lower()


func _seat_door(k: Dictionary) -> Vector3:
	var seat := _state.building(int(k.get("seat_id", -1)))
	return PeopleManager.door_of(seat) if not seat.is_empty() else k.center


func _log(k: Dictionary, text: String) -> void:
	_state.chronicle_add(_hour, text, k.id)


func _log_both(a: Dictionary, b: Dictionary, text: String) -> void:
	_log(a, text)
	_log(b, text)
