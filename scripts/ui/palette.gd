## Couleurs, noms des symboles et petits utilitaires d'affichage partagés par l'UI.
class_name Palette
extends RefCounted

# Direction artistique "Terminal netrunner" : fond noir bleuté, 3 couleurs vives (une par symbole).
const BG := Color("#07090f")
const PANEL := Color("#0e1422")
const PANEL_LIGHT := Color("#1e2a44")
const TEXT := Color("#c8f7ff")
const TEXT_DIM := Color("#5e6b8c")
const DAMAGE := Color("#ff3b3b")
const SHIELD := Color("#2ee6ff")
const HEAT := Color("#ffb020")
const HEAL := Color("#3dffa8")
const ENERGY := Color("#ffe066")

const SYMBOL_COLORS := {
	"intrusion": Color("#ff2e88"),
	"chaleur": Color("#ffb020"),
	"brouillage": Color("#2ee6ff"),
}

# Polices : Rajdhani (titres et texte, condensée) et JetBrains Mono (chiffres).
# JetBrains Mono sert aussi de secours pour les caractères absents de Rajdhani (½, →…).
static var _fonts := {}


static func font(kind: String) -> Font:
	if _fonts.is_empty():
		var mono: FontFile = load("res://assets/fonts/JetBrainsMono-Bold.ttf")
		var ui: FontFile = load("res://assets/fonts/Rajdhani-SemiBold.ttf")
		var title: FontFile = load("res://assets/fonts/Rajdhani-Bold.ttf")
		ui.fallbacks = [mono]
		title.fallbacks = [mono]
		_fonts = {"mono": mono, "ui": ui, "title": title}
	return _fonts[kind]
const SYMBOL_NAMES := {
	"intrusion": "Intrusion",
	"chaleur": "Chaleur",
	"brouillage": "Brouillage",
}
const SYMBOL_TOKENS := {"{I}": "intrusion", "{C}": "chaleur", "{B}": "brouillage"}


static func symbol_color(symbol: String) -> Color:
	return SYMBOL_COLORS.get(symbol, TEXT)


## Remplace {I} {C} {B} par le nom du symbole en couleur (BBCode pour RichTextLabel).
static func card_bbcode(text: String) -> String:
	var out := text
	for token in SYMBOL_TOKENS:
		var sym: String = SYMBOL_TOKENS[token]
		out = out.replace(token, "[color=#%s]%s[/color]" % [symbol_color(sym).to_html(false), SYMBOL_NAMES[sym]])
	return out


## Boîte de style simple : fond, bordure, coins arrondis.
static func box(bg: Color, border: Color = Color.TRANSPARENT, border_width: int = 0, radius: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(8)
	return sb


## Texte d'une intention ennemie, ex. "Attaque 3×2 + Bouclier 6".
static func intent_text(actions: Array, jam: int) -> String:
	var parts: Array = []
	var jam_left := jam
	for a in actions:
		match a["type"]:
			"attack":
				var dmg: int = max(0, int(a["amount"]) - jam_left)
				jam_left = 0
				var hits := int(a.get("hits", 1))
				var s := "[color=#%s]ATTAQUE %d%s[/color]" % [DAMAGE.to_html(false), dmg, ("×%d" % hits) if hits > 1 else ""]
				parts.append(s)
			"shield":
				parts.append("[color=#%s]BOUCLIER %d[/color]" % [SHIELD.to_html(false), int(a["amount"])])
	return " + ".join(parts)
