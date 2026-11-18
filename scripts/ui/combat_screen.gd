## Écran de combat de la vertical slice.
## Construit toute l'interface en code (portrait 720x1280), relie le moteur (CombatEngine)
## aux vues, et rejoue les événements du moteur avec animations et sons.
##
## Contrôles :
##  - Téléphone : glisser une carte dans une case, ou la toucher (première case libre).
##    Toucher une carte posée la renvoie en main. Toucher un ennemi = le viser.
##  - PC : pareil à la souris, plus clavier : 1-9 poser une carte, Entrée/Espace exécuter,
##    Retour arrière vider le Script, Tab changer de cible.
extends Control

const STEP_TIME := 0.32  # durée d'une étape de la cascade (secondes)

var data: GameData
var engine: CombatEngine
var sfx: Sfx

var _busy := false       # une animation est en cours : entrées bloquées
var _fast := false       # toucher pendant l'animation = accélérer
var _chain := 0          # longueur du Lien en cours (pour la hauteur des notes)

# Vues
var _world: MarginContainer
var _fx_layer: Control
var _turn_label: Label
var _piles_label: Label
var _enemy_views: Array = []
var _hp_bar: ProgressBar
var _hp_label: Label
var _shield_label: Label
var _heat_bar: ProgressBar
var _heat_label: Label
var _energy_label: Label
var _slot_zones: Array = []
var _link_marks: Array = []
var _preview_label: RichTextLabel
var _execute_btn: Button
var _clear_btn: Button
var _hand_zone: DropZone
var _hand_box: HBoxContainer
var _player_panel: PanelContainer
var _toast: Label


func _ready() -> void:
	data = GameData.load_default()
	engine = CombatEngine.new(data)
	engine.setup(data.decks["slice"], data.encounters["slice"])
	sfx = Sfx.new()
	add_child(sfx)
	_build_ui()
	_play(engine.start_player_turn())


