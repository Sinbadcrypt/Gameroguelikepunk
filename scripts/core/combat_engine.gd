## Moteur de combat : logique pure, sans aucun nœud ni affichage.
##
## Toute la partie est dans `state` (un Dictionary), ce qui permet de la copier
## pour calculer l'aperçu du Script sans toucher à la vraie partie.
## Chaque action renvoie une liste d'événements que l'interface rejoue avec
## des animations. Chaque événement contient un instantané (`snap`) des valeurs
## après l'événement, pour que l'affichage suive la cascade pas à pas.
class_name CombatEngine
extends RefCounted

const SYMBOLS := ["intrusion", "chaleur", "brouillage"]

var data: GameData
var state: Dictionary = {}
var rng := RandomNumberGenerator.new()
var _next_uid := 1


func _init(game_data: GameData) -> void:
	data = game_data


# ---------------------------------------------------------------------------
# Mise en place
# ---------------------------------------------------------------------------

## Prépare un combat. `deck_ids` : liste d'ids de cartes. `enemy_ids` : ids d'ennemis.
func setup(deck_ids: Array, enemy_ids: Array, seed_value: int = 0) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	var hp := int(data.rule("player_hp", 60))
	var draw_pile: Array = []
	for id in deck_ids:
		draw_pile.append(_make_card(id))
	_shuffle(draw_pile)
	var enemies: Array = []
	for id in enemy_ids:
		var def := data.enemy(id)
		enemies.append({
			"id": id, "name": def["name"],
			"hp": int(def["hp"]), "max_hp": int(def["hp"]),
			"shield": 0, "jam": 0, "skip": false, "intent_index": 0,
		})
	state = {
		"turn": 0,
		"outcome": "",          # "" en cours, "win" ou "lose"
		"player": {
			"hp": hp, "max_hp": hp, "shield": 0, "heat": 0,
			"energy": 0, "reflect": false, "powers": {},
		},
		"enemies": enemies,
		"target": 0,            # index de l'ennemi visé par les cartes à cible unique
		"draw": draw_pile, "hand": [], "discard": [], "exhausted": [],
		"slots": _empty_slots(),
		"extra_draw": 0,        # cartes en plus à piocher au prochain tour
	}


func _make_card(id: String) -> Dictionary:
	var c := {"uid": _next_uid, "id": id}
	_next_uid += 1
	return c


func _empty_slots() -> Array:
	var slots: Array = []
	slots.resize(int(data.rule("script_slots", 3)))
	return slots


# ---------------------------------------------------------------------------
# Tour du joueur
# ---------------------------------------------------------------------------

## Début de tour : Bouclier à 0, énergie pleine, Surchauffe, pioche.
func start_player_turn() -> Array:
	var events: Array = []
	var p: Dictionary = state["player"]
	state["turn"] += 1
	p["shield"] = 0
	p["reflect"] = false
	p["energy"] = int(data.rule("energy_per_turn", 3))
	# Surchauffe : au-delà du seuil, la Chaleur brûle le joueur.
	if p["heat"] > int(data.rule("overheat_threshold", 12)):
		var dmg := int(data.rule("overheat_damage", 3))
		p["hp"] = max(0, p["hp"] - dmg)
		events.append(_ev({"type": "overheat", "amount": dmg}))
		_check_outcome()
	var count := int(data.rule("hand_size", 5)) + int(state["extra_draw"])
	state["extra_draw"] = 0
	for i in count:
		if not _draw_one():
			break
	events.append(_ev({"type": "turn_start", "turn": state["turn"]}))
	return events


func _draw_one() -> bool:
	if state["draw"].is_empty():
		if state["discard"].is_empty():
			return false
		state["draw"] = state["discard"]
		state["discard"] = []
		_shuffle(state["draw"])
	state["hand"].append(state["draw"].pop_back())
	return true


func _shuffle(arr: Array) -> void:
	# Fisher-Yates avec notre propre RNG, pour des parties reproductibles (graine).
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


# ---------------------------------------------------------------------------
# Composition du Script
# ---------------------------------------------------------------------------

func def_of(card: Dictionary) -> Dictionary:
	return data.card(card["id"])


## Énergie déjà réservée par les cartes posées dans le Script.
func committed_energy() -> int:
	var total := 0
	for c in state["slots"]:
		if c != null:
			total += int(def_of(c)["cost"])
	return total


