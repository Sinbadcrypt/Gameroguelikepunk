## Couleurs, noms des symboles et petits utilitaires d'affichage partagés par l'UI.
class_name Palette
extends RefCounted

const BG := Color("#0b0d17")
const PANEL := Color("#161a2b")
const PANEL_LIGHT := Color("#22284a")
const TEXT := Color("#e8ecff")
const TEXT_DIM := Color("#8a93b8")
const DAMAGE := Color("#ff4d6d")
const SHIELD := Color("#5ec8ff")
const HEAT := Color("#ff9a2e")
const HEAL := Color("#7dff9a")
const ENERGY := Color("#ffe066")

const SYMBOL_COLORS := {
	"intrusion": Color("#ff3d7f"),
	"chaleur": Color("#ff9a2e"),
	"brouillage": Color("#2ee6ff"),
}
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
				var s := "[color=#%s]Attaque %d%s[/color]" % [DAMAGE.to_html(false), dmg, ("×%d" % hits) if hits > 1 else ""]
				parts.append(s)
			"shield":
				parts.append("[color=#%s]Bouclier %d[/color]" % [SHIELD.to_html(false), int(a["amount"])])
	return " + ".join(parts)
