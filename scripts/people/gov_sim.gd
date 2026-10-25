class_name GovSim
extends RefCounted
## The hourly government of a kingdom (stage 8), run by VillageSim right after HouseSim: the
## founder's absence and the regent's crowning, succession when a ruler dies or leaves, the founder's
## return (handover or refusal), the decrees carried out (tax, guard muster), the NPC ruler's ways
## (corruption, cult) and deposition by the House heads. Every act is a deed of a person (rule 17);
## everything goes to the ADM chronicle, never to the HUD. Randomness is seeded by (seed, tag, kingdom, day).

const P := GameConstants.Profession
const R := GameConstants.Res

var _state: WorldState
var _houses: HouseSim
var _is_player_in: Callable
var _hour := 0.0


func setup(state: WorldState, houses: HouseSim, is_player_in: Callable) -> void:
	_state = state
	_houses = houses
	_is_player_in = is_player_in
	houses.extra_deed = complete_deed
	houses.ruler_skim = ruler_skimmed


func tick_hour(k: Dictionary, hour: float) -> void:
	_hour = hour
	var inside: bool = _is_player_in.call(k)
	k.away_hours = 0.0 if inside else float(k.away_hours) + 1.0
	if not inside:
		k.refused = false # the next return is told again
	_ruler_still_here(k)
	_pending(k, inside)
	if int(k.ruler_id) == GameConstants.GOV_PLAYER and float(k.away_hours) >= GameConstants.GOV_ABSENCE_HOURS \
			and int(k.get("pending_ruler", -1)) < 0:
		_name_ruler(k, GovRules.choose_regent(_state, k), false)
	if int(k.ruler_id) == GameConstants.GOV_NOBODY and int(k.get("pending_ruler", -1)) < 0:
		# Nobody is on the way to the seat: the founder takes over if the people want him back,
		# else whoever can rule is named (an adult may have grown up meanwhile).
		if inside and GovRules.mean_opinion(_state, k) >= 0.0:
			_set_player(k)
		else:
			_name_ruler(k, GovRules.choose_regent(_state, k), false)
	if inside and int(k.ruler_id) >= 0:
		_return(k)
	if int(fmod(hour, 24.0)) == int(GameConstants.DEED_HOUR):
		_taxes(k)
		_guard(k)
		_ruler_nights(k)
		_worship(k)
		_deposition(k)


# --- Who rules ------------------------------------------------------------------------------

## The founder may build, demolish and donate here unless a ruler who keeps the kingdom governs.
func player_may_act(k: Dictionary) -> bool:
	var ruler := int(k.ruler_id)
	if ruler < 0 or _state.person(ruler).is_empty():
		return true
	return GovRules.gives_back(String(k.ruler_way), GovRules.mean_opinion(_state, k))


## The answer to the founder's act in a kingdom that is no longer theirs.
func refusal(k: Dictionary) -> String:
	var ruler := _state.person(int(k.ruler_id))
	return GameConstants.GOV_NOT_YOURS % [k.name,
			PersonGen.full_name(ruler) if not ruler.is_empty() else GameConstants.GOV_SOMEONE]


## The founder changes a decree (only while governing). Opinions move; the decree is announced.
func set_decree(k: Dictionary, key: String, value: Variant) -> bool:
	if int(k.ruler_id) != GameConstants.GOV_PLAYER or not (k.decrees as Dictionary).has(key) or k.decrees[key] == value:
		return false
	var old: Variant = k.decrees[key]
	k.decrees[key] = value
	for p in _state.residents(k.id):
		if SocietyRules.is_adult(p):
			var f := _state.family(int(p.get("family_id", -1)))
			p.opinion = clampf(float(p.opinion) + GovRules.decree_opinion(p, f, key, old, value), -1.0, 1.0)
	_state.chronicle_add(_hour, GameConstants.GOV_MSG_DECREE % [GameConstants.GOV_DECREE_NAMES[key], value_name(key, value)], k.id)
	return true


