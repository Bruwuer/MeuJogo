class_name PeopleManager
extends Node3D
## Gives people in loaded chunks a Person node (cap PEOPLE_MAX_ACTIVE, a few per frame) and
## applies their work to the world: real trees, rocks and bushes are removed and carried to the
## kingdom stock, farmers make food, builders raise sites. Also keeps the loaded chunks in step
## with the VillageSim (new, growing, finished and abandoned sites; props cut off-screen).
## Nodes that leave the loaded area are freed, and what they carried goes to the stock.

signal message(text: String)

const B := GameConstants.Building
const R := GameConstants.Res
const _FALL_LIMIT := 4.0
const _REGROUND := 0.3

var _state: WorldState
var _gen: TerrainGenerator
var _scatter: PropScatter
var _streamer: ChunkStreamer
var _library: ModelLibrary
var _day_night: DayNight
var _sim: VillageSim
var _player: Node3D
var _nodes: Dictionary[int, Person] = {}
var _queue: Array[int] = []
var _claims: Dictionary = {} # person id -> Vector3i(chunk.x, chunk.y, prop id) or building id
var _snaps: Dictionary = {} # kingdom id -> [msec, snapshot]
var _sync_left := 0.0


func setup(state: WorldState, gen: TerrainGenerator, scatter: PropScatter, streamer: ChunkStreamer,
		library: ModelLibrary, day_night: DayNight, sim: VillageSim, player: Node3D) -> void:
	_state = state
	_gen = gen
	_scatter = scatter
	_streamer = streamer
	_library = library
	_day_night = day_night
	_sim = sim
	_player = player
	sim.has_node = func(id: int) -> bool: return _nodes.has(id) and is_instance_valid(_nodes[id])
	sim.is_kingdom_loaded = is_kingdom_loaded
	sim.message.connect(func(t: String) -> void: message.emit(t))
	sim.site_opened.connect(_show_building)
	sim.houses.buildings_changed.connect(_on_house_buildings)
	sim.site_finished.connect(_refresh_building)
	sim.site_finished.connect(func(_r: Dictionary) -> void: refresh_crests())
	sim.families_changed.connect(refresh_crests)
	sim.person_born.connect(func(_r: Dictionary) -> void: _fill())
	sim.person_died.connect(func(r: Dictionary) -> void: _free_node(r.id))
	sim.site_abandoned.connect(_hide_building)
	sim.building_burned.connect(_hide_building)
	sim.body_removed.connect(_free_node)
	sim.prop_removed.connect(_remove_prop)
	sim.traveler_spawned.connect(func(_r: Dictionary) -> void: _fill())
	streamer.chunk_loaded.connect(func(_c: Vector2i) -> void:
		_fill()
		refresh_crests())
	streamer.chunk_unloaded.connect(_on_chunk_unloaded)


func pending_spawns() -> int:
	return _queue.size()


func active_count() -> int:
	return _nodes.size()


func node_for(id: int) -> Person:
	var n = _nodes.get(id)
	return n if is_instance_valid(n) else null


func active_people() -> Array[Person]:
	var out: Array[Person] = []
	for id in _nodes:
		var n := node_for(id)
		if n:
			out.append(n)
	return out


## Nearest visible person within `max_dist` of `pos`, or null.
func nearest_person(pos: Vector3, max_dist: float) -> Person:
	var best: Person = null
	var best_d := max_dist
	for n in active_people():
		if not n.visible or n.is_dead():
			continue
		var d := _flat(n.global_position, pos)
		if d <= best_d:
			best = n
			best_d = d
	return best


func is_kingdom_loaded(k: Dictionary) -> bool:
	return _streamer.is_loaded(ChunkMath.world_to_chunk(k.center))


func _process(delta: float) -> void:
	_spawn_queued()
	_sync_left -= delta
	if _sync_left <= 0.0:
		_sync_left = GameConstants.PEOPLE_SYNC_SEC
		_sync()


## Writes live people back to their records and frees those out of the loaded area.
func _sync() -> void:
	for id in _nodes.keys():
		var n := node_for(id)
		if n == null:
			_nodes.erase(id)
			continue
		var rec := _state.person(int(id))
		if rec.is_empty() or (rec.status == "dead" and int(rec.get("carrier_id", -1)) >= 0):
			_free_node(id) # buried, or picked up: the body is in someone's arms now
			continue
		var p := n.global_position
		var ground := _gen.height_at(p.x, p.z)
		if p.y < ground - _FALL_LIMIT:
			n.global_position = Vector3(p.x, ground + _REGROUND, p.z)
		_store(n)
		if not _streamer.is_loaded(ChunkMath.world_to_chunk(n.global_position)):
			_free_node(id)
	_fill()
	refresh_crests() # catches any owner change the signals did not announce


