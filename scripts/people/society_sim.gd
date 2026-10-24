class_name SocietySim
extends RefCounted
## The hourly social life of one kingdom, run by VillageSim for every kingdom (records only, no
## nodes): newcomers found or join families, people meet and become friends or rivals, couples marry
## and move in together, children are born and grow up, the old die, members break away to found
## their own house, empty families dissolve, and opinions of the player drift into allies and
## enemies who give gifts or steal. Randomness is seeded by (world seed, kingdom, hour).

signal families_changed
signal person_born(rec: Dictionary)
## Emitted before the record is removed (its node, if any, must go).
signal person_died(rec: Dictionary)

const B := GameConstants.Building

var _state: WorldState
var _say: Callable # (k: Dictionary, text: String)
var _is_player_in: Callable # (k: Dictionary) -> bool
var _snapshot: Callable # (k: Dictionary) -> Dictionary (VillageSim.snapshot)
var _hour := 0.0
var _changed := false


func setup(state: WorldState, say: Callable, is_player_in: Callable, snapshot: Callable) -> void:
	_state = state
	_say = say
	_is_player_in = is_player_in
	_snapshot = snapshot


## One simulated hour of kingdom `k`; `hour` = total game hours of that hour.
func tick_hour(k: Dictionary, hour: float) -> void:
	_hour = hour
	_changed = false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_state.seed, "society", k.id, int(hour)])
	_ensure_families(k)
	_age(k, rng)
	_meetings(k, rng)
	_marriages(k)
	_reunite(k)
	_births(k, rng)
	_splits(k, rng)
	_cleanup_families(k)
	_opinions(k)
	_stances(k)
	_deeds(k)
	if _changed:
		families_changed.emit()


## Residents sorted by id (stable order for seeded draws).
func _people(k: Dictionary) -> Array[Dictionary]:
	var out := _state.residents(k.id)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	return out


# --- Families -------------------------------------------------------------------------------

## Residents without a family join kin (same surname) or found their own house.
func _ensure_families(k: Dictionary) -> void:
	for p in _people(k):
		if int(p.family_id) >= 0 and not _state.family(p.family_id).is_empty():
			continue
		var kin := {}
		for f in _state.families_of(k.id):
			if f.surname == p.surname:
				kin = f
				break
		if not kin.is_empty():
			for m in _state.family_members(kin.id):
				_state.add_relation(p.id, m.id, GameConstants.KIN_START_RELATION)
			p.family_id = kin.id
			_say.call(k, GameConstants.SOCIETY_MSG_KIN % [PersonGen.full_name(p), kin.surname])
		else:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([_state.seed, "crest", p.id])
			var f := _state.add_family(p.surname, Crest.generate(rng, _crests(k)), k.id, p.id, _hour)
			p.family_id = f.id
		_changed = true


func _crests(k: Dictionary) -> Array:
	return _state.families_of(k.id).map(func(f: Dictionary) -> Dictionary: return f.crest)


## Empty families dissolve; a family whose head is gone gets the oldest adult (or oldest child).
func _cleanup_families(k: Dictionary) -> void:
	for f in _state.families_of(k.id):
		var members := _state.family_members(f.id)
		if members.is_empty():
			_state.remove_family(f.id)
			_say.call(k, GameConstants.SOCIETY_MSG_DISSOLVED % f.surname)
			_changed = true
			continue
		if members.any(func(m: Dictionary) -> bool: return m.id == f.head_id):
			continue
		members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var aa := SocietyRules.is_adult(a)
			if aa != SocietyRules.is_adult(b):
				return aa
			return float(a.age) > float(b.age))
		f.head_id = members[0].id
		_changed = true


# --- Meetings and couples -------------------------------------------------------------------

## A few pairs meet each hour; half of them between people who live or work together. Children
## only meet their own family.
func _meetings(k: Dictionary, rng: RandomNumberGenerator) -> void:
	var people := _people(k)
	if people.size() < 2:
		return
	for i in GameConstants.SOCIAL_PAIRS_PER_HOUR:
		var a: Dictionary = people[rng.randi() % people.size()]
		var pool: Array[Dictionary] = []
		for b in people:
			if b.id != a.id and (i % 2 == 1 or _close(a, b) or a.profession == b.profession):
				pool.append(b)
		if pool.is_empty():
			continue
		var b: Dictionary = pool[rng.randi() % pool.size()]
		var close := _close(a, b)
		if not close and (not SocietyRules.is_adult(a) or not SocietyRules.is_adult(b)):
			continue
		_state.add_relation(a.id, b.id, SocietyRules.meeting_delta(a, b, close, rng))


static func _close(a: Dictionary, b: Dictionary) -> bool:
	return (int(a.home_id) >= 0 and a.home_id == b.home_id) or (int(a.family_id) >= 0 and a.family_id == b.family_id)


