class_name PauseMenu
extends CanvasLayer
## The pause menu (stage 12): Esc with nothing else using it. The whole tree pauses (this menu keeps
## running). Continue, Save, Options, Back to menu and Quit — the last two only after a good save.

var open_menu: Callable = func() -> void: get_tree().change_scene_to_file(GameConstants.MENU_SCENE)
var quit: Callable = func() -> void: get_tree().quit()
var settings_path := Settings.DEFAULT_PATH

var _world: World
var _hud: Hud
var _page := "main"
var _settings: Settings
var _root: Control
var _list: MenuList
var _message: Label


func setup(world: World, hud: Hud) -> void:
	_world = world
	_hud = hud


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 14)
	_root.add_child(box)
	var title := Label.new()
	title.text = GameConstants.PAUSE_TITLE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", GameConstants.MENU_TITLE_SIZE)
	box.add_child(title)
	_list = MenuList.new()
	box.add_child(_list)
	_message = Label.new()
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_message)


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_settings = Settings.load_from(settings_path)
	_message.text = ""
	_show("main")
	_root.visible = true
	get_tree().paused = true


func close() -> void:
	_root.visible = false
	get_tree().paused = false


func items() -> Array[String]:
	return _list.items()


func message_text() -> String:
	return _message.text


func select(i: int) -> void:
	_list.select(i)


## Esc: closes the options page, closes the menu, or opens it when nothing else uses Esc.
func on_esc() -> void:
	if is_open():
		if _page == "options":
			_show("main")
		else:
			close()
	elif _hud == null or _hud.esc_free():
		open()


func confirm() -> void:
	var item := items()[_list.selected]
	if _page == "options":
		match _settings.option_confirm(_list.selected):
			"back":
				_show("main")
			"changed":
				_options_changed()
		return
	match item:
		GameConstants.PAUSE_CONTINUE:
			close()
		GameConstants.PAUSE_SAVE:
			_message.text = GameConstants.PAUSE_SAVED if _save() else GameConstants.PAUSE_SAVE_FAILED
		GameConstants.MENU_OPTIONS:
			_show("options")
		GameConstants.PAUSE_TO_MENU:
			if _save():
				close()
				open_menu.call()
			else:
				_message.text = GameConstants.PAUSE_SAVE_FAILED
		GameConstants.PAUSE_QUIT:
			if _save():
				close()
				quit.call()
			else:
				_message.text = GameConstants.PAUSE_SAVE_FAILED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		var was_open := is_open()
		on_esc()
		if was_open or is_open():
			get_viewport().set_input_as_handled()
		return
	if not is_open():
		return
	if event.is_action_pressed("ui_up"):
		_list.move(-1)
	elif event.is_action_pressed("ui_down"):
		_list.move(1)
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		if _page == "options" and _settings.option_change(_list.selected, -1 if event.is_action_pressed("ui_left") else 1):
			_options_changed()
	elif event.is_action_pressed("ui_accept"):
		confirm()
	else:
		return
	var sound := get_tree().root.get_node_or_null("Sound")
	if sound and sound.has_method("ui"):
		sound.ui()
	get_viewport().set_input_as_handled()


func _save() -> bool:
	return _world != null and _world.save_now() == OK


func _show(page: String) -> void:
	_page = page
	_list.selected = 0
	if page == "options":
		_list.set_items(_settings.option_items())
	else:
		_list.set_items([GameConstants.PAUSE_CONTINUE, GameConstants.PAUSE_SAVE, GameConstants.MENU_OPTIONS,
				GameConstants.PAUSE_TO_MENU, GameConstants.PAUSE_QUIT])


func _options_changed() -> void:
	_settings.save_to(settings_path)
	_settings.apply(get_tree())
	var keep := _list.selected
	_list.set_items(_settings.option_items())
	_list.select(keep)
