## Zone qui accepte une carte glissée : une case du Script (slot >= 0) ou la main (slot = -1).
## La décision est déléguée à l'écran de combat via deux Callables.
class_name DropZone
extends PanelContainer

var slot := -1
var can_drop_fn: Callable   # func(data: Dictionary, slot: int) -> bool
var drop_fn: Callable       # func(data: Dictionary, slot: int) -> void
var _hover := false
var _base_style: StyleBoxFlat
var _hover_style: StyleBoxFlat


func setup(slot_index: int, can_drop: Callable, on_drop: Callable, base: StyleBoxFlat, hover: StyleBoxFlat) -> DropZone:
	slot = slot_index
	can_drop_fn = can_drop
	drop_fn = on_drop
	_base_style = base
	_hover_style = hover
	add_theme_stylebox_override("panel", base)
	mouse_filter = Control.MOUSE_FILTER_STOP
	return self


func _can_drop_data(_at_position: Vector2, data) -> bool:
	var ok: bool = typeof(data) == TYPE_DICTIONARY and data.get("kind", "") == "card" and can_drop_fn.call(data, slot)
	_set_hover(ok)
	return ok


func _drop_data(_at_position: Vector2, data) -> void:
	_set_hover(false)
	drop_fn.call(data, slot)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
		_set_hover(false)


func _set_hover(on: bool) -> void:
	if on == _hover:
		return
	_hover = on
	add_theme_stylebox_override("panel", _hover_style if on else _base_style)