func sync_all() -> void:
	for n in active_people():
		_store(n)


func _store(n: Person) -> void:
	if n.record.is_empty() or _state.person(n.record.id).is_empty():
		return
	n.sync_record()
	_state.move_person(n.record.id, n.global_position)


func _on_chunk_unloaded(c: Vector2i) -> void:
	for id in _nodes.keys():
		var n := node_for(id)
		if n and ChunkMath.world_to_chunk(n.global_position) == c:
			_store(n)
			_free_node(id)


## Queues people without a node in loaded chunks, nearest to the player first.
func _fill() -> void:
	var waiting: Array[Dictionary] = []
	for rec in _state.all_people():
		if rec.status == "dead" and int(rec.get("carrier_id", -1)) >= 0:
			continue # carried: drawn in the bearer's arms
		if not _nodes.has(rec.id) and _streamer.is_loaded(ChunkMath.world_to_chunk(rec.pos)):
			waiting.append(rec)
	var center := _player.global_position if is_instance_valid(_player) else Vector3.ZERO
	waiting.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return center.distance_squared_to(a.pos) < center.distance_squared_to(b.pos))
	_queue.assign(waiting.map(func(r: Dictionary) -> int: return r.id))


func _spawn_queued() -> void:
	if _queue.is_empty() or not _library.is_ready():
		return
	var made := 0
	while not _queue.is_empty() and made < GameConstants.PEOPLE_SPAWNS_PER_FRAME:
		if _nodes.size() >= GameConstants.PEOPLE_MAX_ACTIVE:
			_queue.clear()
			return
		var rec := _state.person(_queue.pop_front())
		if rec.is_empty() or _nodes.has(rec.id) or not _streamer.is_loaded(ChunkMath.world_to_chunk(rec.pos)):
			continue
		var p: Vector3 = rec.pos
		rec.pos = Vector3(p.x, _gen.height_at(p.x, p.z) + _REGROUND, p.z)
		var n := Person.new()
		add_child(n)
		n.setup(rec, _library, self)
		_nodes[rec.id] = n
		made += 1


## Loses the node: whatever it carried goes to the stock (no work is lost or doubled).
func _free_node(id: int) -> void:
	var n := node_for(id)
	_nodes.erase(id)
	_claims.erase(id)
	if n:
		_deposit_record(n.record)
		n.queue_free()


# --- Context for PersonBrain ----------------------------------------------------------------

func person_context(n: Person) -> Dictionary:
	var rec := n.record
	var k := _state.kingdom(rec.kingdom_id)
	var me := {is_work_time = _sim.is_work_time(), is_sleep_time = _sim.is_sleep_time()}
	var ctx := {work_target = {}}
	if k.is_empty():
		ctx.exit_pos = rec.pos
		return {me = me, ctx = ctx}
	var seat := _state.building(k.seat_id)
	var seat_front: Vector3 = door_of(seat) if not seat.is_empty() else k.center
	ctx.seat_pos = seat_front
	ctx.deposit_pos = _deposit_spot(k, n.global_position, seat_front)
	ctx.campfire_pos = _campfire(k)
	var out: Vector3 = n.global_position - k.center
	out.y = 0.0
	if out.length() < 1.0:
		out = Vector3.BACK
	ctx.exit_pos = k.center + out.normalized() * (k.radius + GameConstants.TRAVELER_DISTANCE.y)
	var home := _state.building(rec.home_id)
	if not home.is_empty():
		me.home_pos = home.pos
		me.door_pos = door_of(home)
		if not SocietyRules.is_adult(rec):
			ctx.seat_pos = me.door_pos # children play by their front door
	me.raid = _state.all_packs().any(func(p: Dictionary) -> bool: return p.raid_kingdom == k.id)
	me.rain = _state.raining(_sim.now_hours())
	me.threat_pos = _threat(n)
	var guard: bool = rec.status == "resident" and int(rec.profession) == GameConstants.Profession.GUARD \
			and SocietyRules.is_adult(rec)
	if guard: # guards stand their ground, keep watch at night and through raids
		me.threat_pos = null
		me.raid = false
		me.is_work_time = VillageRules.guard_on_duty(_sim.hour_of_day())
		me.is_sleep_time = not me.is_work_time
	var deed: Dictionary = rec.get("deed", {})
	if rec.status in ["resident", "merchant"] and Deeds.is_due(deed, _sim.now_hours()):
		me.deed = {pos = deed.pos, reach = deed.reach, work_sec = deed.work_sec}
	if rec.status == "resident" and me.is_work_time and not me.raid:
		var job := VillageRules.choose_job(rec, _snapshot(k))
		rec.job = job
		ctx.work_target = _work_target(n, k, job)
	elif rec.status == "resident":
		rec.job = "rest"
	return {me = me, ctx = ctx}


