class_name WorldState
extends RefCounted
## Everything that differs from the freshly generated world (delta persistence): removed props,
## buildings and kingdoms (with their stock), people, creatures, resources, player position, time
## of day and the world seed.
## File layout: MAGIC | u32 payload length | 16-byte MD5 of payload | var_to_bytes(Dictionary).
## Saving goes through `.tmp` and keeps the previous save as `.bak` until the new one is in
## place; loading falls back to `.bak` and then `.tmp`, so an interrupted save never loses the world.

const MAGIC := "MJSV"
const _MD5_SIZE := 16
const _FALLBACK_SUFFIXES := ["", ".bak", ".tmp"]

signal resources_changed
## Any building that leaves the world (demolished, destroyed, abandoned site), after cleanup.
signal building_removed(rec: Dictionary)
## Every chronicle entry as it is written (the ADM log file listens).
signal chronicled(entry: Dictionary)

var seed := 0
var time_of_day := GameConstants.START_TIME_OF_DAY
var day := 1
var player_position := Vector3.ZERO
var has_player_position := false

var _removed: Dictionary[Vector2i, PackedInt32Array] = {}
var _resources: Dictionary[int, int] = {}
var _buildings: Dictionary[int, Dictionary] = {} # id -> {id, type, pos, rot, color}
var _buildings_by_chunk: Dictionary[Vector2i, PackedInt32Array] = {} # derived index, not saved
var _kingdoms: Array[Dictionary] = [] # {id, name, color, center, radius, seat_id}
var _next_building_id := 1
var _building_hp: Dictionary[int, float] = {} # only damaged buildings
var _creatures: Dictionary[int, Dictionary] = {} # id -> {id, genome, pos, hp, age, pack_id, hunger}
var _creatures_by_chunk: Dictionary[Vector2i, PackedInt32Array] = {} # derived index, not saved
var _creature_chunk: Dictionary[int, Vector2i] = {} # id -> chunk it is indexed under (records move in place)
var _next_creature_id := 1
var _packs: Dictionary[int, Dictionary] = {} # id -> {id, species, den, motives..., leader_id}
var _next_pack_id := 1
var _visited: Dictionary[Vector2i, bool] = {} # chunks whose initial creatures were spawned
var _people: Dictionary[int, Dictionary] = {} # id -> person (see add_person)
var _people_by_chunk: Dictionary[Vector2i, PackedInt32Array] = {} # derived index, not saved
var _person_chunk: Dictionary[int, Vector2i] = {}
var _next_person_id := 1
var _families: Dictionary[int, Dictionary] = {} # id -> family (see add_family)
var _next_family_id := 1
var _ancestry: Dictionary = {} # person id -> {parents, adopted_by, name, female}: kept after death or departure
var _chronicle: Array = [] # {hour, text, kingdom_id, public}, oldest first
var _relations: Dictionary[Vector2i, float] = {} # (lower id, higher id) -> -1..1, symmetric
## The player's reputation: average opinion of every resident (-1..1), refreshed hourly.
var fame := 0.0


func mark_removed(c: Vector2i, id: int) -> void:
	var ids: PackedInt32Array = _removed.get(c, PackedInt32Array())
	if not ids.has(id):
		ids.append(id)
	_removed[c] = ids


func removed_in(c: Vector2i) -> PackedInt32Array:
	return _removed.get(c, PackedInt32Array())


func add_resource(res: int, amount: int) -> void:
	_resources[res] = get_resource(res) + amount
	resources_changed.emit()


func get_resource(res: int) -> int:
	return _resources.get(res, 0)


func can_afford(cost: Dictionary) -> bool:
	for res in cost:
		if get_resource(res) < cost[res]:
			return false
	return true


## Spends the whole cost, or nothing when any resource is short.
func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for res in cost:
		_resources[res] = get_resource(res) - cost[res]
	resources_changed.emit()
	return true


func refund(cost: Dictionary, ratio: float) -> void:
	for res in cost:
		add_resource(res, floori(cost[res] * ratio))


