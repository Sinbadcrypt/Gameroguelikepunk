## Écran de combat (portrait 720 px de large), direction "Terminal netrunner".
## Construit l'interface en code, relie le moteur (CombatEngine) aux vues, et rejoue
## les événements du moteur avec animations et sons.
##
## Disposition, de haut en bas : HUD fin · ennemis · PV · Script (avec jauge de Chaleur)
## · énergie + RUN · main. Les décisions sont en bas, sous le pouce.
##
## Contrôles :
##  - Téléphone : toucher une carte = première case libre ; glisser = case précise (le Script
##    est aimanté et l'aperçu se met à jour pendant le survol) ; maintenir = détail de la carte.
##    Toucher une carte posée la renvoie en main. Toucher un ennemi = le viser.
##  - PC : pareil à la souris, plus clavier : 1-9 poser, Entrée/Espace exécuter,
##    Retour arrière vider, Tab changer de cible.
extends Control

const STEP_TIME := 0.32        # durée d'une étape de la cascade (secondes)
const SAFE_TOP := 120          # marge pour les boutons de l'app (Claude, navigateur)
const SAFE_BOTTOM := 34        # marge pour la barre d'accueil iOS

var data: GameData
var engine: CombatEngine
var sfx: Sfx

var _busy := false       # animation en cours : entrées bloquées
var _fast := false       # toucher pendant l'animation = accélérer
var _chain := 0          # longueur du Lien en cours (hauteur des notes)