func energy_left() -> int:
	return int(state["player"]["energy"]) - committed_energy()


## Renvoie "" si la carte (uid, dans la main) peut aller dans la case, sinon la raison.
func can_place(uid: int, slot: int) -> String:
	if state["outcome"] != "":
		return "Combat terminé"
	if slot < 0 or slot >= state["slots"].size():
		return "Case invalide"
	var card = _find_in(state["hand"], uid)
	if card == null:
		return "Carte absente de la main"
	var def := def_of(card)
	var freed := 0
	if state["slots"][slot] != null:
		freed = int(def_of(state["slots"][slot])["cost"])
	if int(def["cost"]) > energy_left() + freed:
		return "Pas assez d'énergie"
	if def.get("unique_in_script", false):
		for i in state["slots"].size():
			var other = state["slots"][i]
			if i != slot and other != null and other["id"] == card["id"]:
				return "Max 1 %s par Script" % def["name"]
	return ""


## Pose une carte de la main dans une case. Une carte déjà présente retourne en main.
func place(uid: int, slot: int) -> bool:
	if can_place(uid, slot) != "":
		return false
	var card = _find_in(state["hand"], uid)
	state["hand"].erase(card)
	if state["slots"][slot] != null:
		state["hand"].append(state["slots"][slot])
	state["slots"][slot] = card
	return true


## Première case libre, ou -1.
func first_free_slot() -> int:
	for i in state["slots"].size():
		if state["slots"][i] == null:
			return i
	return -1


## Retire la carte d'une case et la remet en main.
func unplace(slot: int) -> void:
	var c = state["slots"][slot]
	if c != null:
		state["slots"][slot] = null
		state["hand"].append(c)


## Échange le contenu de deux cases (réorganiser est gratuit).
func swap_slots(a: int, b: int) -> void:
	var tmp = state["slots"][a]
	state["slots"][a] = state["slots"][b]
	state["slots"][b] = tmp


func clear_script() -> void:
	for i in state["slots"].size():
		unplace(i)


func set_target(index: int) -> void:
	if index >= 0 and index < state["enemies"].size() and state["enemies"][index]["hp"] > 0:
		state["target"] = index


## Le Lien de la carte en case `slot` est-il actif ? (case vide avant = pas de Lien)
func is_linked(slot: int) -> bool:
	var card = state["slots"][slot]
	if card == null or slot == 0:
		return false
	var link = def_of(card).get("link", null)
	var prev = state["slots"][slot - 1]
	if prev == null:
		return false
	var prev_def := def_of(prev)
	# Une carte sans Lien écrit n'a rien à activer, même après une Injection.
	if link == null:
		return false
	# Injection (grants_link) active le Lien de la carte suivante, quel que soit son symbole.
	return prev_def.get("grants_link", false) or prev_def["symbol"] == link["symbol"]


## Les 3 symboles différents sont-ils présents dans le Script ?
func is_full_stack() -> bool:
	var seen := {}
	for c in state["slots"]:
		if c != null:
			seen[def_of(c)["symbol"]] = true
	return seen.size() >= SYMBOLS.size()


# ---------------------------------------------------------------------------
# Exécution du Script
# ---------------------------------------------------------------------------

## Exécute le Script de gauche à droite, puis termine le tour du joueur.
## L'interface appelle ensuite enemy_turn() puis start_player_turn().
func execute() -> Array:
	var events: Array = []
	var p: Dictionary = state["player"]
	p["energy"] -= committed_energy()
	var full_stack := is_full_stack()
	for i in state["slots"].size():
		var card = state["slots"][i]
		if card == null:
			continue
		if state["outcome"] != "":
			break
		var def := def_of(card)
		var linked := is_linked(i)
		events.append(_ev({"type": "card_start", "slot": i, "uid": card["uid"], "linked": linked}))
		var effects: Array = def["link"]["effects"] if linked else def["effects"]
		for eff in effects:
			_apply_effect(eff, i, linked, def, events)
			if state["outcome"] != "":
				break
	if full_stack and state["outcome"] == "":
		state["extra_draw"] += int(data.rule("full_stack_draw", 1))
		events.append(_ev({"type": "full_stack"}))
	# Défausse : cartes jouées (ou épuisées) et reste de la main.
	for i in state["slots"].size():
		var c = state["slots"][i]
		if c != null:
			if def_of(c).get("exhaust", false):
				state["exhausted"].append(c)
			else:
				state["discard"].append(c)
	state["slots"] = _empty_slots()
	state["discard"].append_array(state["hand"])
	state["hand"] = []
	events.append(_ev({"type": "script_end"}))
	return events