# ---------------------------------------------------------------------------
# Construction de l'interface
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = _make_theme()

	var bg := ColorRect.new()
	bg.color = Palette.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_world = MarginContainer.new()
	_world.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		_world.add_theme_constant_override("margin_" + side, 16)
	_world.add_theme_constant_override("margin_top", 28)
	add_child(_world)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	_world.add_child(col)

	# --- Barre du haut : tour + piles ---
	var top := HBoxContainer.new()
	col.add_child(top)
	_turn_label = Label.new()
	_turn_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	top.add_child(_turn_label)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	_piles_label = Label.new()
	_piles_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	top.add_child(_piles_label)

	# --- Ennemis ---
	var enemies_row := HBoxContainer.new()
	enemies_row.add_theme_constant_override("separation", 12)
	enemies_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(enemies_row)
	for i in engine.state["enemies"].size():
		var e: Dictionary = engine.state["enemies"][i]
		var ev := EnemyView.new().setup(i, e["name"], int(e["max_hp"]))
		ev.selected.connect(_on_enemy_selected)
		enemies_row.add_child(ev)
		_enemy_views.append(ev)

	# --- Joueur : PV, Bouclier, Chaleur, Énergie ---
	_player_panel = PanelContainer.new()
	_player_panel.add_theme_stylebox_override("panel", Palette.box(Palette.PANEL, Palette.PANEL_LIGHT, 2, 14))
	col.add_child(_player_panel)
	var pgrid := GridContainer.new()
	pgrid.columns = 2
	pgrid.add_theme_constant_override("h_separation", 16)
	pgrid.add_theme_constant_override("v_separation", 8)
	_player_panel.add_child(pgrid)

	var hp_box := _bar_with_label(Palette.HEAL)
	_hp_bar = hp_box[0]
	_hp_label = hp_box[1]
	_hp_bar.max_value = engine.state["player"]["max_hp"]
	pgrid.add_child(hp_box[2])
	_shield_label = Label.new()
	_shield_label.add_theme_color_override("font_color", Palette.SHIELD)
	pgrid.add_child(_shield_label)

	var heat_box := _bar_with_label(Palette.HEAT)
	_heat_bar = heat_box[0]
	_heat_label = heat_box[1]
	_heat_bar.max_value = int(data.rule("overheat_threshold", 12)) + 4
	pgrid.add_child(heat_box[2])
	_energy_label = Label.new()
	_energy_label.add_theme_color_override("font_color", Palette.ENERGY)
	_energy_label.add_theme_font_size_override("font_size", 26)
	pgrid.add_child(_energy_label)

	# --- Script : 3 cases reliées par des marqueurs de Lien ---
	var script_title := Label.new()
	script_title.text = "SCRIPT  ·  exécuté de gauche à droite"
	script_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	script_title.add_theme_color_override("font_color", Palette.TEXT_DIM)
	script_title.add_theme_font_size_override("font_size", 16)
	col.add_child(script_title)

	var script_row := HBoxContainer.new()
	script_row.alignment = BoxContainer.ALIGNMENT_CENTER
	script_row.add_theme_constant_override("separation", 6)
	col.add_child(script_row)
	var slot_base := Palette.box(Palette.PANEL, Palette.PANEL_LIGHT, 2, 14)
	var slot_hover := Palette.box(Palette.PANEL_LIGHT, Palette.ENERGY, 3, 14)
	for i in engine.state["slots"].size():
		if i > 0:
			var mark := Label.new()
			mark.text = "›"
			mark.add_theme_font_size_override("font_size", 40)
			mark.add_theme_color_override("font_color", Palette.PANEL_LIGHT)
			mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			script_row.add_child(mark)
			_link_marks.append(mark)
		var zone := DropZone.new().setup(i, _can_drop, _on_drop, slot_base, slot_hover)
		zone.custom_minimum_size = Vector2(CardView.BASE_SIZE.x + 16, CardView.BASE_SIZE.y + 16)
		script_row.add_child(zone)
		_slot_zones.append(zone)

	_preview_label = RichTextLabel.new()
	_preview_label.bbcode_enabled = true
	_preview_label.fit_content = true
	_preview_label.scroll_active = false
	_preview_label.custom_minimum_size = Vector2(0, 56)
	_preview_label.add_theme_font_size_override("normal_font_size", 18)
	col.add_child(_preview_label)

	# --- Boutons ---
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	col.add_child(btns)
	_clear_btn = Button.new()
	_clear_btn.text = "Vider"
	_clear_btn.custom_minimum_size = Vector2(160, 72)
	_clear_btn.pressed.connect(_on_clear)
	btns.add_child(_clear_btn)
	_execute_btn = Button.new()
	_execute_btn.text = "EXÉCUTER"
	_execute_btn.custom_minimum_size = Vector2(0, 72)
	_execute_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_execute_btn.add_theme_font_size_override("font_size", 28)
	_execute_btn.add_theme_stylebox_override("normal", Palette.box(Palette.symbol_color("intrusion").darkened(0.35), Palette.symbol_color("intrusion"), 2, 14))
	_execute_btn.add_theme_stylebox_override("hover", Palette.box(Palette.symbol_color("intrusion").darkened(0.2), Palette.symbol_color("intrusion"), 2, 14))
	_execute_btn.add_theme_stylebox_override("pressed", Palette.box(Palette.symbol_color("intrusion"), Palette.TEXT, 2, 14))
	_execute_btn.pressed.connect(_on_execute)
	btns.add_child(_execute_btn)

	# --- Main (zone de dépôt pour reprendre une carte du Script) ---
	_hand_zone = DropZone.new().setup(-1, _can_drop, _on_drop,
		Palette.box(Color(0, 0, 0, 0), Color.TRANSPARENT, 0, 14),
		Palette.box(Palette.PANEL, Palette.TEXT_DIM, 2, 14))
	_hand_zone.custom_minimum_size = Vector2(0, CardView.BASE_SIZE.y + 20)
	col.add_child(_hand_zone)
	_hand_box = HBoxContainer.new()
	_hand_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand_box.add_theme_constant_override("separation", 6)
	_hand_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand_zone.add_child(_hand_box)

	if OS.has_feature("pc") and not OS.has_feature("web"):
		var hint := Label.new()
		hint.text = "Clavier : 1-9 poser · Entrée exécuter · Retour vider · Tab cible"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_font_size_override("font_size", 14)
		hint.add_theme_color_override("font_color", Palette.TEXT_DIM)
		col.add_child(hint)

	# Couche d'effets (chiffres flottants, messages) au-dessus de tout.
	_fx_layer = Control.new()
	_fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_layer)
	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.add_theme_color_override("font_color", Palette.ENERGY)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_preset(Control.PRESET_CENTER)
	_toast.modulate.a = 0.0
	_fx_layer.add_child(_toast)


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 22
	t.set_color("font_color", "Label", Palette.TEXT)
	t.set_color("default_color", "RichTextLabel", Palette.TEXT)
	t.set_color("font_color", "Button", Palette.TEXT)
	t.set_stylebox("normal", "Button", Palette.box(Palette.PANEL_LIGHT, Palette.TEXT_DIM, 2, 14))
	t.set_stylebox("hover", "Button", Palette.box(Palette.PANEL_LIGHT.lightened(0.1), Palette.TEXT, 2, 14))
	t.set_stylebox("pressed", "Button", Palette.box(Palette.PANEL, Palette.TEXT, 2, 14))
	t.set_stylebox("disabled", "Button", Palette.box(Palette.PANEL, Palette.PANEL_LIGHT, 2, 14))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	return t


