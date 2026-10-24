class_name Hud
extends CanvasLayer
## On-screen info: resource counters (top-left), clock (top-right), kingdom name (top-center),
## harvest prompt or build line + block reason (bottom-center), key hint (bottom-left) and a
## centered toast for big moments. Text is Portuguese and outlined so it reads at night.

const _FONT_SIZE := 22
const _TOAST_FONT_SIZE := 34
const _OUTLINE := 6
const _MARGIN := 16.0
const _PROMPT_BOTTOM := 90.0
const _BUILD_BOTTOM := 130.0
const _WIDE := 520.0
const _REASON_COLOR := Color(1.0, 0.45, 0.4)
const _MESSAGE_COLOR := Color(1.0, 0.88, 0.6)
const _MAX_MESSAGES := 4
const _MESSAGE_SEC := 8.0
const _CARD_WIDTH := 440.0
const _CARD_COLOR := Color(0.1, 0.08, 0.06, 0.82)
const _CARD_CREST_SCALE := 2.0
const _ROW_CREST_SCALE := 1.0
const _FAMILIES_WIDTH := 560.0

var _state: WorldState
var _harvest: HarvestSystem
var _day_night: DayNight
var _player: Node3D
var _build: BuildSystem
var _resources: Label
var _prompt: Label
var _clock: Label
var _kingdom: Label
var _build_line: Label
var _reason: Label
var _hint: Label
var _toast: Label
var _toast_left := 0.0
var _health: Label
var _weapon: Label
var _messages: Label
var _message_list: Array = [] # [text, seconds left], oldest first
var _people: PeopleManager
var _village: Label
var _card: PanelContainer
var _card_label: Label
var _card_left := 0.0
var _card_crest: TextureRect
var _families: PanelContainer
var _families_box: VBoxContainer
var _families_left := 0.0


func setup(state: WorldState, harvest: HarvestSystem, day_night: DayNight, player: Node3D,
		build: BuildSystem = null) -> void:
	_state = state
	_harvest = harvest
	_day_night = day_night
	_player = player
	_build = build
	_resources = _make_label("Resources", Control.PRESET_TOP_LEFT, HORIZONTAL_ALIGNMENT_LEFT)
	_resources.position = Vector2(_MARGIN, _MARGIN)
	_clock = _make_label("Clock", Control.PRESET_TOP_RIGHT, HORIZONTAL_ALIGNMENT_RIGHT)
	_clock.offset_left = -320.0
	_clock.offset_right = -_MARGIN
	_clock.offset_top = _MARGIN
	_kingdom = _make_label("Kingdom", Control.PRESET_CENTER_TOP, HORIZONTAL_ALIGNMENT_CENTER)
	_center_h(_kingdom, _WIDE)
	_kingdom.offset_top = _MARGIN
	_kingdom.visible = false
	_village = _make_label("Village", Control.PRESET_CENTER_TOP, HORIZONTAL_ALIGNMENT_CENTER)
	_center_h(_village, _WIDE * 2.0)
	_village.offset_top = _MARGIN + _FONT_SIZE * 1.5
	_village.visible = false
	_card = PanelContainer.new()
	_card.name = "Card"
	_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_card.offset_left = -_CARD_WIDTH - _MARGIN
	_card.offset_right = -_MARGIN
	_card.grow_vertical = Control.GROW_DIRECTION_BOTH # long cards stay on screen
	_card.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = _CARD_COLOR
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	_card.add_theme_stylebox_override("panel", style)
	_card_label = Label.new()
	_card_label.add_theme_font_size_override("font_size", _FONT_SIZE - 2)
	_card_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_card_crest = _crest_rect(_CARD_CREST_SCALE)
	row.add_child(_card_crest)
	_card_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_card_label)
	_card.add_child(row)
	add_child(_card)
	_make_families_panel(style)
	_prompt = _make_label("Prompt", Control.PRESET_CENTER_BOTTOM, HORIZONTAL_ALIGNMENT_CENTER)
	_center_h(_prompt, 400.0)
	_prompt.offset_top = -_PROMPT_BOTTOM
	_prompt.visible = false
	_build_line = _make_label("Build", Control.PRESET_CENTER_BOTTOM, HORIZONTAL_ALIGNMENT_CENTER)
	_center_h(_build_line, _WIDE * 2.0)
	_build_line.offset_top = -_BUILD_BOTTOM
	_build_line.visible = false
	_reason = _make_label("BuildReason", Control.PRESET_CENTER_BOTTOM, HORIZONTAL_ALIGNMENT_CENTER)
	_center_h(_reason, _WIDE)
	_reason.offset_top = -_PROMPT_BOTTOM
	_reason.add_theme_color_override("font_color", _REASON_COLOR)
	_reason.visible = false
	_hint = _make_label("Hint", Control.PRESET_BOTTOM_LEFT, HORIZONTAL_ALIGNMENT_LEFT)
	_hint.offset_left = _MARGIN
	_hint.offset_top = -_MARGIN - _FONT_SIZE * 1.5
	_hint.text = "E fala · G doa · C famílias · B construir · X demolir · Espaço ataca · H come · F flechas"
	_toast = _make_label("Toast", Control.PRESET_CENTER, HORIZONTAL_ALIGNMENT_CENTER)
	_toast.add_theme_font_size_override("font_size", _TOAST_FONT_SIZE)
	_center_h(_toast, _WIDE * 2.0)
	_toast.offset_top = -120.0
	_toast.visible = false
	_health = _make_label("Health", Control.PRESET_TOP_LEFT, HORIZONTAL_ALIGNMENT_LEFT)
	_health.position = Vector2(_MARGIN, _MARGIN + _FONT_SIZE * 1.5)
	_weapon = _make_label("Weapon", Control.PRESET_TOP_LEFT, HORIZONTAL_ALIGNMENT_LEFT)
	_weapon.position = Vector2(_MARGIN, _MARGIN + _FONT_SIZE * 3.0)
	_messages = _make_label("Messages", Control.PRESET_TOP_LEFT, HORIZONTAL_ALIGNMENT_LEFT)
	_messages.position = Vector2(_MARGIN, _MARGIN + _FONT_SIZE * 5.0)
	_messages.add_theme_color_override("font_color", _MESSAGE_COLOR)
	if _player.has_signal("message"):
		_player.message.connect(add_message)
	_state.resources_changed.connect(_refresh_resources)
	if _build:
		_build.kingdom_founded.connect(_on_kingdom_founded)
	_refresh_resources()