## The spot in front of a building's door (+Z of the model, turned by rot quarters).
static func door_of(b: Dictionary) -> Vector3:
	var fp: Vector2 = GameConstants.BUILD_FOOTPRINT[b.type]
	var a: float = b.rot * PI * 0.5
	return (b.pos as Vector3) + Vector3(sin(a), 0.0, cos(a)) * (fp.y * 0.5 + GameConstants.PERSON_DOOR_GAP)


func _snapshot(k: Dictionary) -> Dictionary:
	var now := Time.get_ticks_msec()
	var cached: Array = _snaps.get(k.id, [])
	if cached.is_empty() or now - int(cached[0]) > GameConstants.PEOPLE_SNAPSHOT_MS:
		cached = [now, _sim.snapshot(k)]
		_snaps[k.id] = cached
	return cached[1]


func _deposit_spot(k: Dictionary, from: Vector3, fallback: Vector3) -> Vector3:
	var best := fallback
	var best_d := _flat(from, fallback)
	for b in VillageRules.kingdom_buildings(_state, k):
		if b.type == B.STORAGE and not b.get("site", false):
			var d := door_of(b)
			if _flat(from, d) < best_d:
				best = d
				best_d = _flat(from, d)
	return best


func _campfire(k: Dictionary) -> Variant:
	for b in VillageRules.kingdom_buildings(_state, k):
		if b.type == B.CAMPFIRE:
			return b.pos
	return null


## Nearest carnivore (or raiding creature) close enough to scare a person.
func _threat(n: Person) -> Variant:
	if not n.visible:
		return null
	var best: Variant = null
	var best_d := GameConstants.PERSON_THREAT_RADIUS
	for c in get_tree().get_nodes_in_group("creatures"):
		var cr := c as Creature
		if cr == null or cr.is_dead() or cr.record.is_empty():
			continue
		var pack := _state.pack(cr.record.pack_id)
		var raiding: bool = not pack.is_empty() and pack.raid_kingdom != -1
		if cr.genome.diet != GameConstants.Diet.CARNIVORE and not raiding:
			continue
		var d := _flat(cr.global_position, n.global_position)
		if d < best_d:
			best_d = d
			best = cr.global_position
	return best


func _work_target(n: Person, k: Dictionary, job: String) -> Dictionary:
	var id: int = n.record.id
	match job:
		"wood", "stone", "berries":
			return _prop_target(id, k, job)
		"build":
			var site := _state.building(k.site_id)
			if site.is_empty():
				return {}
			return {kind = "site", id = site.id, pos = site.pos, duration = GameConstants.PERSON_SITE_SEC,
					reach = GameConstants.BUILD_FOOTPRINT[site.type].length() * 0.5 + GameConstants.PERSON_ARRIVE}
		"farm":
			var farm := _claim_building(id, k, B.FARM)
			if farm.is_empty():
				return {}
			return {kind = "farm", id = farm.id, pos = farm.pos, duration = GameConstants.PERSON_FARM_SEC,
					reach = GameConstants.BUILD_FOOTPRINT[B.FARM].x * 0.5}
		"market":
			var market := _claim_building(id, k, B.MARKET)
			if market.is_empty():
				return {}
			return {kind = "market", id = market.id, pos = door_of(market), duration = GameConstants.PERSON_FARM_SEC,
					reach = GameConstants.PERSON_ARRIVE}
		"guard":
			return guard_target(k, id, n.global_position, Time.get_ticks_msec() / 1000.0, _hostiles())
	_claims.erase(id)
	return {}


## A guard's next move: strike the nearest hostile in (or near) the territory, else walk the patrol
## ring. `hostiles`: [{id, pos}]; `time_sec` moves the patrol point along.
static func guard_target(k: Dictionary, guard_id: int, guard_pos: Vector3, time_sec: float, hostiles: Array) -> Dictionary:
	var best := {}
	var best_d := INF
	for h: Dictionary in hostiles:
		if _flat(h.pos, k.center) > float(k.radius) + GameConstants.GUARD_ALERT_MARGIN:
			continue
		var d := _flat(h.pos, guard_pos)
		if d < best_d:
			best_d = d
			best = h
	if not best.is_empty():
		return {kind = "guard_attack", id = best.id, pos = best.pos, duration = GameConstants.GUARD_STRIKE_SEC,
				reach = GameConstants.GUARD_REACH}
	var angle := time_sec * GameConstants.GUARD_PATROL_SPEED + guard_id * 1.7
	var r := float(k.radius) * GameConstants.GUARD_PATROL_SHARE
	var pos: Vector3 = k.center + Vector3(sin(angle), 0.0, cos(angle)) * r
	return {kind = "patrol", pos = pos, duration = 2.0, reach = 2.0}