static func value_name(key: String, value: Variant) -> String:
	match key:
		"tax":
			return GameConstants.GOV_TAX_NAMES[value]
		"ration":
			return GameConstants.GOV_RATION_NAMES[value]
		"guards":
			return "livre" if int(value) < 0 else str(value)
		"build":
			return "livre" if int(value) < 0 else (GameConstants.BUILD_NAMES[int(value)] as String).to_lower()
	return str(value)


## The ruler died or left: the heir (or the best supported) is crowned.
func _ruler_still_here(k: Dictionary) -> void:
	var ruler_id := int(k.ruler_id)
	if ruler_id < 0:
		return
	var ruler := _state.person(ruler_id)
	if not ruler.is_empty() and ruler.status == "resident" and int(ruler.kingdom_id) == k.id:
		k.ruler_family = int(ruler.get("family_id", -1)) # unions move people between Houses
		return
	k.ruler_id = GameConstants.GOV_NOBODY
	var heir := GovRules.heir_of(_state, k, int(k.get("ruler_family", -1)), ruler_id)
	if heir >= 0:
		_name_ruler(k, heir, true)
	else:
		_name_ruler(k, GovRules.choose_regent(_state, k, ruler_id), false)


## `id` will rule once crowned at the seat.
func _name_ruler(k: Dictionary, id: int, heir: bool) -> void:
	if id < 0:
		return
	k.pending_ruler = id
	k.pending_heir = heir
	_plan_crowning(k)


func _plan_crowning(k: Dictionary) -> void:
	var p := _state.person(int(k.pending_ruler))
	if p.is_empty() or not _free(p):
		return
	var w := Deeds.next_window(_hour, GameConstants.DEED_CEREMONY.x, GameConstants.DEED_CEREMONY.y)
	_houses.plan_deed(p, Deeds.make("crowning", _seat_door(k), GameConstants.PERSON_ARRIVE, w.x, w.y,
			GameConstants.DEED_CEREMONY_SEC, {kingdom_id = k.id}))


## A crowning on its way: called off when the founder is back (and still rules), replanned when the
## deed was lost, given up when the chosen one is gone.
func _pending(k: Dictionary, inside: bool) -> void:
	var id := int(k.get("pending_ruler", -1))
	if id < 0:
		return
	var p := _state.person(id)
	if p.is_empty() or p.status != "resident":
		k.pending_ruler = -1
		if int(k.ruler_id) == GameConstants.GOV_NOBODY:
			_name_ruler(k, GovRules.choose_regent(_state, k, id), false)
		return
	if inside and int(k.ruler_id) == GameConstants.GOV_PLAYER:
		k.pending_ruler = -1
		if (p.get("deed", {}) as Dictionary).get("kind", "") == "crowning":
			p.deed = {}
		return
	if (p.get("deed", {}) as Dictionary).get("kind", "") != "crowning":
		_plan_crowning(k)


func _crowned(k: Dictionary, p: Dictionary) -> void:
	if int(k.get("pending_ruler", -1)) != p.id:
		return
	var f := _state.family(int(p.get("family_id", -1)))
	k.ruler_id = p.id
	k.ruler_family = int(p.get("family_id", -1))
	k.ruler_way = GovRules.ruler_way(p)
	k.ruler_corrupt = GovRules.is_corrupt(p, f)
	k.ruler_since = _hour
	k.decrees = GovRules.npc_decrees(String(k.ruler_way), bool(k.ruler_corrupt), k.decrees)
	k.pending_ruler = -1
	k.refused = false
	if k.get("pending_heir", false):
		_log(k, GameConstants.GOV_MSG_HEIR % [PersonGen.full_name(p), k.name])
	else:
		_log(k, GameConstants.GOV_MSG_CROWNED % [PersonGen.full_name(p), k.name, GameConstants.GOV_WAY_NAMES[k.ruler_way]])