func resources_text() -> String:
	return "%s: %d   %s: %d   %s: %d" % [
		GameConstants.RES_NAMES[GameConstants.Res.WOOD], _state.get_resource(GameConstants.Res.WOOD),
		GameConstants.RES_NAMES[GameConstants.Res.STONE], _state.get_resource(GameConstants.Res.STONE),
		GameConstants.RES_NAMES[GameConstants.Res.BERRIES], _state.get_resource(GameConstants.Res.BERRIES),
	]


static func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for res in cost:
		parts.append("%d %s" % [cost[res], (GameConstants.RES_NAMES[res] as String).to_lower()])
	return ", ".join(parts)


func _physics_process(delta: float) -> void:
	if _state == null:
		return
	_clock.text = _day_night.clock_text()
	var kingdom := _state.kingdom_at(_player.global_position)
	_kingdom.visible = not kingdom.is_empty()
	if _kingdom.visible:
		_kingdom.text = "Reino de %s" % kingdom.name
		_village.text = village_line(kingdom)
	_village.visible = _kingdom.visible
	_update_families(delta, kingdom)
	if _card_left > 0.0:
		_card_left -= delta
		_card.visible = _card_left > 0.0
	if _toast_left > 0.0:
		_toast_left -= delta
		_toast.visible = _toast_left > 0.0
	_update_combat(delta)

	var building := _build != null and _build.active
	_build_line.visible = building
	_hint.visible = not building
	if building:
		_prompt.visible = false
		_build_line.text = "Construindo: %s — %s · R gira · Clique constrói · Esc sai" % [
			GameConstants.BUILD_NAMES[_build.type], cost_text(GameConstants.BUILD_COST[_build.type])]
		var check := _build.preview()
		_reason.visible = not check.ok
		_reason.text = check.reason
		return
	_reason.visible = false
	var person: Person = _people.nearest_person(_player.global_position, GameConstants.TALK_RANGE) if _people else null
	if person:
		_prompt.visible = true
		_prompt.text = GameConstants.TALK_PROMPT % person.record.name
		return
	var target := _harvest.find_target(_player.global_position)
	_prompt.visible = not target.is_empty()
	if _prompt.visible:
		_prompt.text = GameConstants.HARVEST_PROMPTS[target.prop.type]


## Villagers: the talk prompt, the card and the kingdom line use them.
func set_people(people: PeopleManager) -> void:
	_people = people
	if _player.has_signal("talked"):
		_player.talked.connect(func(n: Node3D) -> void: show_card((n as Person).record))


## "Moradores: 5 · Estoque: Madeira 12, Pedra 3, Comida 8, Frutas 4".
func village_line(kingdom: Dictionary) -> String:
	var parts: PackedStringArray = []
	for res in [GameConstants.Res.WOOD, GameConstants.Res.STONE, GameConstants.Res.FOOD, GameConstants.Res.BERRIES]:
		parts.append("%s %d" % [GameConstants.RES_NAMES[res], _state.stock_of(kingdom, res)])
	return GameConstants.VILLAGE_LINE % [_state.residents(kingdom.id).size(), _state.families_of(kingdom.id).size(),
			", ".join(parts)]


func show_card(rec: Dictionary) -> void:
	_card_label.text = PeopleManager.card_text(rec, _state)
	var fam := _state.family(int(rec.get("family_id", -1)))
	_card_crest.texture = Crest.texture(fam.crest) if not fam.is_empty() else null
	_card_crest.visible = _card_crest.texture != null
	_card.visible = true
	_card_left = GameConstants.PERSON_CARD_SEC