## Living carnivores and raiders (what guards fight): [{id, pos}].
func _hostiles() -> Array:
	var out := []
	for c in get_tree().get_nodes_in_group("creatures"):
		var cr := c as Creature
		if cr == null or cr.is_dead() or cr.record.is_empty():
			continue
		var pack := _state.pack(cr.record.pack_id)
		if cr.genome.diet == GameConstants.Diet.CARNIVORE or (not pack.is_empty() and pack.raid_kingdom != -1):
			out.append({id = cr.record.id, pos = cr.global_position})
	return out


## The prop this person is working on, or the free one nearest to the kingdom center.
func _prop_target(id: int, k: Dictionary, job: String) -> Dictionary:
	var types := VillageSim._job_props(job)
	var claim = _claims.get(id)
	var prop := {}
	if claim is Vector3i and not _state.removed_in(Vector2i(claim.x, claim.y)).has(claim.z):
		prop = _claimed_prop(k, claim)
	if prop.is_empty() or not (prop.type in types):
		var exclude := {}
		for other in _claims:
			if other != id and _claims[other] is Vector3i:
				exclude[_claims[other]] = true
		prop = _sim.nearest_prop(k.center, types, exclude)
		if prop.is_empty():
			_claims.erase(id)
			return {}
		var pc := ChunkMath.world_to_chunk(prop.pos)
		_claims[id] = Vector3i(pc.x, pc.y, prop.id)
	var radius: float = GameConstants.PROP_COLLISION_RADIUS[prop.type] * prop.scale
	return {kind = "prop", prop = prop, pos = prop.pos, duration = GameConstants.PERSON_HARVEST_SEC[prop.type],
			reach = radius + GameConstants.PERSON_RADIUS + GameConstants.PERSON_WORK_GAP}


func _claimed_prop(k: Dictionary, claim: Vector3i) -> Dictionary:
	for p in _sim.nearest_prop_list(k.center):
		if p.id == claim.z and ChunkMath.world_to_chunk(p.pos) == Vector2i(claim.x, claim.y):
			return p
	return {}


## A building of `type` in the kingdom tended by nobody else (one farmer per farm).
func _claim_building(id: int, k: Dictionary, type: int) -> Dictionary:
	var mine = _claims.get(id)
	if mine is int:
		var b := _state.building(mine)
		if not b.is_empty() and b.type == type:
			return b
	var taken := {}
	for other in _claims:
		if other != id and _claims[other] is int:
			taken[_claims[other]] = true
	for b in VillageRules.kingdom_buildings(_state, k):
		if b.type == type and not b.get("site", false) and not taken.has(b.id):
			_claims[id] = b.id
			return b
	_claims.erase(id)
	return {}


# --- Callbacks from Person ------------------------------------------------------------------

func finish_work(n: Person) -> void:
	var t := n.work_target
	var rec := n.record
	var k := _state.kingdom(rec.kingdom_id)
	if t.is_empty() or k.is_empty():
		return
	match t.kind:
		"prop":
			var prop: Dictionary = t.prop
			var c := ChunkMath.world_to_chunk(prop.pos)
			_claims.erase(rec.id)
			if _state.removed_in(c).has(prop.id):
				return # someone else got it first
			_state.mark_removed(c, prop.id)
			_remove_prop(c, prop.id)
			var y: Array = GameConstants.HARVEST_YIELD[prop.type]
			var carrying: Dictionary = rec.carrying
			carrying[y[0]] = int(carrying.get(y[0], 0)) + int(y[1])
		"guard_attack":
			for c in get_tree().get_nodes_in_group("creatures"):
				var cr := c as Creature
				if cr and not cr.is_dead() and not cr.record.is_empty() and int(cr.record.id) == int(t.id) \
						and _flat(cr.global_position, n.global_position) <= GameConstants.GUARD_REACH + 1.0:
					cr.health.damage(GameConstants.GUARD_DAMAGE, n)
		"farm":
			_sim.add_fraction(k, "food", R.FOOD, GameConstants.FARM_FOOD_PER_HOUR * float(t.duration) / _sec_per_hour())
		"site":
			var site := _state.building(t.id)
			if site.is_empty() or not site.get("site", false):
				return
			_sim.work_on_site(t.id, float(t.duration) / _sec_per_hour())
			var after := _state.building(t.id)
			if after.get("site", false):
				_refresh_building(after)


## The person finished a House deed where it happens: settle it, with whoever saw it.
func finish_deed(n: Person) -> void:
	var rec := n.record
	var k := _state.kingdom(rec.kingdom_id)
	var deed: Dictionary = rec.get("deed", {})
	if k.is_empty() or deed.is_empty():
		return
	var pool := []
	for o in active_people():
		pool.append({id = o.record.id, family_id = int(o.record.get("family_id", -1)), pos = o.global_position,
				adult = SocietyRules.is_adult(o.record) and not o.is_dead(), visible = o.visible})
	var data: Dictionary = deed.data
	var seen := witness_ids(rec.id, HouseSim.quiet_families(data, rec), data.get("party", []), n.global_position, pool)
	_sim.houses.complete_deed(k, rec, seen, _sim.now_hours())


