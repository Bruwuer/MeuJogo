class_name SaveSlots
extends RefCounted
## The three save slots (stage 12): file paths, a small summary written after each good save
## (kingdom, day, when), clearing a slot for a new game, and moving the old single save into slot 1.

var dir: String


func _init(base_dir := "user://") -> void:
	dir = base_dir


func path(i: int) -> String:
	return dir + "save_%d.bin" % i


func summary_path(i: int) -> String:
	return path(i) + ".meta"


func legacy_path() -> String:
	return dir + "save.bin"


## A game is saved in slot `i` (the save, or what the safe save left behind).
func used(i: int) -> bool:
	return WorldState.any_file_exists(path(i))


## The slot whose save path is `save_path` (0 when none).
func slot_of(save_path: String) -> int:
	for i in range(1, GameConstants.SAVE_SLOTS + 1):
		if path(i) == save_path:
			return i
	return 0


## Writes the summary of slot `i` (through a .tmp, then swapped in) after a good save.
func write_summary(i: int, state: WorldState, unix: int) -> void:
	var kingdom := ""
	for k in state.kingdoms():
		if String(k.get("founder", "player")) == "player":
			kingdom = k.name
			break
	var cfg := ConfigFile.new()
	cfg.set_value("save", "kingdom", kingdom)
	cfg.set_value("save", "day", state.day)
	cfg.set_value("save", "saved_unix", unix)
	var tmp := summary_path(i) + ".tmp"
	if cfg.save(tmp) != OK:
		return
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(summary_path(i)))


## {kingdom, day, saved_unix} of slot `i` ({} when there is no summary).
func summary(i: int) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(summary_path(i)) != OK:
		return {}
	return {kingdom = cfg.get_value("save", "kingdom", ""), day = cfg.get_value("save", "day", 1),
			saved_unix = cfg.get_value("save", "saved_unix", 0)}


## "Espaço 1 · Reino de Valdemar, dia 7 · 25/10 03:10", or the empty slot's text.
func label(i: int) -> String:
	if not used(i):
		return GameConstants.SLOT_EMPTY
	var m := summary(i)
	if m.is_empty():
		return GameConstants.SLOT_SAVED
	var when := Time.get_datetime_dict_from_unix_time(int(m.saved_unix))
	var where: String = GameConstants.SLOT_KINGDOM % m.kingdom if String(m.kingdom) != "" else GameConstants.SLOT_NO_KINGDOM
	return GameConstants.SLOT_LABEL % [where, int(m.day), when.day, when.month, when.hour, when.minute]


## The slot saved last (-1 when none is used).
func latest() -> int:
	var best := -1
	var best_time := -1
	for i in range(1, GameConstants.SAVE_SLOTS + 1):
		if not used(i):
			continue
		var t := int(summary(i).get("saved_unix", 0))
		if t > best_time:
			best = i
			best_time = t
	return best


## Removes every trace of slot `i` (a new game must not come back from a backup).
func clear(i: int) -> void:
	for p in [path(i), path(i) + ".bak", path(i) + ".tmp", path(i) + ".corrupt", summary_path(i), summary_path(i) + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


## The single save of older versions becomes slot 1 (with its backups), only if slot 1 is empty.
func migrate_legacy() -> void:
	if used(1) or not WorldState.any_file_exists(legacy_path()):
		return
	for ext: String in ["", ".bak", ".tmp"]:
		var from := legacy_path() + ext
		if FileAccess.file_exists(from):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(path(1) + ext))