## Barre + texte superposé. Renvoie [barre, texte, conteneur].
func _bar_with_label(fill: Color) -> Array:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 30)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_theme_stylebox_override("background", Palette.box(Palette.BG, Color.TRANSPARENT, 0, 8))
	bar.add_theme_stylebox_override("fill", Palette.box(fill.darkened(0.15), Color.TRANSPARENT, 0, 8))
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	bar.add_child(label)
	return [bar, label, bar]


# ---------------------------------------------------------------------------
# Rafraîchissement de l'affichage
# ---------------------------------------------------------------------------

## Reconstruit la main et le Script depuis l'état du moteur, puis l'aperçu.
func _refresh() -> void:
	var st := engine.state
	_turn_label.text = "Tour %d" % st["turn"]
	_piles_label.text = "Pioche %d · Défausse %d" % [st["draw"].size(), st["discard"].size()]
	_apply_snap(engine._ev({})["snap"])

	# Script
	for i in _slot_zones.size():
		var zone: DropZone = _slot_zones[i]
		for child in zone.get_children():
			child.queue_free()
		var c = st["slots"][i]
		if c == null:
			var hint := Label.new()
			hint.text = str(i + 1)
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			hint.add_theme_font_size_override("font_size", 40)
			hint.add_theme_color_override("font_color", Palette.PANEL_LIGHT)
			hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
			zone.add_child(hint)
		else:
			var cv := CardView.new().setup(c["uid"], engine.def_of(c), i)
			cv.drop_owner = zone
			cv.tapped.connect(_on_card_tapped)
			zone.add_child(cv)

	# Main : les cartes rétrécissent si la main dépasse 5 cartes.
	for child in _hand_box.get_children():
		child.queue_free()
	var hand: Array = st["hand"]
	var avail := size.x - 32.0 if size.x > 0 else 688.0
	var w: float = min(CardView.BASE_SIZE.x, (avail - 6.0 * max(0, hand.size() - 1)) / max(1, hand.size()))
	for c in hand:
		var cv := CardView.new().setup(c["uid"], engine.def_of(c), -1)
		cv.set_card_width(w)
		cv.drop_owner = _hand_zone
		var slot := engine.first_free_slot()
		cv.playable = slot >= 0 and engine.can_place(c["uid"], slot) == ""
		cv.tapped.connect(_on_card_tapped)
		_hand_box.add_child(cv)

	_refresh_preview()
	_execute_btn.disabled = _busy or st["outcome"] != ""
	_clear_btn.disabled = _busy or st["outcome"] != ""


## Applique un instantané (PV, Bouclier, Chaleur, ennemis) aux vues.
func _apply_snap(snap: Dictionary) -> void:
	var p: Dictionary = engine.state["player"]
	var tw := create_tween()
	tw.tween_property(_hp_bar, "value", snap["hp"], 0.15)
	_hp_label.text = "PV %d / %d" % [snap["hp"], p["max_hp"]]
	_shield_label.text = "Bouclier %d" % snap["shield"]
	var threshold := int(data.rule("overheat_threshold", 12))
	_heat_bar.value = snap["heat"]
	var over: bool = snap["heat"] > threshold
	_heat_label.text = ("SURCHAUFFE %d / %d" if over else "Chaleur %d / %d") % [snap["heat"], threshold]
	_heat_bar.modulate = Color(1.6, 0.6, 0.6) if over else Color.WHITE
	_energy_label.text = "Énergie %d / %d" % [engine.energy_left(), int(data.rule("energy_per_turn", 3))]
	for i in _enemy_views.size():
		_enemy_views[i].apply_snap(snap["enemies"][i], engine.intent_of(i))
		_enemy_views[i].set_targeted(i == engine.state["target"])


