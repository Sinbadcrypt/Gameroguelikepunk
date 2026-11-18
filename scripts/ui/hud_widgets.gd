## Petits éléments d'interface dessinés en vectoriel (pas d'images à produire).
class_name HudWidgets
extends RefCounted


## Pastilles d'énergie : pleines = disponibles, contour = réservées par le Script, sombres = dépensées.
class EnergyPips extends Control:
	var total := 3
	var available := 3
	var reserved := 0
	var _blink := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(150, 44)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_values(t: int, avail: int, res: int) -> void:
		total = t
		available = avail
		reserved = res
		queue_redraw()

	func _process(delta: float) -> void:
		if reserved > 0:
			_blink += delta
			queue_redraw()

	func _draw() -> void:
		var r := 14.0
		for i in total:
			var c := Vector2(r + 4 + i * (r * 2 + 12), size.y / 2.0)
			if i < available:
				draw_circle(c, r, Palette.ENERGY)
				draw_circle(c, r * 0.45, Palette.ENERGY.lightened(0.6))
			elif i < available + reserved:
				var a := 0.55 + 0.45 * sin(_blink * 6.0)
				draw_arc(c, r - 1.5, 0, TAU, 32, Color(Palette.ENERGY, a), 3.0, true)
			else:
				draw_arc(c, r - 1.5, 0, TAU, 32, Palette.PANEL_LIGHT, 3.0, true)


## Jauge de Chaleur segmentée, intégrée en tête du cadre du Script.
## Les segments au-delà du seuil sont rouges : c'est la zone de Surchauffe.
class HeatGauge extends Control:
	var heat := 0
	var threshold := 12
	var segments := 16

	func _init() -> void:
		custom_minimum_size = Vector2(0, 16)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_heat(h: int, thr: int) -> void:
		heat = h
		threshold = thr
		segments = thr + 4
		queue_redraw()

	func _draw() -> void:
		var gap := 3.0
		var w := (size.x - gap * (segments - 1)) / segments
		for i in segments:
			var rect := Rect2(i * (w + gap), 0, w, size.y)
			var danger := i >= threshold
			var lit := i < heat
			var col: Color
			if lit:
				col = Palette.DAMAGE if danger else Palette.HEAT.lerp(Palette.DAMAGE, float(i) / threshold * 0.6)
			else:
				col = Color(Palette.DAMAGE, 0.25) if danger else Palette.PANEL_LIGHT
			draw_rect(rect, col)


## Trace de circuit entre deux cases du Script. S'allume quand le Lien est actif,
## et une impulsion la parcourt pendant l'exécution.
class LinkTrace extends Control:
	var lit := false
	var color := Palette.PANEL_LIGHT
	var pulse_t := -1.0  # -1 = pas d'impulsion ; 0..1 = position de l'impulsion

	func _init() -> void:
		custom_minimum_size = Vector2(26, 0)
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_state(on: bool, col: Color) -> void:
		lit = on
		color = col if on else Palette.PANEL_LIGHT
		queue_redraw()

	func pulse(duration: float) -> void:
		var tw := create_tween()
		tw.tween_method(_set_pulse, 0.0, 1.0, duration)
		tw.tween_callback(_set_pulse.bind(-1.0))

	func _set_pulse(v: float) -> void:
		pulse_t = v
		queue_redraw()

	func _draw() -> void:
		var y := size.y / 2.0
		var w := 4.0 if lit else 2.0
		if lit:
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(color, 0.25), 12.0)  # halo
		draw_line(Vector2(0, y), Vector2(size.x, y), color, w)
		# Pointe de flèche : le flux va de gauche à droite.
		var tip := Vector2(size.x, y)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-9, -7), tip + Vector2(-9, 7)]), color)
		if pulse_t >= 0.0:
			draw_circle(Vector2(size.x * pulse_t, y), 7.0, Color.WHITE)


## Silhouettes néon des ennemis, dessinées en lignes (remplaçables plus tard par des sprites).
class EnemyArt extends Control:
	var kind := "agent_secu"
	var color := Palette.symbol_color("intrusion")
	var texture: Texture2D = null  # illustration (data/enemies.json > art), sinon silhouette

	func _init(k: String = "agent_secu", art_path: String = "") -> void:
		kind = k
		if art_path != "" and ResourceLoader.exists(art_path):
			texture = load(art_path)
		custom_minimum_size = Vector2(0, 120)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if texture:
			# Image carrée, centrée, à la plus grande taille qui tient dans la zone.
			var side: float = min(size.x, size.y)
			draw_texture_rect(texture, Rect2((size - Vector2(side, side)) / 2.0, Vector2(side, side)), false)
			return
		var c := size / 2.0
		var col := color
		var glow := Color(col, 0.18)
		match kind:
			"drone":
				_neon_ellipse(c + Vector2(0, 8), Vector2(46, 22), col, glow)
				for side in [-1, 1]:
					var arm := c + Vector2(side * 62, -18)
					draw_line(c + Vector2(side * 40, 0), arm, col, 3.0, true)
					draw_line(arm + Vector2(-26, 0), arm + Vector2(26, 0), col, 3.0, true)
				draw_circle(c + Vector2(0, 8), 9.0, col)
				draw_circle(c + Vector2(0, 8), 4.0, Color.WHITE)
			_:
				# Agent : tête, visière, épaules.
				var head := c + Vector2(0, -26)
				draw_circle(head, 30.0, glow)
				draw_arc(head, 24.0, 0, TAU, 40, col, 3.0, true)
				draw_line(head + Vector2(-18, 2), head + Vector2(18, 2), col, 6.0, true)
				var sh := PackedVector2Array([
					c + Vector2(-60, 56), c + Vector2(-44, 12), c + Vector2(44, 12), c + Vector2(60, 56)])
				draw_polyline(sh, col, 3.0, true)
				draw_line(c + Vector2(0, 12), c + Vector2(0, 40), col, 2.0, true)

	func _neon_ellipse(center: Vector2, radii: Vector2, col: Color, glow: Color) -> void:
		var pts := PackedVector2Array()
		for i in 41:
			var a := TAU * i / 40.0
			pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
		draw_colored_polygon(pts, glow)
		draw_polyline(pts, col, 3.0, true)
