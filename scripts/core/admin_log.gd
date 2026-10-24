class_name AdminLog
extends Node
## The ADM log: every chronicle entry (secrets included) appended to a text file as it happens.
## The player never sees it; the dev panels (F9/F10) read the same chronicle in game.

const DEFAULT_PATH := "user://adm_log.txt"

var _state: WorldState
var _path := DEFAULT_PATH


func setup(state: WorldState, path := DEFAULT_PATH) -> void:
	_state = state
	_path = path
	state.chronicled.connect(_write)


## "Dia 3, 9h — [Ravmia] [segredo] Martim fugiu" (game hours already count from day 1).
static func line(state: WorldState, e: Dictionary) -> String:
	var h := float(e.hour)
	var out := "Dia %d, %dh — " % [floori(h / 24.0), floori(fmod(h, 24.0))]
	var k := state.kingdom(int(e.kingdom_id)) if int(e.kingdom_id) >= 0 else {}
	if not k.is_empty():
		out += "[%s] " % k.name
	if not e.get("public", true):
		out += "[segredo] "
	return out + String(e.text)


func _write(e: Dictionary) -> void:
	if _path.is_empty():
		return
	var f := FileAccess.open(_path, FileAccess.READ_WRITE if FileAccess.file_exists(_path) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(line(_state, e))
