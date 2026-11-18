# Script — roguelike deck builder cyberpunk

Vertical slice : **un combat complet**, jouable sur téléphone (navigateur) et sur PC.

**Jouer :** https://sinbadcrypt.github.io/gameroguelikepunk/ (mis à jour à chaque push sur `main`).

## Le principe
Chaque tour, tu poses jusqu'à 3 cartes dans le **Script**. Elles s'exécutent de gauche à droite.
Une carte active son **Lien** si la carte juste avant porte le bon symbole :
Intrusion (losange rose), Chaleur (anneau orange), Brouillage (disque cyan).
Les 3 symboles dans un même Script = **Full stack** : +1 carte au tour suivant.
Au-delà de 12 de Chaleur : **Surchauffe**, −3 PV par tour.

Contrôles : glisser une carte vers une case, ou la toucher. Toucher une carte posée la reprend.
Toucher un ennemi le cible. Toucher l'écran pendant l'animation l'accélère.
PC : 1-9 poser, Entrée exécuter, Retour arrière vider, Tab changer de cible.

## Structure
| Dossier | Contenu |
| --- | --- |
| `data/` | **Toutes les données de jeu** : `cards.json`, `enemies.json`, `setup.json` (règles, decks, rencontres) |
| `scripts/core/` | Logique pure, sans affichage : `game_data.gd` (chargement JSON), `combat_engine.gd` |
| `scripts/ui/` | Interface construite en code : écran de combat, cartes, ennemis, sons synthétisés |
| `tests/` | Tests du moteur (`godot --headless -s res://tests/test_engine.gd`) |

Ajouter une carte = ajouter une entrée dans `data/cards.json`. Effets disponibles :
`damage` (cible ou `"target": "all"`), `shield`, `heat`, `heat_half`, `set_heat`, `draw_next`,
`jam` (Brouillé), `skip_intent`, `reflect`, `power`. Un montant peut être dynamique :
`{ "stat": "heat" | "intrusion_before", "mult": 2, "div": 2, "add": 4 }`.

Moteur : Godot 4.3, rendu Compatibility, portrait 720×1280.