## `owner`: OWNER_PLAYER, OWNER_KINGDOM (built by the villagers) or a person id.
func add_building(type: int, pos: Vector3, rot: int, color := Color.WHITE, owner := GameConstants.OWNER_PLAYER) -> Dictionary:
	var rec := {id = _next_building_id, type = type, pos = pos, rot = rot, color = color, owner = owner}
	_next_building_id += 1
	_buildings[rec.id] = rec
	_index_building(rec)
	return rec


## Removes a building and everything that pointed at it: residents lose their home (and step out),
## an unfinished site gives its reserved cost back to the kingdom stock.
func remove_building(id: int) -> Dictionary:
	if not _buildings.has(id):
		return {}
	var rec: Dictionary = _buildings[id]
	_buildings.erase(id)
	_building_hp.erase(id)
	var c := ChunkMath.world_to_chunk(rec.pos)
	var ids: PackedInt32Array = _buildings_by_chunk.get(c, PackedInt32Array())
	var i := ids.find(id)
	if i >= 0:
		ids.remove_at(i)
		_buildings_by_chunk[c] = ids
	for p: Dictionary in _people.values():
		if p.home_id == id:
			p.home_id = -1
		if p.inside == id:
			p.inside = -1
	if rec.get("site", false):
		var k := kingdom(rec.kingdom_id)
		if not k.is_empty():
			for res in rec.reserved:
				add_stock(k, res, rec.reserved[res])
			if k.site_id == id:
				k.site_id = -1
	building_removed.emit(rec)
	return rec


func building(id: int) -> Dictionary:
	return _buildings.get(id, {})


func buildings_in(c: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in _buildings_by_chunk.get(c, PackedInt32Array()):
		out.append(_buildings[id])
	return out


func all_buildings() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_buildings.values())
	return out


func add_kingdom(kingdom_name: String, color: Color, center: Vector3, seat_id: int) -> Dictionary:
	var k := {id = _kingdoms.size() + 1, name = kingdom_name, color = color, center = center,
			radius = GameConstants.KINGDOM_RADIUS, seat_id = seat_id,
			stock = GameConstants.KINGDOM_START_STOCK.duplicate()}
	_kingdom_defaults(k)
	_kingdoms.append(k)
	return k


func kingdom(id: int) -> Dictionary:
	for k in _kingdoms:
		if k.id == id:
			return k
	return {}


## Fields added after stage 4 (old saves lack them). Old kingdoms get the founders' supplies too,
## or their first villagers would starve and nobody would ever stay.
static func _kingdom_defaults(k: Dictionary) -> void:
	if not k.has("stock"):
		k.stock = GameConstants.KINGDOM_START_STOCK.duplicate()
	for key in ["site_id", "next_traveler_hour"]:
		if not k.has(key):
			k[key] = -1.0 if key == "next_traveler_hour" else -1
	if not k.has("last_raid_hour"):
		k.last_raid_hour = -1e9
	if not k.has("people_ever"):
		k.people_ever = 0


func kingdoms() -> Array[Dictionary]:
	return _kingdoms


## The kingdom whose territory contains `pos` (flat distance), or {}.
func kingdom_at(pos: Vector3) -> Dictionary:
	for k in _kingdoms:
		if Vector2(pos.x - k.center.x, pos.z - k.center.z).length() <= k.radius:
			return k
	return {}


func _index_building(rec: Dictionary) -> void:
	var c := ChunkMath.world_to_chunk(rec.pos)
	var ids: PackedInt32Array = _buildings_by_chunk.get(c, PackedInt32Array())
	ids.append(rec.id)
	_buildings_by_chunk[c] = ids


