# Repères pour Claude Code

Fiche écrite pour être lue au début de chaque session : le contexte du projet, la méthode de
travail imposée, les commandes exactes, les pièges déjà payés et l'état d'avancement.

## 1. Le projet

- Jeu **open world mafia** façon *Tulsa King*, vue à la troisième personne, en **3D**.
- Moteur **Godot 4.7.2** (Forward+, D3D12 sous Windows), tout le code en **GDScript**.
- Dépôt GitHub `JLCanadaPrice/Game-Godot-gta-like-`, branche de travail **`carte-3d`**.
- Tag de retour : `avant-chantier-routes`.
- Le projet vit sur un **disque externe dont la lettre change selon le PC** (actuellement `D:`,
  il a déjà été `E:`). Vérifier les chemins avant de relancer une commande d'une autre session.
- Git refuse le dépôt pour cause de propriétaire douteux : préfixer **toutes** les commandes par
  `git -c safe.directory=<chemin du dépôt>`.
- Binaire Godot : `<disque>:/p-recree/Godot_v4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe`
  (la variante `_console` écrit sur la sortie standard, c'est celle qu'il faut pour les tests).
- `README.md` décrit un état très ancien du projet (sol gris de test) : ne pas s'y fier.
- **L'historique a été réécrit le 2026-09-19** (`git filter-repo`) pour sortir 16 dossiers de
  sources d'assets brutes — `.fbx`, `.obj`, `.blend`, planches de textures d'origine, tous déjà
  ignorés par Godot via `.gdignore` et jamais chargés. Le dépôt est passé de **564 à 278 Mo**,
  l'arbre de travail de **2,19 Go à 987 Mo**. Ces sources vivent maintenant dans un **dépôt privé
  séparé** (`D:/p-recree/sources-brutes`, arborescence identique) : privé parce que plusieurs packs
  sont à licence NON VÉRIFIÉE. Conséquences pratiques : tous les SHA d'avant le 2026-09-19 sont
  périmés, et **ne jamais recommiter une source brute dans ce dépôt-ci** — si un pack doit être
  retravaillé, le copier hors du projet. Le compte de `ProjectLoadCheck` n'a pas bougé (584), ce qui
  est la preuve que rien de chargé n'est parti.

## 2. Méthode de travail (imposée, non négociable)

- **Mesurer depuis les vertices du maillage cuit**, jamais depuis une valeur théorique, une
  constante ou un nom de fichier. Les outils de `scenes/world/map/tools/` en lecture seule
  (`RampAudit`, `RampPoints`, `RampSteps`, `RampDrive`, `PlacesRangeAudit`) sont faits pour ça et
  doivent être rejoués après chaque correction.
- **Sauvegarde `.bak` datée avant chaque modification** :
  `<Nom>_backup_<AAAA-MM-JJ_HHMM>.<ext>.bak`. **Jamais de copie `.tscn` ou `.gd`** sous un nom que
  Godot va scanner : ça duplique l'UID et Godot charge la mauvaise scène. Ces `.bak` sont suivis
  par git.
- **Chaîne de cuisson COMPLÈTE, dans l'ordre documenté, sans sauter une seule étape** (§4). Sauter
  `DistrictsBake`/`PlacesBake` fait perdre le nivellement des parcelles et casse `MapDistrictsTest` ;
  sauter `VegetationBake` laisse une carte qui n'est pas celle que la chaîne produit.
- **Tests headless après chaque étape** (§5), **un commit séparé par étape**.
- **Captures au niveau du sol**, à hauteur d'homme ou de conduite, jamais vues du ciel : c'est
  comme ça que le jeu se joue. Les images restent hors du dépôt, seuls les chiffres vont dans le
  message de commit.
- **Si un test casse : corriger la cause, jamais contourner.** Si un échec est antérieur à la
  modification, le prouver (rejouer le test sur `HEAD~1`) et le dire.
- Ne jamais utiliser `git stash` sur `scenes/world/map/generated` : une cuisson non commitée y a
  déjà été perdue. Copier le dossier ailleurs si besoin.

## 3. Seuil de performance

