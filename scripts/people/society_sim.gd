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
			_move_with_children(a, b.home_id)
		elif int(a.home_id) >= 0 and room(_state, _state.building(a.home_id)) > 0:
			_move_with_children(b, a.home_id)
		else:
			for h in VillageRules.kingdom_buildings(_state, k):
				if h.type == B.HOUSE and not h.get("site", false) and room(_state, h) >= 2:
					_move_with_children(a, h.id)
					_move_with_children(b, h.id)
					break


## Moves `p` and, while there is room, p's minor children who lived with p.
func _move_with_children(p: Dictionary, home_id: int) -> void:
	var old: int = p.home_id
	_move_home(p, home_id)
	if old < 0:
		return
	for c in _state.all_people():
		if c.home_id == old and c.status == "resident" and not SocietyRules.is_adult(c) \
				and (c.parents as Array).has(p.id) and room(_state, _state.building(home_id)) > 0:
			_move_home(c, home_id)


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
	var total := HouseRules.beds(b)
	return total - occupants(state, b.id) if total > 0 else 0


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

## Everyone ages each hour (children much faster); a child of ADULT_AGE takes the trade the kingdom
## needs most; the old may die.
func _age(k: Dictionary, rng: RandomNumberGenerator) -> void:
	for p in _people(k):
		var was_child := not SocietyRules.is_adult(p)
		var rate := GameConstants.CHILD_YEARS_PER_DAY if was_child else GameConstants.ADULT_YEARS_PER_DAY
		p.age = float(p.age) + rate / 24.0
		if was_child and SocietyRules.is_adult(p):
			var grown := HouseRules.grown_profession(p, _state.family(int(p.family_id)), VillageRules.needed_profession(_snapshot.call(k)))
			p.profession = grown.profession
			p.conflict = grown.conflict
			_say.call(k, GameConstants.SOCIETY_MSG_GREW % [PersonGen.full_name(p), PersonGen.profession_name(p)])
		elif float(p.age) >= GameConstants.OLD_AGE \
				and rng.randf() < SocietyRules.hourly_chance(GameConstants.DEATH_CHANCE_PER_DAY):
			_die(k, p)


## `p` dies of something else than age (a battle): homes pass on, the node goes, `text` is told.
func kill(k: Dictionary, p: Dictionary, text := "") -> void:
	transfer_houses(_state, p.id, [p.id])
	if text != "":
		_say.call(k, text)
	person_died.emit(p)
	_state.remove_person(p.id)
	_changed = true
	families_changed.emit()


func _die(k: Dictionary, p: Dictionary) -> void:
	transfer_houses(_state, p.id, [p.id])
	_say.call(k, GameConstants.SOCIETY_MSG_DIED % [PersonGen.full_name(p), floori(float(p.age))])
	person_died.emit(p)
	_state.remove_person(p.id)
	_changed = true


## A happy couple living together with food and a free bed may have a child.
func _births(k: Dictionary, rng: RandomNumberGenerator) -> void:
	var people := _people(k)
	if people.size() >= GameConstants.KINGDOM_BIRTH_CAP:
		return
	var snap := VillageRules.snapshot(_state, k, _hour)
	if snap.food_days < GameConstants.BIRTH_FOOD_DAYS:
		return
	var chance := SocietyRules.hourly_chance(GameConstants.BIRTH_CHANCE_PER_DAY)
	for a in people:
		var b := _state.person(a.spouse_id)
		if b.is_empty() or b.status != "resident" or a.id > b.id:
			continue
		var mother := SocietyRules.birth_mother(a, b)
		if mother.is_empty() or int(a.home_id) < 0 or a.home_id != b.home_id:
			continue
		if room(_state, _state.building(a.home_id)) <= 0:
			continue
		if minf(float(a.contentment), float(b.contentment)) < GameConstants.BIRTH_CONTENTMENT:
			continue
		if _hour - float(mother.last_birth_hour) < GameConstants.BIRTH_GAP_HOURS or rng.randf() >= chance:
			continue
		_bear(k, mother, b if mother == a else a, rng)
		if _state.residents(k.id).size() >= GameConstants.KINGDOM_BIRTH_CAP:
			return


