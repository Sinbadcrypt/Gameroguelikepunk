## Le Script : cadre "processeur" avec jauge de Chaleur, 3 cases reliées par des traces
## de circuit, et une ligne d'aperçu façon terminal.
## Tout le cadre est une zone de dépôt aimantée : la carte va dans la case la plus proche
## du doigt, sans viser précisément.
class_name ScriptZone
extends PanelContainer

var can_drop_fn: Callable  # func(data, slot) -> bool
var drop_fn: Callable      # func(data, slot) -> void
var hover_fn: Callable     # func(data, slot) -> void ; slot = -1 quand le survol s'arrête

var slots: Array = []      # PanelContainer par case
var traces: Array = []     # HudWidgets.LinkTrace entre les cases
var heat_gauge: HudWidgets.HeatGauge
var heat_label: Label
var terminal: RichTextLabel
var _hover_slot := -1
var _heat_tier := 0


func setup(slot_count: int, can_drop: Callable, on_drop: Callable, on_hover: Callable) -> ScriptZone:
	can_drop_fn = can_drop
	drop_fn = on_drop
	hover_fn = on_hover
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_heat_tier(0)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)

	# En-tête : jauge de Chaleur intégrée au cadre (c'est le processeur qui chauffe).
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	var t := _label("CHALEUR", "title", 18, Palette.HEAT)
	head.add_child(t)
	heat_gauge = HudWidgets.HeatGauge.new()
	heat_gauge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(heat_gauge)
	heat_label = _label("0/12", "mono", 18, Palette.HEAT)
	head.add_child(heat_label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	for i in slot_count:
		if i > 0:
			var tr := HudWidgets.LinkTrace.new()
			row.add_child(tr)
			traces.append(tr)
		var s := PanelContainer.new()
		s.custom_minimum_size = CardView.BASE_SIZE + Vector2(12, 12)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(s)
		slots.append(s)
	_restyle_slots()

	terminal = RichTextLabel.new()
	terminal.bbcode_enabled = true
	terminal.fit_content = true
	terminal.scroll_active = false
	terminal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	terminal.custom_minimum_size = Vector2(0, 30)
	terminal.add_theme_font_override("normal_font", Palette.font("mono"))
	terminal.add_theme_font_size_override("normal_font_size", 18)
	terminal.add_theme_color_override("default_color", Palette.TEXT)
	v.add_child(terminal)
	return self


func _label(t: String, kind: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", Palette.font(kind))
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	return l


## Palier de Chaleur : 0 nominal, 1 chaud, 2 critique, 3 surchauffe. Change la couleur du cadre.
func set_heat_tier(tier: int) -> void:
	_heat_tier = tier
	var border: Color = [Color(Palette.SHIELD, 0.35), Palette.HEAT, Palette.DAMAGE, Palette.DAMAGE][tier]
	var sb := Palette.box(Color(Palette.PANEL, 0.85), border, 2 if tier < 2 else 3, 4)
	sb.corner_radius_top_left = 18
	sb.corner_radius_bottom_right = 18
	sb.set_content_margin_all(12)
	sb.shadow_color = Color(border, 0.35 if tier >= 2 else 0.0)
	sb.shadow_size = 10 if tier >= 2 else 0
	add_theme_stylebox_override("panel", sb)


func _restyle_slots() -> void:
	for i in slots.size():
		var hot := i == _hover_slot
		var sb := Palette.box(Palette.BG, Palette.ENERGY if hot else Palette.PANEL_LIGHT, 3 if hot else 1, 4)
		sb.set_content_margin_all(6)
		slots[i].add_theme_stylebox_override("panel", sb)


## Case la plus proche horizontalement d'un point (coordonnées locales de la zone).
func slot_at(p: Vector2) -> int:
	var best := 0
	var best_d := INF
	for i in slots.size():
		var c: Control = slots[i]
		var cx := c.global_position.x - global_position.x + c.size.x / 2.0
		var d := absf(p.x - cx)
		if d < best_d:
			best_d = d
			best = i
	return best


func _can_drop_data(at_position: Vector2, data) -> bool:
	if typeof(data) != TYPE_DICTIONARY or data.get("kind", "") != "card":
		return false
	var slot := slot_at(at_position)
	var ok: bool = can_drop_fn.call(data, slot)
	var target := slot if ok else -1
	if target != _hover_slot:
		_hover_slot = target
		_restyle_slots()
		hover_fn.call(data, target)
		if target >= 0:
			Input.vibrate_handheld(10)
	return ok


func _drop_data(at_position: Vector2, data) -> void:
	var slot := slot_at(at_position)
	end_hover()
	drop_fn.call(data, slot)


func end_hover() -> void:
	if _hover_slot != -1:
		_hover_slot = -1
		_restyle_slots()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		end_hover()
	elif what == NOTIFICATION_MOUSE_EXIT and _hover_slot != -1:
		# La carte glissée quitte le Script : on revient à l'aperçu normal.
		end_hover()
		hover_fn.call({}, -1)