## Ids of the people who see a deed done at `at`: awake (visible) adults close by, outside the
## Houses that keep the secret (`quiet_families`) and the deed's party.
## `people`: [{id, family_id, pos, adult, visible}].
static func witness_ids(doer_id: int, quiet_families: Array, party: Array, at: Vector3, people: Array) -> Array:
	var out := []
	for o: Dictionary in people:
		if o.id == doer_id or party.has(o.id) or not o.adult or not o.visible:
			continue
		if quiet_families.has(o.family_id):
			continue
		if _flat(o.pos, at) <= GameConstants.DEED_WITNESS_RADIUS:
			out.append(o.id)
	return out


func deposit(n: Person) -> void:
	_deposit_record(n.record)
	_snaps.erase(n.record.kingdom_id)


func _deposit_record(rec: Dictionary) -> void:
	var carrying: Dictionary = rec.get("carrying", {})
	if carrying.is_empty():
		return
	var k := _state.kingdom(rec.kingdom_id)
	if not k.is_empty():
		for res in carrying:
			_state.add_stock(k, res, carrying[res])
	rec.carrying = {}


func evaluate(n: Person) -> void:
	_sim.decide(n.record)


func entered(n: Person) -> void:
	n.record.inside = n.record.home_id


func exited(n: Person) -> void:
	n.record.inside = -1


func left_map(n: Person) -> void:
	var id: int = n.record.id
	_nodes.erase(id)
	_claims.erase(id)
	_state.remove_person(id)
	n.queue_free()


# --- The player -----------------------------------------------------------------------------

## G inside a kingdom: up to DONATE_MAX of each resource goes from the player to the stock, and
## the residents who see it think better of the player. Returns the message to show.
## The player trades with the merchant nearby ("bread", "arrows", "sell_wood").
func trade(pos: Vector3, what: String) -> String:
	var best: Person = null
	var best_d := GameConstants.TALK_RANGE * 2.0
	for n in active_people():
		if n.record.status == "merchant" and _flat(n.global_position, pos) <= best_d:
			best = n
			best_d = _flat(n.global_position, pos)
	if best == null:
		return GameConstants.MERCHANT_NONE
	return MerchantRules.trade(_state, best.record, what)


func donate(pos: Vector3) -> String:
	var k := _state.kingdom_at(pos)
	if k.is_empty():
		return GameConstants.DONATE_OUTSIDE_MSG
	if not _sim.gov.player_may_donate(k):
		return _sim.gov.refusal(k)
	var cost := {}
	var parts: PackedStringArray = []
	for res in GameConstants.DONATE_RES:
		var n := mini(GameConstants.DONATE_MAX, _state.get_resource(res))
		if n > 0:
			cost[res] = n
			parts.append("%d %s" % [n, (GameConstants.RES_NAMES[res] as String).to_lower()])
	var total := 0
	for res in cost:
		total += int(cost[res])
	if cost.is_empty() or not _state.spend(cost):
		return GameConstants.DONATE_NOTHING_MSG
	for res in cost:
		_state.add_stock(k, res, cost[res])
	sync_all()
	for p in _state.residents(k.id):
		if _flat(p.pos, pos) <= GameConstants.DONATE_RADIUS:
			p.opinion = clampf(float(p.opinion) + donation_opinion(total), -1.0, 1.0)
	_snaps.erase(k.id)
	return GameConstants.DONATE_MSG % [", ".join(parts), k.name]


## The player killed a creature: a raider (or a carnivore) inside a kingdom means it protected
## the people there.
func on_creature_killed(rec: Dictionary, by_player: bool) -> void:
	if not by_player:
		return
	var k := _state.kingdom_at(rec.pos)
	if k.is_empty():
		return
	var pack := _state.pack(rec.get("pack_id", -1))
	var raider: bool = not pack.is_empty() and pack.raid_kingdom == k.id
	if not raider and rec.genome.diet != GameConstants.Diet.CARNIVORE:
		return
	for p in _state.residents(k.id):
		p.opinion = clampf(float(p.opinion) + GameConstants.PROTECT_OPINION, -1.0, 1.0)