func save_to(path: String) -> Error:
	var err := write_payload(path + ".tmp", {
		version = GameConstants.WORLDGEN_VERSION,
		seed = seed,
		time_of_day = time_of_day,
		day = day,
		player_position = player_position,
		has_player_position = has_player_position,
		removed = _removed,
		resources = _resources,
		buildings = _buildings.values(),
		kingdoms = _kingdoms,
		next_building_id = _next_building_id,
		building_hp = _building_hp,
		creatures = _creatures.values(),
		next_creature_id = _next_creature_id,
		packs = _packs.values(),
		next_pack_id = _next_pack_id,
		visited = _visited.keys(),
		people = _people.values(),
		next_person_id = _next_person_id,
		fame = fame,
		families = _families.values(),
		next_family_id = _next_family_id,
		relations = _relation_list(),
		ancestry = _ancestry,
		chronicle = _chronicle,
	})
	if err != OK:
		return err
	var abs_path := ProjectSettings.globalize_path(path)
	var bak := abs_path + ".bak"
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.remove_absolute(bak)
		err = DirAccess.rename_absolute(abs_path, bak)
		if err != OK:
			return err
	err = DirAccess.rename_absolute(abs_path + ".tmp", abs_path)
	if err != OK:
		return err # .bak (or .tmp) is still there for load_from
	if FileAccess.file_exists(path + ".bak"):
		DirAccess.remove_absolute(bak)
	return OK


## Returns null when no readable save exists at `path`, `path.bak` or `path.tmp`.
## On a WORLDGEN_VERSION mismatch the removed-prop list is dropped (ids would point at
## different props) and the rest is kept.
static func load_from(path: String) -> WorldState:
	for suffix in _FALLBACK_SUFFIXES:
		var data: Variant = read_payload(path + suffix)
		if data is Dictionary:
			if suffix != "":
				push_warning("WorldState: recovered save from %s" % (path + suffix))
			return _from_dict(data)
	return null


## True if any of the save files (main, .bak, .tmp) exists, readable or not.
static func any_file_exists(path: String) -> bool:
	return _FALLBACK_SUFFIXES.any(func(s: String) -> bool: return FileAccess.file_exists(path + s))


static func write_payload(path: String, data: Dictionary) -> Error:
	var bytes := var_to_bytes(data)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(MAGIC.to_ascii_buffer())
	f.store_32(bytes.size())
	f.store_buffer(_md5(bytes))
	f.store_buffer(bytes)
	f.close()
	return OK


