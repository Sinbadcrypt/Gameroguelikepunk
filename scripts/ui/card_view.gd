## Affichage d'une carte.
## - Recto compact : coût, symbole, nom, résumé court (short) et Lien en une ligne.
## - Version détaillée (detailed = true) : texte complet, utilisée pour l'inspection et le glisser.
## Gestes : toucher = signal `tapped` ; maintenir = signal `inspect` (true/false) ;
## glisser = données {kind, uid, from_slot} reçues par le Script ou la main.
class_name CardView
extends PanelContainer

signal tapped(card_view: CardView)
signal inspect(card_view: CardView, on: bool)

const BASE_SIZE := Vector2(132, 200)
const TAP_DISTANCE := 14.0
const HOLD_TIME := 0.35

var uid := -1
var def: Dictionary = {}
var from_slot := -1            # -1 = dans la main, sinon index de la case
var drop_owner: Control = null  # zone de dépôt à laquelle on délègue (Script ou main)
var detailed := false
var linked := false            # Lien actif (carte posée) : la ligne Lien s'allume
var playable := true:
	set(value):
		playable = value
		modulate = Color.WHITE if value else Color(0.5, 0.5, 0.58)

var _press_pos := Vector2.ZERO
var _pressed := false
var _holding := false
var _hold_timer: SceneTreeTimer = null
var _link_row: Control = null


func setup(card_uid: int, card_def: Dictionary, slot: int = -1, is_detailed: bool = false) -> CardView:
	uid = card_uid
	def = card_def
	from_slot = slot
	detailed = is_detailed
	_build()
	return self


func _style(border_w: int) -> StyleBoxFlat:
	var col := Palette.symbol_color(def["symbol"])
	var sb := Palette.box(Palette.PANEL, col, border_w, 4)
	sb.corner_radius_top_left = 14   # un coin coupé "cyber"
	sb.corner_radius_bottom_right = 14
	sb.set_content_margin_all(6)
	sb.shadow_color = Color(col, 0.25)
	sb.shadow_size = 6 if linked else 0
	return sb


func _build() -> void:
	custom_minimum_size = BASE_SIZE * (1.5 if detailed else 1.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _style(2))
	var col := Palette.symbol_color(def["symbol"])
	var k := 1.3 if detailed else 1.0

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)

	# Coût (chiffre mono) + icône de symbole.
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	var cost := _label(str(int(def["cost"])), "mono", int(26 * k), Palette.ENERGY)
	top.add_child(cost)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(sp)
	top.add_child(SymbolIcon.new(def["symbol"], 24 * k))

	var name_label := _label(String(def["name"]).to_upper(), "title", int(21 * k), col.lightened(0.25))
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_label)

	var line := ColorRect.new()
	line.color = Color(col, 0.35)
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(line)

	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if detailed:
		# Hors conteneur (inspection, glisser) : largeur fixe pour un retour à la ligne correct.
		body.custom_minimum_size.x = custom_minimum_size.x - 12
	body.add_theme_font_override("normal_font", Palette.font("title"))
	var text: String = def.get("text", "") if detailed else def.get("short", def.get("text", ""))
	body.add_theme_font_size_override("normal_font_size", int((20 if detailed else 21) * k))
	body.add_theme_color_override("default_color", Palette.TEXT)
	body.text = "[center]%s[/center]" % Palette.card_bbcode(text)
	v.add_child(body)

	# Ligne Lien (recto compact) : "LIEN ◆ 9 DÉG", allumée quand le Lien est actif.
	if not detailed and def.has("link") and def.has("short_link"):
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 4)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lsym: String = def["link"]["symbol"]
		row.add_child(_label("LIEN", "title", 15, Palette.TEXT_DIM))
		row.add_child(SymbolIcon.new(lsym, 15))
		v.add_child(row)
		var ltxt := _label(def["short_link"], "title", 18, Palette.symbol_color(lsym))
		ltxt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ltxt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(ltxt)
		_link_row = ltxt
		ltxt.modulate.a = 1.0 if linked else 0.6

	resized.connect(func(): pivot_offset = size / 2.0)


func _label(t: String, font_kind: String, font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", Palette.font(font_kind))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	return l


## Carte posée dont le Lien est actif : halo + ligne Lien pleine intensité.
func set_linked(on: bool) -> void:
	linked = on
	add_theme_stylebox_override("panel", _style(3 if on else 2))
	if _link_row:
		_link_row.modulate.a = 1.0 if on else 0.6


## Main chargée : cartes plus étroites.
func set_card_width(w: float) -> void:
	custom_minimum_size = Vector2(w, BASE_SIZE.y)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			_press_pos = event.position
			_hold_timer = get_tree().create_timer(HOLD_TIME)
			_hold_timer.timeout.connect(_on_hold.bind(_hold_timer))
		elif _pressed:
			_pressed = false
			if _holding:
				_holding = false
				inspect.emit(self, false)
			elif event.position.distance_to(_press_pos) < TAP_DISTANCE:
				tapped.emit(self)
			accept_event()
	elif event is InputEventMouseMotion and _pressed and not _holding:
		if event.position.distance_to(_press_pos) >= TAP_DISTANCE:
			_hold_timer = null  # le geste devient un glisser


func _on_hold(timer: SceneTreeTimer) -> void:
	if _pressed and timer == _hold_timer:
		_holding = true
		inspect.emit(self, true)


func _get_drag_data(_at_position: Vector2):
	if _holding:
		# Maintenir puis glisser : on ferme l'inspection et on soulève la carte.
		_holding = false
		inspect.emit(self, false)
	_pressed = false
	_hold_timer = null
	# Carte soulevée : version détaillée, au-dessus du doigt pour rester visible.
	var preview := CardView.new().setup(uid, def, -1, true)
	preview.modulate.a = 0.95
	var holder := Control.new()
	holder.add_child(preview)
	preview.position = Vector2(-CardView.BASE_SIZE.x * 0.75, -CardView.BASE_SIZE.y * 1.5 - 70)
	set_drag_preview(holder)
	modulate.a = 0.35
	return {"kind": "card", "uid": uid, "from_slot": from_slot}


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		playable = playable  # réapplique la teinte normale


# Une carte posée (ou en main) laisse passer le dépôt à sa zone, en coordonnées de la zone.
func _can_drop_data(at_position: Vector2, data) -> bool:
	return drop_owner != null and drop_owner._can_drop_data(_to_owner(at_position), data)


func _drop_data(at_position: Vector2, data) -> void:
	if drop_owner != null:
		drop_owner._drop_data(_to_owner(at_position), data)


func _to_owner(p: Vector2) -> Vector2:
	return p + global_position - drop_owner.global_position


## Animation "pulse" quand la carte s'exécute.
func pulse(strength: float = 1.15, duration: float = 0.18) -> void:
	pivot_offset = size / 2.0
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE * strength, duration * 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, duration * 0.6)