func _bear(k: Dictionary, mother: Dictionary, father: Dictionary, rng: RandomNumberGenerator) -> void:
	var fam := _state.family(mother.family_id)
	if fam.is_empty():
		fam = _state.family(father.family_id)
	var surname: String = fam.surname if not fam.is_empty() else mother.surname
	var siblings := _state.all_people().filter(func(p: Dictionary) -> bool: return (p.parents as Array).has(mother.id)).map(
			func(p: Dictionary) -> String: return p.name)
	var kid := _state.add_person(PersonGen.child(mother, father, surname, rng, siblings), mother.pos, k.id, _hour)
	kid.status = "resident"
	kid.home_id = mother.home_id
	kid.inside = mother.home_id if mother.inside == mother.home_id else -1
	kid.family_id = fam.get("id", -1)
	kid.parents = [mother.id, father.id]
	for parent in [mother, father]:
		_state.set_relation(kid.id, parent.id, GameConstants.SPOUSE_START_RELATION)
	mother.last_birth_hour = _hour
	var word: String = GameConstants.CHILD_WORDS[1 if kid.female else 0]
	_say.call(k, GameConstants.SOCIETY_MSG_BORN % [kid.name, word, PersonGen.full_name(mother), PersonGen.full_name(father)])
	person_born.emit(kid)
	_changed = true


## A member who is the head's bitter rival breaks away; a big family lets a household with its
## own house branch off in peace. At most one split per family per cooldown.
func _splits(k: Dictionary, rng: RandomNumberGenerator) -> void:
	var cooldown := GameConstants.FAMILY_SPLIT_COOLDOWN_DAYS * 24.0
	var branch_chance := SocietyRules.hourly_chance(GameConstants.BRANCH_CHANCE_PER_DAY)
	for f in _state.families_of(k.id):
		if _hour - float(f.last_split_hour) < cooldown:
			continue
		var head := _state.person(f.head_id)
		if head.is_empty():
			continue
		var members := _state.family_members(f.id)
		members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
		for m in members:
			if m.id == head.id or m.id == head.spouse_id or not SocietyRules.is_adult(m):
				continue
			if _state.relation(m.id, head.id) <= GameConstants.SPLIT_RIVAL_AT:
				_split(k, f, m, "rival", rng)
				break
			var spouse := _state.person(m.spouse_id)
			if members.size() > GameConstants.FAMILY_BRANCH_SIZE and not spouse.is_empty() \
					and spouse.family_id == f.id and int(m.home_id) >= 0 and m.home_id != head.home_id \
					and rng.randf() < branch_chance:
				_split(k, f, m, "branch", rng)
				break


func _split(k: Dictionary, f: Dictionary, leader: Dictionary, kind: String, rng: RandomNumberGenerator) -> void:
	var group: Array[Dictionary] = [leader]
	var spouse := _state.person(leader.spouse_id)
	if not spouse.is_empty() and spouse.family_id == f.id and spouse.status == "resident":
		group.append(spouse)
	var kids: Array[Dictionary] = []
	for c in _state.family_members(f.id):
		if not SocietyRules.is_adult(c) and group.any(func(g: Dictionary) -> bool: return (c.parents as Array).has(g.id)):
			kids.append(c)
	group.append_array(kids)
	var old_name := PersonGen.full_name(leader)
	var surname := _new_surname(k, leader, rng)
	var crest := Crest.rival(f.crest, rng, _crests(k)) if kind == "rival" else Crest.derive(f.crest, rng, _crests(k))
	var nf := _state.add_family(surname, crest, k.id, leader.id, _hour, f.id, kind)
	var ids := group.map(func(g: Dictionary) -> int: return g.id)
	for g in group:
		g.family_id = nf.id
	leader.surname = surname
	for c in kids:
		c.surname = surname
	for o in _state.family_members(f.id):
		if not ids.has(o.id):
			var d := GameConstants.SPLIT_RELATION_HIT if kind == "rival" else GameConstants.BRANCH_RELATION_GAIN
			_state.add_relation(leader.id, o.id, d)
	f.last_split_hour = _hour
	var text := GameConstants.SOCIETY_MSG_BROKE if kind == "rival" else GameConstants.SOCIETY_MSG_BRANCH
	_say.call(k, text % [old_name, f.surname, surname])
	_changed = true


## A surname no family or resident of the kingdom uses ("Seixas de Martim" when none is left).
func _new_surname(k: Dictionary, leader: Dictionary, rng: RandomNumberGenerator) -> String:
	var used := {}
	for f in _state.families_of(k.id):
		used[f.surname] = true
	for p in _state.residents(k.id):
		used[p.surname] = true
	var free: Array = GameConstants.SURNAMES.filter(func(s: String) -> bool: return not used.has(s))
	if free.is_empty():
		return "%s de %s" % [leader.surname, leader.name]
	return free[rng.randi() % free.size()]


