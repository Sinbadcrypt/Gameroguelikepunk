## Panneau d'un ennemi, compact : intention dans une bulle au-dessus, silhouette néon,
## PV avec Bouclier en puce, états, et aperçu du Script en cours.
## Toucher le panneau = choisir cet ennemi comme cible (réticule).
class_name EnemyView
extends Control

signal selected(index: int)

var index := 0
var enemy_name := ""
var _intent: RichTextLabel
var _art: HudWidgets.EnemyArt
var _hp_bar: ProgressBar
var _hp_label: Label
var _shield_chip: Label
var _status: RichTextLabel
var _preview: Label
var _targeted := false
var _dead := false
var _reticle_t := 0.0


func setup(i: int, enemy_id: String, display_name: String, max_hp: int) -> EnemyView:
	index = i
	enemy_name = display_name
	custom_minimum_size = Vector2(300, 300)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 6)
	add_child(v)

	# Bulle d'intention : la première chose qu'on lit.
	var bubble := PanelContainer.new()
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var bsb := Palette.box(Palette.PANEL, Palette.PANEL_LIGHT, 1, 4)
	bsb.set_content_margin_all(6)
	bsb.content_margin_left = 14
	bsb.content_margin_right = 14
	bubble.add_theme_stylebox_override("panel", bsb)
	v.add_child(bubble)
	_intent = _rich(28)
	_intent.autowrap_mode = TextServer.AUTOWRAP_OFF
	bubble.add_child(_intent)

	_art = HudWidgets.EnemyArt.new(enemy_id)
	_art.custom_minimum_size = Vector2(0, 130)
	v.add_child(_art)

	var name_l := Label.new()
	name_l.text = display_name.to_upper()
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_override("font", Palette.font("title"))
	name_l.add_theme_font_size_override("font_size", 20)
	name_l.add_theme_color_override("font_color", Palette.TEXT_DIM)
	v.add_child(name_l)

	# Barre de PV + puce de Bouclier.
	var hp_row := HBoxContainer.new()
	hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_row.add_theme_constant_override("separation", 6)
	v.add_child(hp_row)
	_hp_bar = ProgressBar.new()
	_hp_bar.max_value = max_hp
	_hp_bar.value = max_hp
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(0, 24)
	_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bar.add_theme_stylebox_override("background", Palette.box(Palette.PANEL, Palette.PANEL_LIGHT, 1, 2))
	_hp_bar.add_theme_stylebox_override("fill", Palette.box(Palette.symbol_color("intrusion"), Color.TRANSPARENT, 0, 2))
	hp_row.add_child(_hp_bar)
	_hp_label = Label.new()
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hp_label.add_theme_font_override("font", Palette.font("mono"))
	_hp_label.add_theme_font_size_override("font_size", 17)
	_hp_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hp_label.add_theme_constant_override("outline_size", 5)
	_hp_bar.add_child(_hp_label)
	_shield_chip = Label.new()
	_shield_chip.add_theme_font_override("font", Palette.font("mono"))
	_shield_chip.add_theme_font_size_override("font_size", 18)
	_shield_chip.add_theme_color_override("font_color", Palette.BG)
	var chip := Palette.box(Palette.SHIELD, Color.TRANSPARENT, 0, 4)
	chip.set_content_margin_all(2)
	chip.content_margin_left = 8
	chip.content_margin_right = 8
	_shield_chip.add_theme_stylebox_override("normal", chip)
	hp_row.add_child(_shield_chip)

	_status = _rich(18)
	v.add_child(_status)

	_preview = Label.new()
	_preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview.add_theme_font_override("font", Palette.font("mono"))
	_preview.add_theme_color_override("font_color", Palette.symbol_color("intrusion"))
	_preview.add_theme_font_size_override("font_size", 22)
	_preview.custom_minimum_size = Vector2(0, 28)
	v.add_child(_preview)
	return self


func _rich(font_size: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_override("normal_font", Palette.font("title"))
	r.add_theme_font_size_override("normal_font_size", font_size)
	r.add_theme_color_override("default_color", Palette.TEXT)
	return r


## Met à jour depuis un instantané d'ennemi {hp, shield, jam, skip}.
func apply_snap(s: Dictionary, intent: Array) -> void:
	var hp := int(s["hp"])
	create_tween().tween_property(_hp_bar, "value", hp, 0.15)
	_hp_label.text = "%d/%d" % [hp, int(_hp_bar.max_value)]
	_dead = hp <= 0
	var shield := int(s["shield"])
	_shield_chip.text = "%d" % shield
	_shield_chip.visible = shield > 0
	_status.text = ("[center][color=#%s]BROUILLÉ %d[/color][/center]" % [Palette.symbol_color("brouillage").to_html(false), int(s["jam"])]) if int(s["jam"]) > 0 else ""
	if _dead:
		_intent.text = "[color=#%s]HORS LIGNE[/color]" % Palette.TEXT_DIM.to_html(false)
		modulate = Color(1, 1, 1, 0.3)
	elif s["skip"]:
		_intent.text = "[color=#%s]GELÉ[/color]" % Palette.SHIELD.to_html(false)
	else:
		_intent.text = Palette.intent_text(intent, int(s["jam"]))
	queue_redraw()


## Aperçu du Script en cours de composition (ou du glisser en cours).
func set_preview(damage: int, dead: bool, jam: int = 0, skip: bool = false) -> void:
	var bits: Array = []
	if damage > 0:
		bits.append(("-%d KO" % damage) if dead else "-%d" % damage)
	if jam > 0:
		bits.append("BRL+%d" % jam)
	if skip:
		bits.append("GEL")
	_preview.text = "  ".join(bits)


func set_targeted(on: bool) -> void:
	_targeted = on and not _dead
	queue_redraw()


func _process(delta: float) -> void:
	if _targeted:
		_reticle_t += delta
		queue_redraw()


## Réticule de ciblage : 4 coins qui "respirent" autour de la silhouette.
func _draw() -> void:
	if not _targeted:
		return
	var r := Rect2(_art.position + Vector2(20, -6), _art.size - Vector2(40, -12))
	var k := 4.0 * sin(_reticle_t * 4.0)
	r = r.grow(k)
	var col := Palette.symbol_color("intrusion")
	var l := 22.0
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var dx := l if corner.x == r.position.x else -l
		var dy := l if corner.y == r.position.y else -l
		draw_line(corner, corner + Vector2(dx, 0), col, 3.0)
		draw_line(corner, corner + Vector2(0, dy), col, 3.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not _dead:
		selected.emit(index)
		accept_event()


## Flash blanc quand l'ennemi est touché.
func hit_flash() -> void:
	modulate = Color(2.2, 2.2, 2.2)
	create_tween().tween_property(self, "modulate", Color(1, 1, 1, 0.3) if _dead else Color.WHITE, 0.2)


## L'ennemi "s'avance" quand il agit.
func pulse_attack() -> void:
	pivot_offset = size / 2.0
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.08, 1.08), 0.08)
	tw.tween_property(self, "scale", Vector2.ONE, 0.12)
