# Structure du projet — Mafia Open World (Godot 4.x)

## Installation

1. Dézippe et copie tout le contenu (autoloads/, scenes/, resources/, scripts/) à la racine de ton projet Godot (`res://`). Si t'as pas encore de projet, crée-en un nouveau vide dans Godot d'abord.
2. **Project > Project Settings > onglet "Généraux" > sous-onglet Autoload** (chez toi c'était pas un onglet séparé, c'est dans "Généraux") : ajoute ces 5 scripts si c'est pas déjà fait :
   - `res://autoloads/GameManager.gd` → nom `GameManager`
   - `res://autoloads/EconomyManager.gd` → nom `EconomyManager`
   - `res://autoloads/SaveSystem.gd` → nom `SaveSystem`
   - `res://autoloads/PoliceManager.gd` → nom `PoliceManager`
   - `res://autoloads/BuildingRegistry.gd` → nom `BuildingRegistry`
3. **Project > Project Settings > Input Map** : ajoute ces actions (touches par défaut suggérées entre parenthèses) :
   - `toggle_map` (M) — pour `MapMenu.gd`
   - `move_forward` (Z ou W selon ton clavier)
   - `move_back` (S)
   - `move_left` (Q ou A selon ton clavier)
   - `move_right` (D)
   - `jump` (Espace)
   - `ui_cancel` existe déjà par défaut (Échap) — sert à relâcher la souris capturée par la caméra
4. **Project > Project Settings > Application > Run > Main Scene** : sélectionne `res://scenes/world/World.tscn`, sinon F5 ne lance rien.
5. Lance le projet (F5) : tu dois voir un sol gris, un capsule (le Player) qui tombe dessus, et pouvoir te déplacer en ZQSD/WASD + sauter en Espace. La souris est capturée automatiquement (Échap pour la relâcher).

## Le projet est en 3D

Player, NPC, Building et le monde utilisent les nodes 3D de Godot (`CharacterBody3D`, `Node3D`, `Area3D`, etc.), pas les versions 2D.

## Ce qui est du code réel (fonctionnel)

- `autoloads/GameManager.gd` : argent, réputation, bâtiments possédés + signaux
- `autoloads/BuildingRegistry.gd` : charge automatiquement tous les `.tres` de `resources/buildings/`
- `scripts/data/BuildingData.gd` : Resource custom pour définir un bâtiment (position en `Vector3` maintenant qu'on est en 3D)
- `scripts/data/BusinessData.gd` : Resource custom pour l'économie criminelle stylisée (stock, prix, demande, risque)
- `scenes/ui/MapMenu.tscn` + `.gd` : menu carte qui s'ouvre avec M, liste les bâtiments, gère le fast travel vers les bâtiments possédés
- `scenes/ui/BuildingMapIcon.tscn` + `.gd` : icône cliquable par bâtiment sur la carte (vert = possédé, jaune = pas encore acheté)
- `scenes/world/World.tscn` : **assemblée** — Player, HUD et MapMenu sont instanciés dedans, plus une DirectionalLight3D et un sol de test (`TestFloor`, juste une grosse boîte grise, à remplacer par ta vraie ville plus tard)
- `scenes/player/Player.tscn` + `.gd` : **déplacement 3D fonctionnel** (WASD/ZQSD relatif à la caméra, saut, gravité) + caméra troisième personne (SpringArm3D qui suit la souris) — le Player est dans le groupe `player`
- `scenes/buildings/Building.tscn` + `.gd` : zone Area3D qui détecte le joueur (boîte orange visible), prévient l'UI d'achat quand tu entres/sors
- `scenes/ui/BuildingPurchaseUI.tscn` + `.gd` : panneau qui affiche nom/prix/revenu du bâtiment approché, bouton Acheter qui débite `GameManager.money` et marque le bâtiment comme possédé
- `resources/buildings/warehouse.tres` : un premier bâtiment de test ("Entrepôt abandonné", 2000$), placé à 10 unités du point de spawn dans World.tscn — marche jusqu'à la boîte orange pour tester

## Ce qui est une coquille vide (juste le bon type de node, à remplir plus tard)

- Les 4 districts (Downtown, Industrial, Residential, Docks) — pas encore intégrés dans World.tscn, juste des fichiers séparés pour l'instant
- `scenes/npc/NPC.tscn` (capsule juste pour voir un volume dans l'éditeur, pas de logique dedans)
- `scenes/ui/HUD.tscn` : toujours vide (pas encore d'affichage argent/réputation à l'écran)

## Pas encore fait du tout

- Logique EconomyManager, SaveSystem, PoliceManager (juste des TODO pour l'instant)
- Les districts ne sont pas encore placés dans World.tscn (juste des fichiers séparés)
- HUD qui affiche l'argent/réputation en permanence à l'écran
- Le fast travel du MapMenu ne téléporte pas encore réellement le joueur (juste un TODO dans le code)
- NPC : aucune logique, juste un CharacterBody3D vide
- La vente de drogue / économie criminelle stylisée en tant que telle (EconomyManager est vide pour l'instant)

## Prochaine étape

HUD qui affiche argent + réputation en direct (connecté aux signaux `money_changed`/`reputation_changed` de GameManager), ou on attaque l'économie criminelle stylisée (EconomyManager) — dis-moi.

