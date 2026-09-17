extends RefCounted

# Plan de masse du centre-ville reconstruit (chantier centre-ville, étape D1) : trame de rues hiérarchisée, îlots
# regroupés, zonage des hauteurs, lieux et boutiques conservés. Source unique de DowntownLayout (géométrie dérivée),
# des générateurs du centre-ville et de ses tests. Mètres du jeu, nord = −Z.
#
# Cadre : les rues du pourtour gardent les lignes d'avant (x −892 et −28, z −460 et 116) pour conserver les 8 raccords
# avec les routes de la carte (MapSpec.NODES "g_*", confondus avec les carrefours du Circuit) et les lieux déjà posés
# autour, hors grille : Ashford Grand Hotel (façade est à x −906), Central Precinct et St. Anselm (parvis à z ≥ 127),
# parc de Liberty Motors (x ≥ 4). Côté extérieur du pourtour, l'emprise ne dépasse pas l'ancienne (9 m de l'axe) ; le
# long des boutiques visitables (façades nord à z −451), trottoir de 2 m sur Harbor Avenue ; Liberty Motors (x −125 à
# −109) garde une rue de 18 m d'emprise sur x −100 au nord de Water Street.
# Disposition calée sur l'image de référence : cœur d'affaires autour du croisement Main Street × Central Boulevard,
# quartier du casino au nord du cœur (Jackson Avenue), hôtel au nord-ouest, commissariat au sud-ouest, hôpital au
# sud, port au nord-est ; hauteurs décroissantes du cœur vers le pourtour.

# --- profils en travers ---------------------------------------------------------------------------------------------
# lanes : voies par sens (double sens) ou au total (sens unique) ; lane : largeur d'une voie ; median : terre-plein
# central planté ; parking : bande de stationnement de chaque côté ; sidewalk : trottoir de chaque côté.
const PROFILES := {
	"boulevard": {"lanes": 2, "lane": 3.5, "median": 2.0, "parking": 0.0, "sidewalk": 5.0},
	"avenue": {"lanes": 2, "lane": 3.5, "median": 0.0, "parking": 0.0, "sidewalk": 4.0},
	"perimeter": {"lanes": 2, "lane": 3.5, "median": 0.0, "parking": 0.0, "sidewalk": 3.5},
	"street": {"lanes": 1, "lane": 3.5, "median": 0.0, "parking": 2.0, "sidewalk": 3.5},
	"one_way": {"lanes": 2, "lane": 3.5, "median": 0.0, "parking": 1.5, "sidewalk": 3.5},
}
const ALLEY_WIDTH := 6.0
const OUTER_SIDEWALK := 2.0       # côté extérieur du pourtour : emprise d'avant (7 m de chaussée + 2 m = 9 m)
const ROAD_TOP := 0.05            # surface roulable (Car.ROAD_TOP_Y, RoadNetwork.ROAD_TOP) : y = 0 dans le Circuit
const SIDEWALK_RISE := 0.15       # trottoir au-dessus de la chaussée (RoadNetwork.SIDEWALK_RISE)