func card_visible() -> bool:
	return _card.visible


func card_text() -> String:
	return _card_label.text


func village_visible() -> bool:
	return _village.visible


func village_text() -> String:
	return _village.text


func prompt_text() -> String:
	return _prompt.text if _prompt.visible else ""


## Shows a line (raids, destroyed buildings, deaths) for a few seconds; keeps the last four.
func add_message(text: String) -> void:
	_message_list = _message_list.filter(func(m: Array) -> bool: return m[0] != text) # repeats refresh
	_message_list.append([text, _MESSAGE_SEC])
	while _message_list.size() > _MAX_MESSAGES:
		_message_list.pop_front()
	_messages.text = messages_text()


func messages_text() -> String:
	return "\n".join(PackedStringArray(_message_list.map(func(m: Array) -> String: return m[0])))


func _update_combat(delta: float) -> void:
	var p := _player as Player
	if p:
		_health.text = "Vida: %d/%d" % [ceili(p.health.hp), roundi(p.health.max_hp)]
		_weapon.text = "%s · Q troca · Flechas: %d" % [GameConstants.WEAPONS[p.weapon].name,
				_state.get_resource(GameConstants.Res.ARROWS)]
	var before := _message_list.size()
	for m: Array in _message_list:
		m[1] -= delta
	_message_list = _message_list.filter(func(m: Array) -> bool: return m[1] > 0.0)
	if _message_list.size() != before:
		_messages.text = messages_text()


func _on_kingdom_founded(kingdom: Dictionary) -> void:
	_toast.text = "Você fundou o Reino de %s!" % kingdom.name
	_toast.visible = true
	_toast_left = GameConstants.FOUNDING_TOAST_SEC


func _refresh_resources() -> void:
	_resources.text = resources_text()


func _center_h(label: Label, width: float) -> void:
	label.offset_left = -width * 0.5
	label.offset_right = width * 0.5


func _make_label(node_name: String, preset: Control.LayoutPreset, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.name = node_name
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", _FONT_SIZE)
	label.add_theme_constant_override("outline_size", _OUTLINE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.set_anchors_and_offsets_preset(preset)
	add_child(label)
	return label


func card_crest() -> Texture2D:
	return _card_crest.texture if _card_crest.visible else null


## A crest icon: the 32 x 40 image scaled up without blurring.
func _crest_rect(scale: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = "Crest"
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.custom_minimum_size = Vector2(GameConstants.CREST_SIZE) * scale
	rect.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return rect


# --- Families panel (C) ---------------------------------------------------------------------

func _make_families_panel(style: StyleBox) -> void:
	_families = PanelContainer.new()
	_families.name = "Families"
	_families.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_families.offset_left = _MARGIN
	_families.offset_right = _MARGIN + _FAMILIES_WIDTH
	_families.offset_top = -160.0
	_families.add_theme_stylebox_override("panel", style)
	_families.visible = false
	_families_box = VBoxContainer.new()
	_families_box.add_theme_constant_override("separation", 6)
	_families.add_child(_families_box)
	add_child(_families)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("families"):
		toggle_families()


## Opens the list of the families of the kingdom the player is in (or closes it).
func toggle_families() -> void:
	if _families.visible:
		_families.visible = false
		return
	var k := _state.kingdom_at(_player.global_position)
	if k.is_empty():
		return
	_fill_families(k)
	_families.visible = true
	_families_left = GameConstants.FAMILIES_REFRESH_SEC


func families_visible() -> bool:
	return _families.visible


func families_rows() -> int:
	return maxi(0, _families_box.get_child_count() - 1)


func families_text() -> String:
	var lines: PackedStringArray = []
	for label: Label in _families_box.find_children("*", "Label", true, false):
		lines.append(label.text)
	return "\n".join(lines)


func _update_families(delta: float, kingdom: Dictionary) -> void:
	if not _families.visible:
		return
	if kingdom.is_empty():
		_families.visible = false
		return
	_families_left -= delta
	if _families_left <= 0.0:
		_families_left = GameConstants.FAMILIES_REFRESH_SEC
		_fill_families(kingdom)


func _fill_families(k: Dictionary) -> void:
	for c in _families_box.get_children():
		_families_box.remove_child(c)
		c.queue_free()
	var title := Label.new()
	title.text = GameConstants.FAMILIES_TITLE % k.name
	title.add_theme_font_size_override("font_size", _FONT_SIZE)
	_families_box.add_child(title)
	var rows := PeopleManager.family_rows(_state, k)
	if rows.is_empty():
		title.text += "\n" + GameConstants.FAMILIES_EMPTY
	for r in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var icon := _crest_rect(_ROW_CREST_SCALE)
		icon.texture = Crest.texture(r.crest)
		row.add_child(icon)
		var label := Label.new()
		label.text = r.text
		label.add_theme_font_size_override("font_size", _FONT_SIZE - 4)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(label)
		_families_box.add_child(row)


func card_rect() -> Rect2:
	return _card.get_global_rect()


func hide_card() -> void:
	_card_left = 0.0
	_card.visible = false
