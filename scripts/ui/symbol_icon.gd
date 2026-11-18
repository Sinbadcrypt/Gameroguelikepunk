## Icône de symbole dessinée en vectoriel (pas de dépendance à une police) :
## Intrusion = losange, Chaleur = anneau, Brouillage = disque barré.
class_name SymbolIcon
extends Control

var symbol := "intrusion":
	set(value):
		symbol = value
		queue_redraw()


func _init(sym: String = "intrusion", px: float = 24.0) -> void:
	symbol = sym
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := Palette.symbol_color(symbol)
	var r: float = min(size.x, size.y) * 0.45
	var center := size / 2.0
	match symbol:
		"intrusion":
			var pts := PackedVector2Array([
				center + Vector2(0, -r), center + Vector2(r, 0),
				center + Vector2(0, r), center + Vector2(-r, 0)])
			draw_colored_polygon(pts, c)
		"chaleur":
			draw_arc(center, r * 0.75, 0, TAU, 32, c, r * 0.4, true)
		"brouillage":
			draw_circle(center, r, c)
			draw_line(center + Vector2(-r * 0.6, r * 0.6), center + Vector2(r * 0.6, -r * 0.6), Palette.BG, r * 0.3, true)
