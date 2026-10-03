# Repères pour Claude Code — jeu Godot (dépôt de référence)

Version courte du 2026-10-03, faite à la demande du joueur : rôle du dépôt, règles, méthode, commandes, pièges encore
actuels, emplacements. **Tout l'historique** (séries datées, mesures, récits des pièges, chantiers) est dans
`CLAUDE_HISTORIQUE.md`, à côté : il n'est pas chargé automatiquement ; le lire PAR SECTION (index au §8) quand un sujet y
renvoie. Aucune règle n'a été retirée.

## 1. Le projet et son état

- Jeu **open world mafia** façon *Tulsa King*, troisième personne, 3D. **Godot 4.7.2** (Forward+, D3D12), tout en
  **GDScript**. Dépôt GitHub `JLCanadaPrice/Game-Godot-gta-like-`, branche de travail **`carte-3d`**, tag de retour
  `avant-chantier-routes`.
- **CE DÉPÔT EST LA RÉFÉRENCE, GELÉE.** Le jeu a migré vers **Unreal Engine 5.8** (décision du joueur, 2026-09-25) :
  projet `F:\Projets\MafiaOpenWorld\MafiaOpenWorld` (dépôt privé `JLCanadaPrice/MafiaOpenWorld`, sa méthode dans SON
  `CLAUDE.md`). `MIGRATION_UNREAL.md`, à la racine d'ici, dit ce qui se migre et ce qui se réécrit. La carte et les fiches
  sont exportées HORS dépôt dans `F:\p-recree\export_unreal\` (son `LISEZMOI.md`). **Ce dépôt ne se modifie plus que sur
  demande du joueur.** Le travail courant se fait dans une session ouverte dans le dossier du projet Unreal.
- **Tout vit dans `F:\p-recree`** depuis le 2026-09-26. `D:\p-recree` garde l'ancienne copie, intacte : ne pas y
  travailler ; vérifier les chemins avant de relancer une commande d'une ancienne session.
- Git refuse le dépôt (propriétaire douteux) : préfixer TOUTES les commandes par `git -c safe.directory=<chemin du dépôt>`.
- `README.md` décrit un état très ancien : ne pas s'y fier.
- **Historique réécrit le 2026-09-19** (`git filter-repo`) : les SHA d'avant sont périmés. Les sources brutes d'assets
  (`.fbx`, `.obj`, `.blend`, planches d'origine) vivent dans un dépôt PRIVÉ séparé, `F:/p-recree/sources-brutes` (même
  arborescence), parce que plusieurs packs sont à licence NON VÉRIFIÉE. **Ne jamais recommiter une source brute ici** ;
  pour retravailler un pack, le copier hors du projet.

Emplacements hors dépôt : sondes `F:/p-recree/sondes/` ; captures `F:/p-recree/ground_shots/` ; vidéos
`F:/p-recree/videos_conduite/` et `videos_joueur/` ; Blender `F:/p-recree/blender-5.2.2-windows-x64/blender.exe` ;
référence GTA V `F:/p-recree/reference_gta/` (jamais recopiée, §2).

## 2. Règles du joueur (non négociables)

- **Rien d'acheté** : assets gratuits seulement, licence vérifiée. **Aucun mot de passe, aucune connexion, aucun paiement
  saisi** : si on en demande un, s'arrêter et le dire.
- **Rien repris de GTA, d'autres jeux commerciaux ni de leurs mods** : style et proportions seulement ; aucun maillage,
  texture, logo ni nom réel. Le `handling.meta` de GTA V du joueur sert de référence et n'est JAMAIS recopié (ni extrait ni
  tableau : ce dépôt est public) ; les fiches gardent leurs propres valeurs, seuls les NOMS de colonnes sont ceux de GTA V.
- **Noms de lieux et de marques inventés** ; aucun nom de la série *Tulsa King*.
- **Aucun fichier supprimé hors du projet** ; ne rien supprimer sans montrer la liste d'abord. **Jamais rien de cassé
  commité.**
- **Pousser** : quand la demande dit « commit et pousse » ou « pousse », même dans un texte collé, pousser soi-même à la
  fin (`git -c safe.directory=<dépôt> push origin carte-3d`) et donner les commits poussés ; sans ce mot, s'arrêter aux
  commits locaux et le dire. Sur une erreur d'authentification, ne pas réessayer : donner la commande au joueur.
- **Conduite : celle de GTA V, et le joueur seul tourne les roues.** Aucun contre-braquage automatique, aucune aide de
  dérive. La seule réduction du braquage est la courbe de GTA V avec la vitesse, levée pendant une glisse au frein à main
  (`CLAUDE_HISTORIQUE.md` §15). La stabilité vient de la physique.
- **Réglages des véhicules : une fiche par modèle, jamais de catégories**, dans un tableau que le joueur ajuste à la main
  (`resources/vehicle_physics/fiches_vehicules.csv`, colonnes aux noms du handling.meta, documentées dans son en-tête ;
  réglages globaux dans `reglages_conduite.tres`).
- **Aucune touche du jeu sur F1 à F12** (raccourcis de l'éditeur de Godot : F8 arrête le jeu). Relever TOUT ce qui est
  déjà pris avant de donner une touche (liste dans l'historique, §6).
- **Lumières** : on allume la géométrie qui existe dans le modèle (optique, verre, vitre), jamais des rectangles ajoutés
  par-dessus ; s'il faut plus de luminaires, des copies du luminaire du modèle, sur son pas.
- **On ne peint pas ce qui n'existe pas** : un modèle sans fenêtre ou sans optique séparable reste éteint, et on le dit.
- Pour le projet Unreal (rappel, détaillé dans son `CLAUDE.md`) : contenu Fab jamais dans Git, critique AAA indépendant,
  asset gratuit de niveau AAA avant toute modélisation, économie de quota.

## 3. Méthode de travail (imposée)

- **Mesurer depuis les sommets du maillage cuit**, jamais depuis une valeur théorique, une constante ou un nom de
  fichier. Les outils en lecture seule de `scenes/world/map/tools/` (`RampAudit`, `RampPoints`, `RampSteps`, `RampDrive`,
  `PlacesRangeAudit`) se rejouent après chaque correction.
- **Sauvegarde `.bak` datée avant chaque modification** : `<Nom>_backup_<AAAA-MM-JJ_HHMM>.<ext>.bak`. Jamais de copie
  `.tscn` ou `.gd` sous un nom que Godot scanne (UID dupliqué). Ces `.bak` sont suivis par git.
- **Chaîne de cuisson COMPLÈTE, dans l'ordre, sans sauter une étape** (§5).
- **Tests headless après chaque étape**, **un commit séparé par étape**. Sur un petit correctif : seulement les 2-3
  tests directement concernés.
- **Vérifications, règles du joueur** : pas de simulation longue de 30 minutes sans demande explicite ; une vérification
  de plus de 10 minutes : demander d'abord ; les tests longs, c'est le joueur qui les lance.
- **Captures au niveau du sol**, à hauteur d'homme ou de conduite, jamais du ciel. Les images restent hors du dépôt, les
  chiffres vont dans le message de commit.
- **Regarder l'image avant de conclure d'un compteur** : un seuil sert à localiser, jamais à prouver. Quand tous les
  contrôles de structure sont bons et que « ça ne marche pas », suspecter l'instrument de mesure.
- **Reproduire le défaut dans la situation de jeu où le joueur l'a vu**, et montrer cette situation dans les captures.
- **Une correction qui vaut pour une population se vérifie sur TOUTE la population** (recensement, liste complète par
  modèle), pas sur trois cas.
- **Si un test casse : corriger la cause, jamais contourner.** Un échec antérieur à la modification se prouve (rejouer
  sur `HEAD~1`) et se dit.
- **Une conclusion écrite ici qui se révèle fausse se corrige par écrit** (« CORRECTION du ... »), pas seulement dans le
  code.
- Avant de dire qu'une chose réelle « ne tient pas », essayer toute la plage réaliste du paramètre (une rampe de parking
  à 16-18 %, pas seulement à 12 %). Entre deux compromis, prendre la règle du monde réel et la faire respecter dans le
  jeu (une barre de hauteur et son panneau).
- Ne jamais `git stash` sur `scenes/world/map/generated` : copier le dossier ailleurs.

## 4. Seuil de performance

- **+10 % d'appels de dessin au plus** sur les 6 vues de référence (`echangeur_nord_ouest`, `carrefour_willow_lake`,
  `rond_point_echo`, `losange_aeroport`, `quartier_bluffview_survol`, `lieu_echo_circle`) ; pour le ferroviaire, **+30
  appels** sur les 6 vues `voie_ferree_*`. La mesure « avant » se refait sur la machine du jour, code non modifié.
- Toute vue se mesure **de jour ET de nuit** (`MapShotsTest --heure=1`).
- **Les appels de dessin ne mesurent ni les lumières ni le LOD** : pour eux, le nombre de primitives et le temps GPU
  (`RenderPerfTest`, `--heure=`, `--bassin=`, `--toutes-lampes`, `--parking`), sur une machine dont le GPU est le goulot.
- L'Intel UHD 750 de l'école n'est plus la machine de référence du jeu (il y gèle) ; on n'y ouvre que l'éditeur. Un mode
  graphique léger est à faire. Tableaux de référence : historique §3.
- Tout objet posé EN PERMANENCE sur la carte a besoin d'une portée de visibilité (`visibility_range_end`).

## 5. Commandes

```bash
GODOT="F:/p-recree/Godot_v4.7.2-stable/Godot_v4.7.2-stable_win64_console.exe"; PROJET="F:/p-recree/test/test"
# chaîne de cuisson (~106 s), dans cet ordre ; l'--import final n'est pas facultatif
for c in RoadBake DistrictsBake PlacesBake VegetationBake MapBackgroundBake; do "$GODOT" --headless --path "$PROJET" --script res://scenes/world/map/tools/$c.gd; done
"$GODOT" --headless --path "$PROJET" --script res://scenes/world/map/tools/TerrainBake.gd -- --from-heights
"$GODOT" --headless --path "$PROJET" --import
# un test (scène) ; résultat : une ligne <NOM>_RESULT OK ou FAIL
"$GODOT" --headless --path "$PROJET" [--fixed-fps 60] res://scenes/tests/<Test>.tscn
"$GODOT" --headless --path "$PROJET" --script res://scenes/world/map/tools/ProjectLoadCheck.gd    # 645 fichiers, 0 échec
# captures et compteurs de rendu (fenêtré) ; --heure=<0..24>, --sans-image, --bassin=<n>, --feu-obstacle=1|0
"$GODOT" --path "$PROJET" --resolution 800x450 res://scenes/tests/MapShotsTest.tscn -- --out=<dossier> --views=vue1,vue2
```

- **Cuissons hors chaîne** : `RoadTexturesBake`, `TerrainTexturesBake`, `BuildingCatalogBake`, `TrainsBake`,
  `DowntownFurnitureBake`, `DowntownBuildingsBake`. **Toucher aux lampadaires impose `RoadBake` ET
  `DowntownFurnitureBake`** ; **toucher à `BuildingModels` ou à un modèle EverythingLibrary impose la chaîne ET
  `DowntownBuildingsBake`**. Enveloppes par pièce des 18 camions, bus et pick-up : `EnveloppesExport.gd` puis Blender
  (historique §4).
- **Tests** (`scenes/tests/`), sans option : `MapRoadsTest`, `MapRailTest`, `MapDistrictsTest`, `MapPlacesTest`,
  `MapTerrainTest`, `MapVegetationTest`, `MapExplorationTest`, `MapGateTest`, `SimulationCullingTest`, `DayNightTest`,
  `VehicleLightsTest`, `WorldTrafficSmokeTest`, `NoclipTest`, `CarKerbTest`, `WheelSpinTest`, `DowntownStreetsTest`,
  `DowntownBuildingsTest`, `ShopBuildingsTest` (échec ANTÉRIEUR connu : ne pas le « réparer » au passage).
  Avec `--fixed-fps 60` : `MapTrainsTest`, `RoundaboutTrafficTest`, `VehicleCatalogTest` (`--quit-after 300`),
  `CarDrivingTest`, `CarDropTest`, `ConduiteReelleTest`, `ChassisBancTest` (6 silhouettes ; `-- --tous --lot=i/3` pour les
  72 modèles), `ParkingStructureTest`, `JoueurAPiedTest`. Ce que chacun vérifie : historique §5.
- Retirer un véhicule de la circulation : `traffic_weight` à 0 dans son `resources/vehicle_models/<id>.tres` ; le sortir
  du catalogue : le déplacer dans `resources/vehicle_models/retires/`.

## 6. Pièges encore actuels (le récit de chacun est dans l'historique, §6 et suivants)

Cuisson et scènes
- `_own()` (`PlacesBake`) ne descend pas dans une scène instanciée : un réglage posé sur les enfants d'un modèle est
  perdu. Fusionner le modèle en un maillage `.res` et régler la portée sur son `MeshInstance3D`.
- Les `.tscn` cuits changent textuellement à chaque cuisson : un « modifié » de `git status` ne prouve rien.
- Le lac du quai n'est PAS cuit : il vit dans `World.tscn` (`Downtown/Quay/Water/Mesh`), réglé par le joueur.
- Deux cuiseurs n'écrivent jamais le même fichier (`parked.json` et `parked_parkings.json`).
- Rien de solide à moins de 12 m d'un des 43 points de contrôle de `MapGateTest`.

Rendu
- ACES délave ce qui est posé à 1,0 : couleurs émissives nettement sous 1 (0,62 pour un rouge).
- Un atlas de palette ne dit pas son sens de V : regarder le rendu. Les fenêtres du pack lowpoly_city SONT séparables,
  au texel de palette ; 20 modèles de véhicules sur 72 n'ont AUCUNE optique séparable (ne pas élargir les couleurs).
- Une lumière portée par un véhicule ne doit jamais éclairer les carrosseries (calque visuel 3 hors du `light_cull_mask`).
- Deux états d'un même modèle ne partagent jamais un calque `MultiMesh` ; un matériau partagé par état, jamais par
  véhicule.
- `CityRenderOptimizer` laisse une lumière qui règle déjà son fondu ; son LOD tourne aussi dans l'éditeur (`@tool`) : ne
  pas activer « Enfants modifiables » sur `Map` ou `Downtown`.
- Dans l'éditeur, décocher le gadget `CollisionShape3D` (26 M de segments) et ne jamais cocher « Formes de collision
  visibles ».
- Captures : le GPU a décroché au-dessus de 800x450 sur d'anciens PC (1920x1080 a tenu au PC de la maison le 2026-10-03) ;
  le premier lancement compile les shaders. Geler la circulation pour une capture demande `PROCESS_MODE_DISABLED` ; un
  relevé se prend AU DÉCLENCHEMENT ; avec la caméra du joueur, rendre la souris libre.

Physique et code
- **Jolt : deux formes concaves ne se touchent pas.** Jamais de trimesh sur ce qui bouge (enveloppes convexes) ; un sol
  en `WorldBoundaryShape3D` loin de l'origine laisse passer ; au-delà de 10 240 corps, Jolt refuse en silence.
- `move_and_slide()` ne monte aucune marche ; ce qui soulève un personnage reste SOUS la portée de ce qui le recale.
- L'avant d'une VOITURE est `-basis.z`, l'avant d'un MODÈLE son `+Z` (lacet de catalogue de 180°). Un réglage « dans le
  repère de la caisse » passe par la base du parent du nœud.
- Tout `RigidBody3D` reçoit l'amortissement par défaut du projet (0,1 /s) : le couper s'il fausse une mesure.
  `RigidBody3D.linear_velocity` n'est relue qu'après le pas : lire l'état direct du `PhysicsServer3D`.
- Un `PackedArray` rangé dans un `Dictionary` ou un `Array` est une COPIE : relire, ajouter, réécrire.
- Les autoloads ne sont pas enregistrés en `--script` : lancer une sonde comme scène, toujours sous `timeout` (un script
  qui ne compile pas laisse Godot ouvert). `trait` est un mot réservé.
- Un `CharacterBody3D` inerte n'est jamais repoussé ; une sonde s'exclut du décor qu'elle mesure et vérifie QUEL mur elle
  a trouvé ; toute sonde de sol exclut la couche 3 (véhicules).
- Une voiture garée passe par `Car.is_parked()` ; `LoopSpawner` ne compte que ses propres enfants (`_actifs()`).
- Tests à aléa connu : `RoundaboutTrafficTest` (peu de marge sur ses 20 sorties : rejouer une fois, ne pas baisser le
  seuil), `WorldTrafficSmokeTest`, `NoclipTest` (rejouer deux fois, puis sur `HEAD~1`).
- Un import reciblé (BoneMap) perd les pistes de position : `Suit.gltf.import` garde `unimportant_positions = false`.
- `du -h` sur un disque externe compte les blocs : `du -b` ou `stat` pour une taille.

## 7. État et suite

Fait : la carte 3D entière (terrain, rivière, routes, voie ferrée et trains, 1 196 bâtiments de quartiers, 441 du
centre-ville, 12 lieux, 20 297 arbres), circulation et piétons, cycle jour / nuit et éclairages, parkings à étages,
collisions exactes, conduite façon GTA V sur 72 modèles (`ChassisGTA`), joueur à pied (pieds au sol, arme, visée).

Reste à faire dans la liste du joueur (désormais portée par le projet Unreal) : combat et zones de touche des PNJ, gangs
rivaux, labo de drogue, porte d'entrepôt, appartements reliés à la carte, concessionnaire enrichi (0 voiture exposée),
mode graphique léger, gel en deux temps de la circulation, chocs réels contre la circulation, relier les bâtiments à la
route (682 coupés par de l'herbe), trains étape 5, accessoires convertis à poser. Détail : historique §7.

## 8. Index de `CLAUDE_HISTORIQUE.md`

| § | contenu |
|---|---|
| en-tête | résumé des séries du 2026-09-24 au 26, migration, déménagement |
| 1 | projet, historique réécrit, compte de `ProjectLoadCheck` au fil du temps |
| 2 | méthode de travail, texte d'origine |
| 3 | seuils de performance, tableaux de référence de jour et de nuit |
| 4 | chaîne de cuisson, durées, cuissons hors chaîne, enveloppes par pièce |
| 5 | batterie de tests headless : chaque commande et ce qu'elle vérifie ; `MapShotsTest` |
| 6 | tous les pièges, avec leur récit et leurs mesures ; touches déjà prises |
| 7 | état d'avancement, feuille de route, chantier « relier les bâtiments à la route », parc de véhicules |
| 8 | trains en mouvement (étapes 1 à 4 faites, étape 5 à faire) |
| 9 | cycle jour / nuit, lampadaires, fenêtres allumées, balisage de l'aéroport, feux et gyrophares, véhicules garés |
| 10 | circulation : Echo Circle à deux voies, les quatre interblocages, pièges de mesure |
| 11 | parking à étages : anatomie, rampes, escalier, éclairage, places (étapes 1 à 14) |
| 12 | collisions : inventaire mesuré, décisions, véhicules, lieux, bâtiments, rampes d'entrée, anti-apparition |
| 13 | conduite réaliste, essai sur la berline (remplacé) |
| 14 | une fiche par véhicule, banc des 72 modèles, frein à main, circulation par modèle, physique des PNJ mesurée |
| 15 | conduite façon GTA V (`ChassisGTA`) : les trois versions de la direction, freiner en tournant |
| 16 | joueur à pied : pieds, course à 7 m/s, arme sortie, visée, vérification à l'image |