## Unmarried adults marry the one they love most (if the love is mutual enough).
func _marriages(k: Dictionary) -> void:
	var people := _people(k)
	for a in people:
		if int(a.spouse_id) >= 0:
			continue
		var best := {}
		var best_rel := -INF
		for b in people:
			var rel := _state.relation(a.id, b.id)
			if rel > best_rel and SocietyRules.can_marry(a, b, rel):
				best = b
				best_rel = rel
		if not best.is_empty():
			_marry(k, a, best)


func _marry(k: Dictionary, a: Dictionary, b: Dictionary) -> void:
	a.spouse_id = b.id
	b.spouse_id = a.id
	a.widowed = false
	b.widowed = false
	_say.call(k, GameConstants.SOCIETY_MSG_MARRIED % [PersonGen.full_name(a), PersonGen.full_name(b)])
	_changed = true
	if a.family_id == b.family_id:
		return
	var fa := _state.family(a.family_id)
	var fb := _state.family(b.family_id)
	if fa.is_empty() or fb.is_empty():
		return
	var na := _state.family_members(fa.id).size()
	var nb := _state.family_members(fb.id).size()
	var target := fa if na > nb or (na == nb and fa.id < fb.id) else fb
	var mover := b if target == fa else a
	var old := _state.family(mover.family_id)
	_move_to_family(mover, target)
	# Minor children follow a parent who remarries when their other parent is gone.
	for c in _people(k):
		if c.family_id == old.id and not SocietyRules.is_adult(c) and (c.parents as Array).has(mover.id):
			var other_alive := (c.parents as Array).any(func(id: int) -> bool:
				return id != mover.id and _state.person(id).get("status", "") == "resident")
			if not other_alive:
				_move_to_family(c, target)
	if _state.family_members(old.id).is_empty():
		_state.remove_family(old.id)
		_say.call(k, GameConstants.SOCIETY_MSG_MERGED % [old.surname, target.surname])


func _move_to_family(p: Dictionary, f: Dictionary) -> void:
	p.family_id = f.id
	_changed = true


## Married couples living apart move into a home of one of them with room, or both into a house
## with two free beds.
func _reunite(k: Dictionary) -> void:
	for a in _people(k):
		var b := _state.person(a.spouse_id)
		if b.is_empty() or b.status != "resident" or a.id > b.id:
			continue
		if int(a.home_id) >= 0 and a.home_id == b.home_id:
			continue
		if int(b.home_id) >= 0 and room(_state, _state.building(b.home_id)) > 0:
			_move_home(a, b.home_id)
		elif int(a.home_id) >= 0 and room(_state, _state.building(a.home_id)) > 0:
			_move_home(b, a.home_id)
		else:
			for h in VillageRules.kingdom_buildings(_state, k):
				if h.type == B.HOUSE and not h.get("site", false) and room(_state, h) >= 2:
					_move_home(a, h.id)
					_move_home(b, h.id)
					break


func _move_home(p: Dictionary, home_id: int) -> void:
	if p.home_id == home_id:
		return
	p.home_id = home_id
	if int(p.inside) >= 0:
		p.inside = -1
	var h := _state.building(home_id)
	if h.type == B.HOUSE and int(h.get("owner", -1)) < 0 and SocietyRules.is_adult(p):
		h.owner = p.id
	_changed = true


## Free beds of a home (0 for anything that is not a finished home).
static func room(state: WorldState, b: Dictionary) -> int:
	if b.is_empty() or b.get("site", false) or not GameConstants.HOUSE_CAPACITY.has(b.type):
		return 0
	return GameConstants.HOUSE_CAPACITY[b.type] - occupants(state, b.id)


static func occupants(state: WorldState, id: int) -> int:
	var n := 0
	for p in state.all_people():
		if p.home_id == id:
			n += 1
	return n


## Houses owned by `person_id` pass to the oldest adult living there who is not in `leaving`
## (ids), else to the kingdom (and lose their banner).
static func transfer_houses(state: WorldState, person_id: int, leaving: Array) -> void:
	for b in state.all_buildings():
		if b.get("owner", GameConstants.OWNER_PLAYER) != person_id:
			continue
		var heir := {}
		for p in state.all_people():
			if p.home_id == b.id and p.status == "resident" and not leaving.has(p.id) and SocietyRules.is_adult(p):
				if heir.is_empty() or float(p.age) > float(heir.age):
					heir = p
		b.owner = heir.id if not heir.is_empty() else GameConstants.OWNER_KINGDOM


# --- Life (Task 5) and opinion (Task 6) -----------------------------------------------------

func _age(_k: Dictionary, _rng: RandomNumberGenerator) -> void:
	pass


func _births(_k: Dictionary, _rng: RandomNumberGenerator) -> void:
	pass


func _splits(_k: Dictionary, _rng: RandomNumberGenerator) -> void:
	pass


func _opinions(_k: Dictionary) -> void:
	pass


func _stances(_k: Dictionary) -> void:
	pass


func _deeds(_k: Dictionary) -> void:
	pass
