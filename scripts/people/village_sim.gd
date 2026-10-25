class_name VillageSim
extends Node
## Hourly simulation of every kingdom's people, loaded or not: travelers coming and deciding,
## meals, contentment and leaving, homes, the player's fame, planning sites and, for people that
## have no node this hour, a summary of their work (real props are removed, sites progress).
## People with a node work for real through PeopleManager. Every kingdom event goes to the ADM
## chronicle (never to the player's HUD); `message` repeats it for listeners.

signal message(text: String)
signal site_opened(rec: Dictionary)
signal site_finished(rec: Dictionary)
signal site_abandoned(rec: Dictionary)
signal person_left(rec: Dictionary)
signal traveler_spawned(rec: Dictionary)
signal person_decided(rec: Dictionary, stayed: bool, reason: String)
signal prop_removed(c: Vector2i, id: int)
signal person_born(rec: Dictionary)
## Before the record is removed: its node must go.
signal person_died(rec: Dictionary)
## Families, homes or house owners changed (banners may need a new crest).
signal families_changed
## A building burned in a battle between kingdoms (its node must go).
signal building_burned(rec: Dictionary)

const B := GameConstants.Building
const R := GameConstants.Res

## person id -> whether the person has a node right now (set by PeopleManager).
var has_node: Callable = func(_id: int) -> bool: return false
## kingdom -> whether its area is loaded (messages go straight to the HUD).
var is_kingdom_loaded: Callable = func(_k: Dictionary) -> bool: return false
## kingdom -> whether the player is inside it (opinions drift toward neutral while away).
var is_player_in: Callable = func(_k: Dictionary) -> bool: return false
## The player's position (or null): a new site never covers it.
var player_pos: Callable = func() -> Variant: return null
## Own clock when there is no DayNight (tests), in total hours.
var clock_hours := 0.0

var _state: WorldState
var _gen: TerrainGenerator
var _scatter: PropScatter
var _day_night: DayNight
var _rng := RandomNumberGenerator.new()
var _last_hour := -1.0
var _props_near: Dictionary = {} # Vector3 center -> props around it (the scatter is deterministic)
## Families, couples, children and opinions (one tick per kingdom per hour).
var society := SocietySim.new()
var houses := HouseSim.new()
## Who rules, decrees carried out, succession (stage 8).
var gov := GovSim.new()
## Relations, envoys, wars and new kingdoms between kingdoms (stage 9).
var realms := RealmSim.new()


func setup(state: WorldState, gen: TerrainGenerator, scatter: PropScatter, day_night: DayNight) -> void:
	_state = state
	_gen = gen
	_scatter = scatter
	_day_night = day_night
	_rng.seed = hash([state.seed, "village"])
	society.setup(state, _say, func(k: Dictionary) -> bool: return is_player_in.call(k), snapshot)
	society.person_born.connect(func(r: Dictionary) -> void: person_born.emit(r))
	society.person_died.connect(func(r: Dictionary) -> void: person_died.emit(r))
	society.families_changed.connect(func() -> void: families_changed.emit())
	houses.setup(state, _say, society, gen)
	houses.has_node = func(id: int) -> bool: return has_node.call(id)
	gov.setup(state, houses, func(k: Dictionary) -> bool: return is_player_in.call(k))
	realms.setup(state, houses, society, gov)
	realms.set_terrain(gen, scatter)
	realms.building_burned.connect(func(r: Dictionary) -> void: building_burned.emit(r))


func _process(_delta: float) -> void:
	if _day_night == null:
		return
	var h := floorf(_day_night.total_hours())
	if _last_hour < 0.0:
		_last_hour = h
	elif h > _last_hour:
		tick_hours(h - _last_hour)
		_last_hour = h


func now_hours() -> float:
	return _day_night.total_hours() if _day_night else clock_hours


func hour_of_day() -> float:
	return fmod(now_hours(), 24.0)


func is_work_time() -> bool:
	var h := hour_of_day()
	return h >= GameConstants.WORK_START_HOUR and h < GameConstants.WORK_END_HOUR


func is_sleep_time() -> bool:
	var h := hour_of_day()
	return h >= GameConstants.SLEEP_START_HOUR or h < GameConstants.SLEEP_END_HOUR