## Aperçu : exécute le Script sur une copie de la partie et résume le résultat.
func preview() -> Dictionary:
	var saved_state := state
	var saved_uid := _next_uid
	state = state.duplicate(true)
	var before: Dictionary = saved_state
	var events := execute()
	var after := state
	state = saved_state
	_next_uid = saved_uid
	var enemies: Array = []
	for i in before["enemies"].size():
		var b: Dictionary = before["enemies"][i]
		var a: Dictionary = after["enemies"][i]
		enemies.append({
			"damage": (b["hp"] - a["hp"]),
			"dead": a["hp"] <= 0 and b["hp"] > 0,
			"jam": a["jam"] - b["jam"],
			"skip": a["skip"] and not b["skip"],
		})
	var linked: Array = []
	for i in before["slots"].size():
		linked.append(is_linked(i))
	return {
		"enemies": enemies,
		"shield": after["player"]["shield"] - before["player"]["shield"],
		"heat": after["player"]["heat"] - before["player"]["heat"],
		"heat_after": after["player"]["heat"],
		"extra_draw": after["extra_draw"] - before["extra_draw"],
		"linked": linked,
		"full_stack": is_full_stack(),
		"events": events,
	}


func _apply_effect(eff: Dictionary, slot: int, linked: bool, def: Dictionary, events: Array) -> void:
	var p: Dictionary = state["player"]
	match eff["type"]:
		"damage":
			var amount := _value(eff.get("amount", 0), slot)
			# Rootkit : bonus sur chaque Lien Intrusion activé.
			if linked and def.has("link") and def["link"]["symbol"] == "intrusion":
				amount += int(p["powers"].get("rootkit", 0))
			if eff.get("target", "single") == "all":
				for idx in state["enemies"].size():
					if state["enemies"][idx]["hp"] > 0:
						_damage_enemy(idx, amount, events)
			else:
				_damage_enemy(_current_target(), amount, events)
		"shield":
			var s := _value(eff.get("amount", 0), slot)
			p["shield"] += s
			events.append(_ev({"type": "shield", "amount": s}))
		"heat":
			var h := _value(eff.get("amount", 0), slot)
			p["heat"] = max(0, p["heat"] + h)
			events.append(_ev({"type": "heat", "amount": h}))
		"heat_half":
			p["heat"] = int(p["heat"] / 2)
			events.append(_ev({"type": "heat", "amount": 0}))
		"set_heat":
			p["heat"] = max(0, _value(eff.get("amount", 0), slot))
			events.append(_ev({"type": "heat", "amount": 0}))
		"draw_next":
			var n := _value(eff.get("amount", 1), slot)
			state["extra_draw"] += n
			events.append(_ev({"type": "draw_next", "amount": n}))
		"jam":
			var t := _current_target()
			if t >= 0:
				var j := _value(eff.get("amount", 0), slot)
				state["enemies"][t]["jam"] += j
				events.append(_ev({"type": "jam", "enemy": t, "amount": j}))
		"skip_intent":
			var t2 := _current_target()
			if t2 >= 0:
				state["enemies"][t2]["skip"] = true
				events.append(_ev({"type": "skip", "enemy": t2}))
		"reflect":
			p["reflect"] = true
			events.append(_ev({"type": "reflect"}))
		"power":
			var key: String = eff["power"]
			p["powers"][key] = int(p["powers"].get(key, 0)) + _value(eff.get("amount", 1), slot)
			events.append(_ev({"type": "power", "power": key}))
		_:
			push_warning("Effet inconnu : %s" % eff["type"])


## Valeur d'un montant : entier, ou { stat, mult, div, add } = add + stat × mult ÷ div.
## Stats disponibles : heat (Chaleur), intrusion_before (cartes Intrusion avant cette case).
func _value(spec, slot: int) -> int:
	if typeof(spec) != TYPE_DICTIONARY:
		return int(spec)
	var stat := 0
	match spec.get("stat", ""):
		"heat":
			stat = int(state["player"]["heat"])
		"intrusion_before":
			for i in slot:
				var c = state["slots"][i]
				if c != null and def_of(c)["symbol"] == "intrusion":
					stat += 1
	var mult := int(spec.get("mult", 1))
	var div := maxi(1, int(spec.get("div", 1)))
	return int(spec.get("add", 0)) + int(stat * mult / div)


