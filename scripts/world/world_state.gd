class_name WorldState
extends RefCounted
## Everything that differs from the freshly generated world (delta persistence): removed props,
## buildings and kingdoms, resources, player position, time of day and the world seed.
## File layout: MAGIC | u32 payload length | 16-byte MD5 of payload | var_to_bytes(Dictionary).
## Saving goes through `.tmp` and keeps the previous save as `.bak` until the new one is in
## place; loading falls back to `.bak` and then `.tmp`, so an interrupted save never loses the world.

const MAGIC := "MJSV"
const _MD5_SIZE := 16
const _FALLBACK_SUFFIXES := ["", ".bak", ".tmp"]

signal resources_changed

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


func add_building(type: int, pos: Vector3, rot: int, color := Color.WHITE) -> Dictionary:
	var rec := {id = _next_building_id, type = type, pos = pos, rot = rot, color = color}
	_next_building_id += 1
	_buildings[rec.id] = rec
	_index_building(rec)
	return rec


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
			radius = GameConstants.KINGDOM_RADIUS, seat_id = seat_id}
	_kingdoms.append(k)
	return k


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
		s._buildings[rec.id] = rec
		s._index_building(rec)
	s._kingdoms.assign(data.get("kingdoms", []))
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
			cubs_alarm = 0.0, leader_id = -1, raid_kingdom = -1, next_raid_hour = 0.0}
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