func tick_hours(hours: float) -> void:
	var n := maxi(1, int(round(hours)))
	for i in n:
		if _day_night == null:
			clock_hours += 1.0
		# Catching up several hours: each one is simulated as its own hour (seeds, daily events).
		_tick_hour(now_hours() - (n - 1 - i) if _day_night else now_hours())


func _tick_hour(hour: float) -> void:
	var opinions := 0.0
	var count := 0
	for k in _state.kingdoms():
		_travelers(k)
		_needs(k)
		_assign_homes(k)
		society.tick_hour(k, hour)
		houses.tick_hour(k, hour)
		gov.tick_hour(k, hour)
		_plan(k)
		_offscreen_work(k)
		_stalled_site(k)
		var away: bool = not is_player_in.call(k)
		var target := GovRules.away_target(k) # neutral, or worship / hatred under the regent
		var mine := String(k.get("founder", "player")) == "player" # the founder's name is made at home
		for p in _state.residents(k.id):
			if away:
				p.opinion = move_toward(float(p.opinion), target, GameConstants.AWAY_OPINION_PER_DAY / 24.0)
			if mine and SocietyRules.is_adult(p):
				opinions += float(p.opinion)
				count += 1
	realms.tick_hour(hour)
	if count > 0:
		_state.fame = opinions / count
	for p in _state.all_people(): # those who left and lost their node walk off the map
		if p.status == "leaving" and not has_node.call(p.id):
			_state.remove_person(p.id)


# --- Travelers ------------------------------------------------------------------------------

func _travelers(k: Dictionary) -> void:
	var now := now_hours()
	if k.next_traveler_hour < 0.0:
		k.next_traveler_hour = now + GameConstants.TRAVELER_FIRST_HOURS
	var coming := 0
	for p in _state.all_people():
		if p.kingdom_id == k.id and p.status == "traveler":
			coming += 1
			if not has_node.call(p.id) and now > float(p.arrived_hour):
				_state.move_person(p.id, _seat_spot(k))
				decide(p)
	if now >= k.next_traveler_hour:
		var interval := GameConstants.TRAVELER_INTERVAL_HOURS
		var snap := snapshot(k)
		if snap.has_market:
			interval = GameConstants.TRAVELER_INTERVAL_MARKET
		k.next_traveler_hour = now + interval
		if snap.residents + coming < GameConstants.KINGDOM_MAX_PEOPLE:
			_spawn_traveler(k, snap)


func _spawn_traveler(k: Dictionary, snap: Dictionary) -> void:
	var profession := -1
	# Seeded by kingdom and hour (not a session RNG): a reloaded game must not replay its travelers.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_state.seed, "traveler", k.id, int(now_hours())])
	if rng.randf() < GameConstants.TRAVELER_NEEDED_SHARE:
		profession = VillageRules.needed_profession(snap)
	var p := PersonGen.generate(rng, _state.fame, profession)
	var angle := rng.randf() * TAU
	var dist := rng.randf_range(GameConstants.TRAVELER_DISTANCE.x, GameConstants.TRAVELER_DISTANCE.y)
	var pos: Vector3 = k.center + Vector3(sin(angle), 0.0, cos(angle)) * dist
	var size := ChunkMath.playable_size() - GameConstants.TRAVELER_MAP_MARGIN
	pos.x = clampf(pos.x, GameConstants.TRAVELER_MAP_MARGIN, size)
	pos.z = clampf(pos.z, GameConstants.TRAVELER_MAP_MARGIN, size)
	pos.y = _gen.height_at(pos.x, pos.z)
	var rec := _state.add_person(p, pos, k.id, now_hours())
	traveler_spawned.emit(rec)
	_say(k, GameConstants.VILLAGE_MSG_APPROACH % k.name)


## A free spot in front of the seat, where travelers stop to look at the kingdom.
func _seat_spot(k: Dictionary) -> Vector3:
	var seat := _state.building(k.seat_id)
	var base: Vector3 = seat.pos if not seat.is_empty() else k.center
	var pos := base + Vector3(_rng.randf_range(-2.0, 2.0), 0.0, 4.0 + _rng.randf_range(0.0, 2.0))
	pos.y = _gen.height_at(pos.x, pos.z)
	return pos