# Vues
var _world: MarginContainer
var _fx_layer: Control
var _crt: ColorRect
var _turn_label: Label
var _piles_label: Label
var _enemy_views: Array = []
var _hp_bar: ProgressBar
var _hp_label: Label
var _shield_chip: Label
var _script: ScriptZone
var _pips: HudWidgets.EnergyPips
var _execute_btn: Button
var _clear_btn: Button
var _hand_zone: DropZone
var _hand_box: HBoxContainer
var _player_row: Control
var _toast: Label
var _inspector: CardView = null


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
	_world.add_theme_constant_override("margin_left", 16)
	_world.add_theme_constant_override("margin_right", 16)
	_world.add_theme_constant_override("margin_top", SAFE_TOP)
	_world.add_theme_constant_override("margin_bottom", SAFE_BOTTOM)
	add_child(_world)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_world.add_child(col)

	# --- HUD fin : tour + piles ---
	var top := HBoxContainer.new()
	col.add_child(top)
	_turn_label = _label("", "mono", 18, Palette.TEXT_DIM)
	top.add_child(_turn_label)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	_piles_label = _label("", "mono", 18, Palette.TEXT_DIM)
	top.add_child(_piles_label)

	# --- Ennemis (prennent la hauteur restante) ---
	var enemies_row := HBoxContainer.new()
	enemies_row.add_theme_constant_override("separation", 12)
	enemies_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(enemies_row)
	for i in engine.state["enemies"].size():
		var e: Dictionary = engine.state["enemies"][i]
		var ev := EnemyView.new().setup(i, e["id"], e["name"], int(e["max_hp"]))
		ev.selected.connect(_on_enemy_selected)
		enemies_row.add_child(ev)
		_enemy_views.append(ev)

	# --- Joueur : PV + Bouclier en puce ---
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 10)
	col.add_child(prow)
	_player_row = prow
	prow.add_child(_label("PV", "title", 22, Palette.HEAL))
	_hp_bar = ProgressBar.new()
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(0, 28)
	_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hp_bar.max_value = engine.state["player"]["max_hp"]
	_hp_bar.add_theme_stylebox_override("background", Palette.box(Palette.PANEL, Palette.PANEL_LIGHT, 1, 2))
	_hp_bar.add_theme_stylebox_override("fill", Palette.box(Palette.HEAL.darkened(0.25), Color.TRANSPARENT, 0, 2))
	prow.add_child(_hp_bar)
	_hp_label = _label("", "mono", 18, Palette.TEXT)
	_hp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hp_label.add_theme_constant_override("outline_size", 5)
	_hp_bar.add_child(_hp_label)
	_shield_chip = _label("", "mono", 20, Palette.BG)
	var chip := Palette.box(Palette.SHIELD, Color.TRANSPARENT, 0, 4)
	chip.set_content_margin_all(3)
	chip.content_margin_left = 10
	chip.content_margin_right = 10
	_shield_chip.add_theme_stylebox_override("normal", chip)
	prow.add_child(_shield_chip)

	# --- Script ---
	_script = ScriptZone.new().setup(engine.state["slots"].size(), _can_drop_script, _on_drop_script, _on_hover_script)
	col.add_child(_script)

	# --- Énergie + boutons, sous le pouce ---
	var act := HBoxContainer.new()
	act.add_theme_constant_override("separation", 12)
	col.add_child(act)
	_pips = HudWidgets.EnergyPips.new()
	_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	act.add_child(_pips)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	act.add_child(sp2)
	_clear_btn = Button.new()
	_clear_btn.text = "VIDER"
	_clear_btn.custom_minimum_size = Vector2(120, 80)
	_clear_btn.pressed.connect(_on_clear)
	act.add_child(_clear_btn)
	_execute_btn = Button.new()
	_execute_btn.text = "RUN  ▶"
	_execute_btn.custom_minimum_size = Vector2(250, 88)
	_execute_btn.add_theme_font_override("font", Palette.font("title"))
	_execute_btn.add_theme_font_size_override("font_size", 36)
	var pink := Palette.symbol_color("intrusion")
	_execute_btn.add_theme_stylebox_override("normal", _btn_style(pink.darkened(0.55), pink, 2))
	_execute_btn.add_theme_stylebox_override("hover", _btn_style(pink.darkened(0.4), pink, 2))
	_execute_btn.add_theme_stylebox_override("pressed", _btn_style(pink, Palette.TEXT, 2))
	_execute_btn.add_theme_stylebox_override("disabled", _btn_style(Palette.PANEL, Palette.PANEL_LIGHT, 1))
	_execute_btn.pressed.connect(_on_execute)
	act.add_child(_execute_btn)

	# --- Main (zone de dépôt pour reprendre une carte du Script) ---
	_hand_zone = DropZone.new().setup(-1, _can_drop_hand, _on_drop_hand,
		Palette.box(Color(0, 0, 0, 0), Color.TRANSPARENT, 0, 8),
		Palette.box(Palette.PANEL, Palette.TEXT_DIM, 1, 8))
	_hand_zone.custom_minimum_size = Vector2(0, CardView.BASE_SIZE.y + 16)
	col.add_child(_hand_zone)
	_hand_box = HBoxContainer.new()
	_hand_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand_box.add_theme_constant_override("separation", 6)
	_hand_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand_zone.add_child(_hand_box)

	# Couche d'effets (chiffres flottants, messages, inspection) au-dessus de tout.
	_fx_layer = Control.new()
	_fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_layer)
	_toast = _label("", "title", 30, Palette.ENERGY)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.modulate.a = 0.0
	_fx_layer.add_child(_toast)

	# Calque CRT (lignes de balayage, vignettage, alerte Surchauffe).
	_crt = ColorRect.new()
	_crt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/crt.gdshader")
	_crt.material = mat
	add_child(_crt)


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = Palette.font("ui")
	t.default_font_size = 24
	t.set_color("font_color", "Label", Palette.TEXT)
	t.set_color("default_color", "RichTextLabel", Palette.TEXT)
	t.set_color("font_color", "Button", Palette.TEXT)
	t.set_color("font_disabled_color", "Button", Palette.TEXT_DIM)
	t.set_font("font", "Button", Palette.font("title"))
	t.set_font_size("font_size", "Button", 24)
	t.set_stylebox("normal", "Button", _btn_style(Palette.PANEL, Palette.PANEL_LIGHT, 1))
	t.set_stylebox("hover", "Button", _btn_style(Palette.PANEL_LIGHT, Palette.TEXT_DIM, 1))
	t.set_stylebox("pressed", "Button", _btn_style(Palette.PANEL, Palette.TEXT, 1))
	t.set_stylebox("disabled", "Button", _btn_style(Palette.PANEL, Palette.PANEL_LIGHT, 1))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	return t


