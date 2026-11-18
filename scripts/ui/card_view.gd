## Affichage d'une carte. Se glisse (souris ou doigt) ou se touche.
## - Toucher/cliquer : signal `tapped` (l'écran décide : poser ou retirer).
## - Glisser : données {kind, uid, from_slot} reçues par une case ou la main.
class_name CardView
extends PanelContainer

signal tapped(card_view: CardView)

const BASE_SIZE := Vector2(128, 210)
const TAP_DISTANCE := 12.0

var uid := -1
var def: Dictionary = {}
var from_slot := -1           # -1 = dans la main, sinon index de la case
var drop_owner: Control = null  # cible de dépôt à laquelle on délègue (case ou main)
var playable := true:
	set(value):
		playable = value
		modulate = Color.WHITE if value else Color(0.55, 0.55, 0.6)

var _press_pos := Vector2.ZERO
var _pressed := false
var _cost_label: Label
var _text: RichTextLabel
var _name_label: Label


func setup(card_uid: int, card_def: Dictionary, slot: int = -1) -> CardView:
	uid = card_uid
	def = card_def
	from_slot = slot
	_build()
	return self


func _build() -> void:
	custom_minimum_size = BASE_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col := Palette.symbol_color(def["symbol"])
	var sb := Palette.box(Palette.PANEL, col, 3, 12)
	sb.set_content_margin_all(5)
	add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)

	# Ligne du haut : coût + icône du symbole.
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	_cost_label = Label.new()
	_cost_label.text = str(int(def["cost"]))
	_cost_label.add_theme_color_override("font_color", Palette.ENERGY)
	_cost_label.add_theme_font_size_override("font_size", 26)
	top.add_child(_cost_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	top.add_child(SymbolIcon.new(def["symbol"], 26))

	_name_label = Label.new()
	_name_label.text = def["name"]
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 19)
	_name_label.add_theme_color_override("font_color", col.lightened(0.3))
	v.add_child(_name_label)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("normal_font_size", 18)
	_text.text = "[center]%s[/center]" % Palette.card_bbcode(def.get("text", ""))
	v.add_child(_text)

	resized.connect(func(): pivot_offset = size / 2.0)


## Redimensionne la carte (main chargée : cartes plus étroites).
func set_card_width(w: float) -> void:
	custom_minimum_size = Vector2(w, BASE_SIZE.y * clampf(w / BASE_SIZE.x, 0.85, 1.0))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			_press_pos = event.position
		elif _pressed:
			_pressed = false
			if event.position.distance_to(_press_pos) < TAP_DISTANCE:
				tapped.emit(self)
				accept_event()


func _get_drag_data(_at_position: Vector2):
	_pressed = false
	var preview := CardView.new().setup(uid, def)
	preview.modulate.a = 0.85
	preview.rotation_degrees = -4
	# Le preview suit le doigt ; on le décale pour que la carte reste visible au-dessus.
	var holder := Control.new()
	holder.add_child(preview)
	preview.position = -CardView.BASE_SIZE / 2.0 - Vector2(0, 40)
	set_drag_preview(holder)
	return {"kind": "card", "uid": uid, "from_slot": from_slot}


# Une carte posée sur une case (ou dans la main) laisse passer le dépôt à son conteneur.
func _can_drop_data(at_position: Vector2, data) -> bool:
	return drop_owner != null and drop_owner._can_drop_data(at_position, data)


func _drop_data(at_position: Vector2, data) -> void:
	if drop_owner != null:
		drop_owner._drop_data(at_position, data)


## Petite animation "pulse" quand la carte s'exécute.
func pulse(strength: float = 1.15, duration: float = 0.18) -> void:
	pivot_offset = size / 2.0
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE * strength, duration * 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, duration * 0.6)