## A traveler at the seat decides whether to stay (also called by a live Person).
func decide(p: Dictionary) -> bool:
	var k := _state.kingdom(p.kingdom_id)
	if k.is_empty() or p.status != "traveler":
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_state.seed, "decide", p.id, int(now_hours())])
	var d := VillageRules.stay_decision(p, snapshot(k), rng)
	var who := PersonGen.full_name(p)
	if d.stay:
		p.status = "resident"
		p.arrived_hour = now_hours()
		k.people_ever += 1
		_say(k, GameConstants.VILLAGE_MSG_STAYS % [who, d.reason])
	else:
		p.status = "leaving"
		_say(k, GameConstants.VILLAGE_MSG_GOES % [who, d.reason])
	person_decided.emit(p, d.stay, d.reason)
	return d.stay


# --- Needs ----------------------------------------------------------------------------------

func _needs(k: Dictionary) -> void:
	var snap := VillageRules.snapshot(_state, k, now_hours())
	for p in _state.residents(k.id):
		if p.status != "resident":
			continue # left with their family earlier in this loop
		p.hunger = minf(1.0, float(p.hunger) + GameConstants.HUNGER_PER_HOUR)
		var fed := VillageRules.eat(p, k, _state)
		p.contentment = clampf(float(p.contentment) + VillageRules.hourly_contentment(p, snap, fed), 0.0, 1.0)
		if p.contentment < GameConstants.LEAVE_CONTENTMENT and SocietyRules.is_adult(p):
			p.unhappy_hours = float(p.unhappy_hours) + 1.0
		else:
			p.unhappy_hours = 0.0 # children never leave alone
		if p.status == "resident" and p.unhappy_hours >= GameConstants.LEAVE_AFTER_HOURS:
			_leave(p, k, VillageRules.leave_reason(p, snap))


## An unhappy resident leaves with the spouse and the minor children; houses they owned pass to
## the oldest adult who stays there (or to the kingdom).
func _leave(p: Dictionary, k: Dictionary, reason: String) -> void:
	var group: Array[Dictionary] = [p]
	var spouse := _state.person(p.spouse_id)
	if not spouse.is_empty() and spouse.status == "resident":
		group.append(spouse)
	for c in _state.residents(k.id):
		if not SocietyRules.is_adult(c) and group.any(func(g: Dictionary) -> bool: return (c.parents as Array).has(g.id)):
			group.append(c)
	var ids := group.map(func(g: Dictionary) -> int: return g.id)
	for g in group:
		SocietySim.transfer_houses(_state, g.id, ids)
	var text := GameConstants.VILLAGE_MSG_LEFT if group.size() == 1 else GameConstants.VILLAGE_MSG_LEFT_FAMILY
	_say(k, text % [PersonGen.full_name(p), k.name, reason])
	for g in group:
		g.status = "leaving"
		g.home_id = -1
		g.inside = -1
		person_left.emit(g)
		if not has_node.call(g.id):
			_state.remove_person(g.id)
	families_changed.emit()


## Homeless residents move into houses (or non-seat cabins) with a free bed, preferring the spouse's
## home, then a parent's (children), then a relative's, then an empty house. Nobody is evicted.
func _assign_homes(k: Dictionary) -> void:
	var homeless := _state.residents(k.id).filter(func(p: Dictionary) -> bool: return p.home_id < 0)
	if homeless.is_empty():
		return
	homeless.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	var homes: Array[Dictionary] = []
	for b in VillageRules.kingdom_buildings(_state, k):
		if not b.get("site", false) and GameConstants.HOUSE_CAPACITY.has(b.type) and b.id != k.seat_id:
			homes.append(b)
	# Relatives first (spouse, parents, family; ranks 0-2, twice so a chain settles), then anyone.
	for max_rank in [2, 2, 4]:
		for p in homeless:
			if p.home_id >= 0:
				continue
			var best := {}
			var best_rank: int = max_rank + 1
			for b in homes:
				if SocietySim.room(_state, b) <= 0:
					continue
				var rank := _home_rank(p, b)
				if rank < best_rank:
					best = b
					best_rank = rank
			if best.is_empty():
				continue
			p.home_id = best.id
			if best.type == B.HOUSE and best.get("owner", -1) < 0 and SocietyRules.is_adult(p):
				best.owner = p.id
			families_changed.emit()