func _btn_style(bg: Color, border: Color, w: int) -> StyleBoxFlat:
	var sb := Palette.box(bg, border, w, 4)
	sb.corner_radius_top_left = 16
	sb.corner_radius_bottom_right = 16
	return sb


func _label(t: String, kind: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", Palette.font(kind))
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	return l


# ---------------------------------------------------------------------------
# Rafraîchissement de l'affichage
# ---------------------------------------------------------------------------

## Reconstruit le Script et la main depuis l'état du moteur, puis l'aperçu.
func _refresh() -> void:
	var st := engine.state
	_turn_label.text = "TOUR %02d" % st["turn"]
	_piles_label.text = "PIOCHE %d · DÉFAUSSE %d" % [st["draw"].size(), st["discard"].size()]
	_apply_snap(engine._ev({})["snap"])

	# Script
	for i in _script.slots.size():
		var frame: PanelContainer = _script.slots[i]
		for child in frame.get_children():
			child.queue_free()
		var c = st["slots"][i]
		if c == null:
			var hint := _label("%02d" % (i + 1), "mono", 34, Palette.PANEL_LIGHT)
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			frame.add_child(hint)
		else:
			var cv := CardView.new().setup(c["uid"], engine.def_of(c), i)
			cv.drop_owner = _script
			cv.tapped.connect(_on_card_tapped)
			cv.inspect.connect(_on_inspect)
			cv.set_linked(engine.is_linked(i))
			frame.add_child(cv)

	# Main : les cartes rétrécissent si la main dépasse 5 cartes.
	for child in _hand_box.get_children():
		child.queue_free()
	var hand: Array = st["hand"]
	var avail := (size.x - 32.0) if size.x > 0 else 688.0
	var n: int = max(1, hand.size())
	var w: float = min(CardView.BASE_SIZE.x, (avail - 6.0 * (n - 1)) / n)
	for c in hand:
		var cv := CardView.new().setup(c["uid"], engine.def_of(c), -1)
		cv.set_card_width(w)
		cv.drop_owner = _hand_zone
		var slot := engine.first_free_slot()
		cv.playable = slot >= 0 and engine.can_place(c["uid"], slot) == ""
		cv.tapped.connect(_on_card_tapped)
		cv.inspect.connect(_on_inspect)
		_hand_box.add_child(cv)

	_refresh_preview()
	_execute_btn.disabled = _busy or st["outcome"] != ""
	_clear_btn.disabled = _busy or st["outcome"] != ""


## Applique un instantané (PV, Bouclier, Chaleur, ennemis) aux vues.
func _apply_snap(snap: Dictionary) -> void:
	var p: Dictionary = engine.state["player"]
	create_tween().tween_property(_hp_bar, "value", snap["hp"], 0.15)
	_hp_label.text = "%d/%d" % [snap["hp"], p["max_hp"]]
	_shield_chip.text = "BOUCLIER %d" % snap["shield"]
	_shield_chip.modulate.a = 1.0 if snap["shield"] > 0 else 0.3
	var threshold := int(data.rule("overheat_threshold", 12))
	var heat: int = snap["heat"]
	_script.heat_gauge.set_heat(heat, threshold)
	_script.heat_label.text = "%d/%d" % [heat, threshold]
	var tier := 0 if heat <= threshold / 2 else (1 if heat <= threshold * 3 / 4 else (2 if heat <= threshold else 3))
	_script.set_heat_tier(tier)
	(_crt.material as ShaderMaterial).set_shader_parameter("heat", float(heat) / threshold)
	_pips.set_values(int(data.rule("energy_per_turn", 3)), max(0, engine.energy_left()), engine.committed_energy())
	for i in _enemy_views.size():
		_enemy_views[i].apply_snap(snap["enemies"][i], engine.intent_of(i))
		_enemy_views[i].set_targeted(i == engine.state["target"])


## Aperçu du Script tel qu'il est posé.
func _refresh_preview() -> void:
	var has_card := false
	for c in engine.state["slots"]:
		if c != null:
			has_card = true
	if _busy:
		for ev in _enemy_views:
			ev.set_preview(0, false)
		_script.terminal.text = "[center][color=#%s]> exécution…[/color][/center]" % Palette.TEXT_DIM.to_html(false)
		return
	if not has_card:
		_show_preview({})
		return
	_show_preview(engine.preview())


## Affiche un aperçu (réel ou hypothétique pendant un glisser) : traces, ennemis, terminal.
func _show_preview(pv: Dictionary) -> void:
	var dim := Palette.TEXT_DIM.to_html(false)
	if pv.is_empty():
		for tr in _script.traces:
			tr.set_state(false, Palette.PANEL_LIGHT)
		for ev in _enemy_views:
			ev.set_preview(0, false)
		_script.terminal.text = "[center][color=#%s]> glisse ou touche une carte_[/color][/center]" % dim
		return
	for i in _script.traces.size():
		var lit: bool = pv["linked"][i + 1]
		var sym: String = pv["symbols"][i]
		_script.traces[i].set_state(lit, Palette.symbol_color(sym) if sym != "" else Palette.ENERGY)
	for i in _enemy_views.size():
		var pe: Dictionary = pv["enemies"][i]
		_enemy_views[i].set_preview(pe["damage"], pe["dead"], pe["jam"], pe["skip"])
	var parts: Array = []
	var total := 0
	for e in pv["enemies"]:
		total += int(e["damage"])
	if total > 0:
		parts.append("[color=#%s]%d DÉG[/color]" % [Palette.symbol_color("intrusion").to_html(false), total])
	if pv["shield"] > 0:
		parts.append("[color=#%s]+%d BCL[/color]" % [Palette.SHIELD.to_html(false), pv["shield"]])
	if pv["heat"] != 0:
		parts.append("[color=#%s]%+d CHL[/color]" % [Palette.HEAT.to_html(false), pv["heat"]])
	if pv["extra_draw"] > 0:
		parts.append("[color=#%s]+%d CARTE[/color]" % [Palette.ENERGY.to_html(false), pv["extra_draw"]])
	var links := 0
	for l in pv["linked"]:
		if l:
			links += 1
	if links > 0:
		parts.append("[color=#%s]LIEN×%d[/color]" % [Palette.ENERGY.to_html(false), links])
	if pv["full_stack"]:
		parts.append("[color=#%s]FULL STACK[/color]" % Palette.SHIELD.to_html(false))
	var text := "> " + " · ".join(parts)
	if pv["heat_after"] > int(data.rule("overheat_threshold", 12)):
		text += "\n[color=#%s]> THERMAL WARNING : -%d PV au prochain tour[/color]" % [Palette.DAMAGE.to_html(false), int(data.rule("overheat_damage", 3))]
	_script.terminal.text = "[center]%s[/center]" % text


# ---------------------------------------------------------------------------
# Entrées
# ---------------------------------------------------------------------------

func _can_drop_script(d: Dictionary, slot: int) -> bool:
	if _busy:
		return false
	if d["from_slot"] >= 0:
		return true  # réorganiser le Script : toujours permis
	return engine.can_insert(d["uid"], slot) == ""


func _on_drop_script(d: Dictionary, slot: int) -> void:
	if d["from_slot"] >= 0:
		if d["from_slot"] == slot:
			_refresh()
			return
		engine.move_slot(d["from_slot"], slot)
	else:
		engine.insert(d["uid"], slot)
	_after_place(slot)


## Pendant un glisser au-dessus du Script : aperçu de ce que donnerait le dépôt.
func _on_hover_script(d: Dictionary, slot: int) -> void:
	if slot < 0 or d.is_empty():
		_refresh_preview()
		return
	_show_preview(engine.preview_if({"uid": d["uid"], "from_slot": d["from_slot"], "to_slot": slot}))


func _can_drop_hand(d: Dictionary, _slot: int) -> bool:
	return not _busy and d["from_slot"] >= 0


func _on_drop_hand(d: Dictionary, _slot: int) -> void:
	engine.unplace(d["from_slot"])
	sfx.blip(420.0, 0.05, "sine", 0.2)
	_refresh()


## Son + vibration après une pose ; plus marqué si la carte active un Lien.
func _after_place(slot: int) -> void:
	if engine.is_linked(slot) or (slot + 1 < engine.state["slots"].size() and engine.is_linked(slot + 1)):
		sfx.blip(780.0, 0.08, "square", 0.25)
		Input.vibrate_handheld(25)
	else:
		sfx.blip(520.0, 0.05, "sine", 0.2)
	_refresh()


func _on_card_tapped(cv: CardView) -> void:
	if _busy:
		return
	if cv.from_slot >= 0:
		engine.unplace(cv.from_slot)
		sfx.blip(420.0, 0.05, "sine", 0.2)
		_refresh()
		return
	var slot := engine.first_free_slot()
	var why := "SCRIPT PLEIN" if slot < 0 else engine.can_place(cv.uid, slot)
	if why != "":
		_show_toast(why.to_upper())
		return
	engine.place(cv.uid, slot)
	_after_place(slot)


## Maintenir une carte : grande version détaillée au-dessus de la main.
func _on_inspect(cv: CardView, on: bool) -> void:
	if _inspector:
		_inspector.queue_free()
		_inspector = null
	if not on:
		return
	_inspector = CardView.new().setup(cv.uid, cv.def, -1, true)
	_inspector.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(_inspector)
	_inspector.size = _inspector.get_combined_minimum_size()
	var sz := _inspector.size
	var hand_top := _hand_zone.global_position.y - _fx_layer.global_position.y
	_inspector.position = Vector2((size.x - sz.x) / 2.0, hand_top - sz.y - 30)
	_inspector.scale = Vector2.ONE * 0.8
	_inspector.pivot_offset = sz / 2.0
	_inspector.create_tween().tween_property(_inspector, "scale", Vector2.ONE, 0.1)


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


func _notification(what: int) -> void:
	# Fin d'un glisser (déposé ou annulé) : l'aperçu revient à l'état réel.
	if what == NOTIFICATION_DRAG_END and engine != null and not _busy:
		_refresh.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
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
			var cards := _hand_box.get_children()
			if num >= 0 and num < 9 and num < cards.size():
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
		_show_toast("SCRIPT VIDE : FIN DU TOUR")
	_busy = true
	_fast = false
	_chain = 0
	_execute_btn.disabled = true
	_clear_btn.disabled = true
	_refresh_preview()
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
			_float_text(_player_row, "-%d SURCHAUFFE" % ev["amount"], Palette.DAMAGE)
			_shake(10.0)
			_glitch()
	if engine.state["outcome"] != "":
		_show_end()


func _play_events(events: Array) -> void:
	for ev in events:
		await _play_event(ev)


func _play_event(ev: Dictionary) -> void:
	match ev["type"]:
		"card_start":
			var slot: int = ev["slot"]
			var frame: PanelContainer = _script.slots[slot]
			if ev["linked"]:
				_chain += 1
				if slot > 0:
					_script.traces[slot - 1].pulse(STEP_TIME * 0.4 * (0.3 if _fast else 1.0))
					await _wait(STEP_TIME * 0.35)
				_float_text(frame, "LIEN", Palette.ENERGY, -60.0)
			else:
				_chain = 0
			sfx.card_note(_chain)
			for child in frame.get_children():
				if child is CardView:
					child.pulse(1.18 + 0.04 * _chain)
			await _wait(STEP_TIME * 0.5)
		"damage":
			var view: EnemyView = _enemy_views[ev["enemy"]]
			_apply_snap(ev["snap"])
			view.hit_flash()
			if ev["amount"] > 0:
				_float_text(view, "-%d" % ev["amount"], Palette.symbol_color("intrusion"))
				_shake(4.0 + min(ev["amount"], 20) * 0.4)
			if ev["blocked"] > 0:
				_float_text(view, "%d BLOQUÉS" % ev["blocked"], Palette.SHIELD, 30.0)
			sfx.hit()
			await _wait(STEP_TIME * 0.6)
		"enemy_dead":
			_float_text(_enemy_views[ev["enemy"]], "HORS LIGNE", Palette.TEXT, -60.0)
			_glitch()
			await _wait(STEP_TIME * 0.4)
		"shield":
			_apply_snap(ev["snap"])
			_float_text(_player_row, "+%d BOUCLIER" % ev["amount"], Palette.SHIELD)
			sfx.shield()
			await _wait(STEP_TIME * 0.5)
		"heat":
			_apply_snap(ev["snap"])
			_float_text(_script, "CHALEUR %d" % ev["snap"]["heat"], Palette.HEAT, -80.0)
			await _wait(STEP_TIME * 0.4)
		"jam", "skip":
			_apply_snap(ev["snap"])
			_float_text(_enemy_views[ev["enemy"]], "BROUILLÉ" if ev["type"] == "jam" else "GELÉ", Palette.SHIELD)
			await _wait(STEP_TIME * 0.5)
		"draw_next":
			_float_text(_player_row, "+%d CARTE AU PROCHAIN TOUR" % ev["amount"], Palette.ENERGY, -30.0)
			await _wait(STEP_TIME * 0.4)
		"reflect", "power":
			_float_text(_player_row, "CONTRE-MESURE ACTIVE" if ev["type"] == "reflect" else "ROOTKIT INSTALLÉ", Palette.ENERGY)
			await _wait(STEP_TIME * 0.4)
		"full_stack":
			_show_toast("FULL STACK · +1 CARTE")
			_glitch()
			sfx.blip(880.0, 0.25, "square", 0.3)
			await _wait(STEP_TIME)
		"script_end":
			_refresh()
		"enemy_start":
			_enemy_views[ev["enemy"]].pulse_attack()
			await _wait(STEP_TIME * 0.4)
		"enemy_skip":
			_float_text(_enemy_views[ev["enemy"]], "GELÉ", Palette.SHIELD)
			await _wait(STEP_TIME * 0.5)
		"enemy_shield":
			_apply_snap(ev["snap"])
			_float_text(_enemy_views[ev["enemy"]], "+%d BOUCLIER" % ev["amount"], Palette.SHIELD)
			await _wait(STEP_TIME * 0.5)
		"player_hit":
			_apply_snap(ev["snap"])
			if ev["amount"] > 0:
				_float_text(_player_row, "-%d" % ev["amount"], Palette.DAMAGE)
				_shake(8.0 + min(ev["amount"], 20) * 0.5)
				_red_flash()
				sfx.blip(70.0, 0.18, "noise", 0.4)
			if ev["blocked"] > 0:
				_float_text(_player_row, "%d BLOQUÉS" % ev["blocked"], Palette.SHIELD, 30.0)
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
	var l := _label(text, "title", 40, color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 10)
	_fx_layer.add_child(l)
	var center := anchor.global_position + anchor.size / 2.0 - _fx_layer.global_position
	var ms := l.get_minimum_size()
	l.position = center + Vector2(-ms.x / 2.0 + randf_range(-20, 20), y_offset - 20)
	l.pivot_offset = ms / 2.0
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


## Glitch court (événement seulement : Full stack, ennemi détruit, Surchauffe).
func _glitch() -> void:
	var tw := create_tween()
	for i in 4:
		tw.tween_property(_world, "modulate", Color(0.6, 1.6, 1.8) if i % 2 == 0 else Color(1.8, 0.6, 1.4), 0.04)
	tw.tween_property(_world, "modulate", Color.WHITE, 0.08)


func _red_flash() -> void:
	_world.modulate = Color(1.6, 0.7, 0.7)
	create_tween().tween_property(_world, "modulate", Color.WHITE, 0.2)


func _show_toast(text: String) -> void:
	_toast.text = text
	var ms := _toast.get_minimum_size()
	_toast.position = Vector2(size.x / 2.0 - ms.x / 2.0, size.y * 0.40)
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
	overlay.color = Color(0, 0, 0, 0.8)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	move_child(_crt, -1)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 24)
	overlay.add_child(box)
	var title := _label("ACCÈS OBTENU" if win else "CONNEXION PERDUE", "title", 56, Palette.HEAL if win else Palette.DAMAGE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var info := _label("> TOUR %d · PV %d" % [engine.state["turn"], engine.state["player"]["hp"]], "mono", 22, Palette.TEXT)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(info)
	var again := Button.new()
	again.text = "REJOUER"
	again.custom_minimum_size = Vector2(280, 84)
	again.pressed.connect(func(): get_tree().reload_current_scene())
	box.add_child(again)
	await get_tree().process_frame
	box.position = (size - box.size) / 2.0
	overlay.modulate.a = 0.0
	overlay.create_tween().tween_property(overlay, "modulate:a", 1.0, 0.3)