func _set_player(k: Dictionary) -> void:
	var pending := _state.person(int(k.get("pending_ruler", -1)))
	if (pending.get("deed", {}) as Dictionary).get("kind", "") == "crowning":
		pending.deed = {}
	k.ruler_id = GameConstants.GOV_PLAYER
	k.ruler_way = ""
	k.ruler_corrupt = false
	k.pending_ruler = -1


# --- The founder's return ---------------------------------------------------------------------

func _return(k: Dictionary) -> void:
	var ruler := _state.person(int(k.ruler_id))
	if ruler.is_empty():
		return
	if not GovRules.gives_back(String(k.ruler_way), GovRules.mean_opinion(_state, k)):
		if not k.get("refused", false):
			k.refused = true
			_log(k, GameConstants.GOV_MSG_REFUSED % [PersonGen.full_name(ruler), k.name])
		return
	if (ruler.get("deed", {}) as Dictionary).get("kind", "") == "handover" or not _free(ruler):
		return
	var w := Deeds.next_window(_hour, GameConstants.DEED_DAY.x, GameConstants.DEED_DAY.y)
	_houses.plan_deed(ruler, Deeds.make("handover", _seat_door(k), GameConstants.PERSON_ARRIVE, w.x, w.y,
			GameConstants.DEED_CEREMONY_SEC, {kingdom_id = k.id}))


# --- Decrees carried out ----------------------------------------------------------------------

## Each House that owes tax sends a free adult with it to the seat (the ruler's House pays nothing).
func _taxes(k: Dictionary) -> void:
	var rate: float = GameConstants.GOV_TAX_RATE.get(String(k.decrees.tax), 0.0)
	if rate <= 0.0:
		return
	var today := floori(_hour / 24.0)
	for f in _state.families_of(k.id):
		if f.id == int(k.ruler_family) and int(k.ruler_id) >= 0:
			continue # the ruler's own House pays nothing
		if float(f.wealth) < GameConstants.GOV_TAX_FLOOR or int(f.get("tax_day", -1)) >= today:
			continue
		var bearer := _free_adult_of(f)
		if bearer.is_empty():
			continue
		var w := Deeds.next_window(_hour, GameConstants.DEED_DAY.x, GameConstants.DEED_DAY.y)
		_houses.plan_deed(bearer, Deeds.make("tax", _seat_door(k), GameConstants.PERSON_ARRIVE * GameConstants.GOV_REACH_MULT,
				w.x, w.y,
				GameConstants.DEED_WORK_SEC, {family_id = f.id, kingdom_id = k.id}))


func _taxed(k: Dictionary, f: Dictionary) -> void:
	f.tax_day = floori(_hour / 24.0) # paid: a lost errand is tried again tomorrow
	var rate: float = GameConstants.GOV_TAX_RATE.get(String(k.decrees.tax), 0.0)
	var n := floori(float(f.wealth) * rate / GameConstants.SKIM_VALUE)
	if n <= 0:
		return
	var res := _least(k)
	f.wealth = float(f.wealth) - n * GameConstants.SKIM_VALUE
	_state.add_stock(k, res, n)
	_log(k, GameConstants.GOV_MSG_TAX % [f.surname, n, SocietySim._res_name(res)])


## The guard grows by muster (the chosen walks to the seat) or shrinks by dismissal.
func _guard(k: Dictionary) -> void:
	var target := int(k.decrees.guards)
	if target < 0:
		return
	var guards := _state.residents(k.id).filter(func(p: Dictionary) -> bool:
		return int(p.profession) == P.GUARD and SocietyRules.is_adult(p))
	var coming := _state.residents(k.id).filter(func(p: Dictionary) -> bool:
		return (p.get("deed", {}) as Dictionary).get("kind", "") == "muster").size()
	if guards.size() + coming < target:
		var id := GovRules.muster_candidate(_state, k)
		var p := _state.person(id)
		if not p.is_empty():
			var w := Deeds.next_window(_hour, GameConstants.DEED_DAY.x, GameConstants.DEED_DAY.y)
			_houses.plan_deed(p, Deeds.make("muster", _seat_door(k), GameConstants.PERSON_ARRIVE, w.x, w.y,
					GameConstants.DEED_WORK_SEC, {kingdom_id = k.id}))
	elif guards.size() > target:
		guards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.age) < float(b.age) or (float(a.age) == float(b.age) and a.id > b.id))
		var g: Dictionary = guards[0]
		g.profession = GovRules.civil_profession(g, _state.family(int(g.get("family_id", -1))))
		_log(k, GameConstants.GOV_MSG_DISMISS % PersonGen.full_name(g))