## Contentment, the family and friends/rivals move each opinion of the player; every delta is
## computed from the opinions at the start of the hour, then applied.
func _opinions(k: Dictionary) -> void:
	var people := _people(k)
	var means := {}
	for f in _state.families_of(k.id):
		means[f.id] = SocietyRules.adult_mean(_state.family_members(f.id))
	var deltas: Array[float] = []
	for p in people:
		var mean: Variant = means.get(p.family_id)
		var ties := []
		var rels := _state.relations_of(p.id)
		for other_id in rels:
			var o := _state.person(other_id)
			if not o.is_empty() and o.status == "resident" and o.kingdom_id == k.id:
				ties.append([rels[other_id], float(o.opinion)])
		deltas.append(SocietyRules.opinion_drift(p, float(p.opinion) if mean == null else mean, ties))
	for i in people.size():
		people[i].opinion = clampf(float(people[i].opinion) + deltas[i], -1.0, 1.0)


## Adults and families become allies or enemies of the player (announced once, on entering).
func _stances(k: Dictionary) -> void:
	for p in _people(k):
		var now := SocietyRules.stance_for(float(p.opinion), p.stance) if SocietyRules.is_adult(p) else ""
		if now != p.stance and now != "":
			var forms: Array = GameConstants.SOCIETY_MSG_ALLY if now == "ally" else GameConstants.SOCIETY_MSG_ENEMY
			_say.call(k, forms[1 if p.female else 0] % PersonGen.full_name(p))
		p.stance = now
	for f in _state.families_of(k.id):
		var now := SocietyRules.family_stance(_state.family_members(f.id), f.stance)
		if now != f.stance and now != "":
			var text := GameConstants.SOCIETY_MSG_FAMILY_ALLY if now == "ally" else GameConstants.SOCIETY_MSG_FAMILY_ENEMY
			_say.call(k, text % f.surname)
		if now != f.stance:
			_changed = true
		f.stance = now


## Once a day from DEED_HOUR, with the player in the kingdom: ally families give a gift from the
## stock, the worst enemies steal from the player.
func _deeds(k: Dictionary) -> void:
	if fmod(_hour, 24.0) < GameConstants.DEED_HOUR or not _is_player_in.call(k) \
			or String(k.get("founder", "player")) != "player": # only the founder's own people
		return
	var today := floori(_hour / 24.0)
	for f in _state.families_of(k.id):
		if f.stance != "ally" or int(f.deed_day) >= today:
			continue
		f.deed_day = today
		var res := _most(GameConstants.GIFT_RES, func(r: int) -> int: return _state.stock_of(k, r))
		if _state.stock_of(k, res) < GameConstants.GIFT_MIN_STOCK:
			continue
		_state.add_stock(k, res, -GameConstants.GIFT_AMOUNT)
		_state.add_resource(res, GameConstants.GIFT_AMOUNT)
		_say.call(k, GameConstants.SOCIETY_MSG_GIFT % [f.surname, GameConstants.GIFT_AMOUNT, _res_name(res)])
	var enemies := _people(k).filter(func(p: Dictionary) -> bool:
		return p.stance == "enemy" and int(p.deed_day) < today)
	enemies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.opinion) < float(b.opinion))
	for i in enemies.size():
		var p: Dictionary = enemies[i]
		p.deed_day = today
		if i >= GameConstants.THEFT_MAX_PER_DAY:
			continue
		var res := _most(GameConstants.THEFT_RES, func(r: int) -> int: return _state.get_resource(r))
		var n := mini(GameConstants.THEFT_AMOUNT, _state.get_resource(res))
		if n <= 0 or not _state.spend({res: n}):
			continue
		_state.add_stock(k, res, n)
		_say.call(k, GameConstants.SOCIETY_MSG_THEFT % [PersonGen.full_name(p), n, _res_name(res)])


## The resource of `options` with the largest amount (ties: the first).
static func _most(options: Array, amount: Callable) -> int:
	var best: int = options[0]
	for r: int in options:
		if amount.call(r) > amount.call(best):
			best = r
	return best


static func _res_name(res: int) -> String:
	return (GameConstants.RES_NAMES[res] as String).to_lower()
