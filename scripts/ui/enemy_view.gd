## Panneau d'un ennemi : nom, intention visible, PV, Bouclier, états, et aperçu des dégâts.
## Toucher le panneau = choisir cet ennemi comme cible.
class_name EnemyView
extends PanelContainer

signal selected(index: int)

var index := 0
var enemy_name := ""
var _name: Label
var _intent: RichTextLabel
var _hp_bar: ProgressBar
var _hp_label: Label
var _status: RichTextLabel
var _preview: Label
var _targeted := false
var _dead := false


func setup(i: int, display_name: String, max_hp: int) -> EnemyView:
	index = i
	enemy_name = display_name
	custom_minimum_size = Vector2(300, 240)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 6)
	add_child(v)

	_intent = _rich(24)
	v.add_child(_intent)

	# "Silhouette" de l'ennemi : un bloc stylisé (à remplacer par un sprite plus tard).
	var body := ColorRect.new()
	body.custom_minimum_size = Vector2(0, 70)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.color = Palette.PANEL_LIGHT
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(body)
	_name = Label.new()
	_name.text = display_name
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.set_anchors_preset(Control.PRESET_FULL_RECT)
	_name.add_theme_font_size_override("font_size", 24)
	body.add_child(_name)

	_hp_bar = ProgressBar.new()
	_hp_bar.max_value = max_hp
	_hp_bar.value = max_hp
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(0, 22)
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bar.add_theme_stylebox_override("background", Palette.box(Palette.BG, Color.TRANSPARENT, 0, 6))
	_hp_bar.add_theme_stylebox_override("fill", Palette.box(Palette.DAMAGE, Color.TRANSPARENT, 0, 6))
	v.add_child(_hp_bar)
	_hp_label = Label.new()
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hp_label.add_theme_font_size_override("font_size", 16)
	_hp_bar.add_child(_hp_label)

	_status = _rich(16)
	v.add_child(_status)

	_preview = Label.new()
	_preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview.add_theme_color_override("font_color", Palette.DAMAGE)
	_preview.add_theme_font_size_override("font_size", 18)
	v.add_child(_preview)
	_refresh_style()
	return self


func _rich(font_size: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_size_override("normal_font_size", font_size)
	return r


## Met à jour depuis un instantané d'ennemi {hp, shield, jam, skip}.
func apply_snap(s: Dictionary, intent: Array) -> void:
	var hp := int(s["hp"])
	var tw := create_tween()
	tw.tween_property(_hp_bar, "value", hp, 0.15)
	_hp_label.text = "%d / %d" % [hp, int(_hp_bar.max_value)]
	_dead = hp <= 0
	var bits: Array = []
	if int(s["shield"]) > 0:
		bits.append("[color=#%s]Bouclier %d[/color]" % [Palette.SHIELD.to_html(false), int(s["shield"])])
	if int(s["jam"]) > 0:
		bits.append("[color=#%s]Brouillé %d[/color]" % [Palette.symbol_color("brouillage").to_html(false), int(s["jam"])])
	_status.text = "[center]%s[/center]" % "  ".join(bits)
	if _dead:
		_intent.text = "[center][color=#%s]Déconnecté[/color][/center]" % Palette.TEXT_DIM.to_html(false)
		modulate = Color(1, 1, 1, 0.35)
	elif s["skip"]:
		_intent.text = "[center][color=#%s]Gelé : passe son tour[/color][/center]" % Palette.SHIELD.to_html(false)
	else:
		_intent.text = "[center]%s[/center]" % Palette.intent_text(intent, int(s["jam"]))
	_refresh_style()


## Aperçu du Script en cours de composition.
func set_preview(damage: int, dead: bool, jam: int = 0, skip: bool = false) -> void:
	var bits: Array = []
	if damage > 0:
		bits.append(("−%d (détruit)" % damage) if dead else "−%d" % damage)
	if jam > 0:
		bits.append("Brouillé +%d" % jam)
	if skip:
		bits.append("Gelé")
	_preview.text = "  ".join(bits)


func set_targeted(on: bool) -> void:
	_targeted = on
	_refresh_style()


func _refresh_style() -> void:
	var border := Palette.symbol_color("intrusion") if (_targeted and not _dead) else Palette.PANEL_LIGHT
	add_theme_stylebox_override("panel", Palette.box(Palette.PANEL, border, 3 if _targeted else 2, 14))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not _dead:
		selected.emit(index)
		accept_event()


## Flash blanc quand l'ennemi est touché.
func hit_flash() -> void:
	var tw := create_tween()
	modulate = Color(2.2, 2.2, 2.2)
	tw.tween_property(self, "modulate", Color(1, 1, 1, 0.35) if _dead else Color.WHITE, 0.2)


## L'ennemi "s'avance" quand il agit.
func pulse_attack() -> void:
	pivot_offset = size / 2.0
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.08, 1.08), 0.08)
	tw.tween_property(self, "scale", Vector2.ONE, 0.12)
