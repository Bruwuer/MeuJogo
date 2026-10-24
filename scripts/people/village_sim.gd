class_name VillageSim
extends Node
## Hourly simulation of every kingdom's people, loaded or not: travelers coming and deciding,
## meals, contentment and leaving, homes, the player's fame, planning sites and, for people that
## have no node this hour, a summary of their work (real props are removed, sites progress).
## People with a node work for real through PeopleManager. Messages of kingdoms that are not
## loaded wait in `pending_messages` until the player is back.

signal message(text: String)
signal site_opened(rec: Dictionary)
signal site_finished(rec: Dictionary)
signal site_abandoned(rec: Dictionary)
signal person_left(rec: Dictionary)
signal traveler_spawned(rec: Dictionary)
signal person_decided(rec: Dictionary, stayed: bool, reason: String)
signal prop_removed(c: Vector2i, id: int)

const B := GameConstants.Building
const R := GameConstants.Res

## Messages from kingdoms that were not loaded (shown when the player returns).
var pending_messages: Array[String] = []
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


func setup(state: WorldState, gen: TerrainGenerator, scatter: PropScatter, day_night: DayNight) -> void:
	_state = state
	_gen = gen
	_scatter = scatter
	_day_night = day_night
	_rng.seed = hash([state.seed, "village"])


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


func take_messages() -> Array[String]:
	var out := pending_messages
	pending_messages = []
	return out


func tick_hours(hours: float) -> void:
	for i in maxi(1, int(round(hours))):
		if _day_night == null:
			clock_hours += 1.0
		_tick_hour()


func _tick_hour() -> void:
	var opinions := 0.0
	var count := 0
	for k in _state.kingdoms():
		_travelers(k)
		_needs(k)
		_assign_homes(k)
		_plan(k)
		_offscreen_work(k)
		_stalled_site(k)
		var away: bool = not is_player_in.call(k)
		for p in _state.residents(k.id):
			if away:
				p.opinion = move_toward(float(p.opinion), 0.0, GameConstants.AWAY_OPINION_PER_DAY / 24.0)
			opinions += float(p.opinion)
			count += 1
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
		p.hunger = minf(1.0, float(p.hunger) + GameConstants.HUNGER_PER_HOUR)
		var fed := VillageRules.eat(p, k, _state)
		p.contentment = clampf(float(p.contentment) + VillageRules.hourly_contentment(p, snap, fed), 0.0, 1.0)
		if p.contentment < GameConstants.LEAVE_CONTENTMENT:
			p.unhappy_hours = float(p.unhappy_hours) + 1.0
		else:
			p.unhappy_hours = 0.0
		if p.unhappy_hours >= GameConstants.LEAVE_AFTER_HOURS:
			_leave(p, k, VillageRules.leave_reason(p, snap))


func _leave(p: Dictionary, k: Dictionary, reason: String) -> void:
	p.status = "leaving"
	for b in _state.all_buildings():
		if b.get("owner", GameConstants.OWNER_PLAYER) == p.id:
			b.owner = GameConstants.OWNER_KINGDOM
	p.home_id = -1
	p.inside = -1
	_say(k, GameConstants.VILLAGE_MSG_LEFT % [PersonGen.full_name(p), k.name, reason])
	person_left.emit(p)
	if not has_node.call(p.id):
		_state.remove_person(p.id)


## Homeless residents move into houses (or non-seat cabins) with a free bed.
func _assign_homes(k: Dictionary) -> void:
	var homeless := _state.residents(k.id).filter(func(p: Dictionary) -> bool: return p.home_id < 0)
	if homeless.is_empty():
		return
	for b in VillageRules.kingdom_buildings(_state, k):
		if homeless.is_empty():
			return
		if b.get("site", false) or not GameConstants.HOUSE_CAPACITY.has(b.type) or b.id == k.seat_id:
			continue
		var room: int = GameConstants.HOUSE_CAPACITY[b.type] - _occupants(b.id)
		while room > 0 and not homeless.is_empty():
			var p: Dictionary = homeless.pop_front()
			p.home_id = b.id
			if b.type == B.HOUSE and b.get("owner", -1) < 0:
				b.owner = p.id
			room -= 1


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
	if rec.type == B.HOUSE:
		var homeless := _state.residents(k.id).filter(func(p: Dictionary) -> bool: return p.home_id < 0)
		if not homeless.is_empty():
			rec.owner = homeless[0].id
			text = GameConstants.VILLAGE_MSG_HOUSE_DONE % PersonGen.full_name(homeless[0])
			for i in mini(homeless.size(), GameConstants.HOUSE_CAPACITY[B.HOUSE]):
				homeless[i].home_id = rec.id
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


func _say(k: Dictionary, text: String) -> void:
	if is_kingdom_loaded.call(k):
		message.emit(text)
	else:
		pending_messages.append(text)


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
