class_name WorldState
extends RefCounted
## Everything that differs from the freshly generated world (delta persistence): removed props
## per chunk, resources, player position, time of day and the world seed. Saved as a small
## binary file: MAGIC header + store_var(Dictionary).

const MAGIC := "MJSV"

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


## Writes to `path + ".tmp"` first, then replaces `path`, so a crash never leaves half a save.
func save_to(path: String) -> Error:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(MAGIC.to_ascii_buffer())
	f.store_var({
		version = GameConstants.WORLDGEN_VERSION,
		seed = seed,
		time_of_day = time_of_day,
		day = day,
		player_position = player_position,
		has_player_position = has_player_position,
		removed = _removed,
		resources = _resources,
	})
	f.close()
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(abs_path)
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), abs_path)


## Returns null when the file is missing or not a save. On a WORLDGEN_VERSION mismatch the
## removed-prop list is dropped (ids would point at different props) and the rest is kept.
static func load_from(path: String) -> WorldState:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() <= MAGIC.length():
		return null
	if f.get_buffer(MAGIC.length()).get_string_from_ascii() != MAGIC:
		push_warning("WorldState: %s is not a save file" % path)
		return null
	var data: Variant = f.get_var()
	f.close()
	if not data is Dictionary:
		push_warning("WorldState: %s is unreadable" % path)
		return null
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
