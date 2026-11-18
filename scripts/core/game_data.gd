## Charge les fichiers de données JSON (cartes, ennemis, réglages).
## Aucune donnée de jeu n'est écrite en dur dans le code : tout vient de res://data/.
class_name GameData
extends RefCounted

const CARDS_PATH := "res://data/cards.json"
const ENEMIES_PATH := "res://data/enemies.json"
const SETUP_PATH := "res://data/setup.json"

var cards: Dictionary = {}    # id -> définition de carte
var enemies: Dictionary = {}  # id -> définition d'ennemi
var rules: Dictionary = {}
var decks: Dictionary = {}
var encounters: Dictionary = {}


static func load_default() -> GameData:
	var data := GameData.new()
	data.load_from(CARDS_PATH, ENEMIES_PATH, SETUP_PATH)
	return data


func load_from(cards_path: String, enemies_path: String, setup_path: String) -> void:
	for c in _read_json(cards_path).get("cards", []):
		cards[c["id"]] = c
	for e in _read_json(enemies_path).get("enemies", []):
		enemies[e["id"]] = e
	var setup := _read_json(setup_path)
	rules = setup.get("rules", {})
	decks = setup.get("decks", {})
	encounters = setup.get("encounters", {})


func card(id: String) -> Dictionary:
	assert(cards.has(id), "Carte inconnue : %s" % id)
	return cards[id]


func enemy(id: String) -> Dictionary:
	assert(enemies.has(id), "Ennemi inconnu : %s" % id)
	return enemies[id]


func rule(key: String, default_value = 0):
	return rules.get(key, default_value)


static func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Impossible d'ouvrir %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("JSON invalide : %s" % path)
		return {}
	return parsed