## The stored Dictionary, or null if the file is missing, truncated or fails its checksum.
static func read_payload(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < MAGIC.length() + 4 + _MD5_SIZE:
		return null
	if f.get_buffer(MAGIC.length()).get_string_from_ascii() != MAGIC:
		return null
	var size := f.get_32()
	var md5 := f.get_buffer(_MD5_SIZE)
	if f.get_length() - f.get_position() != size:
		return null
	var bytes := f.get_buffer(size)
	f.close()
	if _md5(bytes) != md5:
		return null
	var data: Variant = bytes_to_var(bytes)
	return data if data is Dictionary else null


static func _md5(bytes: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(bytes)
	return ctx.finish()


static func _from_dict(data: Dictionary) -> WorldState:
	var s := WorldState.new()
	s.seed = data.get("seed", 0)
	s.time_of_day = data.get("time_of_day", GameConstants.START_TIME_OF_DAY)
	s.day = data.get("day", 1)
	s.player_position = data.get("player_position", Vector3.ZERO)
	s.has_player_position = data.get("has_player_position", false)
	for res in data.get("resources", {}):
		s._resources[res] = data.resources[res]
	for rec: Dictionary in data.get("buildings", []):
		if not rec.has("owner"):
			rec.owner = GameConstants.OWNER_PLAYER
		s._buildings[rec.id] = rec
		s._index_building(rec)
	s._kingdoms.assign(data.get("kingdoms", []))
	for k in s._kingdoms:
		_kingdom_defaults(k)
	s._next_building_id = data.get("next_building_id", 1)
	var hps: Dictionary = data.get("building_hp", {})
	for id in hps:
		s._building_hp[id] = hps[id]
	for rec: Dictionary in data.get("creatures", []):
		s._creatures[rec.id] = rec
		s._index_creature(rec)
	s._next_creature_id = data.get("next_creature_id", 1)
	for p: Dictionary in data.get("packs", []):
		s._packs[p.id] = p
	s._next_pack_id = data.get("next_pack_id", 1)
	for p: Dictionary in data.get("people", []):
		person_defaults(p)
		s._people[p.id] = p
		s._index_person(p)
	s._next_person_id = data.get("next_person_id", 1)
	s.fame = data.get("fame", 0.0)
	for fam: Dictionary in data.get("families", []):
		s._families[fam.id] = fam
		s._family_defaults(fam)
	for id in data.get("ancestry", {}):
		s._ancestry[id] = data.ancestry[id]
	s._chronicle.assign(data.get("chronicle", []))
	s._next_family_id = data.get("next_family_id", 1)
	for r: Array in data.get("relations", []):
		s._relations[Vector2i(r[0], r[1])] = r[2]
	for c in data.get("visited", []):
		s._visited[c] = true
	if data.get("version", -1) == GameConstants.WORLDGEN_VERSION:
		for c in data.get("removed", {}):
			s._removed[c] = data.removed[c]
	else:
		push_warning("WorldState: world generation changed, removed props reset")
	return s


# --- Creatures and packs -------------------------------------------------------------------

func add_creature(genome: Dictionary, pos: Vector3, pack_id: int, age := 1.0) -> Dictionary:
	var rec := {id = _next_creature_id, genome = genome, pos = pos, hp = float(genome.max_hp), age = age,
			pack_id = pack_id, hunger = 0.0}
	_next_creature_id += 1
	_creatures[rec.id] = rec
	_index_creature(rec)
	return rec


func remove_creature(id: int) -> Dictionary:
	if not _creatures.has(id):
		return {}
	var rec: Dictionary = _creatures[id]
	_creatures.erase(id)
	_unindex_creature(id)
	return rec


func creature(id: int) -> Dictionary:
	return _creatures.get(id, {})


func creatures_in(c: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in _creatures_by_chunk.get(c, PackedInt32Array()):
		if _creatures.has(id):
			out.append(_creatures[id])
	return out


func all_creatures() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_creatures.values())
	return out


## Updates a creature's position, moving it to another chunk's index when it crosses a border.
func move_creature(id: int, pos: Vector3) -> void:
	var rec: Dictionary = _creatures.get(id, {})
	if rec.is_empty():
		return
	rec.pos = pos
	if _creature_chunk.get(id) != ChunkMath.world_to_chunk(pos):
		_unindex_creature(id)
		_index_creature(rec)


func add_pack(species: String, den: Vector3) -> Dictionary:
	var p := {id = _next_pack_id, species = species, den = den, hunger = 0.0, territory = 0.0, grudge = 0.0,
			cubs_alarm = 0.0, leader_id = -1, raid_kingdom = -1, next_raid_hour = 0.0,
			territory_buildings = 0, territory_accepted = 0}
	_next_pack_id += 1
	_packs[p.id] = p
	return p


func pack(id: int) -> Dictionary:
	return _packs.get(id, {})


func all_packs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_packs.values())
	return out


func pack_members(pack_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rec: Dictionary in _creatures.values():
		if rec.pack_id == pack_id:
			out.append(rec)
	return out


func remove_pack(id: int) -> void:
	_packs.erase(id)


func visited(c: Vector2i) -> bool:
	return _visited.has(c)


func mark_visited(c: Vector2i) -> void:
	_visited[c] = true


func _index_creature(rec: Dictionary) -> void:
	var c := ChunkMath.world_to_chunk(rec.pos)
	var ids: PackedInt32Array = _creatures_by_chunk.get(c, PackedInt32Array())
	ids.append(rec.id)
	_creatures_by_chunk[c] = ids
	_creature_chunk[rec.id] = c


func _unindex_creature(id: int) -> void:
	if not _creature_chunk.has(id):
		return
	var c: Vector2i = _creature_chunk[id]
	_creature_chunk.erase(id)
	var ids: PackedInt32Array = _creatures_by_chunk.get(c, PackedInt32Array())
	var i := ids.find(id)
	if i >= 0:
		ids.remove_at(i)
		_creatures_by_chunk[c] = ids


# --- Building health -----------------------------------------------------------------------

func building_hp(id: int) -> float:
	var rec := building(id)
	if rec.is_empty():
		return 0.0
	return _building_hp.get(id, GameConstants.BUILD_HP[rec.type])


func is_seat(id: int) -> bool:
	return _kingdoms.any(func(k: Dictionary) -> bool: return k.seat_id == id)


## Returns true when the building was destroyed (and removed). The seat cabin stops at 1 hp.
func damage_building(id: int, amount: float) -> bool:
	if building(id).is_empty():
		return false
	var hp := building_hp(id) - amount
	if is_seat(id):
		_building_hp[id] = maxf(1.0, hp)
		return false
	if hp <= 0.0:
		_building_hp.erase(id)
		remove_building(id)
		return true
	_building_hp[id] = hp
	return false


# --- People ---------------------------------------------------------------------------------

## Adds a person made by PersonGen. `kingdom_id` -1 = nobody's yet (a traveler on the road).
func add_person(p: Dictionary, pos: Vector3, kingdom_id := -1, hour := 0.0) -> Dictionary:
	var rec := p.duplicate(true)
	rec.merge({id = _next_person_id, pos = pos, kingdom_id = kingdom_id, home_id = -1, inside = -1,
			hunger = 0.0, contentment = GameConstants.PERSON_START_CONTENTMENT, status = "traveler",
			unhappy_hours = 0.0, job = "", carrying = {}, arrived_hour = hour}, true)
	person_defaults(rec)
	_next_person_id += 1
	_people[rec.id] = rec
	_index_person(rec)
	return rec


func remove_person(id: int) -> Dictionary:
	if not _people.has(id):
		return {}
	var rec: Dictionary = _people[id]
	note_ancestry(rec)
	_people.erase(id)
	_unindex_person(id)
	var spouse: Dictionary = _people.get(int(rec.get("spouse_id", -1)), {})
	if not spouse.is_empty() and spouse.spouse_id == id:
		spouse.spouse_id = -1
		spouse.widowed = true
	for key in _relations.keys():
		if key.x == id or key.y == id:
			_relations.erase(key)
	return rec


## Fields added in stages 6 and 7 (records from older saves lack them). `parents` is never cleared: kinship
## still counts after a parent is gone.
static func person_defaults(p: Dictionary) -> void:
	var defaults := {family_id = -1, spouse_id = -1, parents = [], stance = "", last_birth_hour = -1e9,
			talk_day = -1, deed_day = -1, widowed = false,
			vocation = -1, desire = {kind = GameConstants.Desire.NONE, target_id = -1}, resentment = 0.0,
			secret = {}, adopted_by = [], deed = {}}
	for key in defaults:
		if not p.has(key):
			p[key] = defaults[key]


# --- Families and relations -----------------------------------------------------------------

## origin: "founded" (a newcomer), "branch" (left in peace), "rival" (broke away).
func add_family(surname: String, crest: Dictionary, kingdom_id: int, head_id: int, hour: float,
		parent_id := -1, origin := "founded") -> Dictionary:
	var f := {id = _next_family_id, surname = surname, crest = crest, kingdom_id = kingdom_id, head_id = head_id,
			founded_hour = hour, parent_id = parent_id, origin = origin, stance = "", deed_day = -1,
			last_split_hour = hour}
	_next_family_id += 1
	_families[f.id] = f
	_family_defaults(f)
	return f


func family(id: int) -> Dictionary:
	return _families.get(id, {})


func all_families() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_families.values())
	return out


func families_of(kingdom_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f: Dictionary in _families.values():
		if f.kingdom_id == kingdom_id:
			out.append(f)
	return out


## Residents of the family (people leaving are not members any more).
func family_members(id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in _people.values():
		if p.get("family_id", -1) == id and p.status == "resident":
			out.append(p)
	return out


func remove_family(id: int) -> void:
	_families.erase(id)


func relation(a: int, b: int) -> float:
	return _relations.get(_pair(a, b), 0.0)


func set_relation(a: int, b: int, v: float) -> void:
	if a == b:
		return
	_relations[_pair(a, b)] = clampf(v, -1.0, 1.0)


func add_relation(a: int, b: int, d: float) -> void:
	set_relation(a, b, relation(a, b) + d)


## Every relation of `id`: other person id -> value.
func relations_of(id: int) -> Dictionary:
	var out := {}
	for key: Vector2i in _relations:
		if key.x == id:
			out[key.y] = _relations[key]
		elif key.y == id:
			out[key.x] = _relations[key]
	return out


static func _pair(a: int, b: int) -> Vector2i:
	return Vector2i(mini(a, b), maxi(a, b))


func _relation_list() -> Array:
	var out := []
	for key: Vector2i in _relations:
		out.append([key.x, key.y, _relations[key]])
	return out


func person(id: int) -> Dictionary:
	return _people.get(id, {})


func all_people() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_people.values())
	return out


func people_in(c: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in _people_by_chunk.get(c, PackedInt32Array()):
		if _people.has(id):
			out.append(_people[id])
	return out


## People who live in the kingdom (travelers still deciding are not counted).
func residents(kingdom_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in _people.values():
		if p.kingdom_id == kingdom_id and p.status == "resident":
			out.append(p)
	return out


func move_person(id: int, pos: Vector3) -> void:
	var rec: Dictionary = _people.get(id, {})
	if rec.is_empty():
		return
	rec.pos = pos
	if _person_chunk.get(id) != ChunkMath.world_to_chunk(pos):
		_unindex_person(id)
		_index_person(rec)


func _index_person(rec: Dictionary) -> void:
	var c := ChunkMath.world_to_chunk(rec.pos)
	var ids: PackedInt32Array = _people_by_chunk.get(c, PackedInt32Array())
	ids.append(rec.id)
	_people_by_chunk[c] = ids
	_person_chunk[rec.id] = c


func _unindex_person(id: int) -> void:
	if not _person_chunk.has(id):
		return
	var c: Vector2i = _person_chunk[id]
	_person_chunk.erase(id)
	var ids: PackedInt32Array = _people_by_chunk.get(c, PackedInt32Array())
	var i := ids.find(id)
	if i >= 0:
		ids.remove_at(i)
		_people_by_chunk[c] = ids


# --- Kingdom stock and construction sites ---------------------------------------------------

func stock_of(k: Dictionary, res: int) -> int:
	return (k.stock as Dictionary).get(res, 0)


func add_stock(k: Dictionary, res: int, amount: int) -> void:
	k.stock[res] = stock_of(k, res) + amount


func can_afford_stock(k: Dictionary, cost: Dictionary) -> bool:
	for res in cost:
		if stock_of(k, res) < cost[res]:
			return false
	return true


## Spends the whole cost from the kingdom stock, or nothing when any resource is short.
func spend_stock(k: Dictionary, cost: Dictionary) -> bool:
	if not can_afford_stock(k, cost):
		return false
	for res in cost:
		k.stock[res] = stock_of(k, res) - cost[res]
	return true


## Opens the kingdom's construction site, paying (reserving) its cost from the stock now.
## Returns {} when the stock can't pay. The site already occupies its footprint.
func add_site(type: int, pos: Vector3, rot: int, k: Dictionary, hour: float) -> Dictionary:
	var cost: Dictionary = GameConstants.BUILD_COST[type]
	if not spend_stock(k, cost):
		return {}
	var rec := add_building(type, pos, rot, Color.WHITE, GameConstants.OWNER_KINGDOM)
	rec.merge({site = true, progress = 0.0, reserved = cost.duplicate(), kingdom_id = k.id,
			started_hour = hour, worked_hour = hour}, true)
	k.site_id = rec.id
	return rec


## Adds person-hours of work to a site. Returns true when this finished it (it becomes a normal
## building of the kingdom; the reserved cost is spent for good).
func add_progress(id: int, work_hours: float, hour: float) -> bool:
	var rec := building(id)
	if rec.is_empty() or not rec.get("site", false):
		return false
	rec.progress = minf(1.0, float(rec.progress) + work_hours / float(GameConstants.BUILD_WORK_HOURS[rec.type]))
	rec.worked_hour = hour
	if rec.progress < 1.0:
		return false
	var k := kingdom(rec.kingdom_id)
	if not k.is_empty() and k.site_id == id:
		k.site_id = -1
	for key in ["site", "progress", "reserved", "started_hour", "worked_hour"]:
		rec.erase(key)
	return true


# --- Houses (stage 7): defaults, ancestry, chronicle ----------------------------------------

## Fields a House gets in stage 7 (also fills families from older saves). The tradition follows
## the head's trade when there is one.
func _family_defaults(f: Dictionary) -> void:
	if not f.has("tradition"):
		var head := person(int(f.get("head_id", -1)))
		f.tradition = tradition_of_profession(int(head.get("profession", -1)))
	if not f.has("values"):
		f.values = (GameConstants.TRADITION_VALUES[f.tradition] as Dictionary).duplicate()
	var defaults := {wealth = 0.0, plots = [], skill = {}, prestige = 0.0, goal = {}, rival_id = -1, secrets = [],
			dishonor = 0.0, insulted_by = -1,
			known_secrets = [], claim = Rect2()}
	for key in defaults:
		if not f.has(key):
			f[key] = defaults[key].duplicate() if defaults[key] is Array or defaults[key] is Dictionary else defaults[key]


## The tradition whose expected trades include `profession` (FOREST when none does).
static func tradition_of_profession(profession: int) -> int:
	for t in GameConstants.TRADITION_PROFESSIONS:
		if (GameConstants.TRADITION_PROFESSIONS[t] as Array).has(profession):
			return t
	return GameConstants.Tradition.FOREST


## Remembers who someone's parents are, so kinship survives deaths and departures.
func note_ancestry(p: Dictionary) -> void:
	_ancestry[p.id] = {parents = (p.get("parents", []) as Array).duplicate(),
			adopted_by = (p.get("adopted_by", []) as Array).duplicate(), name = p.get("name", ""),
			female = p.get("female", false)}


## A living person's record, or what is remembered of someone gone ({} if unknown).
func ancestry(id: int) -> Dictionary:
	var p := person(id)
	if not p.is_empty():
		return p
	return _ancestry.get(id, {})


func chronicle_add(hour: float, text: String, kingdom_id: int, public := true) -> void:
	var entry := {hour = hour, text = text, kingdom_id = kingdom_id, public = public}
	_chronicle.append(entry)
	chronicled.emit(entry)
	var count := 0
	for e: Dictionary in _chronicle:
		if e.kingdom_id == kingdom_id:
			count += 1
	if count > GameConstants.CHRONICLE_MAX:
		for i in _chronicle.size():
			if _chronicle[i].kingdom_id == kingdom_id:
				_chronicle.remove_at(i)
				break


## The last `n` public entries of a kingdom, oldest first.
func chronicle(kingdom_id: int, n: int) -> Array:
	var out := _chronicle.filter(func(e: Dictionary) -> bool: return e.kingdom_id == kingdom_id and e.public)
	return out.slice(maxi(0, out.size() - n))


## The last `n` entries of a kingdom, secrets included (the ADM view), oldest first. -2: every kingdom.
func chronicle_all(kingdom_id: int, n: int) -> Array:
	var out := _chronicle.filter(func(e: Dictionary) -> bool: return kingdom_id == -2 or e.kingdom_id == kingdom_id)
	return out.slice(maxi(0, out.size() - n))
