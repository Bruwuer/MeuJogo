class_name Settings
extends RefCounted
## Player options kept outside the world save (stage 12): music and effects volume, music on/off.

const DEFAULT_PATH := "user://settings.cfg"

var music_volume := 0.7
var sfx_volume := 0.8
var music_on := true


static func load_from(path := DEFAULT_PATH) -> Settings:
	var s := Settings.new()
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		s.music_volume = clampf(float(cfg.get_value("sound", "music_volume", s.music_volume)), 0.0, 1.0)
		s.sfx_volume = clampf(float(cfg.get_value("sound", "sfx_volume", s.sfx_volume)), 0.0, 1.0)
		s.music_on = bool(cfg.get_value("sound", "music_on", s.music_on))
	return s


func save_to(path := DEFAULT_PATH) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("sound", "music_volume", music_volume)
	cfg.set_value("sound", "sfx_volume", sfx_volume)
	cfg.set_value("sound", "music_on", music_on)
	return cfg.save(path)


# --- The options page, shared by the start menu and the pause menu ---

func option_items() -> Array[String]:
	return [GameConstants.OPT_MUSIC_VOLUME % roundi(music_volume * 100.0),
			GameConstants.OPT_SFX_VOLUME % roundi(sfx_volume * 100.0),
			GameConstants.OPT_MUSIC_ON if music_on else GameConstants.OPT_MUSIC_OFF, GameConstants.MENU_BACK]


## Left/right on row `row`. True when something changed.
func option_change(row: int, d: int) -> bool:
	match row:
		0:
			music_volume = snappedf(clampf(music_volume + d * GameConstants.OPT_STEP, 0.0, 1.0), 0.01)
		1:
			sfx_volume = snappedf(clampf(sfx_volume + d * GameConstants.OPT_STEP, 0.0, 1.0), 0.01)
		2:
			music_on = not music_on
		_:
			return false
	return true


## Enter on row `row`: "back" (leave the page), "changed" or "".
func option_confirm(row: int) -> String:
	if row == 3:
		return "back"
	if row == 2:
		music_on = not music_on
		return "changed"
	return ""


## Tells the Sound autoload (when there is one) to use these options.
func apply(tree: SceneTree) -> void:
	var sound := tree.root.get_node_or_null("Sound")
	if sound and sound.has_method("apply_settings"):
		sound.apply_settings(self)