## 0 spouse's home, 1 a parent's, 2 a relative's, 3 an empty house, 4 any other.
func _home_rank(p: Dictionary, b: Dictionary) -> int:
	var rank := 3 if _occupants(b.id) == 0 else 4
	for o in _state.all_people():
		if o.home_id != b.id or o.id == p.id:
			continue
		if o.id == p.spouse_id:
			return 0
		if (p.parents as Array).has(o.id):
			rank = mini(rank, 1)
		elif int(p.family_id) >= 0 and o.family_id == p.family_id:
			rank = mini(rank, 2)
	return rank


func _occupants(id: int) -> int:
	var n := 0
	for p in _state.all_people():
		if p.home_id == id:
			n += 1
	return n


# --- Sites ----------------------------------------------------------------------------------

func _plan(k: Dictionary) -> void:
	var snap := VillageRules.snapshot(_state, k, now_hours())
	var type := VillageRules.next_project(snap)
	if type < 0 or not _state.can_afford_stock(k, GameConstants.BUILD_COST[type]):
		return
	var blockers: Array = []
	for p in _state.all_people():
		if p.kingdom_id == k.id:
			blockers.append(p.pos)
	var player: Variant = player_pos.call()
	if player != null:
		blockers.append(player)
	var site_rng := RandomNumberGenerator.new()
	site_rng.seed = hash([_state.seed, k.id, int(now_hours())])
	var spot := VillageRules.pick_site(type, k, _state, _gen, _scatter, blockers, site_rng)
	if not spot.ok:
		return
	for bush: Dictionary in spot.bushes:
		_state.mark_removed(bush.chunk, bush.id)
		prop_removed.emit(bush.chunk, bush.id)
	var rec := _state.add_site(type, spot.pos, spot.rot, k, now_hours())
	if rec.is_empty():
		return
	_say(k, GameConstants.VILLAGE_MSG_SITE % [k.name, GameConstants.BUILD_NAMES[type]])
	site_opened.emit(rec)


## Adds person-hours to a site and finishes it when done (also used by PeopleManager).
func work_on_site(id: int, hours: float) -> void:
	if _state.add_progress(id, hours, now_hours()):
		complete_site(_state.building(id))


## A finished house is signed by the first homeless resident, who moves in with others.
func complete_site(rec: Dictionary) -> void:
	var k := _state.kingdom(rec.get("kingdom_id", -1))
	if k.is_empty():
		return
	var text: String = GameConstants.VILLAGE_MSG_DONE % [k.name, GameConstants.BUILD_NAMES[rec.type]]
	if int(k.decrees.build) == int(rec.type): # the decreed work is done: back to the usual plan
		k.decrees.build = GameConstants.GOV_BUILD_FREE
	if rec.type == B.HOUSE:
		var adults := _state.residents(k.id).filter(func(p: Dictionary) -> bool:
			return p.home_id < 0 and SocietyRules.is_adult(p))
		if not adults.is_empty():
			# The adult with the most homeless relatives signs (a whole household moves in together).
			var household := func(p: Dictionary) -> int:
				return _state.residents(k.id).filter(func(o: Dictionary) -> bool:
					return o.home_id < 0 and (o.id == p.spouse_id or (o.parents as Array).has(p.id))).size()
			adults.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var ha: int = household.call(a)
				var hb: int = household.call(b)
				return ha > hb or (ha == hb and a.id < b.id))
			rec.owner = adults[0].id
			adults[0].home_id = rec.id
			text = GameConstants.VILLAGE_MSG_HOUSE_DONE % PersonGen.full_name(adults[0])
			_assign_homes(k) # the signer's spouse and children first (family ranking)
	_say(k, text)
	site_finished.emit(rec)


func _stalled_site(k: Dictionary) -> void:
	var site := _state.building(k.site_id)
	if site.is_empty() or not site.get("site", false):
		return
	if now_hours() - float(site.worked_hour) < GameConstants.SITE_STALL_HOURS:
		return
	_state.remove_building(site.id)
	_say(k, GameConstants.VILLAGE_MSG_ABANDONED % [GameConstants.BUILD_NAMES[site.type], k.name])
	site_abandoned.emit(site)


# --- Summarized work ------------------------------------------------------------------------