# --- The NPC ruler ----------------------------------------------------------------------------

## A corrupt ruler goes to the storage some nights and takes from the stock for the own House.
func _ruler_nights(k: Dictionary) -> void:
	if int(k.ruler_id) < 0 or not k.ruler_corrupt:
		return
	var ruler := _state.person(int(k.ruler_id))
	var f := _state.family(int(ruler.get("family_id", -1)))
	if ruler.is_empty() or f.is_empty() or not _free(ruler):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_state.seed, "gov_skim", k.id, floori(_hour / 24.0)])
	if rng.randf() < GameConstants.GOV_SKIM_PER_DAY:
		_houses._night_deed(ruler, "skim", _houses._storage_door(k), {family_id = f.id, by_ruler = true, quiet = [f.id]})


## Under a cult ruler the devout pray to the founder at the flag at dusk.
func _worship(k: Dictionary) -> void:
	if int(k.ruler_id) < 0 or String(k.ruler_way) != "culto":
		return
	var today := floori(_hour / 24.0)
	for p in _state.residents(k.id):
		if not SocietyRules.is_adult(p) or not PersonGen.has_trait(p, GameConstants.Trait.DEVOUT) \
				or int(p.get("worship_day", -1)) >= today or not _free(p):
			continue
		var w := Deeds.next_window(_hour, GameConstants.DEED_DUSK.x, GameConstants.DEED_DUSK.y)
		_houses.plan_deed(p, Deeds.make("worship", _flag_spot(k), GameConstants.PERSON_ARRIVE * GameConstants.GOV_REACH_MULT,
				w.x, w.y,
				GameConstants.DEED_WORK_SEC, {kingdom_id = k.id}))


## The heads who hate the ruler meet at night near the seat; their leader carries it out.
func _deposition(k: Dictionary) -> void:
	if not GovRules.wants_deposition(_state, k, _hour):
		return
	if _state.residents(k.id).any(func(p: Dictionary) -> bool:
			return (p.get("deed", {}) as Dictionary).get("kind", "") == "depose"):
		return
	var ruler_id := int(k.ruler_id)
	var leader := {}
	var worst := INF
	for f in _state.families_of(k.id):
		var head := _state.person(int(f.head_id))
		if head.is_empty() or head.id == ruler_id or f.id == int(k.ruler_family) or not _free(head):
			continue
		var rel := _state.relation(head.id, ruler_id)
		if rel < worst:
			worst = rel
			leader = head
	if not leader.is_empty():
		_houses._night_deed(leader, "depose", _seat_door(k) + GameConstants.GOV_PLOT_OFFSET, {kingdom_id = k.id,
				ruler_id = ruler_id, quiet = [int(leader.get("family_id", -1))]})


func _deposed(k: Dictionary, leader: Dictionary, seen: Array) -> void:
	var ruler := _state.person(int(k.ruler_id))
	if int(k.ruler_id) < 0 or ruler.is_empty():
		return
	if not seen.is_empty(): # the plot was seen: the ruler knows, the plotters are shamed
		var f := _state.family(int(leader.get("family_id", -1)))
		if not f.is_empty():
			f.dishonor = float(f.get("dishonor", 0.0)) + GameConstants.SCANDAL_DISHONOR
		_state.add_relation(leader.id, ruler.id, GameConstants.FEUD_RELATION_HIT)
		_log(k, GameConstants.GOV_MSG_PLOT_SEEN % [_houses._witness_name(seen), PersonGen.full_name(leader)])
		return
	_log(k, GameConstants.GOV_MSG_DEPOSED % PersonGen.full_name(ruler))
	var old: int = ruler.id
	if _is_player_in.call(k) and GovRules.mean_opinion(_state, k) >= 0.0:
		_set_player(k)
		return
	k.ruler_id = GameConstants.GOV_NOBODY
	_name_ruler(k, GovRules.choose_regent(_state, k, old), false)