## Aperçu du Script : Liens actifs, dégâts prévus, Bouclier, Chaleur.
func _refresh_preview() -> void:
	var has_card := false
	for c in engine.state["slots"]:
		if c != null:
			has_card = true
	for i in _link_marks.size():
		var lit := engine.is_linked(i + 1)
		_link_marks[i].add_theme_color_override("font_color", Palette.ENERGY if lit else Palette.PANEL_LIGHT)
	if not has_card or _busy:
		for ev in _enemy_views:
			ev.set_preview(0, false)
		_preview_label.text = "[center][color=#%s]Glisse ou touche des cartes pour écrire ton Script.[/color][/center]" % Palette.TEXT_DIM.to_html(false) if not _busy else ""
		return
	var pv := engine.preview()
	for i in _enemy_views.size():
		var pe: Dictionary = pv["enemies"][i]
		_enemy_views[i].set_preview(pe["damage"], pe["dead"], pe["jam"], pe["skip"])
	var parts: Array = []
	var total := 0
	for e in pv["enemies"]:
		total += int(e["damage"])
	if total > 0:
		parts.append("[color=#%s]%d dégâts[/color]" % [Palette.DAMAGE.to_html(false), total])
	if pv["shield"] > 0:
		parts.append("[color=#%s]+%d Bouclier[/color]" % [Palette.SHIELD.to_html(false), pv["shield"]])
	if pv["heat"] != 0:
		parts.append("[color=#%s]%+d Chaleur[/color]" % [Palette.HEAT.to_html(false), pv["heat"]])
	if pv["extra_draw"] > 0:
		parts.append("[color=#%s]+%d carte(s) au prochain tour[/color]" % [Palette.ENERGY.to_html(false), pv["extra_draw"]])
	var links := 0
	for l in pv["linked"]:
		if l:
			links += 1
	if links > 0:
		parts.append("[color=#%s]%d Lien(s)[/color]" % [Palette.ENERGY.to_html(false), links])
	var text := "  ·  ".join(parts)
	if pv["full_stack"]:
		text += "\n[color=#%s]FULL STACK[/color]" % Palette.symbol_color("brouillage").to_html(false)
	if pv["heat_after"] > int(data.rule("overheat_threshold", 12)):
		text += "\n[color=#%s]Attention : Surchauffe au prochain tour[/color]" % Palette.DAMAGE.to_html(false)
	_preview_label.text = "[center]%s[/center]" % text


# ---------------------------------------------------------------------------
# Entrées
# ---------------------------------------------------------------------------

func _can_drop(d: Dictionary, slot: int) -> bool:
	if _busy:
		return false
	if slot == -1:
		return d["from_slot"] >= 0  # reprendre une carte du Script
	if d["from_slot"] >= 0:
		return d["from_slot"] != slot  # réorganiser : toujours permis
	return engine.can_place(d["uid"], slot) == ""


func _on_drop(d: Dictionary, slot: int) -> void:
	if slot == -1:
		engine.unplace(d["from_slot"])
	elif d["from_slot"] >= 0:
		engine.swap_slots(d["from_slot"], slot)
	else:
		engine.place(d["uid"], slot)
	sfx.blip(520.0, 0.05, "sine", 0.2)
	_refresh()


func _on_card_tapped(cv: CardView) -> void:
	if _busy:
		return
	if cv.from_slot >= 0:
		engine.unplace(cv.from_slot)
	else:
		var slot := engine.first_free_slot()
		var why := "Script plein" if slot < 0 else engine.can_place(cv.uid, slot)
		if why != "":
			_show_toast(why)
			return
		engine.place(cv.uid, slot)
	sfx.blip(520.0, 0.05, "sine", 0.2)
	_refresh()


func _on_enemy_selected(index: int) -> void:
	if _busy:
		return
	engine.set_target(index)
	_refresh()


func _on_clear() -> void:
	if _busy:
		return
	engine.clear_script()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		if event is InputEventMouseButton and event.pressed:
			_fast = true
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_on_execute()
		KEY_BACKSPACE:
			_on_clear()
		KEY_TAB:
			var n: int = engine.state["enemies"].size()
			for k in range(1, n + 1):
				var idx: int = (engine.state["target"] + k) % n
				if engine.state["enemies"][idx]["hp"] > 0:
					engine.set_target(idx)
					break
			_refresh()
		_:
			var num: int = event.keycode - KEY_1
			if num >= 0 and num < 9 and num < engine.state["hand"].size():
				var cards := _hand_box.get_children()
				if num < cards.size():
					_on_card_tapped(cards[num])


