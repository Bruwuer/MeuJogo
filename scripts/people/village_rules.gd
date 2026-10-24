class_name VillageRules
extends RefCounted
## Pure village logic, no scene: what a kingdom offers (snapshot), whether a traveler stays and
## why, hourly contentment, meals, what to build next and where, and each person's job.

const B := GameConstants.Building
const R := GameConstants.Res
const T := GameConstants.Trait
const P := GameConstants.Profession

const _ROTS_TO_CENTER := 4


## What the kingdom offers right now. `hour` = DayNight.total_hours().
static func snapshot(state: WorldState, k: Dictionary, hour: float) -> Dictionary:
	var residents := state.residents(k.id)
	var beds := 0
	var farms := 0
	var has := {campfire = false, well = false, market = false, storage = false}
	for b in kingdom_buildings(state, k):
		if b.get("site", false):
			continue
		match b.type:
			B.HOUSE:
				beds += GameConstants.HOUSE_CAPACITY[B.HOUSE]
			B.CABIN:
				if b.id == k.seat_id:
					has.campfire = true # the seat shelters people sleeping outdoors
				else:
					beds += GameConstants.HOUSE_CAPACITY[B.CABIN]
			B.CAMPFIRE:
				has.campfire = true
			B.WELL:
				has.well = true
			B.MARKET:
				has.market = true
			B.STORAGE:
				has.storage = true
			B.FARM:
				farms += 1
	var homed := 0
	var apart := 0 # married people not living with their spouse
	var professions := {}
	for p in residents:
		if p.home_id >= 0:
			homed += 1
		if int(p.profession) >= 0:
			professions[p.profession] = int(professions.get(p.profession, 0)) + 1
		var spouse := state.person(p.spouse_id)
		if not spouse.is_empty() and spouse.status == "resident" and spouse.home_id != p.home_id:
			apart += 1
	var food := state.stock_of(k, R.FOOD) + state.stock_of(k, R.BERRIES)
	var eaters := maxi(1, residents.size())
	return {
		residents = residents.size(), homeless = residents.size() - homed, free_beds = maxi(0, beds - homed),
		has_campfire = has.campfire, has_well = has.well, has_market = has.market, has_storage = has.storage,
		farms = farms, food = food, food_days = float(food) / float(eaters * GameConstants.FOOD_PER_DAY),
		recent_raid = hour - float(k.last_raid_hour) < GameConstants.RAID_RECENT_HOURS,
		site = k.site_id, stock = (k.stock as Dictionary).duplicate(), professions = professions,
		people_ever = k.people_ever, apart = apart,
		surnames = state.families_of(k.id).map(func(f: Dictionary) -> String: return f.surname),
		families = state.families_of(k.id).size(),
	}