func _current_target() -> int:
	var t: int = state["target"]
	if t >= 0 and t < state["enemies"].size() and state["enemies"][t]["hp"] > 0:
		return t
	# La cible est morte : on vise le premier ennemi vivant.
	for i in state["enemies"].size():
		if state["enemies"][i]["hp"] > 0:
			state["target"] = i
			return i
	return -1


func _damage_enemy(idx: int, amount: int, events: Array) -> void:
	if idx < 0:
		return
	var e: Dictionary = state["enemies"][idx]
	var blocked: int = min(e["shield"], amount)
	e["shield"] -= blocked
	e["hp"] = max(0, e["hp"] - (amount - blocked))
	events.append(_ev({"type": "damage", "enemy": idx, "amount": amount - blocked, "blocked": blocked}))
	if e["hp"] <= 0:
		events.append(_ev({"type": "enemy_dead", "enemy": idx}))
	_check_outcome()


# ---------------------------------------------------------------------------
# Tour des ennemis
# ---------------------------------------------------------------------------

## Intention actuelle d'un ennemi (liste d'actions), pour l'afficher.
func intent_of(idx: int) -> Array:
	var e: Dictionary = state["enemies"][idx]
	var pattern: Array = data.enemy(e["id"])["pattern"]
	return pattern[e["intent_index"] % pattern.size()]


func enemy_turn() -> Array:
	var events: Array = []
	for idx in state["enemies"].size():
		var e: Dictionary = state["enemies"][idx]
		if e["hp"] <= 0 or state["outcome"] != "":
			continue
		e["shield"] = 0
		if e["skip"]:
			e["skip"] = false
			events.append(_ev({"type": "enemy_skip", "enemy": idx}))
		else:
			events.append(_ev({"type": "enemy_start", "enemy": idx}))
			for action in intent_of(idx):
				_enemy_action(idx, action, events)
				if state["outcome"] != "":
					break
		e["intent_index"] += 1
	return events


func _enemy_action(idx: int, action: Dictionary, events: Array) -> void:
	var e: Dictionary = state["enemies"][idx]
	var p: Dictionary = state["player"]
	match action["type"]:
		"attack":
			var jam: int = e["jam"]
			e["jam"] = 0  # Brouillé ne s'applique qu'à la prochaine attaque.
			for h in int(action.get("hits", 1)):
				var dmg: int = max(0, int(action["amount"]) - jam)
				var blocked: int = min(p["shield"], dmg)
				p["shield"] -= blocked
				p["hp"] = max(0, p["hp"] - (dmg - blocked))
				events.append(_ev({"type": "player_hit", "enemy": idx, "amount": dmg - blocked, "blocked": blocked}))
				if p["reflect"] and blocked > 0:
					_damage_enemy(idx, blocked, events)
				_check_outcome()
				if state["outcome"] != "":
					return
		"shield":
			e["shield"] += int(action["amount"])
			events.append(_ev({"type": "enemy_shield", "enemy": idx, "amount": int(action["amount"])}))


# ---------------------------------------------------------------------------
# Utilitaires
# ---------------------------------------------------------------------------

func _check_outcome() -> void:
	if state["outcome"] != "":
		return
	if state["player"]["hp"] <= 0:
		state["outcome"] = "lose"
		return
	for e in state["enemies"]:
		if e["hp"] > 0:
			return
	state["outcome"] = "win"


## Ajoute à l'événement un instantané des valeurs visibles.
func _ev(ev: Dictionary) -> Dictionary:
	var p: Dictionary = state["player"]
	var es: Array = []
	for e in state["enemies"]:
		es.append({"hp": e["hp"], "shield": e["shield"], "jam": e["jam"], "skip": e["skip"]})
	ev["snap"] = {"hp": p["hp"], "shield": p["shield"], "heat": p["heat"], "enemies": es}
	return ev


func _find_in(arr: Array, uid: int):
	for c in arr:
		if c["uid"] == uid:
			return c
	return null