# --- trame --------------------------------------------------------------------------------------------------------
# Rues nord-sud (x constant) : tronçons [de z, à z] ; rues est-ouest (z constant) : tronçons [de x, à x]. Un tronçon
# commence et finit sur une rue transversale (jamais d'impasse). Sens unique : "dir" +1 vers les coordonnées
# croissantes, −1 vers les décroissantes. "outer" : côté extérieur du pourtour (−1 ou +1) ; "sidewalks" : largeurs
# imposées [côté −, côté +] sur un tronçon.
# Îlots doubles : cœur (Lincoln Plaza, Founders Plaza), casino, et en périphérie parkings et grands lots (face à
# l'hôtel, au commissariat, à l'hôpital, derrière le casino, à l'est).
const X_STREETS := [
	{"x": -892.0, "name": "Riverside Avenue", "outer": -1, "spans": [[-460.0, 116.0, "perimeter"]]},
	{"x": -820.0, "name": "Cedar Street", "spans": [[-460.0, -316.0, "street"], [-244.0, 116.0, "street"]]},
	{"x": -748.0, "name": "Walnut Street", "spans": [[-460.0, 44.0, "street"]]},
	{"x": -676.0, "name": "Lincoln Avenue", "spans": [[-388.0, 116.0, "avenue"]]},
	{"x": -604.0, "name": "Grand Street", "spans": [[-460.0, 116.0, "street"]]},
	{"x": -532.0, "name": "Main Street", "spans": [[-460.0, 116.0, "boulevard"]]},
	{"x": -460.0, "name": "Union Street", "spans": [[-460.0, -244.0, "street"], [-172.0, 116.0, "street"]]},
	{"x": -388.0, "name": "Monroe Avenue", "spans": [[-460.0, 116.0, "avenue"]]},
	{"x": -316.0, "name": "Fifth Street", "dir": -1, "spans": [[-460.0, 116.0, "one_way"]]},
	{"x": -244.0, "name": "Sixth Street", "dir": 1, "spans": [[-460.0, 116.0, "one_way"]]},
	{"x": -172.0, "name": "Dock Street", "spans": [[-460.0, -244.0, "street"], [-100.0, 116.0, "street"]]},
	{"x": -100.0, "name": "Commerce Avenue", "spans": [[-460.0, -388.0, "street"], [-388.0, 116.0, "avenue"]]},
	{"x": -28.0, "name": "Frontier Avenue", "outer": 1, "spans": [[-460.0, 116.0, "perimeter"]]},
]
const Z_STREETS := [
	{"z": -460.0, "name": "Harbor Avenue", "outer": -1, "spans": [[-892.0, -28.0, "perimeter", {"sidewalks": [OUTER_SIDEWALK, 2.0]}]]},
	{"z": -388.0, "name": "Water Street", "spans": [[-820.0, -604.0, "street"], [-532.0, -28.0, "street"]]},
	{"z": -316.0, "name": "Jackson Avenue", "spans": [[-892.0, -28.0, "avenue"]]},
	{"z": -244.0, "name": "Pine Street", "spans": [[-892.0, -676.0, "street"], [-604.0, -28.0, "street"]]},
	{"z": -172.0, "name": "Central Boulevard", "spans": [[-892.0, -28.0, "boulevard"]]},
	{"z": -100.0, "name": "Market Street", "dir": -1, "spans": [[-892.0, -28.0, "one_way"]]},
	{"z": -28.0, "name": "Elm Street", "dir": 1, "spans": [[-892.0, -28.0, "one_way"]]},
	{"z": 44.0, "name": "Oak Street", "spans": [[-892.0, -316.0, "street"], [-244.0, -28.0, "street"]]},
	{"z": 116.0, "name": "South Avenue", "outer": 1, "spans": [[-892.0, -28.0, "perimeter"]]},
]

# --- îlots ----------------------------------------------------------------------------------------------------------
# Zone d'un îlot : premier rectangle de la liste qui contient son centre (valeurs de DowntownLayout.ZONE_*).
#  core : tours (gratte-ciels ×6 du SkyScraperBundle, grands modèles) ; midrise : immeubles de 6 à 20 étages ;
#  lowrise : 1 à 4 étages, parkings ; plaza : place piétonne (fontaine, arbres, bancs) ; casino : Scarlet Jack ;
#  shops : îlot d'une boutique visitable (bâtiments voisins hors de son emprise) ; civic : église et square.
const ZONES := [
	{"zone": "plaza", "name": "Founders Plaza", "rect": Rect2(-532, -244, 144, 72)},
	{"zone": "core", "name": "Lincoln Plaza", "rect": Rect2(-676, -316, 72, 144), "plaza": true},
	{"zone": "casino", "name": "Scarlet Jack", "rect": Rect2(-604, -460, 72, 144)},
	{"zone": "shops", "name": "Liberty Motors", "rect": Rect2(-172, -460, 72, 72)},
	{"zone": "shops", "name": "City Realty", "rect": Rect2(-100, -460, 72, 72)},
	{"zone": "civic", "name": "St. Brendan", "rect": Rect2(-820, -100, 72, 72)},
	{"zone": "core", "rect": Rect2(-604, -316, 216, 216)},
	{"zone": "midrise", "rect": Rect2(-748, -388, 504, 432)},
	{"zone": "lowrise", "rect": Rect2(-952, -469, 992, 676)},
]
# Ruelles de service (6 m, sans trottoir, hors circulation et réseau piéton) : au milieu d'un îlot sur deux de ces
# zones dont l'intérieur mesure au moins ALLEY_MIN_BLOCK m dans les deux sens (cf. DowntownLayout._build_alleys).
const ALLEY_ZONES := ["midrise"]
const ALLEY_MIN_BLOCK := 48.0

# --- conservé ---------------------------------------------------------------------------------------------------------
# Boutiques visitables (World.tscn) : emprises monde mesurées (coquille et toit), rien ne doit y empiéter.
const SHOPS := [
	{"name": "Liberty Motors", "node": "Dealership_Building", "rect": Rect2(-125.4, -451.0, 16.3, 21.8)},
	{"name": "City Realty", "node": "Agency_Building", "rect": Rect2(-70.6, -451.0, 13.2, 14.3)},
]
# Lieux de MapSpec.POIS au contact du centre-ville (emprises bâties et pavées de places.json).
const PLACE_IDS := ["hotel", "precinct", "hospital", "liberty_lot", "casino"]
