# Migration vers Unreal Engine 5.8

Le jeu passe de Godot à Unreal pour avoir des **graphismes réalistes**. Ce document dit, système par système, ce que fait
le jeu Godot, ce qu'Unreal fournit déjà et ce qu'il faut réécrire, ce qui mérite d'être migré et ce qui ne l'est pas, et
les leçons de ce dépôt qui restent valables. Écrit le 2026-09-25, sur le code de `carte-3d` (`be11855`).

- **Le projet Unreal** : `F:\Projets\MafiaOpenWorld\MafiaOpenWorld` (C++, modèle Troisième personne, UE 5.8.3 installé
  dans `F:\epic\UE_5.8`), dépôt GitHub privé `JLCanadaPrice/MafiaOpenWorld`. Sa méthode, ses commandes et son plan sont
  dans son `CLAUDE.md`.
- **L'export de la carte** : `D:\p-recree\export_unreal\` (hors dépôt), à lire en commençant par son `LISEZMOI.md`
  (conventions d'axes, fichiers, contrôles). Il se refait sans toucher au jeu.
- **Ce dépôt reste la référence** du jeu : ses mesures, ses décisions et ses pièges (`CLAUDE.md`). On ne le modifie plus
  que sur demande.

## 1. En bref

| | quoi |
|---|---|
| **se migre** | le **plan de la carte** (routes, carrefours, rond-point, bretelles, bâtiments et leurs emprises, lieux, terrain, eau, rail, mobilier, arbres, parkings, graphes de circulation et piétons : exportés) ; les **72 fiches de véhicules** (CSV lisible par une DataTable, vérifié) ; les **assets uniques faits dans Blender** pour ce jeu, comme base à refaire en réaliste ; les **données de jeu** (catalogue, noms de lieux, économie, arme) ; les **décisions du joueur** et les **leçons** (§5) |
| **se réécrit** | tout le code : en **C++** et en scripts **Python d'éditeur**, le moins de Blueprints possible |
| **ne se migre pas** | les scènes et le code Godot ; **tous les packs low-poly** (le joueur veut du réaliste, et plusieurs ont une licence non vérifiée) ; les cuissons et leurs maillages ; les shaders et textures faits pour le low-poly ; le code mort |

## 2. Système par système

État dans le jeu Godot : **complet**, **partiel** ou **ébauche**, relevé sur le code.

### Joueur à pied — complet
- **Godot** : `scenes/player/Player.gd`. CharacterBody3D, capsule de 0,4 x 1,8 m ; 5 m/s, course 7 m/s (Maj), saut avec
  tolérance ; `StepClimb` pour monter jusqu'à 0,40 m ; caméra à bras de 4 m, regard libre (Alt) ; visée au clic droit
  derrière l'épaule droite (2 m, 0,7 m, champ 55°, 3 m/s) ; nage (`WaterZone`) ; noclip (V) ; monter en voiture (E),
  sortie sur une place libre ; animations Quaternius choisies selon le sens et jouées à la vitesse du corps, foulée
  allongée en course ; trois modificateurs de squelette (pose de saut, pieds posés sur le sol réel par une IK des jambes,
  bras tendu vers le réticule).
- **Unreal fournit** : `ACharacter` et son `CharacterMovementComponent` (marche, pentes, marches avec `MaxStepHeight`,
  saut, nage dans les volumes d'eau, accroupi), bras de caméra, Enhanced Input, Animation Blueprint, IK des pieds (Control
  Rig), locomotion réaliste de l'échantillon *Game Animation Sample* (Motion Matching), corps physique pour le ragdoll.
- **À réécrire** : les vitesses et la course, la visée façon GTA V (caméra d'épaule, corps face à la visée), le regard
  libre, l'entrée et la sortie de véhicule (place libre), le noclip de débogage. **Le travail des pieds et des animations
  Godot ne se migre pas** : les solutions d'Unreal le remplacent.

### Conduite du joueur — complet (sans dégâts, sans sons, sans vrais chocs contre la circulation)
- **Godot** : `scenes/vehicles/ChassisGTA.gd` et `RoueGTA.gd`, un modèle de conduite à nous inspiré de GTA V, réglé par
  les fiches (`resources/vehicle_physics/fiches_vehicules.csv`, noms du handling.meta de GTA V) et trois réglages globaux
  (`reglages_conduite.tres`) : suspension à rayons, courbe de traction du pneu, partage de l'adhérence avant / arrière,
  ABS qui partage l'adhérence selon le glissement (on peut freiner ET tourner), frein à main qui bloque l'arrière des
  voitures et pas des camions, patinage au départ, **réduction du braquage avec la vitesse selon la courbe de GTA V**
  (0,15 + 0,9^(v - 7,2), v en m/s), levée pendant une glisse au frein à main, **aucun contre-braquage automatique**,
  **jamais de tonneau** (centre de roulis placé par modèle), report de charge au freinage borné, répartiteur de freinage.
  Enveloppes de collision qui suivent la silhouette, zone exacte pour les tirs.
- **Unreal fournit** : Chaos Vehicles (`ChaosWheeledVehicleMovementComponent` : moteur, boîte, différentiel, suspension,
  friction des pneus, ABS, antipatinage, frein à main, courbe de braquage selon la vitesse, centre de masse), collisions
  simples et complexes séparées, matériaux physiques.
- **À réécrire** : l'application des fiches aux réglages de Chaos (une seule fonction de conversion), les règles du
  joueur (§5, « Conduite »), le banc de mesure (`ChassisBancTest` et `ConduiteReelleTest` du jeu Godot en tests
  automatiques Unreal : 0-100, freinage, rayon, glisse rattrapée au clavier, pas de tonneau), les feux (voir plus bas).
  **Les valeurs se migrent (fiches), le code non.**

### Circulation — complet (cinématique)
- **Godot** : `Car.gd` (IA), `CircuitPath.gd` (graphe, voies, sens uniques, feux à deux phases, cédez-le-passage),
  `LoopSpawner.gd` (jusqu'à 252 voitures, naissance à 60-400 m, jamais en vue sous 150 m), `VehicleCatalog.gd` (72
  modèles, rôles, poids dans le tirage). Suivi, arrêts aux feux et aux passages piétons, priorités, rond-point à deux
  voies, insertions, déblocage des cycles de suivi. Vitesse et accélération de chaque modèle tirées de sa fiche.
- **Unreal fournit** : rien de clé en main dans le moteur. Mass (MassAI) et ZoneGraph y sont ; la circulation de *City
  Sample* (MassTraffic, sur Fab) est la seule réalisation complète, à évaluer.
- **À réécrire** : l'IA (portage en C++ sur le graphe exporté, ou adaptation de MassTraffic), en gardant les règles
  payées (§5, « Circulation »). **Le graphe se migre (export), le code non.**

### Piétons — partiel
- **Godot** : `scenes/npc/NPC.gd`, marche au hasard sur le réseau piéton du centre-ville (2,3 m/s), esquive, fuite du
  conducteur éjecté, 100 points de vie, sang, mort. Tenues de faction cosmétiques. Pas de panique, pas de combat.
- **Unreal fournit** : MassCrowd et ZoneGraph (foule de *City Sample*), ou contrôleurs d'IA, NavMesh, StateTree et EQS
  (déjà actifs par le modèle), MetaHumans, ragdoll, zones de touche par os (corps physiques du squelette).
- **À réécrire** : tout. **Le réseau piéton se migre (export ; il ne couvre que le centre-ville).**

### Gel hors champ — complet
- **Godot** : `scripts/world/SimulationCuller.gd` gèle voitures et piétons à plus de 50 m et hors de vue. Défaut connu :
  une voiture née hors de vue reste gelée ; le « gel en deux temps » (avancer sans physique) était décidé.
- **Unreal fournit** : World Partition, gestionnaire de signification (Significance Manager), LOD de Mass, réglage du
  tick. **À réécrire** au besoin, en appliquant d'emblée le gel en deux temps.

### Jour et nuit, éclairage — complet
- **Godot** : `DayNightCycle.gd` (48 min par jour, soleil à 62° à midi, lune sans ombres), `StreetLights.gd` (verre des
  lampadaires allumé, bassin de 16 vraies lumières près de la caméra, fenêtres allumées, balisage de l'aéroport, feu
  d'obstacle, lumières fixes des parkings), `VehicleLights.gd` (phares, feux arrière à deux niveaux, freins qui éclairent
  le sol, gyrophares par type de véhicule).
- **Unreal fournit** : ciel physique (SkyAtmosphere, SkyLight, nuages volumétriques, brouillard), position réelle du
  soleil, Lumen, **MegaLights** (beaucoup de vraies lumières ombrées : le bassin de 16 n'est peut-être plus nécessaire, à
  mesurer), profils IES, canaux d'éclairage, matériaux émissifs.
- **À réécrire** : le cycle (durée, touches N), l'allumage des lampadaires et des fenêtres, les feux des véhicules et
  les gyrophares (motifs relevés feu par feu, §9 du `CLAUDE.md`).

### Optimisations de rendu — complet, ne se migre pas
`CityRenderOptimizer.gd` (occulteurs, LOD, culling), `DowntownHLOD.gd`, `BuildingField.gd` (MultiMesh) : Unreal les
remplace par Nanite, les HLOD de World Partition et l'occlusion. Leçon qui reste : mesurer le coût sur la machine cible.

### Armes et combat — partiel
- **Godot** : un pistolet (12 coups, 25 dégâts, 100 m), tir instantané depuis le centre de l'écran, traceur, sang. Pas
  d'ennemis, pas de dégâts aux véhicules.
- **Unreal fournit** : traces de collision, Niagara, décalques, corps physiques par os ; la variante Combat du modèle
  (corps à corps) et l'échantillon *Lyra* (Fab) comme référence d'un jeu de tir.
- **À réécrire** : tout, en visant le chantier « combat » décidé (zones de touche par os des PNJ, dégâts aux véhicules).

### Interface — partiel
- **Godot** : HUD (argent, réputation, étoiles, munitions, réticule), minicarte, carte (M, voyage rapide non fait),
  téléphone (T, partiel), inventaire (ébauche), concessionnaire (complet), agence immobilière (partiel), achat de
  bâtiment et gestion d'entreprise (codés mais jamais ouverts).
- **Unreal fournit** : UMG, CommonUI, captures de scène pour la minicarte. **À réécrire** : tout.

### Économie, réputation, police — partiel, INACCESSIBLE en jeu
- **Godot** : autoloads `GameManager` (argent 5 000, réputation), `EconomyManager` (ventes toutes les 30 s),
  `PoliceManager` (étoiles 0-5, sans police), `BuildingRegistry`, `CarRegistry`, `AgencyRegistry`, `PhoneManager` ;
  `InventoryManager`, `ContactsManager` et `SaveSystem` sont des ébauches. **Aucun bâtiment ne peut être acheté dans la
  version actuelle** (`BuildingPurchaseUI` n'est jamais ouverte) : l'économie ne tourne donc jamais.
- **Unreal fournit** : `USaveGame`, sous-systèmes de `GameInstance`, DataTables et DataAssets.
- **À réécrire** : à reconcevoir plutôt que porter. Les données (entreprises, voitures, appartements) se reprennent.

### Intérieurs et boutiques — partiel
- **Godot** : le concessionnaire Liberty Motors et l'agence City Realty sont de vrais intérieurs où l'on entre à pied
  (le toit se cache) ; les appartements (`ApartmentInterior.gd`) existent mais ne sont reliés à rien.
- **Unreal fournit** : Level Instances, Data Layers de World Partition, portes et interactions en C++.
- **À réécrire**, en gardant la règle : de vrais intérieurs à leur place sur la carte, jamais de téléportation.

### Trains — partiel
- **Godot** : `RailPath.gd`, `Train.gd`, `RailCrossing.gd` : voie unique de 4 492 m, cantons, vagues de 3 trains au plus,
  grande vitesse 1+4 caisses à 90 km/h, fret 1+14 à 55 km/h, deux passages à niveau avec barrières et blocs d'arrêt.
  Reste le gel en deux temps et l'instanciation.
- **Unreal fournit** : splines, corps cinématiques. **À réécrire.** **La voie se migre (export).**

### Parkings à étages — complet, se refait
Quatre parkings (3 au centre-ville, 1 à l'aéroport) rendus praticables sur un modèle low-poly (rampes intérieures à 16 %,
escalier, barre de hauteur à 2,15 m, places, plafonniers). Le modèle ne se migre pas ; **se migrent** : l'emplacement, les
280 places (export), et les mesures qui ont décidé la conception (§11 du `CLAUDE.md` : pente, demi-tours de 4,7 m, 10
places par étage, barre de hauteur, garde-corps partout où l'on tombe).

### Véhicules garés — complet
205 véhicules (fiches dans `places.json`, `parked.json`, `parked_parkings.json`), de vraies voitures conduisibles.
**Se migrent** : positions et orientations (export). **À réécrire** : le placement.

### Génération du monde (cuissons) — complet, les données se migrent
`MapSpec.gd` (le plan), `RoadNetwork.gd` et `RoadBake.gd` (routes, échangeurs, bretelles, carrefours, rond-point,
trottoirs, rail, graphe), `TerrainModel.gd` et `TerrainBake.gd` (grille de 4 m), `DistrictsBake.gd` (1 196 bâtiments),
`PlacesBake.gd` (12 lieux), `VegetationBake.gd` (20 255 arbres), centre-ville (`DowntownSpec`, `DowntownLayout`,
`Downtown*Bake` : 113 carrefours, 441 bâtiments, 2 194 objets de mobilier).
- **Unreal fournit** : Landscape (import de la grille), World Partition, PCG (arbres, mobilier), Geometry Script et
  maillages de spline (routes, trottoirs, bordures), plugin Water.
- **Se migre** : tout le résultat, par l'export. Les règles des cuissons (profils, marges, pentes, dégagements) restent
  lisibles dans le code de ce dépôt quand il faudra régénérer ce que l'export ne contient pas (murs, glissières, marquage).

### Eau et nage — complet
Rivière et lacs cuits, **bassin du port posé à la main par le joueur** dans `World.tscn`, nage par `WaterZone`. **Unreal
fournit** le plugin Water (rivières sur spline, lacs, océan, flottaison, nage). **Se migrent** : tracés, largeurs,
niveaux, étendue du port (export).

### Tests — à recréer
38 scènes de test (`scenes/tests/`), une ligne `<NOM>_RESULT OK / FAIL` chacune. Les plus précieuses à recréer en tests
automatiques Unreal : `JoueurAPiedTest`, `ChassisBancTest`, `ConduiteReelleTest`, `CarKerbTest`, `ParkingStructureTest`,
`RoundaboutTrafficTest`, `MapGateTest`, `MapRoadsTest`, `MapPlacesTest`, `VehicleLightsTest`, `DayNightTest`.

## 3. Ce qui mérite d'être migré

1. **Le plan de la carte**, exporté (`D:\p-recree\export_unreal\`) : réseau routier (234 rubans, 149 carrefours et
   raccords, 114 culs-de-sac, rond-point Echo Circle à deux voies, échangeurs, bretelles), graphes de circulation (carte
   et centre-ville, 348 feux) et piéton, plan du centre-ville, terrain (grille de 4 m, relief naturel, masque des tunnels,
   `.r16` prêt pour un paysage), rivière, lacs et port, voie ferrée, 1 637 bâtiments (emprise, hauteur, usage,
   orientation), 12 lieux (modèles posés, panneaux, clôtures, emprises), 509 + 866 lampadaires, 20 255 arbres, 2 194 objets
   du centre-ville, 576 places de stationnement, 205 véhicules garés.
2. **Les 72 fiches de véhicules** : `vehicules/fiches_vehicules.csv` de l'export, lisible par la DataTable de
   `FFicheVehicule` du projet Unreal (import vérifié : 2 016 cases relues identiques). Unités de la fiche Godot ; la
   conversion vers Chaos se fera en un seul endroit.
3. **Les assets uniques faits dans Blender pour ce jeu**, comme BASE à refaire en réaliste (matériaux PBR, UV, détails),
   à l'échelle réelle mesurée : ils sont générés par des scripts `bpy` paramétriques, rejouables.
   - `assets/drug_lab` (24 GLB, 4 `.blend`, 10 scripts, dont `Blends/scripts/run_lot.py` et `dl_common.py`) : kit
     d'entrepôt, culture de cannabis (pots, stades, lampes, séchoirs, table de taille, bocal), labo de cocaïne (table,
     presse, balance, tas, sachets, briques) — jamais utilisé dans le jeu ;
   - `assets/apartments` (`apt_shells.py`, `apt_props.py`) : coques d'appartements Small / Medium / Large, table, PC ;
   - `assets/shops` (`shop_buildings.py`, `shop_dealership.py`, `shop_agency.py`, `shop_common.py`) : concessionnaire et
     agence avec intérieurs, collisions et points d'ancrage ;
   - `assets/faction_gear` (`gear_police.py`) : casquette, insigne et bouclier anti-émeute de la police.
   La **méthode** `scenes/vehicles/tools/enveloppes_pieces.py` (enveloppes convexes par pièce, faites dans Blender) se
   réutilise sur les véhicules réalistes ; ses résultats, taillés pour les modèles low-poly, non.
4. **Les données de jeu** : rôles et poids des 72 modèles dans la circulation (`vehicules/catalogue.json`), noms des
   lieux (inventés), données d'économie (`resources/buildings`, entreprises, voitures du concessionnaire, appartements),
   arme (`WeaponData`).
5. **Les décisions du joueur et les leçons** (§5).

## 4. Ce qui ne se migre pas

- **Les scènes (`.tscn`) et le code GDScript** : Unreal réécrit tout, en C++ et en Python d'éditeur.
- **Tous les packs low-poly**, même pour dépanner : le joueur veut du réaliste. Ce sont `nature_kit`, `city_kit`,
  `dock_models`, `vehicle_models_extra` (les 54 `city_*` et les 12 `lowpoly_*` du catalogue), `animations` (UAL),
  `npc_models`, `building_pack_everythinglibrary` (CC-BY), `modular_roads`, `skyscraper_bundle`, `lowpoly_city_pack`,
  `weapon_models`, `building_pack*`, `player_model`, `Modular Train Pack-zip`, `LowPoly-House-Construction-Site`,
  `low_poly_construction`, `farm_buildings_quaternius`, `airport_ground_vehicles`, `Fbx`, `water_shader`, `traffic_light`,
  `car_physics` (VitaVehicle). Plusieurs ont en plus une licence NON VÉRIFIÉE (tous les véhicules `city_*`, dont les
  véhicules de police et d'urgence).
- **Les cuissons et leurs maillages** (`generated/`) : l'export en porte les données.
- **Les shaders, les post-traitements d'import, les textures procédurales low-poly, la minicarte cuite.**
- **Le code mort** : `CityKitBuilder`, `DistrictBaker`, `MountainZoneBuilder`, `TreeScatter`, `PropScatter`,
  `PropBuilding`, `facade_factory`, `LampPoleLayer`, `StreamingManager`, `BuildingKitBaker`, `CityExpansionBake`,
  `CityGraphMerge`, `PlayerCarPhysics` (VitaVehicle, deux vieux tests seulement).

## 5. Leçons de ce dépôt qui restent valables

Chacune a été payée, et la plupart ne dépendent pas du moteur. Le détail et les chiffres sont dans `CLAUDE.md`.

### Méthode
- **Mesurer sur ce que le moteur calcule vraiment** (sommets, collision, rayons), jamais sur une constante, une cote
  théorique ou un nom de fichier. Un compteur qui ne dépend pas de son seuil est cassé (l'erreur de signe qui a donné
  « 7,9 % des façades » au lieu d'un tiers, §12).
- **Regarder l'image avant de conclure d'un compteur** : le tonemapper délave les couleurs vives et fausse un test par
  rapport de canaux (feux de freinage, §6) ; « tous les contrôles de structure sont bons et ça ne marche pas » accuse
  l'instrument de mesure.
- **Captures au sol, à hauteur d'homme ou de conduite** : une vue du ciel cache les défauts que voit le joueur.
- **Vérifier toute la population**, pas trois exemples (recensement des fenêtres allumées, §9 ; 72 modèles au banc).
- **Reproduire un défaut dans la situation exacte où le joueur l'a vu** (en tournant, en freinant, de nuit).
- **Corriger explicitement dans la doc une conclusion qui s'est révélée fausse**, pour qu'une session suivante ne la
  réapplique pas (fenêtres « non séparables », erratum des collisions).
- **Un test qui casse : corriger la cause, jamais contourner** ; prouver un échec antérieur en rejouant le commit
  précédent.
- **Une sonde s'exclut elle-même** de ce qu'elle mesure, **vérifie quel objet elle touche**, et prend son relevé au
  déclenchement, pas au cadrage (§6, §12).
- **Toute commande de vérification sous `timeout`** : un script qui ne s'analyse pas laisse le moteur ouvert sans fin.
- Les règles du joueur sur les vérifications : pas de simulation de 30 min sans demande, pas de batterie complète sur un
  petit correctif, demander avant plus de 10 min, les tests longs sont au joueur ; un commit par étape.

### Rendu et lumières
- **Allumer la géométrie qui existe dans le modèle** (verre des lampadaires, optiques des véhicules, feu d'obstacle), et,
  quand il manque des luminaires, **copier celui du modèle** au rythme du modèle ; jamais de quads lumineux ajoutés.
- **Une lumière portée par un véhicule n'éclaire pas sa propre carrosserie** (en Unreal : canaux d'éclairage).
- **Deux états d'un même modèle ne partagent jamais un lot d'instances** (la moitié bleue des gyrophares qui
  disparaissait, §9) ; un matériau partagé par ÉTAT, jamais un matériau par objet.
- **Tout objet posé en permanence a besoin d'une distance de visibilité** : sinon il se paie à l'autre bout de la carte
  (§11, étape 11).
- **Le coût des lumières ne se lit pas en appels de dessin** : il se mesure en temps GPU, sur une machine dont le GPU est
  le goulot.

### Physique et collisions
- **Deux formes concaves ne se touchent pas** : jamais de collision exacte (complexe) sur ce qui bouge ; le concave est
  pour le décor statique et les zones de tir. En Unreal : jamais « Use Complex as Simple » sur un corps mobile.
- **La collision de déplacement d'un véhicule suit sa silhouette ; la collision exacte sert aux tirs** (§12).
- **Une boîte englobante engloutit perrons, escaliers et arcades** : collision exacte des bâtiments ; **rampes de collision
  invisibles** sur les escaliers trop raides, l'escalier visible restant.
- **Ce qui soulève un personnage reste sous la portée de ce qui le recale** (marche contre accroche au sol, §6).
- **Une coque creuse n'expulse pas un joueur posé dedans** : la sortie de véhicule et la sortie du noclip cherchent une
  place libre (§12).
- **Avant de régler un moteur physique importé, vérifier ses unités et le moteur pour lequel il a été écrit** (le pack
  VitaVehicle comptait en pieds, §6).
- **Bordures de trottoir de 0,15 m** : la voiture du joueur et le joueur à pied les franchissent, la circulation non.

### Conduite (décisions du joueur)
- **Le joueur seul tourne les roues** : aucun contre-braquage automatique, aucune aide qui braque à sa place ; la
  stabilité vient de la physique (partage de l'adhérence, inertie, amortisseurs, report de charge borné, répartiteur).
- **Braquage réduit avec la vitesse selon la courbe de GTA V**, levée pendant une glisse au frein à main.
- **Frein à main** : bloque l'arrière des voitures pour déraper, ralentit les camions et les bus sans les faire déraper.
- **Freiner en tournant doit tourner** (ABS qui partage l'adhérence selon le glissement de la roue).
- **Jamais de tonneau.** **Réglages par modèle, jamais par catégorie**, dans un tableau lisible à la main.
- **La circulation reste cinématique** ; l'idée retenue pour les chocs : ne passer en physique que la voiture percutée.

### Circulation
- Les interblocages payés (§10) : priorité cédée à la voiture de derrière, cycles de priorité, suivi en rond au milieu
  d'un carrefour ; une voiture arrêtée derrière une autre ne réclame plus sa priorité.
- **Une sonde de circulation LIT l'état de l'IA** (`diag_raison`) au lieu de refaire ses règles, et neutralise le gel.
- **Gel en deux temps** : un objet gelé hors de vue doit continuer d'avancer sans physique (voitures, trains).
- **Anti-apparition** : viser 1 m au-dessus du point, tester la voie et pas le noeud, ne refuser qu'en deçà de 150 m.

### Monde
- **Relier les bâtiments à la route** : 682 bâtiments sur 1 637 (41,7 %), tous dans les quartiers, étaient séparés de la
  chaussée par de l'herbe ; paver sous l'emprise plutôt que contre la boîte du modèle.
- **Une contrainte réelle s'applique physiquement dans le monde, avec un panneau lisible** (barre de hauteur de 2,15 m des
  parkings) plutôt que de tordre la structure pour tout accepter.
- **Avant de dire qu'une structure ne tient pas, essayer toute la plage réaliste** du paramètre (rampes de 15 à 18 %).
- **Bâtiments visitables : de vrais intérieurs à leur place, on y entre à pied**, jamais de téléportation.
- **Noms de lieux inventés**, aucun nom de la série *Tulsa King*.
- **Le bassin du port a été réglé à la main par le joueur** : c'est son étendue qui compte, pas la constante du terrain.

### Entrées et outils
- **Aucune touche du jeu sur F1 à F12** (l'éditeur les garde : F8 arrêtait le jeu) ; relever toutes les touches prises
  avant d'en donner une.
- **Les connexions sont au joueur** (GitHub, Epic, Fab) ; tout le reste se fait sans lui.

## 6. Pièges propres au passage

- **Axes et unités** : Godot compte en mètres, Y vers le haut, nord = -Z ; Unreal en centimètres, Z vers le haut, repère
  main gauche. Correspondance sans miroir : (X, Y, Z) Unreal = 100 x (x, z, y) Godot ; lacet Unreal = -θ (en degrés)
  pour les mêmes axes locaux, 90° - θ pour un asset Unreal dont l'avant est +X alors que le modèle Godot l'avait en +Z.
  Détail dans le `LISEZMOI.md` de l'export.
- **Ce que l'export ne contient pas**, faute d'être stocké autrement qu'en maillages fusionnés : murs de soutènement,
  parapets, piles, tabliers, glissières, marquage au sol, surfaces des lieux (leurs emprises y sont), balisage de
  l'aéroport, feux de la carte hors centre-ville (créés au lancement du jeu). Ils se régénèrent à partir des rubans, du
  terrain et des règles des cuissons.
- **Le centre-ville et le port sont des trous dans la grille du terrain** (valeurs de remplissage -0,08 et -9,8).
- **L'avant des modèles de véhicules Godot est +Z** (mesuré sur les roues à l'export) ; celui d'un véhicule Unreal est +X.