## What the card shows when the player talks to someone.
static func card_text(rec: Dictionary, state: WorldState) -> String:
	if String(rec.get("status", "")) == "merchant": # the price list (stage 10)
		var g: Dictionary = rec.get("goods", {})
		return PersonGen.full_name(rec) + "\n" + GameConstants.MERCHANT_CARD % [int(g.get(GameConstants.Res.BREAD, 0)),
				int(g.get(GameConstants.Res.ARROWS, 0)), int(rec.get("coins", 0)), GameConstants.MERCHANT_BREAD_PRICE,
				GameConstants.MERCHANT_ARROW_LOT, GameConstants.MERCHANT_ARROW_PRICE, GameConstants.MERCHANT_SELL_LOT,
				GameConstants.MERCHANT_WOOD_PRICE]
	var traits: PackedStringArray = []
	for t: int in rec.traits:
		traits.append(PersonGen.trait_name(rec, t))
	var doing: String
	if int(rec.get("inside", -1)) >= 0:
		doing = GameConstants.STATUS_TEXTS.inside
	elif GameConstants.STATUS_TEXTS.has(rec.status):
		doing = GameConstants.STATUS_TEXTS[rec.status]
	else:
		doing = GameConstants.JOB_TEXTS.get(rec.get("job", ""), GameConstants.JOB_TEXTS.idle)
	var need := "none"
	if float(rec.get("hunger", 0.0)) >= GameConstants.HUNGER_MEAL:
		need = "food"
	elif rec.status == "resident" and int(rec.get("home_id", -1)) < 0:
		need = "home"
	elif float(rec.get("contentment", 1.0)) < GameConstants.LEAVE_CONTENTMENT + 0.15:
		need = "mood"
	var k := state.kingdom(rec.get("kingdom_id", -1))
	var g := 1 if rec.female else 0
	var lines: PackedStringArray = ["%s, %d anos" % [PersonGen.full_name(rec), floori(float(rec.age))]]
	if not k.is_empty():
		lines.append("Reino de %s" % k.name if rec.status == "resident" else "De passagem pelo Reino de %s" % k.name)
	var fam := state.family(int(rec.get("family_id", -1)))
	if not fam.is_empty():
		lines.append(GameConstants.CARD_FAMILY % fam.surname + (GameConstants.CARD_HEAD if fam.head_id == rec.id else ""))
	lines.append("%s · %s" % [PersonGen.profession_name(rec).capitalize(), ", ".join(traits)])
	var vocation := int(rec.get("vocation", -1))
	if vocation >= 0 and vocation != int(rec.profession) and SocietyRules.is_adult(rec):
		var dream: String = GameConstants.CARD_VOCATION[g] % GameConstants.PROFESSION_NAMES[vocation][g]
		lines.append(dream + (GameConstants.CARD_AGAINST_HOUSE if rec.get("conflict", false) else ""))
	lines.append_array(_kin_lines(rec, state))
	var relatives := _relatives_line(rec, state)
	if relatives != "":
		lines.append(relatives)
	var desire: Dictionary = rec.get("desire", {})
	if int(desire.get("kind", GameConstants.Desire.NONE)) != GameConstants.Desire.NONE:
		var dt: String = GameConstants.DESIRE_TEXTS[int(desire.kind)]
		if dt.contains("%s"):
			var who := state.person(int(desire.get("target_id", -1)))
			dt = dt % (who.name if not who.is_empty() else "?")
		lines.append(GameConstants.CARD_DESIRE % dt)
	if not fam.is_empty() and not (fam.get("goal", {}) as Dictionary).is_empty():
		lines.append(GameConstants.CARD_HOUSE_GOAL % HouseSim.goal_text_of(state, fam.goal))
	var ties := _ties_line(rec, state)
	if ties != "":
		lines.append(ties)
	lines.append("Agora: %s" % doing)
	var feeling := LifeRules.mood_text(rec)
	if feeling != "":
		lines.append(GameConstants.CARD_FEELING % feeling)
	lines.append("Precisa de: %s" % GameConstants.NEED_TEXTS[need])
	var stance: String = rec.get("stance", "")
	lines.append(opinion_text(float(rec.opinion)) + (GameConstants.CARD_STANCE[stance][g] if stance != "" else ""))
	if not fam.is_empty():
		lines.append(GameConstants.CARD_CREST % Crest.describe(fam.crest))
	return "\n".join(lines)


## Spouse (or widowhood), then parents (for a child) or children.
static func _kin_lines(rec: Dictionary, state: WorldState) -> PackedStringArray:
	var g := 1 if rec.female else 0
	var out: PackedStringArray = []
	var spouse := state.person(int(rec.get("spouse_id", -1)))
	if not spouse.is_empty():
		out.append(GameConstants.CARD_SPOUSE[g] % PersonGen.full_name(spouse))
	elif rec.get("widowed", false):
		out.append(GameConstants.CARD_WIDOWED[g])
	if not SocietyRules.is_adult(rec):
		var names: PackedStringArray = []
		for id: int in rec.get("parents", []):
			var parent := state.person(id)
			if not parent.is_empty():
				names.append(PersonGen.full_name(parent))
		if not names.is_empty():
			out.append(GameConstants.CARD_PARENTS[g] % " e ".join(names))
		return out
	var kids: PackedStringArray = []
	for c in state.all_people():
		if (c.get("parents", []) as Array).has(rec.id):
			kids.append("%s (%d)" % [c.name, floori(float(c.age))])
	if not kids.is_empty():
		out.append(GameConstants.CARD_CHILDREN % ", ".join(kids))
	return out


