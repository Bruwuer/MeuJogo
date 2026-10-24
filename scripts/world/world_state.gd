class_name WorldState
extends RefCounted
## Everything that differs from the freshly generated world (delta persistence): removed props
## per chunk, resources, player position, time of day and the world seed.
## File layout: MAGIC | u32 payload length | 16-byte MD5 of payload | var_to_bytes(Dictionary).
## Saving goes through `.tmp` and keeps the previous save as `.bak` until the new one is in
## place; loading falls back to `.bak` and then `.tmp`, so an interrupted save never loses the world.

const MAGIC := "MJSV"
const _MD5_SIZE := 16
const _FALLBACK_SUFFIXES := ["", ".bak", ".tmp"]

var seed := 0
var time_of_day := GameConstants.START_TIME_OF_DAY
var day := 1
var player_position := Vector3.ZERO
var has_player_position := false

var _removed: Dictionary[Vector2i, PackedInt32Array] = {}
var _resources: Dictionary[int, int] = {}


func mark_removed(c: Vector2i, id: int) -> void:
	var ids: PackedInt32Array = _removed.get(c, PackedInt32Array())
	if not ids.has(id):
		ids.append(id)
	_removed[c] = ids


func removed_in(c: Vector2i) -> PackedInt32Array:
	return _removed.get(c, PackedInt32Array())


func add_resource(res: int, amount: int) -> void:
	_resources[res] = get_resource(res) + amount


func get_resource(res: int) -> int:
	return _resources.get(res, 0)


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
	if data.get("version", -1) == GameConstants.WORLDGEN_VERSION:
		for c in data.get("removed", {}):
			s._removed[c] = data.removed[c]
	else:
		push_warning("WorldState: world generation changed, removed props reset")
	return s
