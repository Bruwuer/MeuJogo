class_name MenuList
extends VBoxContainer
## A keyboard list for the menus: one Label per item, the selected one marked and brighter.

const _ON := Color(1.0, 0.92, 0.6)
const _OFF := Color(0.85, 0.85, 0.85)

var selected := 0
var _items: Array[String] = []


func set_items(items: Array[String]) -> void:
	_items = items
	selected = clampi(selected, 0, maxi(0, items.size() - 1))
	_render()


func items() -> Array[String]:
	return _items


func select(i: int) -> void:
	selected = clampi(i, 0, maxi(0, _items.size() - 1))
	_render()


func move(d: int) -> void:
	if _items.is_empty():
		return
	selected = posmod(selected + d, _items.size())
	_render()


func _render() -> void:
	while get_child_count() > _items.size():
		var c := get_child(get_child_count() - 1)
		remove_child(c)
		c.queue_free()
	while get_child_count() < _items.size():
		var l := Label.new()
		l.add_theme_font_size_override("font_size", GameConstants.MENU_FONT_SIZE)
		l.add_theme_constant_override("outline_size", 6)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(l)
	for i in _items.size():
		var l := get_child(i) as Label
		l.text = ("›  %s  ‹" if i == selected else "%s") % _items[i]
		l.add_theme_color_override("font_color", _ON if i == selected else _OFF)