## Other living relatives in the kingdom (siblings, uncles/aunts, nephews/nieces, cousins,
## grandparents): "irmã de Leonor · primo de Joana" (at most 3).
static func _relatives_line(rec: Dictionary, state: WorldState) -> String:
	var order := ["sibling", "uncle", "nephew", "cousin", "grandparent", "grandchild"]
	var found := []
	for p in state.residents(int(rec.get("kingdom_id", -1))):
		var kind := Kinship.relation_kind(state, rec.id, p.id)
		if kind in order:
			found.append([order.find(kind), p])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] if a[0] != b[0] else a[1].id < b[1].id)
	var parts: PackedStringArray = []
	for item in found.slice(0, 3):
		parts.append("%s de %s" % [Kinship.relation_word(state, rec, item[1]), item[1].name])
	return GameConstants.CARD_KIN % " · ".join(parts) if not parts.is_empty() else ""


## Best friend and worst rival among living people.
static func _ties_line(rec: Dictionary, state: WorldState) -> String:
	var rels := state.relations_of(rec.id)
	var best := {}
	var worst := {}
	for id in rels:
		var o := state.person(id)
		if o.is_empty() or id == rec.get("spouse_id", -1) or String(o.get("status", "")) == "dead":
			continue
		var v: float = rels[id]
		if v >= GameConstants.FRIEND_AT and (best.is_empty() or v > float(rels[best.id])):
			best = o
		if v <= GameConstants.RIVAL_AT and (worst.is_empty() or v < float(rels[worst.id])):
			worst = o
	var parts: PackedStringArray = []
	if not best.is_empty():
		parts.append(GameConstants.CARD_FRIEND[1 if best.female else 0] % PersonGen.full_name(best))
	if not worst.is_empty():
		parts.append(GameConstants.CARD_RIVAL % PersonGen.full_name(worst))
	return " · ".join(parts)


## One row per family of the kingdom: {crest, text} ("Casa Ferreira · 3 pessoas · chefe: Ana ·
## aliada · rival da Casa Couto").
static func family_rows(state: WorldState, k: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var families := state.families_of(k.id)
	families.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := float(a.get("prestige", 0.0))
		var pb := float(b.get("prestige", 0.0))
		return pa > pb if not is_equal_approx(pa, pb) else a.id < b.id)
	for f in families:
		var members := state.family_members(f.id)
		var n := members.size()
		var head := state.person(f.head_id)
		var text := "Casa %s · %d %s" % [f.surname, n, "pessoa" if n == 1 else "pessoas"]
		if not head.is_empty():
			text += " · chefe: %s" % head.name
		text += " · " + GameConstants.FAMILY_STANCE_TEXTS[f.stance]
		var rival := {}
		var worst := GameConstants.RIVAL_AT
		for o in families:
			if o.id == f.id:
				continue
			var r := family_relation(state, members, state.family_members(o.id))
			if r <= worst:
				worst = r
				rival = o
		if not rival.is_empty():
			text += " · rival da Casa %s" % rival.surname
		text += "\n" + house_line(state, k, f)
		out.append({crest = f.crest, text = text})
	return out


## "Lavradores · riqueza 120 · 2 lotes · casa de pedra · referência em agricultor · quer conseguir
## mais terra" (one line: the panel keeps two lines per House).
static func house_line(state: WorldState, k: Dictionary, f: Dictionary) -> String:
	var plots := (f.get("plots", []) as Array).size()
	var head := state.person(int(f.head_id))
	var home := state.building(int(head.get("home_id", -1))) if not head.is_empty() else {}
	var dwelling := "sem casa própria"
	if not home.is_empty() and home.type == B.HOUSE:
		dwelling = GameConstants.HOUSE_LEVEL_NAMES[int(home.get("house_level", 0))]
	var parts: PackedStringArray = [GameConstants.TRADITION_NAMES[int(f.get("tradition", 0))],
			"riqueza %d" % floori(float(f.get("wealth", 0.0))), "%d %s" % [plots, "lote" if plots == 1 else "lotes"], dwelling]
	var best_prof := -1
	var best := GameConstants.REFERENCE_MIN_HOURS
	for prof in (f.get("skill", {}) as Dictionary):
		var h := float(f.skill[prof])
		if h >= best and _top_in_kingdom(state, k, f, prof, h):
			best = h
			best_prof = int(prof)
	if best_prof >= 0:
		parts.append("referência em %s" % GameConstants.PROFESSION_NAMES[best_prof][0])
	if not (f.get("goal", {}) as Dictionary).is_empty():
		parts.append("quer %s" % HouseSim.goal_text_of(state, f.goal))
	return " · ".join(parts)