func _input(event: InputEvent) -> void:
	# Toucher l'écran pendant une animation l'accélère.
	if _busy and event is InputEventMouseButton and event.pressed:
		_fast = true


# ---------------------------------------------------------------------------
# Déroulé d'un tour
# ---------------------------------------------------------------------------

func _on_execute() -> void:
	if _busy or engine.state["outcome"] != "":
		return
	var has_card := false
	for c in engine.state["slots"]:
		if c != null:
			has_card = true
	if not has_card:
		_show_toast("Script vide : fin du tour")
	_busy = true
	_fast = false
	_chain = 0
	_execute_btn.disabled = true
	_refresh_preview()
	# Les cartes restent affichées pendant la cascade : on garde les vues des cases.
	var events := engine.execute()
	await _play_events(events)
	if engine.state["outcome"] == "":
		await _wait(0.25)
		await _play_events(engine.enemy_turn())
	if engine.state["outcome"] == "":
		await _wait(0.2)
		var start := engine.start_player_turn()
		_busy = false
		_play(start)
	else:
		_busy = false
		_refresh()
		_show_end()


## Joue des événements sans bloquer (début de partie / de tour).
func _play(events: Array) -> void:
	_refresh()
	for ev in events:
		if ev["type"] == "overheat":
			_float_text(_player_panel, "−%d Surchauffe" % ev["amount"], Palette.DAMAGE)
			_shake(10.0)
	if engine.state["outcome"] != "":
		_show_end()


func _play_events(events: Array) -> void:
	for ev in events:
		await _play_event(ev)


func _play_event(ev: Dictionary) -> void:
	match ev["type"]:
		"card_start":
			var zone: DropZone = _slot_zones[ev["slot"]]
			if ev["linked"]:
				_chain += 1
				if ev["slot"] > 0:
					var mark: Label = _link_marks[ev["slot"] - 1]
					_flash_label(mark, Palette.ENERGY)
				_float_text(zone, "LIEN", Palette.ENERGY, -40.0)
			else:
				_chain = 0
			sfx.card_note(_chain)
			for child in zone.get_children():
				if child is CardView:
					child.pulse(1.18 + 0.04 * _chain)
			await _wait(STEP_TIME * 0.5)
		"damage":
			var view: EnemyView = _enemy_views[ev["enemy"]]
			_apply_snap(ev["snap"])
			view.hit_flash()
			if ev["amount"] > 0:
				_float_text(view, "−%d" % ev["amount"], Palette.DAMAGE)
				_shake(4.0 + min(ev["amount"], 20) * 0.4)
			if ev["blocked"] > 0:
				_float_text(view, "%d bloqués" % ev["blocked"], Palette.SHIELD, 30.0)
			sfx.hit()
			await _wait(STEP_TIME * 0.6)
		"enemy_dead":
			_float_text(_enemy_views[ev["enemy"]], "DÉCONNECTÉ", Palette.TEXT, -60.0)
			await _wait(STEP_TIME * 0.4)
		"shield":
			_apply_snap(ev["snap"])
			_float_text(_player_panel, "+%d Bouclier" % ev["amount"], Palette.SHIELD)
			sfx.shield()
			await _wait(STEP_TIME * 0.5)
		"heat":
			_apply_snap(ev["snap"])
			_float_text(_player_panel, "Chaleur %d" % ev["snap"]["heat"], Palette.HEAT, 20.0)
			await _wait(STEP_TIME * 0.4)
		"jam", "skip":
			_apply_snap(ev["snap"])
			var v2: EnemyView = _enemy_views[ev["enemy"]]
			_float_text(v2, "Brouillé" if ev["type"] == "jam" else "Gelé", Palette.symbol_color("brouillage"))
			await _wait(STEP_TIME * 0.5)
		"draw_next":
			_float_text(_player_panel, "+%d carte au prochain tour" % ev["amount"], Palette.ENERGY, -30.0)
			await _wait(STEP_TIME * 0.4)
		"reflect", "power":
			_float_text(_player_panel, "Contre-mesure active" if ev["type"] == "reflect" else "Rootkit installé", Palette.ENERGY)
			await _wait(STEP_TIME * 0.4)
		"full_stack":
			_show_toast("FULL STACK  ·  +1 carte au prochain tour")
			_glitch()
			sfx.blip(880.0, 0.25, "square", 0.3)
			await _wait(STEP_TIME)
		"script_end":
			_refresh()
		"enemy_start":
			_enemy_views[ev["enemy"]].pulse_attack()
			await _wait(STEP_TIME * 0.4)
		"enemy_skip":
			_float_text(_enemy_views[ev["enemy"]], "Gelé", Palette.SHIELD)
			await _wait(STEP_TIME * 0.5)
		"enemy_shield":
			_apply_snap(ev["snap"])
			_float_text(_enemy_views[ev["enemy"]], "+%d Bouclier" % ev["amount"], Palette.SHIELD)
			await _wait(STEP_TIME * 0.5)
		"player_hit":
			_apply_snap(ev["snap"])
			if ev["amount"] > 0:
				_float_text(_player_panel, "−%d" % ev["amount"], Palette.DAMAGE)
				_shake(8.0 + min(ev["amount"], 20) * 0.5)
				sfx.blip(70.0, 0.18, "noise", 0.4)
			if ev["blocked"] > 0:
				_float_text(_player_panel, "%d bloqués" % ev["blocked"], Palette.SHIELD, 30.0)
				sfx.shield()
			await _wait(STEP_TIME * 0.7)
		_:
			pass