## Finished buildings and sites inside the kingdom's radius.
static func kingdom_buildings(state: WorldState, k: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var c := Vector2(k.center.x, k.center.z)
	for b in state.all_buildings():
		if Vector2(b.pos.x, b.pos.z).distance_to(c) <= k.radius:
			out.append(b)
	return out


## {stay, score, reason}: a sum of factors; the reason is the strongest one on the winning side.
static func stay_decision(person: Dictionary, snap: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	if snap.people_ever < GameConstants.KINGDOM_FOUNDERS:
		return {stay = true, score = 1.0, reason = GameConstants.STAY_REASONS.founder}
	var f := {} # factor key -> value; keys of STAY_REASONS (> 0) or LEAVE_REASONS (< 0)
	if snap.free_beds > 0:
		f.house = GameConstants.STAY_HOUSE
	elif snap.has_campfire:
		f.campfire = GameConstants.STAY_CAMPFIRE
	else:
		f.no_shelter = GameConstants.STAY_NO_SHELTER
	# The newcomer eats too.
	var days := float(snap.food) / float((snap.residents + 1) * GameConstants.FOOD_PER_DAY)
	if snap.food <= 0:
		f.no_food = GameConstants.STAY_NO_FOOD
	elif days >= GameConstants.FOOD_SAFE_DAYS:
		f.food = GameConstants.STAY_FOOD
	if snap.recent_raid:
		f.raid = GameConstants.STAY_RAID * _raid_mult(person)
	if _has_job(person.profession, snap):
		f.job = GameConstants.STAY_JOB
	if snap.has_well:
		f.well = GameConstants.STAY_WELL
	if snap.residents < GameConstants.STAY_SMALL_BELOW:
		f.small = GameConstants.STAY_SMALL
	if PersonGen.has_trait(person, T.SOCIABLE) and snap.residents > GameConstants.STAY_SOCIABLE_FROM:
		f.sociable = minf(GameConstants.STAY_SOCIABLE_MAX,
				GameConstants.STAY_SOCIABLE_PER * (snap.residents - GameConstants.STAY_SOCIABLE_FROM))
	if PersonGen.has_trait(person, T.LONER) and snap.residents > GameConstants.STAY_LONER_FROM:
		f.loner = GameConstants.STAY_LONER_PER * (snap.residents - GameConstants.STAY_LONER_FROM)
	if (snap.get("surnames", []) as Array).has(person.surname):
		f.kin = GameConstants.STAY_KIN
	var op: float = person.opinion * GameConstants.STAY_OPINION
	if op != 0.0:
		f.opinion = op
	var score := rng.randf_range(-GameConstants.STAY_NOISE, GameConstants.STAY_NOISE)
	for key in f:
		score += f[key]
	var stay := score > 0.0
	var best := ""
	for key in f:
		var v: float = f[key]
		if (v > 0.0) == stay and (best == "" or absf(v) > absf(f[best])):
			best = key
	var reason: String
	if stay:
		reason = GameConstants.STAY_REASONS.get(best, GameConstants.STAY_REASONS.other)
		if best == "job":
			reason = reason % PersonGen.profession_name(person)
	else:
		reason = GameConstants.LEAVE_REASONS.get(best, GameConstants.LEAVE_REASONS.other)
	return {stay = stay, score = score, reason = reason}


static func _raid_mult(person: Dictionary) -> float:
	if PersonGen.has_trait(person, T.FEARFUL):
		return GameConstants.FEARFUL_RAID_MULT
	if PersonGen.has_trait(person, T.BRAVE):
		return GameConstants.BRAVE_RAID_MULT
	return 1.0


## Change of contentment over one hour.
static func hourly_contentment(person: Dictionary, snap: Dictionary, fed: bool) -> float:
	var d := GameConstants.CONTENT_FED if fed else GameConstants.CONTENT_HUNGRY
	if person.home_id >= 0:
		d += GameConstants.CONTENT_HOME
	elif snap.has_campfire:
		d += GameConstants.CONTENT_CAMPFIRE_ONLY
	else:
		d += GameConstants.CONTENT_NO_SHELTER
	if snap.recent_raid:
		d += GameConstants.CONTENT_RAID * _raid_mult(person)
	if snap.has_well:
		d += GameConstants.CONTENT_WELL
	if snap.has_market:
		d += GameConstants.CONTENT_MARKET
	return d


## Why an unhappy resident leaves (past tense, for the message).
static func leave_reason(person: Dictionary, snap: Dictionary) -> String:
	if person.hunger >= GameConstants.HUNGER_MEAL or snap.food <= 0:
		return GameConstants.LEAVE_REASONS_PAST.hunger
	if person.home_id < 0 and not snap.has_campfire:
		return GameConstants.LEAVE_REASONS_PAST.shelter
	if snap.recent_raid:
		return GameConstants.LEAVE_REASONS_PAST.raid
	return GameConstants.LEAVE_REASONS_PAST.other


## A meal from the kingdom stock when hungry (Comida first, then Frutas). Returns whether the
## person is fed (not hungry, or just ate).
static func eat(person: Dictionary, k: Dictionary, state: WorldState) -> bool:
	if person.hunger < GameConstants.HUNGER_MEAL:
		return true
	for res in [R.FOOD, R.BERRIES]:
		if state.stock_of(k, res) > 0:
			state.add_stock(k, res, -1)
			person.hunger = maxf(0.0, person.hunger - GameConstants.HUNGER_MEAL)
			return true
	return false


## Next building the villagers want (or -1): one site at a time.
static func next_project(snap: Dictionary) -> int:
	if snap.site >= 0 or snap.residents == 0:
		return -1
	if snap.food_days < GameConstants.PROJECT_FOOD_DAYS \
			and snap.farms < ceili(float(snap.residents) / GameConstants.PROJECT_FARM_PER_PEOPLE):
		return B.FARM
	if snap.homeless + int(snap.get("apart", 0)) > snap.free_beds:
		return B.HOUSE
	if snap.farms * GameConstants.FARM_FOOD_PER_DAY < snap.residents * GameConstants.FOOD_PER_DAY:
		return B.FARM
	if snap.residents >= GameConstants.PROJECT_MARKET_AT and not snap.has_market:
		return B.MARKET
	if snap.residents >= GameConstants.PROJECT_WELL_AT and not snap.has_well:
		return B.WELL
	if not snap.has_storage:
		return B.STORAGE
	return -1


## A valid place for `type`: a golden-angle spiral from the kingdom center (at most
## SITE_CANDIDATES tries), inside the kingdom, outside every den's territory when possible, with a free
## corridor around it. The door (+Z) turns to the center. {ok, pos, rot}.
static func pick_site(type: int, k: Dictionary, state: WorldState, gen: TerrainGenerator, scatter: PropScatter,
		blockers: Array, rng: RandomNumberGenerator) -> Dictionary:
	var start := rng.randf() * TAU
	var golden := PI * (3.0 - sqrt(5.0))
	var dens: Array[Vector3] = []
	for pk in state.all_packs():
		dens.append(pk.den)
	var fallback := {ok = false, pos = Vector3.ZERO, rot = 0, bushes = []}
	for i in GameConstants.SITE_CANDIDATES:
		var angle := start + i * golden
		var radius := GameConstants.SITE_MIN_RADIUS + i * GameConstants.SITE_SPIRAL_STEP
		var dir := Vector3(sin(angle), 0.0, cos(angle))
		var pos := BuildRules.snap(k.center + dir * radius)
		var rot := _rot_facing(-dir)
		var rect := BuildRules.footprint_rect(type, pos, rot)
		if Vector2(pos.x - k.center.x, pos.z - k.center.z).length() + rect.size.length() * 0.5 > k.radius:
			continue
		var in_den := false
		for d in dens:
			if Vector2(pos.x - d.x, pos.z - d.z).length() <= GameConstants.TERRITORY_RADIUS:
				in_den = true
				break
		if (in_den and fallback.ok) or _crowded(rect.grow(GameConstants.SITE_GAP), state):
			continue
		var check := BuildRules.check_site(type, pos, rot, gen, scatter, state, blockers)
		if not check.ok:
			continue
		var found := {ok = true, pos = Vector3(pos.x, check.y, pos.z), rot = rot, bushes = check.bushes}
		if not in_den:
			return found
		fallback = found # a kingdom founded inside a territory still grows
	return fallback


## Quarter turn whose front (+Z rotated by rot * 90 degrees) is closest to `dir`.
static func _rot_facing(dir: Vector3) -> int:
	var best := 0
	var best_dot := -INF
	for r in _ROTS_TO_CENTER:
		var a := r * PI * 0.5
		var d := Vector3(sin(a), 0.0, cos(a)).dot(dir)
		if d > best_dot:
			best_dot = d
			best = r
	return best


static func _crowded(grown: Rect2, state: WorldState) -> bool:
	var lo := ChunkMath.world_to_chunk(Vector3(grown.position.x, 0, grown.position.y)) - Vector2i.ONE
	var hi := ChunkMath.world_to_chunk(Vector3(grown.end.x, 0, grown.end.y)) + Vector2i.ONE
	for cy in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			for b in state.buildings_in(Vector2i(cx, cy)):
				if grown.intersects(BuildRules.footprint_rect(b.type, b.pos, b.rot)):
					return true
	return false


## "build" | "wood" | "stone" | "berries" | "farm" | "market" | "idle": the own trade when there
## is work for it, else the open site, else whatever the stock lacks.
static func choose_job(person: Dictionary, snap: Dictionary) -> String:
	var own := _profession_job(person.profession, snap)
	if own != "":
		return own
	if snap.site >= 0:
		return "build"
	for job in ["wood", "stone", "berries"]:
		if _needs(job, snap):
			return job
	return "idle"


static func _profession_job(profession: int, snap: Dictionary) -> String:
	match profession:
		P.WOODCUTTER:
			return "wood" if _needs("wood", snap) else ""
		P.MASON:
			return "stone" if _needs("stone", snap) else ""
		P.GATHERER:
			return "berries" if _needs("berries", snap) else ""
		P.FARMER:
			return "farm" if snap.farms > 0 else ""
		P.BUILDER:
			return "build" if snap.site >= 0 else ""
		P.MERCHANT:
			return "market" if snap.has_market else ""
	return ""


static func _has_job(profession: int, snap: Dictionary) -> bool:
	return _profession_job(profession, snap) != ""


## Whether the stock lacks what `job` gathers and there is still some of it near the kingdom
## (`snap.props_left`, filled by the callers that know the map).
static func _needs(job: String, snap: Dictionary) -> bool:
	if not (snap.get("props_left", {}) as Dictionary).get(job, true):
		return false
	match job:
		"wood":
			return int(snap.stock.get(R.WOOD, 0)) < GameConstants.KINGDOM_STOCK_TARGET[R.WOOD]
		"stone":
			return int(snap.stock.get(R.STONE, 0)) < GameConstants.KINGDOM_STOCK_TARGET[R.STONE]
		"berries":
			return snap.food_days < GameConstants.BERRY_FOOD_DAYS
	return false


## The trade the kingdom lacks most (half of the travelers bring it).
static func needed_profession(snap: Dictionary) -> int:
	var count := func(p: int) -> int: return int(snap.professions.get(p, 0))
	if snap.food_days < GameConstants.BERRY_FOOD_DAYS:
		if snap.farms > count.call(P.FARMER):
			return P.FARMER
		if count.call(P.GATHERER) == 0:
			return P.GATHERER
	if count.call(P.BUILDER) == 0:
		return P.BUILDER
	if snap.has_market and count.call(P.MERCHANT) == 0:
		return P.MERCHANT
	var best := P.WOODCUTTER
	for p in [P.WOODCUTTER, P.MASON, P.BUILDER, P.FARMER]:
		if count.call(p) < count.call(best):
			best = p
	return best