static func _top_in_kingdom(state: WorldState, k: Dictionary, f: Dictionary, prof: int, hours: float) -> bool:
	for o in state.families_of(k.id):
		if o.id != f.id and float((o.get("skill", {}) as Dictionary).get(prof, 0.0)) > hours:
			return false
	return true


## Mean relation between the adults of two families (0 when none).
static func family_relation(state: WorldState, a: Array, b: Array) -> float:
	var sum := 0.0
	var n := 0
	for x: Dictionary in a:
		for y: Dictionary in b:
			if SocietyRules.is_adult(x) and SocietyRules.is_adult(y):
				sum += state.relation(x.id, y.id)
				n += 1
	return sum / n if n > 0 else 0.0


static func opinion_text(opinion: float) -> String:
	for i in GameConstants.OPINION_STEPS.size():
		if opinion >= GameConstants.OPINION_STEPS[i]:
			return GameConstants.OPINION_TEXTS[i]
	return GameConstants.OPINION_TEXTS[-1]


# --- Chunks ---------------------------------------------------------------------------------

func _chunk_of(pos: Vector3) -> Chunk:
	var c := ChunkMath.world_to_chunk(pos)
	return _streamer.get_chunk(c) if _streamer.is_loaded(c) else null


func _show_building(rec: Dictionary) -> void:
	var chunk := _chunk_of(rec.pos)
	if chunk:
		chunk.add_building(rec)


## Plot stakes appeared or changed hands, or a home was upgraded: (re)build their nodes.
func _on_house_buildings(recs: Array) -> void:
	for rec: Dictionary in recs:
		var chunk := _chunk_of(rec.pos)
		if chunk:
			chunk.remove_building(rec.id)
			chunk.add_building(rec)


func _refresh_building(rec: Dictionary) -> void:
	var chunk := _chunk_of(rec.pos)
	if chunk:
		chunk.update_site(rec)
	if not rec.get("site", false):
		_clear_footprint(rec)


## A finished site gets its full collision: whoever stands on it steps out to the door first.
func _clear_footprint(rec: Dictionary) -> void:
	if rec.type in GameConstants.BUILD_FLAT:
		return
	var rect := BuildRules.footprint_rect(rec.type, rec.pos, rec.rot)
	var door := door_of(rec)
	var bodies: Array[Node3D] = []
	bodies.append_array(active_people())
	if is_instance_valid(_player):
		bodies.append(_player)
	for b in bodies:
		var p := b.global_position
		if BuildRules.circle_hits_rect(Vector2(p.x, p.z), GameConstants.PERSON_RADIUS, rect):
			b.global_position = Vector3(door.x, _gen.height_at(door.x, door.z) + _REGROUND, door.z)
			b.reset_physics_interpolation()

func _hide_building(rec: Dictionary) -> void:
	var chunk := _chunk_of(rec.pos)
	if chunk:
		chunk.remove_building(rec.id)


func _remove_prop(c: Vector2i, id: int) -> void:
	if _streamer.is_loaded(c):
		_streamer.get_chunk(c).remove_prop(id)


func _sec_per_hour() -> float:
	return GameConstants.DAY_LENGTH_SEC / 24.0


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Opinion a donation of `total` resources earns (a handful of berries is not a full gift).
static func donation_opinion(total: int) -> float:
	return GameConstants.DONATE_OPINION * minf(1.0, float(total) / GameConstants.DONATE_FULL_AT)


## The player talked to `rec` (E): once a game day it changes the person's opinion by temper.
func talked_to(rec: Dictionary) -> void:
	SocietyRules.talk(rec, floori(_sim.now_hours() / 24.0))


## Every loaded house owned by a person shows that person's family crest on its banner.
## Idempotent and cheap (Chunk.set_crest skips unchanged banners).
func refresh_crests() -> void:
	for b in _state.all_buildings():
		if b.type != B.HOUSE or b.get("site", false):
			continue
		var chunk := _chunk_of(b.pos)
		if chunk:
			chunk.set_crest(b, house_crest(_state, b))


## The crest of the family of a house's owner, or {} (kingdom or player houses, no family).
static func house_crest(state: WorldState, b: Dictionary) -> Dictionary:
	var owner := int(b.get("owner", GameConstants.OWNER_PLAYER))
	if owner < 0:
		return {}
	var fam := state.family(int(state.person(owner).get("family_id", -1)))
	return fam.get("crest", {})