# ---------------------------------------------------------------------------
# Game feel : chiffres flottants, tremblement, glitch
# ---------------------------------------------------------------------------

func _wait(t: float) -> void:
	await get_tree().create_timer(t * (0.3 if _fast else 1.0)).timeout


func _float_text(anchor: Control, text: String, color: Color, y_offset: float = 0.0) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 34)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	_fx_layer.add_child(l)
	var center := anchor.global_position + anchor.size / 2.0 - _fx_layer.global_position
	l.position = center + Vector2(-l.get_minimum_size().x / 2.0 + randf_range(-20, 20), y_offset - 20)
	l.pivot_offset = l.get_minimum_size() / 2.0
	l.scale = Vector2.ONE * 0.6
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "scale", Vector2.ONE * 1.1, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - 70.0, 0.8).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.4).set_delay(0.45)
	tw.chain().tween_callback(l.queue_free)


func _shake(strength: float) -> void:
	var tw := create_tween()
	for i in 6:
		var off := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength * (1.0 - i / 6.0)
		tw.tween_property(_world, "position", off, 0.03)
	tw.tween_property(_world, "position", Vector2.ZERO, 0.03)


func _glitch() -> void:
	var tw := create_tween()
	for i in 4:
		tw.tween_property(_world, "modulate", Color(0.6, 1.6, 1.8) if i % 2 == 0 else Color(1.8, 0.6, 1.4), 0.04)
	tw.tween_property(_world, "modulate", Color.WHITE, 0.08)


func _flash_label(l: Label, color: Color) -> void:
	l.add_theme_color_override("font_color", Color.WHITE)
	var tw := create_tween()
	tw.tween_interval(0.12)
	tw.tween_callback(func(): l.add_theme_color_override("font_color", color))


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.position = Vector2(size.x / 2.0 - _toast.get_minimum_size().x / 2.0, size.y * 0.42)
	_toast.modulate.a = 1.0
	var tw := _toast.create_tween()
	tw.tween_interval(0.9)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.3)


# ---------------------------------------------------------------------------
# Fin du combat
# ---------------------------------------------------------------------------

func _show_end() -> void:
	var win: bool = engine.state["outcome"] == "win"
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 24)
	overlay.add_child(box)
	var title := Label.new()
	title.text = "ACCÈS OBTENU" if win else "CONNEXION PERDUE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Palette.HEAL if win else Palette.DAMAGE)
	box.add_child(title)
	var info := Label.new()
	info.text = "Tour %d · PV restants %d" % [engine.state["turn"], engine.state["player"]["hp"]]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(info)
	var again := Button.new()
	again.text = "Rejouer"
	again.custom_minimum_size = Vector2(280, 80)
	again.pressed.connect(func(): get_tree().reload_current_scene())
	box.add_child(again)
	# Centre la boîte une fois sa taille connue.
	await get_tree().process_frame
	box.position = (size - box.size) / 2.0
	overlay.modulate.a = 0.0
	overlay.create_tween().tween_property(overlay, "modulate:a", 1.0, 0.3)
