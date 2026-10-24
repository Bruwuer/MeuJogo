class_name Hud
extends CanvasLayer
## On-screen info: resource counters (top-left), clock (top-right) and the harvest prompt
## (bottom-center). Text is Portuguese and outlined so it reads on grass and at night.

const _FONT_SIZE := 22
const _OUTLINE := 6
const _MARGIN := 16.0
const _PROMPT_BOTTOM := 90.0

var _state: WorldState
var _harvest: HarvestSystem
var _day_night: DayNight
var _player: Node3D
var _resources: Label
var _prompt: Label
var _clock: Label


func setup(state: WorldState, harvest: HarvestSystem, day_night: DayNight, player: Node3D) -> void:
	_state = state
	_harvest = harvest
	_day_night = day_night
	_player = player
	_resources = _make_label("Resources", Control.PRESET_TOP_LEFT, HORIZONTAL_ALIGNMENT_LEFT)
	_resources.position = Vector2(_MARGIN, _MARGIN)
	_clock = _make_label("Clock", Control.PRESET_TOP_RIGHT, HORIZONTAL_ALIGNMENT_RIGHT)
	_clock.offset_left = -320.0
	_clock.offset_right = -_MARGIN
	_clock.offset_top = _MARGIN
	_prompt = _make_label("Prompt", Control.PRESET_CENTER_BOTTOM, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt.offset_left = -200.0
	_prompt.offset_right = 200.0
	_prompt.offset_top = -_PROMPT_BOTTOM
	_prompt.visible = false
	_harvest.resources_changed.connect(_refresh_resources)
	_refresh_resources()


func resources_text() -> String:
	return "%s: %d   %s: %d   %s: %d" % [
		GameConstants.RES_NAMES[GameConstants.Res.WOOD], _state.get_resource(GameConstants.Res.WOOD),
		GameConstants.RES_NAMES[GameConstants.Res.STONE], _state.get_resource(GameConstants.Res.STONE),
		GameConstants.RES_NAMES[GameConstants.Res.BERRIES], _state.get_resource(GameConstants.Res.BERRIES),
	]


func _physics_process(_delta: float) -> void:
	if _state == null:
		return
	_clock.text = _day_night.clock_text()
	var target := _harvest.find_target(_player.global_position)
	_prompt.visible = not target.is_empty()
	if _prompt.visible:
		_prompt.text = GameConstants.HARVEST_PROMPTS[target.prop.type]


func _refresh_resources() -> void:
	_resources.text = resources_text()


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
