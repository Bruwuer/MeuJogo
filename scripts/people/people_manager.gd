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
	sim.site_finished.connect(_refresh_building)
	sim.site_abandoned.connect(_hide_building)
	sim.prop_removed.connect(_remove_prop)
	sim.traveler_spawned.connect(func(_r: Dictionary) -> void: _fill())
	streamer.chunk_loaded.connect(func(_c: Vector2i) -> void: _fill())
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
		if not n.visible:
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
		var p := n.global_position
		var ground := _gen.height_at(p.x, p.z)
		if p.y < ground - _FALL_LIMIT:
			n.global_position = Vector3(p.x, ground + _REGROUND, p.z)
		_store(n)
		if not _streamer.is_loaded(ChunkMath.world_to_chunk(n.global_position)):
			_free_node(id)
	_fill()


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
	me.raid = _state.all_packs().any(func(p: Dictionary) -> bool: return p.raid_kingdom == k.id)
	me.threat_pos = _threat(n)
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
		cached = [now, VillageRules.snapshot(_state, k, _sim.now_hours())]
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
	_claims.erase(id)
	return {}


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
func donate(pos: Vector3) -> String:
	var k := _state.kingdom_at(pos)
	if k.is_empty():
		return GameConstants.DONATE_OUTSIDE_MSG
	var cost := {}
	var parts: PackedStringArray = []
	for res in GameConstants.DONATE_RES:
		var n := mini(GameConstants.DONATE_MAX, _state.get_resource(res))
		if n > 0:
			cost[res] = n
			parts.append("%d %s" % [n, (GameConstants.RES_NAMES[res] as String).to_lower()])
	if cost.is_empty() or not _state.spend(cost):
		return GameConstants.DONATE_NOTHING_MSG
	for res in cost:
		_state.add_stock(k, res, cost[res])
	sync_all()
	for p in _state.residents(k.id):
		if _flat(p.pos, pos) <= GameConstants.DONATE_RADIUS:
			p.opinion = clampf(float(p.opinion) + GameConstants.DONATE_OPINION, -1.0, 1.0)
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
	var lines: PackedStringArray = [
		"%s, %d anos" % [PersonGen.full_name(rec), rec.age],
		"%s · %s" % [PersonGen.profession_name(rec).capitalize(), ", ".join(traits)],
		"Agora: %s" % doing,
		"Precisa de: %s" % GameConstants.NEED_TEXTS[need],
		opinion_text(float(rec.opinion)),
	]
	if not k.is_empty():
		lines.insert(1, "Reino de %s" % k.name if rec.status == "resident" else "De passagem pelo Reino de %s" % k.name)
	return "\n".join(lines)


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


func _refresh_building(rec: Dictionary) -> void:
	var chunk := _chunk_of(rec.pos)
	if chunk:
		chunk.update_site(rec)


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
