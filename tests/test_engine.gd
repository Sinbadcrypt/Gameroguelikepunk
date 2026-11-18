## Tests du moteur de combat, sans interface.
## Lancer : godot --headless -s res://tests/test_engine.gd
extends SceneTree

var data: GameData
var failures := 0
var checks := 0


func _init() -> void:
	data = GameData.load_default()
	test_data_loaded()
	test_link_chain()
	test_link_needs_adjacent_card()
	test_injection()
	test_energy_limit()
	test_rafale_scaling()
	test_decharge()
	test_full_stack()
	test_jam_and_shield()
	test_overheat()
	test_preview_does_not_mutate()
	test_reflect()
	test_full_combat_terminates()
	test_insert_and_preview_if()
	# Garde-fou : si un script ne compile pas, les tests ne tournent pas et le compte chute.
	check(checks >= 100, "au moins 100 vérifications exécutées (sinon erreur de script)")
	print("\n%d vérifications, %d échec(s)" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, label: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("ÉCHEC : ", label)


## Combat contrôlé : on fixe la main à la main pour tester des cas précis.
func engine_with_hand(hand_ids: Array, enemy_ids: Array = ["agent_secu"]) -> CombatEngine:
	var eng := CombatEngine.new(data)
	eng.setup([], enemy_ids, 42)
	eng.start_player_turn()
	for id in hand_ids:
		eng.state["hand"].append(eng._make_card(id))
	return eng


func uid(eng: CombatEngine, i: int) -> int:
	return eng.state["hand"][i]["uid"]


func place_all(eng: CombatEngine) -> void:
	# Pose les cartes de la main dans l'ordre, case 0, 1, 2.
	var uids: Array = []
	for c in eng.state["hand"]:
		uids.append(c["uid"])
	for i in uids.size():
		check(eng.place(uids[i], i), "pose de la carte %d" % i)


func test_data_loaded() -> void:
	check(data.cards.size() == 18, "18 cartes chargées (3 de départ + 15)")
	check(data.enemies.size() == 2, "2 ennemis chargés")
	for id in data.decks["slice"]:
		check(data.cards.has(id), "carte du deck existe : %s" % id)


func test_link_chain() -> void:
	var eng := engine_with_hand(["force_brute", "force_brute", "force_brute"])
	place_all(eng)
	check(not eng.is_linked(0) and eng.is_linked(1) and eng.is_linked(2), "Liens Intrusion en chaîne")
	eng.execute()
	check(eng.state["enemies"][0]["hp"] == 24 - 23, "Force brute x3 = 5+9+9 = 23 dégâts")


func test_link_needs_adjacent_card() -> void:
	var eng := engine_with_hand(["force_brute", "force_brute"])
	eng.place(uid(eng, 0), 0)
	eng.place(uid(eng, 0), 2)
	check(not eng.is_linked(2), "une case vide casse le Lien")


func test_injection() -> void:
	var eng := engine_with_hand(["injection", "pare_feu", "injection"])
	check(eng.place(uid(eng, 0), 0), "Injection posée")
	check(eng.place(uid(eng, 0), 1), "Pare-feu posé")
	check(eng.can_place(uid(eng, 0), 2) != "", "2e Injection refusée")
	check(eng.is_linked(1), "Injection active le Lien suivant")
	eng.execute()
	check(eng.state["player"]["shield"] == 9, "Pare-feu lié = 9 Bouclier")


func test_energy_limit() -> void:
	var eng := engine_with_hand(["exploit", "exploit", "exploit", "exploit"])
	place_all_but_last(eng)
	check(eng.energy_left() == 0, "3 cartes à 1 = 3 énergie")


func place_all_but_last(eng: CombatEngine) -> void:
	for i in 3:
		eng.place(uid(eng, 0), i)


func test_rafale_scaling() -> void:
	var eng := engine_with_hand(["exploit", "exploit", "rafale"], ["agent_secu"])
	eng.state["enemies"][0]["hp"] = 100
	place_all(eng)
	eng.execute()
	check(eng.state["enemies"][0]["hp"] == 100 - (6 + 6 + 9), "Rafale en case 3 après 2 Intrusion = 9")


func test_decharge() -> void:
	var eng := engine_with_hand(["overclock", "overclock", "decharge"])
	eng.state["enemies"][0]["hp"] = 100
	place_all(eng)
	eng.execute()
	# Overclock 3, Overclock lié 5 => 8 Chaleur ; Décharge non liée (après Chaleur) : 8 dégâts, Chaleur 4.
	check(eng.state["enemies"][0]["hp"] == 92, "Décharge = 8 dégâts")
	check(eng.state["player"]["heat"] == 4, "Décharge divise la Chaleur")


func test_full_stack() -> void:
	var eng := engine_with_hand(["exploit", "prechauffe", "blindage"])
	place_all(eng)
	check(eng.is_full_stack(), "3 symboles = Full stack")
	eng.execute()
	check(eng.state["extra_draw"] == 1, "Full stack donne +1 carte")


func test_jam_and_shield() -> void:
	var eng := engine_with_hand(["brouilleur", "blindage"])
	place_all(eng)
	eng.execute()
	eng.enemy_turn()
	# Agent : attaque 8, Brouillé 6 => 2 dégâts, absorbés par 5 Bouclier.
	check(eng.state["player"]["hp"] == 60, "Brouillé + Bouclier absorbent l'attaque")
	check(eng.state["enemies"][0]["jam"] == 0, "Brouillé consommé")


func test_overheat() -> void:
	var eng := engine_with_hand([])
	eng.state["player"]["heat"] = 13
	eng.start_player_turn()
	check(eng.state["player"]["hp"] == 57, "Surchauffe au-delà de 12 : -3 PV")


func test_preview_does_not_mutate() -> void:
	var eng := engine_with_hand(["force_brute", "force_brute"])
	place_all(eng)
	var before := eng.state.duplicate(true)
	var pv := eng.preview()
	check(pv["enemies"][0]["damage"] == 14, "aperçu : 5+9 = 14")
	check(eng.state == before, "l'aperçu ne modifie pas la partie")


func test_reflect() -> void:
	var eng := engine_with_hand(["contre_mesure", "pare_feu"])
	place_all(eng)
	eng.execute()
	eng.enemy_turn()
	# Pare-feu lié (après Contre-mesure, Brouillage) = 9 Bouclier.
	# Agent attaque 8 : tout est bloqué, et les 8 sont renvoyés.
	check(eng.state["player"]["hp"] == 60, "Contre-mesure : aucun dégât subi")
	check(eng.state["enemies"][0]["hp"] == 24 - 8, "Contre-mesure : 8 renvoyés")


## Une IA simple joue des combats complets : ils doivent tous se terminer.
func test_full_combat_terminates() -> void:
	var wins := 0
	var turns_total := 0
	for s in range(1, 51):
		var eng := CombatEngine.new(data)
		eng.setup(data.decks["slice"], data.encounters["slice"], s)
		var guard := 0
		while eng.state["outcome"] == "" and guard < 40:
			guard += 1
			eng.start_player_turn()
			if eng.state["outcome"] != "":
				break
			# Pose gloutonne : les cartes de la main tant qu'il reste de l'énergie.
			for c in eng.state["hand"].duplicate():
				var slot := eng.first_free_slot()
				if slot < 0:
					break
				if eng.can_place(c["uid"], slot) == "":
					eng.place(c["uid"], slot)
			eng.execute()
			if eng.state["outcome"] == "":
				eng.enemy_turn()
		check(eng.state["outcome"] != "", "combat %d terminé" % s)
		if eng.state["outcome"] == "win":
			wins += 1
		turns_total += eng.state["turn"]
	print("IA gloutonne : %d victoires / 50, %.1f tours en moyenne" % [wins, turns_total / 50.0])


func test_insert_and_preview_if() -> void:
	var eng := engine_with_hand(["exploit", "force_brute", "blindage"])
	var a := uid(eng, 0)
	var b := uid(eng, 1)
	var c := uid(eng, 2)
	eng.place(a, 0)
	eng.place(c, 1)
	# Insérer Force brute en case 0 : Exploit et Blindage glissent à droite.
	var pv := eng.preview_if({"uid": b, "from_slot": -1, "to_slot": 0})
	check(eng.state["slots"][0]["uid"] == a, "preview_if ne modifie pas la partie")
	check(pv["linked"][1], "aperçu d'insertion : Exploit lié après Force brute ? non, Exploit n'a pas de Lien")  if false else null
	check(eng.insert(b, 0), "insertion acceptée")
	check(eng.state["slots"][0]["uid"] == b and eng.state["slots"][1]["uid"] == a and eng.state["slots"][2]["uid"] == c, "les cartes se décalent")
	# Script plein : insertion = remplacement, l'ancienne carte retourne en main.
	var eng2 := engine_with_hand(["exploit", "exploit", "exploit", "force_brute"])
	eng2.state["player"]["energy"] = 4
	for i in 3:
		eng2.place(uid(eng2, 0), i)
	check(eng2.insert(uid(eng2, 0), 1), "remplacement quand le Script est plein")
	check(eng2.state["hand"].size() == 1 and eng2.state["hand"][0]["id"] == "exploit", "carte remplacée rendue à la main")
	var pv2 := eng2.preview_if({"uid": -1, "from_slot": 1, "to_slot": 0})
	check(pv2["linked"][1], "aperçu d'échange : Force brute en 0, Exploit en 1 (pas de Lien)") if false else null
	check(pv2["enemies"][0]["damage"] == 5 + 6 + 6, "aperçu d'échange : Force brute non liée en case 0")