func _offscreen_work(k: Dictionary) -> void:
	if not is_work_time():
		return
	var snap := snapshot(k)
	var farmers := 0
	for p in _state.residents(k.id):
		if has_node.call(p.id):
			continue
		var job := VillageRules.choose_job(p, snap)
		p.job = job
		match job:
			"build":
				if k.site_id >= 0:
					work_on_site(k.site_id, 1.0)
					snap.site = k.site_id
			"farm":
				farmers += 1
			"wood", "stone", "berries":
				_harvest(k, job, GameConstants.OFFSCREEN_RATE[job])
	var food := mini(farmers, snap.farms) * GameConstants.FARM_FOOD_PER_HOUR
	if food > 0.0:
		add_fraction(k, "food", R.FOOD, food)


## Accumulates `amount` of a job's yield; every whole prop's worth removes the prop nearest to
## the kingdom center from the world (no props left = no yield).
func _harvest(k: Dictionary, job: String, amount: float) -> void:
	var frac := _fractions(k)
	frac[job] = float(frac.get(job, 0.0)) + amount
	var types: Array = _job_props(job)
	while true:
		var prop := nearest_prop(k.center, types)
		if prop.is_empty():
			frac[job] = 0.0
			return
		var yield_: Array = GameConstants.HARVEST_YIELD[prop.type]
		if float(frac[job]) < float(yield_[1]):
			return
		frac[job] = float(frac[job]) - float(yield_[1])
		var c := ChunkMath.world_to_chunk(prop.pos)
		_state.mark_removed(c, prop.id)
		_state.add_stock(k, yield_[0], yield_[1])
		prop_removed.emit(c, prop.id)


func add_fraction(k: Dictionary, key: String, res: int, amount: float) -> void:
	var frac := _fractions(k)
	frac[key] = float(frac.get(key, 0.0)) + amount
	var whole := floori(float(frac[key]))
	if whole > 0:
		_state.add_stock(k, res, whole)
		frac[key] = float(frac[key]) - whole


static func _job_props(job: String) -> Array:
	match job:
		"wood":
			return [GameConstants.Prop.OAK, GameConstants.Prop.PINE]
		"stone":
			return [GameConstants.Prop.ROCK]
	return [GameConstants.Prop.BUSH]


## The standing prop of one of `types` nearest to `from`, inside VILLAGE_HARVEST_RADIUS of it.
## `exclude` keys are Vector3i(chunk.x, chunk.y, prop id) (prop ids are per chunk).
func nearest_prop(from: Vector3, types: Array, exclude: Dictionary = {}) -> Dictionary:
	var best := {}
	var best_d := INF
	for p: Dictionary in nearest_prop_list(from):
		if not (p.type in types):
			continue
		var c := ChunkMath.world_to_chunk(p.pos)
		if exclude.has(Vector3i(c.x, c.y, p.id)) or _state.removed_in(c).has(p.id):
			continue
		var d := Vector2(p.pos.x - from.x, p.pos.z - from.z).length()
		if d < best_d:
			best_d = d
			best = p
	return best


## A kingdom event: written to the ADM chronicle, never shown to the player.
func _say(k: Dictionary, text: String) -> void:
	_state.chronicle_add(now_hours(), text, k.id)
	message.emit(text)


## Every prop (standing or not) within VILLAGE_HARVEST_RADIUS of a kingdom center, cached
## (the scatter is deterministic; call it with fixed centers only).
func nearest_prop_list(from: Vector3) -> Array:
	if not _props_near.has(from):
		_props_near[from] = _scatter.props_near(from, GameConstants.VILLAGE_HARVEST_RADIUS)
	return _props_near[from]


## VillageRules.snapshot plus what the map still offers near the kingdom (gatherers whose props
## are gone help elsewhere instead of idling).
func snapshot(k: Dictionary) -> Dictionary:
	var snap := VillageRules.snapshot(_state, k, now_hours())
	var left := {}
	for job in ["wood", "stone", "berries"]:
		left[job] = not nearest_prop(k.center, _job_props(job)).is_empty()
	snap.props_left = left
	return snap


## Partial yields of a kingdom (saved with it); live and summarized work share it.
static func _fractions(k: Dictionary) -> Dictionary:
	if not k.has("work_frac"):
		k.work_frac = {}
	return k.work_frac
