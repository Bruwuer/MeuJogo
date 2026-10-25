class_name MainMenu
extends Control
## The start menu (stage 12), keyboard only: Continue (the slot saved last), New game (pick a slot;
## a used one asks first and is cleared), Load (the saved slots), Options, Quit. Esc goes back.

## Save slots (tests point it at their own folder) and the options file.
var slots := SaveSlots.new()
var settings_path := Settings.DEFAULT_PATH
## Opens the world in `slot` (tests replace it; Session.slot is already set).
var open_world: Callable = func(_slot: int) -> void: get_tree().change_scene_to_file(GameConstants.WORLD_SCENE)
var quit: Callable = func() -> void: get_tree().quit()

var _page := "main"
var _confirm_slot := 0
var _settings: Settings
var _title: Label
var _list: MenuList


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slots.migrate_legacy()
	_settings = Settings.load_from(settings_path)
	_settings.apply(get_tree())
	var bg := ColorRect.new()
	bg.color = GameConstants.MENU_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	var center := CenterContainer.new() # keeps the menu in the middle whatever its size
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	center.add_child(box)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", GameConstants.MENU_TITLE_SIZE)
	box.add_child(_title)
	_list = MenuList.new()
	_list.add_theme_constant_override("separation", 8)
	box.add_child(_list)
	var hint := Label.new()
	hint.text = GameConstants.MENU_HINT
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.6)
	box.add_child(hint)
	_show("main")


func items() -> Array[String]:
	return _list.items()


func title_text() -> String:
	return _title.text


func select(i: int) -> void:
	_list.select(i)


func change(d: int) -> void:
	if _page == "options" and _settings.option_change(_list.selected, d):
		_options_changed()


func back() -> void:
	match _page:
		"main":
			pass
		"confirm":
			_show("new")
		_:
			_show("main")


func confirm() -> void:
	var item := items()[_list.selected] if not items().is_empty() else ""
	if item == GameConstants.MENU_BACK:
		back()
		return
	match _page:
		"main":
			match item:
				GameConstants.MENU_CONTINUE:
					_open(slots.latest())
				GameConstants.MENU_NEW:
					_show("new")
				GameConstants.MENU_LOAD:
					_show("load")
				GameConstants.MENU_OPTIONS:
					_show("options")
				GameConstants.MENU_QUIT:
					quit.call()
		"new":
			var slot := _list.selected + 1
			if slots.used(slot):
				_confirm_slot = slot
				_show("confirm")
			else:
				slots.clear(slot)
				_open(slot)
		"confirm":
			if item == GameConstants.MENU_YES:
				slots.clear(_confirm_slot)
				_open(_confirm_slot)
			else:
				_show("new")
		"load":
			_open(_used_slots()[_list.selected])
		"options":
			if _settings.option_confirm(_list.selected) == "changed":
				_options_changed()


func _unhandled_input(event: InputEvent) -> void:
	var handled := true
	if event.is_action_pressed("ui_up"):
		_list.move(-1)
	elif event.is_action_pressed("ui_down"):
		_list.move(1)
	elif event.is_action_pressed("ui_left"):
		change(-1)
	elif event.is_action_pressed("ui_right"):
		change(1)
	elif event.is_action_pressed("ui_accept"):
		confirm()
	elif event.is_action_pressed("ui_cancel"):
		back()
	else:
		handled = false
	if handled:
		_click()
		get_viewport().set_input_as_handled()


func _show(page: String) -> void:
	_page = page
	_list.selected = 0
	var list: Array[String] = []
	match page:
		"main":
			_title.text = GameConstants.MENU_TITLE
			var any := not _used_slots().is_empty()
			if any:
				list.append(GameConstants.MENU_CONTINUE)
			list.append(GameConstants.MENU_NEW)
			if any:
				list.append(GameConstants.MENU_LOAD)
			list.append_array([GameConstants.MENU_OPTIONS, GameConstants.MENU_QUIT])
		"new":
			_title.text = GameConstants.MENU_PICK_NEW
			for i in range(1, GameConstants.SAVE_SLOTS + 1):
				list.append(GameConstants.MENU_SLOT % [i, slots.label(i)])
			list.append(GameConstants.MENU_BACK)
		"confirm":
			_title.text = GameConstants.MENU_CONFIRM_NEW % _confirm_slot
			list.append_array([GameConstants.MENU_NO, GameConstants.MENU_YES])
		"load":
			_title.text = GameConstants.MENU_PICK_LOAD
			for i in _used_slots():
				list.append(GameConstants.MENU_SLOT % [i, slots.label(i)])
			list.append(GameConstants.MENU_BACK)
		"options":
			_title.text = GameConstants.MENU_OPTIONS
			list = _settings.option_items()
	_list.set_items(list)


func _used_slots() -> Array[int]:
	var out: Array[int] = []
	for i in range(1, GameConstants.SAVE_SLOTS + 1):
		if slots.used(i):
			out.append(i)
	return out


func _open(slot: int) -> void:
	if slot < 1:
		return
	var session := get_tree().root.get_node_or_null("Session")
	if session:
		session.slot = slot
	open_world.call(slot)


func _options_changed() -> void:
	_settings.save_to(settings_path)
	_settings.apply(get_tree())
	var keep := _list.selected
	_list.set_items(_settings.option_items())
	_list.select(keep)


func _click() -> void:
	var sound := get_tree().root.get_node_or_null("Sound")
	if sound and sound.has_method("ui"):
		sound.ui()