# --- Deeds ----------------------------------------------------------------------------------

## HouseSim hands over the deeds it does not know. Returns whether the kind was a government one.
func complete_deed(k: Dictionary, p: Dictionary, deed: Dictionary, seen: Array, hour: float) -> bool:
	_hour = hour
	var data: Dictionary = deed.data
	match String(deed.kind):
		"crowning":
			_crowned(k, p)
		"handover":
			if int(k.ruler_id) == p.id and _is_player_in.call(k): # the founder is there to take it
				_set_player(k)
				_log(k, GameConstants.GOV_MSG_HANDOVER % [PersonGen.full_name(p), k.name])
		"tax":
			var f := _state.family(int(data.get("family_id", -1)))
			if not f.is_empty():
				_taxed(k, f)
		"muster":
			if p.status == "resident" and SocietyRules.is_adult(p):
				p.profession = P.GUARD
				_log(k, GameConstants.GOV_MSG_MUSTER % PersonGen.full_name(p))
		"worship":
			p.worship_day = floori(_hour / 24.0)
			p.opinion = clampf(float(p.opinion) + GameConstants.GOV_WORSHIP_OPINION, -1.0, 1.0)
			_log(k, GameConstants.GOV_MSG_WORSHIP % PersonGen.full_name(p))
		"depose":
			if int(data.get("ruler_id", k.ruler_id)) == int(k.ruler_id): # the plot was against this ruler
				_deposed(k, p, seen)
		_:
			return false
	return true


## The ruler's skim came out of the stock: it is counted for the ADM.
func ruler_skimmed(k: Dictionary, p: Dictionary, amount: int, res: int, hour: float) -> void:
	k.ruler_skimmed = int(k.ruler_skimmed) + amount
	_state.chronicle_add(hour, GameConstants.GOV_MSG_RULER_SKIM % [PersonGen.full_name(p), amount, SocietySim._res_name(res)],
			k.id, false)


# --- Helpers --------------------------------------------------------------------------------

func _free(p: Dictionary) -> bool:
	return p.status == "resident" and (p.get("deed", {}) as Dictionary).is_empty()


## The head when free, else the oldest free adult of the House.
func _free_adult_of(f: Dictionary) -> Dictionary:
	var head := _state.person(int(f.head_id))
	if not head.is_empty() and _free(head) and SocietyRules.is_adult(head):
		return head
	var best := {}
	for p in _state.family_members(f.id):
		if _free(p) and SocietyRules.is_adult(p) and (best.is_empty() or float(p.age) > float(best.age)):
			best = p
	return best


## The kingdom's scarcest of wood, stone and food (what a tax in kind brings).
func _least(k: Dictionary) -> int:
	var best := R.WOOD
	for res in [R.WOOD, R.STONE, R.FOOD]:
		if _state.stock_of(k, res) < _state.stock_of(k, best):
			best = res
	return best


func _seat_door(k: Dictionary) -> Vector3:
	var seat := _state.building(int(k.get("seat_id", -1)))
	return PeopleManager.door_of(seat) if not seat.is_empty() else k.center


## In front of the founder's flag (the seat's door when there is none).
func _flag_spot(k: Dictionary) -> Vector3:
	for b in VillageRules.kingdom_buildings(_state, k):
		if b.type == GameConstants.Building.FLAG:
			return b.pos + GameConstants.GOV_FLAG_OFFSET
	return _seat_door(k)


func _log(k: Dictionary, text: String) -> void:
	_state.chronicle_add(_hour, text, k.id)