- **Machine de référence : Intel UHD 750** (PC d'école). Les FPS de la machine de travail ne
  disent rien ; les compteurs de rendu de `MapShotsTest` (appels de dessin, objets, primitives)
  sont la mesure comparable.
- **+10 % d'appels de dessin au maximum** sur les **6 vues de référence** :
  `echangeur_nord_ouest`, `carrefour_willow_lake`, `rond_point_echo`, `losange_aeroport`,
  `quartier_bluffview_survol`, `lieu_echo_circle`.
- Pour tout ce qui touche au ferroviaire, budget complémentaire de **+30 appels de dessin** sur les
  **6 vues ferroviaires** : `voie_ferree_pont_riviere`, `voie_ferree_passage_niveau`,
  `voie_ferree_viaduc_est`, `voie_ferree_sur_voie_express`, `voie_ferree_portail_est`,
  `voie_ferree_heurtoir_ouest`. (Les trains n'apparaissent dans aucune des 6 vues de référence :
  sans ce budget-là, le seuil serait respecté sans rien prouver.)
- La mesure « avant » doit être refaite **sur la machine du jour**, code non modifié, avant la
  modification — pas reprise d'une session ou d'un commentaire.

- **Depuis le cycle jour/nuit, toute vue doit être mesurée DE JOUR ET DE NUIT.** Les 12 vues ci-dessous sont toutes
  diurnes : de jour les halos de lampadaire sont cachés et les vraies lumières éteintes, donc elles ne prouvent
  rien sur le coût nocturne. `MapShotsTest --heure=1` rejoue les mêmes vues de nuit ; les vues `nuit_*` au sol
  servent aux captures.
- **Les appels de dessin ne mesurent PAS le coût des lumières.** Une `OmniLight3D` ou une `SpotLight3D` n'ajoute
  aucun appel de dessin : elle ajoute du travail dans la passe d'ombrage. Mesuré le 2026-09-19 : 0 et 1 540 vraies
  lumières donnent exactement le même nombre d'appels. Pour comparer des approches d'éclairage, il faut le temps
  GPU, et **la machine de développement ne sait pas le mesurer** : elle rend la scène en ~1,8 ms, les lumières y
  sont noyées dans le bruit, et trois métriques s'y sont contredites (cf. §9). La seule mesure valable est
  `RenderPerfTest` sur l'UHD 750, qui accepte maintenant `--heure=`, `--bassin=` et `--toutes-lampes`.

Référence relevée le 2026-09-18 en 800x450 (après le chantier de Northgate Rise) :

| vue de référence | appels | | vue ferroviaire | appels |
|---|---|---|---|---|
| echangeur_nord_ouest | 347 | | pont_riviere | 397 |
| carrefour_willow_lake | 395 | | passage_niveau | 258 |
| rond_point_echo | 661 | | viaduc_est | 385 |
| losange_aeroport | 395 | | sur_voie_express | 407 |
| quartier_bluffview_survol | 267 | | portail_est | 201 |
| lieu_echo_circle | 596 | | heurtoir_ouest | 154 |

Référence relevée le **2026-09-19** en 800x450, après le cycle jour/nuit, sur la machine du jour. Le jour est
mesuré à **12 h** et la nuit à **1 h**. La colonne « avant » est la mesure du même jour, code non modifié :

| vue de référence | avant | jour 12 h | nuit 1 h | | vue ferroviaire | avant | jour | nuit |
|---|---|---|---|---|---|---|---|---|
| echangeur_nord_ouest | 354 | 333 | 259 | | pont_riviere | 406 | 404 | 342 |
| carrefour_willow_lake | 402 | 352 | 175 | | passage_niveau | 268 | 266 | 209 |
| rond_point_echo | 664 | 610 | 454 | | viaduc_est | 396 | 366 | 300 |
| losange_aeroport | 400 | 351 | 252 | | sur_voie_express | 418 | 415 | 357 |
| quartier_bluffview_survol | 274 | 268 | 213 | | portail_est | 199 | 179 | 89 |
| lieu_echo_circle | 592 | 554 | 433 | | heurtoir_ouest | 161 | 152 | 61 |

**La nuit coûte MOINS cher que le jour partout**, de 22 à 56 % d'appels en moins, et le jour lui-même a baissé.
Ce n'est pas une surprise mais une conséquence voulue : `DayNightCycle` **coupe les ombres du soleil la nuit**
(la lune n'en projette pas), et la passe d'ombre directionnelle est le plus gros poste d'appels de dessin de la
scène. La baisse de jour vient du soleil qui culmine maintenant à 62° au lieu des 45° du soleil fixe d'avant :
la cascade d'ombres attrape moins d'objets.

## 4. Chaîne de cuisson (ordre exact)

`GODOT` = le binaire console, `PROJET` = la racine du dépôt.

```bash
GODOT="D:/p-recree/Godot_v4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe"; PROJET="D:/p-recree/test/test"
"$GODOT" --headless --path "$PROJET" --script res://scenes/world/map/tools/RoadBake.gd
"$GODOT" --headless --path "$PROJET" --script res://scenes/world/map/tools/DistrictsBake.gd
"$GODOT" --headless --path "$PROJET" --script res://scenes/world/map/tools/PlacesBake.gd
"$GODOT" --headless --path "$PROJET" --script res://scenes/world/map/tools/VegetationBake.gd
"$GODOT" --headless --path "$PROJET" --script res://scenes/world/map/tools/MapBackgroundBake.gd
"$GODOT" --headless --path "$PROJET" --script res://scenes/world/map/tools/TerrainBake.gd -- --from-heights
"$GODOT" --headless --path "$PROJET" --import
```

La passe `--import` finale n'est pas facultative : `MapBackgroundBake` réécrit
`map_background.png` et, sans réimport, le jeu affiche « Failed loading resource ».

Autres cuissons, plus rares, hors de cette chaîne : `RoadTexturesBake`, `TerrainTexturesBake`,
`BuildingCatalogBake`, `TrainsBake` (fusionne les caisses du pack de trains en un maillage chacune dans
`generated/trains/`, à relancer seulement si le pack change), `DowntownFurnitureBake` (mobilier du centre-ville :
lampadaires, arbres, bancs, camions de caserne, **et les halos de lampadaire du cycle jour/nuit**). Vérifications
sans effet de bord : `MapSpecCheck`, `RoadNetworkPreview`, `ProjectLoadCheck`.

**Toucher aux lampadaires impose DEUX cuissons hors chaîne** : `RoadBake` écrit les luminaires de la carte
(`generated/roads/lamp_heads.tres`) et `DowntownFurnitureBake` ceux du centre-ville
(`downtown/generated/lamp_heads.tres`). Oublier la seconde laisse 906 lampadaires sur 1 375 sans halo et sans
lumière la nuit.

## 5. Batterie de tests headless

Les tests sont des **scènes** (sauf `ProjectLoadCheck`, qui est un script). Chacun imprime une
ligne `<NOM>_RESULT OK` ou `FAIL`.

```bash
"$GODOT" --headless --path "$PROJET" res://scenes/tests/MapRoadsTest.tscn          # rubans, croisements, pentes
"$GODOT" --headless --path "$PROJET" res://scenes/tests/MapRailTest.tscn           # tracé de la voie, gabarit, trottoirs
"$GODOT" --headless --path "$PROJET" --fixed-fps 60 res://scenes/tests/MapTrainsTest.tscn  # cantons, vagues, passages à niveau, collision des caisses
"$GODOT" --headless --path "$PROJET" res://scenes/tests/MapDistrictsTest.tscn      # parcelles nivelées, emprises
"$GODOT" --headless --path "$PROJET" res://scenes/tests/MapPlacesTest.tscn         # entrées à moins de 15 m d'une route, rien sur la chaussée
"$GODOT" --headless --path "$PROJET" res://scenes/tests/MapTerrainTest.tscn        # tuiles, rivière, trous
"$GODOT" --headless --path "$PROJET" res://scenes/tests/MapVegetationTest.tscn     # arbres, troncs, portées
"$GODOT" --headless --path "$PROJET" res://scenes/tests/MapExplorationTest.tscn    # la carte reste parcourable
"$GODOT" --headless --path "$PROJET" res://scenes/tests/MapGateTest.tscn           # portail et bosquet de Hollow Creek
"$GODOT" --headless --path "$PROJET" res://scenes/tests/SimulationCullingTest.tscn # gel hors champ
"$GODOT" --headless --path "$PROJET" res://scenes/tests/DayNightTest.tscn         # cycle jour/nuit, halos, luminaires
"$GODOT" --headless --path "$PROJET" res://scenes/tests/WorldTrafficSmokeTest.tscn # trafic (aléa connu, cf. §6)
"$GODOT" --headless --path "$PROJET" res://scenes/tests/NoclipTest.tscn            # noclip, aléa connu aussi
"$GODOT" --headless --path "$PROJET" --fixed-fps 60 --quit-after 300 res://scenes/tests/VehicleCatalogTest.tscn  # catalogue des véhicules, 20 000 tirages
"$GODOT" --headless --path "$PROJET" res://scenes/tests/CarDrivingTest.tscn
"$GODOT" --headless --path "$PROJET" res://scenes/tests/CarDropTest.tscn
"$GODOT" --headless --path "$PROJET" res://scenes/tests/CarKerbTest.tscn          # bordures : le joueur monte, l'IA non
"$GODOT" --headless --path "$PROJET" res://scenes/tests/DowntownStreetsTest.tscn
"$GODOT" --headless --path "$PROJET" res://scenes/tests/DowntownBuildingsTest.tscn
"$GODOT" --headless --path "$PROJET" res://scenes/tests/ShopBuildingsTest.tscn     # échec ANTÉRIEUR connu
"$GODOT" --headless --path "$PROJET" --script res://scenes/world/map/tools/ProjectLoadCheck.gd   # attendu : 584 fichiers, 0 échec
```

Outil d'inspection, hors batterie : `res://scenes/tests/VehicleSortTest.tscn` aligne les véhicules du catalogue
sur une grille plate, nom de fichier affiché au-dessus, caméra libre (ZQSD, souris, Espace/Ctrl, Maj). Sert à
trier le parc ; un civil à poids nul y est écrit en rouge avec la mention « RETIRÉ DE LA CIRCULATION ».
**Jetable : référencée nulle part, ni dans `World.tscn` ni sur la carte.**

Retirer un véhicule de la circulation, de façon réversible : mettre son `traffic_weight` à 0 dans son
`resources/vehicle_models/<id>.tres`. Pour le sortir carrément du catalogue (et donc du tirage, de la scène de tri
et du futur système de police), le déplacer dans `resources/vehicle_models/retires/` — `VehicleCatalog._load()`
balaie le dossier avec `DirAccess.get_files()`, qui n'est pas récursif. Voir le `LISEZMOI.txt` de ce sous-dossier.

Captures et compteurs de rendu (fenêtré, pas headless : le rendu compte) :

```bash
"$GODOT" --path "$PROJET" --resolution 800x450 res://scenes/tests/MapShotsTest.tscn -- --out=<dossier> --views=vue1,vue2
```

`MapShotsTest` accepte aussi `--heure=<0..24>` (fige le cycle jour/nuit à cette heure, indispensable pour mesurer de
nuit), `--bassin=<n>` (taille du bassin de vraies lumières de lampadaire), `--toutes-lampes` (une vraie lumière par
luminaire : mesure de l'option écartée, jamais un réglage de jeu) et `--sans-image` (mesure sans `get_image()`, donc
sans le plafond de 800x450 du §6). Une vue peut imposer sa propre heure par un 5e champ : c'est ce que font les vues
`nuit_*`, `crepuscule_*` et `aube_*`.

## 6. Pièges connus (tous déjà payés)

- **`_own()` ne descend pas dans une scène instanciée** (`PlacesBake.gd`, fin de fichier) : les
  enfants d'un modèle FBX n'ont pas de propriétaire, ne sont donc pas enregistrés dans la scène
  cuite, et **tout réglage posé dessus est perdu** — les `visibility_range_end` ressortaient à 0,
  donc jamais coupés (47 maillages de chantier encore dessinés à 1,1 km). Faire descendre `_own()`
  partout a été essayé et **rejeté par la mesure** : `Places.tscn` passait de 66 ko à 2,9 Mo et
  chaque maillage était stocké en double. La bonne réponse : fusionner le modèle en un maillage,
  l'enregistrer en `.res` dans `generated/places/`, poser un `MeshInstance3D` par exemplaire et
  régler la portée dessus (cf. `_fbx_model`). `_prop()` a encore le même défaut.
- **`WorldTrafficSmokeTest` et `NoclipTest` ont un aléa** : le premier signale parfois « 1 paires
  avec véhicule long », le second a lâché une fois sur trois sur « voiture à portée » (la voiture
  du trafic n'était pas encore arrivée). Avant d'accuser une modification, rejouer le test deux
  fois, puis le rejouer sur `HEAD~1`.
- **Le GPU décroche en capture** (`0x887A0005`, `DXGI_ERROR_DEVICE_REMOVED` pendant `get_image()`).
  Ne jamais capturer au-dessus de **800x450**, et si une vue tombe quand même, la reprendre seule
  en **640x360** : les compteurs restent comparables entre les deux résolutions, pas les images.
  Le premier lancement d'une session prend plusieurs minutes (compilation du cache de shaders).
- **Un objet posé près d'un point de contrôle de `MapGateTest` casse le test** : le test y pose le joueur et le
  fait marcher 10 m. Une ambulance garée à 3 m du point « parvis du St. Anselm Medical Center » (-290, 137) l'a
  bloqué au bout de 1,4 m. Même règle que pour la végétation : **rien de solide à moins de 12 m d'un point de
  contrôle**. Les 43 points sont listés dans `MapGateTest.gd`.
- **`_fbx_model()` de `PlacesBake` fusionnait avec le transform LOCAL de chaque maillage**, pas avec son transform
  relatif à la racine. Sans conséquence sur les FBX du chantier, dont la hiérarchie est plate, mais un `.glb` dont
  les maillages sont sous un nœud mis à l'échelle sortait à une taille délirante — une ambulance de 225 m de long.
  Corrigé le 2026-09-18 ; le nombre de triangles des modèles déjà posés n'a pas bougé.
- **`ShopBuildingsTest` échoue depuis avant ces chantiers** : ne pas l'imputer à la modification du
  jour, ne pas le « réparer » au passage.
- **Le mode `"sol"` de `MapShotsTest` élève aussi le point visé** : un point visé au-dessus d'un
  bâtiment accroche son toit et retourne la caméra vers le ciel. Pour une caméra devant un immeuble,
  relever la hauteur du sol et écrire des altitudes absolues.
- Les `.tscn` cuits changent textuellement à chaque cuisson (identifiants de sous-ressources tirés
  au hasard) : un `git status` « modifié » ne prouve pas un changement de contenu.
- **Il y a DEUX voitures dans ce jeu, et elles ne réagissent pas pareil au décor.** `Car.gd` est un
  `CharacterBody3D` arcade : c'est le modèle des 252 voitures de la circulation ET ce que le joueur
  conduit quand il prend une voiture dans la rue. `PlayerCarPhysics` (`PlayerCarController.gd` sur le
  cœur `assets/car_physics`) est un `RigidBody3D` dont les quatre roues sont des **RayCast3D** : il n'y
  a aucun collisionneur de roue, et sa coque flotte **2,23 m au-dessus du sol**, son origine reposant à
  **sol + 2,566 m** (mesuré). Posée plus bas, la suspension part en butée et catapulte la voiture à 5 m :
  toute sonde qui instancie cette voiture doit la lâcher à sol + 2,57 m, jamais « juste au-dessus du sol ».
- **`move_and_slide()` ne monte AUCUNE marche verticale**, si basse soit-elle. Les bordures de trottoir
  de la carte font **0,150 m** mesurés sur la collision cuite, en marche franche (la montée tient entre
  deux relevés distants de 2 cm), sur trimesh pour les artères et sur piles de boîtes au centre-ville.
  D'où `Car._try_step_up`, réservé au joueur. `scenes/world/CurbRamp.gd` était la réponse précédente :
  il ne reconnaissait que des `StaticBody3D` nommés `*Walk*` portant une seule `BoxShape3D` — la
  disposition du monde d'essai d'origine — et **il n'était attaché à aucun nœud de `World.tscn`**, donc
  il ne tournait plus du tout. **Supprimé le 2026-09-19** (avec son `.uid`) ; il ne reste que dans
  l'historique git et dans `World_backup_avant_integration.tscn.bak`. Ne pas le ressusciter.
- **Les autoloads ne sont pas enregistrés en mode `--script`** : une sonde qui instancie
  `PlayerCarPhysics` échoue sur « Identifier not found: VitaVehicleSimulation ». La lancer comme
  **scène**, pas comme script.
- **Un `CharacterBody3D` inerte n'est jamais repoussé** : c'est lui qui résout ses pénétrations dans
  `move_and_slide()`. Une sonde qui pose un corps sans l'animer et regarde si un train le pousse mesure
  zéro, quelle que soit la collision d'en face.

## 7. État d'avancement

**Fait** — la carte 3D est le gros du travail accompli : modèle de terrain et rivière, réseau
routier complet (autoroutes, échangeurs, bretelles, artères, anneau et rond-point Echo Circle,
113 carrefours du centre-ville, 114 culs-de-sac en bulbe, glissières, marquage, trottoirs),
voie ferrée de 4,5 km avec ses ouvrages, quartiers et 1 196 bâtiments, 12 lieux (aéroport, motel,
ranch, planque, hôtel, hôpital, commissariat, casino, concessionnaire Liberty Motors, Greenfield,
Echo Circle, chantier de Northgate Rise), végétation (20 297 arbres), trafic routier sur
`CircuitPath` avec feux, cédez-le-passage et suivi de véhicule, PNJ sur `PathGraph`, gel de
simulation hors champ (`SimulationCuller`), centre-ville et intérieurs d'appartements, noclip de
débogage sur `V`.

**Reste à faire** (liste du joueur, par ordre d'importance qu'il donnera lui-même) :

- **combat** ;
- **gangs rivaux** ;
- **labo de drogue** (les modèles sont dans `assets/drug_lab`) ;
- **porte d'entrepôt** ;
- **appartements reliés à la carte** (les intérieurs existent, ils ne sont pas raccordés aux
  bâtiments de la carte) ;
- **concessionnaire enrichi** ;
- **bug : 0 voiture exposée** chez le concessionnaire ;
- **chantier « relier tous les bâtiments à la route »** (cf. ci-dessous).

### Chantier à prévoir : relier les bâtiments à la route

Les lieux et les bâtiments sont posés sur la pelouse sans rien qui les raccorde à la chaussée : on tombe
régulièrement sur 2 à 3 m d'herbe entre une dalle et le trottoir, et sur des dalles voisines séparées par une
bande d'herbe. Le commissariat et l'hôpital ont été traités les 2026-09-19 (`d818e1e`, `ca797e8`), le reste non.

**Recensement du 2026-09-19**, mesuré et non estimé : pour chaque bâtiment on part de son centre et on marche vers
l'extérieur dans les quatre directions d'axe, au pas de 1 m jusqu'à 50 m, en retenant la direction qui atteint une
chaussée ou un trottoir en traversant le moins d'herbe.

| ensemble | bâtiments | reliés sans herbe | **coupés par de l'herbe** | sans route à moins de 50 m |
|---|---|---|---|---|
| quartiers (`buildings/lots.json`) | 1 196 | 486 | **682** | 28 |
| centre-ville (`downtown/generated/buildings.json`) | 441 | 441 | 0 | 0 |
| **total** | **1 637** | 927 | **682 (41,7 %)** | 28 |

Épaisseur d'herbe à traverser : **médiane 8 m, maximum 34 m**. Le centre-ville est indemne parce que l'intérieur
de ses îlots est déjà dur (sol à +0,200 m) ; le problème est entièrement dans les quartiers.

Ce qu'il faut savoir avant de s'y mettre, tiré des deux sites déjà faits :

- Altitudes de référence, relevées au rayon : **pelouse d'îlot -0,050 m, dalle de lieu +0,020 m, chaussée
  +0,050 m, trottoir +0,200 m**. Poser une liaison au même dessus que la dalle qu'elle rejoint (`y + 0,05` dans
  `PlacesBake`) ne crée aucune marche ; la seule marche restante est celle de 7 cm que les dalles avaient déjà
  sur la pelouse.
- **Découper en bandes étroites fabrique le défaut qu'on corrige.** Au commissariat, trois bandes (parvis vers
  trottoir, allée, cheminement) ont laissé un îlot d'herbe de 10 x 10,5 m enclavé entre elles. Mieux vaut peu de
  grands rectangles qui se touchent sur toute leur longueur, et faire mordre chaque liaison de 0,5 m sur la dalle
  qu'elle rejoint.
- Le contrôle qui décide est le **cheminement** : échantillonner la polyligne rue -> entrée tous les 0,25 m et
  exiger zéro case d'herbe. Un balayage de la façade au pas de 1 m sert à débusquer les poches enclavées.

### Parc de véhicules

Le catalogue est `resources/vehicle_models/*.tres` (un `VehicleModelData` par modèle), lu par
`VehicleCatalog` et appliqué par `Car._setup_model()`. **72 modèles, 214 variantes de couleur** :
61 civils, 5 police, 3 urgence, 3 SWAT. Toute la famille `city_*` est à l'échelle **1,65**, mesurée
et non supposée : à cette échelle une berline du pack fait 2,02 m de large contre 2,111 m pour une
voiture du jeu.

`VehicleCatalog.AMBIENT_ROLES` (`civil`, `police`, `emergency`) est ce que tire la circulation de
fond. Le `role` dit ce que le véhicule EST — c'est par lui que le futur système de police ira
chercher ses voitures — et sa présence dans le trafic se règle par son **poids**, pas en le
déguisant en civil. Poids des véhicules rares : police sedan et SUV 0,10, police van 0,05, police
truck 0,03, ambulance 0,08, fourgon d'urgence 0,05, camion de pompiers 0,04, soit **1,4 % du
trafic**.

**SWAT** : rôle `swat`, poids 0, jamais tiré par la circulation. `VehicleCatalogTest` échoue si un
SWAT reçoit un poids. Ils sont prêts pour les missions et le futur système police.

**Hélicoptères** (`Veh_Air_Ambulance_Helicopter`, `Veh_Police_Helicopter`, `Veh_SWAT_Helicopter`) :
**hors catalogue pour l'instant**, et c'est volontaire. Ils sont utilisables plus tard — 10,62 ×
1,69 × 3,38 m à l'échelle 1,65, 726 à 876 triangles, un seul matériau, et surtout `Rotor_Main` et
`Rotor_Tail` sont des **nœuds séparés donc animables** (celui de la police a en plus un
`Search_Light`). Mais ils n'ont **aucune roue** : `Car.gd` est un véhicule terrestre et
`VehicleCatalogTest` exige au moins 3 roues dont exactement 2 avant. Les mettre au catalogue
casserait le test. Il faudra **un contrôleur de vol distinct**, et exempter le rôle `aircraft`
(déjà en réserve dans l'enum de `VehicleModelData`) des contrôles de roues.

Retirer un véhicule de la circulation, de façon réversible : voir la note de la §5 sur
`traffic_weight` et `resources/vehicle_models/retires/`.

## 8. Chantier en cours : trains en mouvement

Étapes 1 à 4 construites et commitées le 2026-09-18 ; **l'étape 5 (optimisation) reste à faire**, le
joueur voulant d'abord essayer en jeu.

Modèles retenus, et eux seuls (pack `assets/Modular Train Pack-zip`, **pas encore commité**,
3,0 Mo, sans fichier de licence, importé le 2026-09-18) : `HighSpeed_Front`, `HighSpeed_Wagon`,
`CargoTrain_Front`, `CargoTrain_Wagon`, `CargoTrain_Container`, `CargoTrain_CoalContainer`. Les
`Locomotive_*` ne sont pas utilisés. Aucun de ces matériaux n'a de texture (couleurs unies,
toutes opaques, `emission` activée par l'import à neutraliser) : chaque caisse peut donc être
cuite en une seule surface à couleurs de sommets, soit **un appel de dessin par caisse**, et les
wagons d'un même type se dessinent en `MultiMeshInstance3D`.

Voie mesurée : 1 124 points au pas de 4,00 m, **4 492 m**, rayon minimal **191,4 m**, pente
maximale **3,00 %**, altitudes de 0,70 à 18,92 m, **voie unique avec deux culs-de-sac** à
(2168, 15,40, 195) et (-2170, 0,70, 800), **3 ouvrages** où le train passe au-dessus d'une route
en tranchée (dégagement 5,80 m), **rien au-dessus de la voie** nulle part, et **2 passages à
niveau** seulement : `art_a7_n:0` en (-389,4 ; 252,2) et `art_a8:0` en (-113,3 ; 274,5), artères
de 10,5 m, ligne d'arrêt à 8,9 m de l'axe.

Les cinq étapes, une par commit :

1. `rail_path.tres` cuit par `RoadBake` + `MapRailTest`. **fait** (`bbf8938`)
2. Modèles fusionnés en `.res`, `RailPath.gd`, `Train.gd`, une rame grande vitesse. **fait** (`cc05177`)
3. Cantons (280 m), plusieurs trains, sens unique par vague, terminus. **fait** (`d3d9df6`)
4. Passages à niveau : blocs d'arrêt invisibles du groupe `vehicle` + barrières en décor. **fait**
5. `SimulationCuller`, `MultiMesh`, mesure de perf sur les 12 vues. **à faire**

Compositions arrêtées : **1 + 4** pour la grande vitesse (60,48 m, 90 km/h), **1 + 14 panachés**
pour le fret (155,56 m, 55 km/h, 73 176 triangles). Repli prévu si l'UHD 750 souffre : 1 + 10.
Pack de trains commité à l'étape 1 avec ses `.import` et un `LICENSE_ATTRIBUTION.txt` qui le classe
en licence NON VÉRIFIÉE.

Ce que l'étape 5 devra savoir :

- **Un appel de dessin par caisse** pour l'instant : 5 pour une rame grande vitesse, 15 pour un fret.
  C'est le `MultiMesh` de l'étape 5 qui doit ramener ça à un appel par type de caisse.
- **Gel en deux temps** : un gel strict au-delà de 50 m ferait qu'un train attendu à un passage à
  niveau, à 240 m et hors écran, n'arriverait jamais. Le gel doit laisser avancer l'abscisse du train
  (`Train.head`) et ne couper que l'écriture des transformations de caisses (`Train._place`).
- **Effet de bord connu des blocs d'arrêt** : `LoopSpawner._process_proximity` compte
  `get_nodes_in_group("vehicle")` pour son plafond `max_active`. Pendant une fermeture, les 2 blocs du
  passage gonflent ce compte, donc une ou deux voitures de moins apparaissent pendant ~20 s. Corrigeable
  d'une ligne dans `LoopSpawner` si ça gêne ; laissé tel quel pour ne toucher à rien du trafic.
- **Piétons aux passages à niveau** : les 4 traversées de trottoir de la carte sont toutes sur les
  2 passages à niveau (mesuré par `MapRailTest`), aucune ailleurs. Les barrières n'arrêtent pas les
  PNJ : il n'y a pas encore de version piétonne des blocs d'arrêt.

Réserve à ne pas oublier à l'étape 5 : un gel strict au-delà de 50 m ferait qu'un train attendu à
un passage à niveau, à 240 m et hors écran, **n'arriverait jamais**. Le gel doit laisser avancer
l'abscisse du train et ne couper que l'écriture des transformations de wagons.

## 9. Cycle jour/nuit et éclairage des lampadaires

Construit le 2026-09-19. Deux nœuds dans `World.tscn`, volontairement séparés parce qu'ils n'ont ni le même rôle
ni le même coût :

- **`DayNight`** (`scenes/world/DayNightCycle.gd`) : l'heure, la course du soleil, le ciel, le brouillard,
  l'ambiante. N'allume rien lui-même ; il publie `hour_changed(heure, facteur_nuit)`.
- **`StreetLights`** (`scenes/world/StreetLights.gd`) : écoute, et allume.

**Durée : 48 minutes réelles pour 24 h de jeu** (2 min par heure de jeu, la durée de GTA V). Jour utile 6 h-20 h
soit 28 min, nuit noire 21 h-5 h soit 16 min. Le « facteur nuit » vaut 0 en plein jour, 1 en pleine nuit et
interpole entre 5-7 h et 19-21 h : c'est lui qui fond les lampadaires, pas un interrupteur.

**Touche `N`** : +1 h. **`Maj+N`** : -1 h. **`Ctrl+N`** : fige ou relance le cycle. Une horloge s'affiche en haut
à droite pendant 2,5 s après chaque changement, et en permanence quand le cycle est figé.

### Comment les 1 375 lampadaires s'allument sans coûter

**Il y a 1 375 mâts et 1 540 luminaires** (les doubles en portent deux) : 509 mâts / 634 luminaires sur la carte
(`RoadBake`), 866 mâts / 906 luminaires au centre-ville (`DowntownFurnitureBake`).

Deux mécanismes, et c'est la séparation qui tient le budget :

1. **Les halos, partout.** Une petite boîte non éclairée sur chaque luminaire, **fusionnée avec les autres en un
   maillage par cellule** (carte) ou par bloc (centre-ville) : 96 maillages, 18 480 triangles pour toute la carte.
   Cachés le jour (0 appel de dessin), visibles la nuit (**1 appel par cellule visible**). Les 1 540 halos
   partagent **UN SEUL matériau** (`scenes/world/lamp_glow_material.tres`) : c'est la condition pour que le moteur
   les regroupe, exactement la leçon déjà payée sur les mâts (cf. `LampPoleLayer`, où une copie de matériau par
   poteau avait fabriqué 378 appels). `DayNightTest` échoue si un deuxième matériau apparaît.
2. **Les vraies lumières, seulement près du joueur.** Un bassin de **16 `SpotLight3D` sans ombre** suit la caméra
   et se pose sur les 16 luminaires les plus proches, réaffecté toutes les 0,25 s ou dès que la caméra a bougé de
   4 m. Cône de 55° et portée 17 m, calés sur la géométrie mesurée (luminaire à 6,2 m, artère de 10,5 m) : la
   flaque couvre la chaussée et ses deux trottoirs.

**Le réglage se change sans recompiler** : `pool` sur le nœud `StreetLights`. À 0, il ne reste que les halos — la
rue garde ses lampadaires visibles mais perd ses flaques de lumière au sol (comparaison au sol faite, la
différence est nette). C'est le bouton à baisser en premier si l'UHD 750 souffre.

### Pourquoi pas une vraie lumière par lampadaire, et pourquoi je ne peux pas le chiffrer ici

L'option a été construite et mesurée (`--toutes-lampes` : 1 540 `SpotLight3D`). **Trois métriques ont été
essayées, aucune ne départage les options sur la machine de développement :**

1. **Appels de dessin** : identiques à l'unité près entre 0, 8, 16, 32, 64 et 1 540 lumières. Normal, et c'est
   une leçon à retenir : une lumière ponctuelle n'ajoute aucun appel de dessin, elle ajoute du travail dans la
   passe d'ombrage. Le seuil du §3 ne mesure donc PAS le coût de l'éclairage.
2. **`viewport_get_measured_render_time_gpu`, 800x450** : « 0 lumière » ressortait plus lent que 1 540, et b32
   plus rapide que b16. Incohérent.
3. **Même compteur en 1920x1080 sans capture, médiane sur 60 images** : b8, b32 et b64 donnaient 0,66 ms au
   centième près, et « 0 lumière » restait la plus lente. Toujours incohérent.
4. **Temps d'image à l'horloge, 1920x1080, vsync coupée, médiane sur 120 images** : 1 540 lumières ressortait
   *plus rapide* que 0 sur une vue. L'écart entre les options est sous le bruit.

Cause : cette machine rend la scène en ~1,8 ms quand l'UHD 750 met 30 à 100 ms (chiffres de `CityRenderOptimizer`).
Le GPU n'est jamais le goulot ici, donc le coût des lumières ne sort pas. **Ne pas recommencer à chercher une
cinquième métrique sur cette machine.** `RenderPerfTest` accepte désormais `--heure=`, `--bassin=` et
`--toutes-lampes` : c'est là, et sur l'UHD 750, que la comparaison se fait.

Le choix du bassin borné ne repose donc pas sur un écart mesuré ici, mais sur le fait que **son pire cas est borné
par construction** : 16 lumières quoi qu'il arrive, où que soit le joueur. Le coût de l'option à 1 540 est, lui,
non borné et non mesuré — ce qui est exactement la raison de ne pas l'embarquer.

### Ce que ça rend possible plus tard

Les **phares de véhicules** et les **gyrophares** se posent sur la même architecture, sans rien réinventer :
le `hour_changed` donne l'allumage automatique au crépuscule, les halos non éclairés à matériau partagé donnent
les feux de tous les véhicules lointains pour un appel de dessin par lot, et un bassin de vraies lumières borné
donne les phares du joueur et des quelques voitures les plus proches. Le seul piège connu : un gyrophare qui
clignote a besoin d'un matériau qui change, donc **il faut un matériau partagé par état** (bleu allumé, rouge
allumé, éteint) et faire clignoter tout le monde en phase, jamais un matériau par véhicule.

### Anomalie antérieure révélée par ce chantier

**5 luminaires (3 mâts) de la carte sont plantés sous un tablier routier**, tête à 0,005 à 0,493 m de l'ouvrage,
en (-697,1 / -694,6 ; 0,84 ; -776,1), (-720,6 / -718,3 ; 0,84 ; -635,8) et (53,3 ; 7,38 ; 791,6). Ces mâts
existent depuis le chantier des routes ; le cycle jour/nuit n'a fait que les révéler, en demandant pour la
première fois OÙ sont les luminaires. La cause est dans la pose des lampadaires de `RoadBake`, qui ne regarde pas
le dégagement au-dessus du mât. `DayNightTest` constate les 5 et **échoue si le nombre augmente**.
