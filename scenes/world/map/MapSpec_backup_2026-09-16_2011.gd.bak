extends RefCounted

# Plan de masse de la carte 3D : toute la géographie en mètres du jeu (x, z ; nord = −Z), calée sur le centre-ville
# existant (1 px de l'image de référence = 2,6 m ; x = −952 + (px − 470) × 2,6 ; z = −700 + (py − 300) × 2,6).
# Source unique de la disposition pour les générateurs des étapes suivantes (terrain, routes, ponts, quartiers,
# lieux) et pour le garde-fou MapGateTest (GATE_SPOTS). Les tracés sont des lignes de conception : les générateurs
# les lissent, les découpent contre l'eau et les routes, et en tirent la géométrie.
# Écarts volontaires avec la référence : la rivière passe ~150 m plus à l'ouest le long du centre-ville pour loger
# la voie express riveraine entre la ville et la berge ; au sud-ouest, l'Autoroute Sud et la Voie express Ouest se
# croisent en un seul échangeur (x_st) au lieu de deux trop rapprochés, la voie ferrée et quelques artères (a3, a4,
# a10) sont décalées pour franchir les autoroutes hors des bretelles (étape 2a).

# Dernière étape construite (0, 1, 2 = 2a, 2.5 = 2b, 3...) : active les points de contrôle correspondants.
const BUILT_STAGE := 2.0

# --- emprises ---------------------------------------------------------------------------------------------------
const PLAYABLE := Rect2(-2174.0, -1480.0, 4347.0, 2447.0)   # zone explorable (4,35 × 2,45 km)
const TERRAIN := Rect2(-2432.0, -1792.0, 4864.0, 3072.0)    # terrain généré, bordure de collines comprise
const DOWNTOWN := Rect2(-952.0, -469.0, 992.0, 676.0)       # sol des 4 districts existants
const HARBOR := Rect2(-520.0, -650.0, 560.0, 190.0)         # quai, bassin et fonds existants du District
const WATER_LEVEL := -0.95                                   # surface du bassin existant, reprise par la rivière

# --- eau --------------------------------------------------------------------------------------------------------
# Rivière du nord au sud : [point de l'axe, largeur en m].
const RIVER := [
	[Vector2(-1640, -1792), 180.0],
	[Vector2(-1576, -1480), 175.0],
	[Vector2(-1460, -1220), 170.0],
	[Vector2(-1330, -960), 165.0],
	[Vector2(-1230, -726), 160.0],
	[Vector2(-1180, -492), 150.0],
	[Vector2(-1160, -258), 150.0],
	[Vector2(-1150, -24), 150.0],
	[Vector2(-1140, 210), 150.0],
	[Vector2(-980, 444), 150.0],
	[Vector2(-760, 652), 150.0],
	[Vector2(-640, 967), 150.0],
	[Vector2(-590, 1280), 150.0],
]
# Plans d'eau : centre, demi-axes (m).
const LAKES := [
	{"id": "willow_lake", "center": Vector2(-1760, -90), "radii": Vector2(70, 48)},
	{"id": "ranch_pond", "center": Vector2(1760, -60), "radii": Vector2(25, 16)},
]

# --- relief -----------------------------------------------------------------------------------------------------
# Collines douces : [centre, rayon, hauteur] (pas de montagne : 30 m au plus).
const HILLS := [
	[Vector2(-1100, -1150), 450.0, 26.0],   # Bluffview Heights
	[Vector2(-1900, -80), 600.0, 30.0],     # Cedar Gulch
	[Vector2(-1850, -950), 520.0, 24.0],    # forêt nord-ouest
	[Vector2(-300, -1250), 420.0, 9.0],     # Midtown Nord
	[Vector2(1500, -330), 520.0, 16.0],     # campagne est
	[Vector2(1950, 320), 480.0, 22.0],
	[Vector2(1300, 760), 360.0, 11.0],      # Hollow Creek
	[Vector2(1850, -1150), 480.0, 20.0],    # bois nord-est
	[Vector2(-1350, 880), 420.0, 14.0],     # sud-ouest
	[Vector2(250, 1050), 380.0, 7.0],
	[Vector2(700, 60), 300.0, 6.0],         # butte boisée de la planque
]
# Plateaux aplanis : rectangle, hauteur, largeur de raccord (m).
const PLATEAUS := [
	{"id": "downtown", "rect": Rect2(-952, -650, 992, 857), "height": 0.0, "blend": 140.0},
	{"id": "airport", "rect": Rect2(62, -1376, 1014, 442), "height": 5.0, "blend": 160.0},
	{"id": "railyard", "rect": Rect2(-449, 262, 1142, 470), "height": 0.5, "blend": 120.0},
]
const NOISE := {"seed": 7331, "frequency": 1.0 / 650.0, "octaves": 3, "amplitude": 4.0}
const EDGE_RISE := {"height": 40.0, "width": 180.0}   # remontée du terrain hors de la zone explorable

# --- réseau routier ---------------------------------------------------------------------------------------------
# Noeuds : grid = noeud existant de la grille du centre-ville (CircuitPath), edge = sortie de carte (tunnel),
# interchange = échangeur autoroutier, diamond = échangeur en losange autoroute × artère, junction (lit = à feux),
# roundabout, end = cul-de-sac (parking, entrée de propriété).
const NODES := {
	"g_o172": {"pos": Vector2(-892, -172), "kind": "grid"},
	"g_o116": {"pos": Vector2(-892, 116), "kind": "grid"},
	"g_n892": {"pos": Vector2(-892, -460), "kind": "grid"},
	"g_n532": {"pos": Vector2(-532, -460), "kind": "grid"},
	"g_e460": {"pos": Vector2(-28, -460), "kind": "grid"},
	"g_e316": {"pos": Vector2(-28, -316), "kind": "grid"},
	"g_s388": {"pos": Vector2(-388, 116), "kind": "grid"},
	"g_s100": {"pos": Vector2(-100, 116), "kind": "grid"},
	"e_an_o": {"pos": Vector2(-2300, -530), "kind": "edge"},
	"e_an_e": {"pos": Vector2(2300, -676), "kind": "edge"},
	"e_vxo_n": {"pos": Vector2(-700, -1640), "kind": "edge"},
	"e_vxo_s": {"pos": Vector2(-330, 1120), "kind": "edge"},
	"e_as_o": {"pos": Vector2(-2300, 582), "kind": "edge"},
	"e_vxe_n": {"pos": Vector2(1180, -1640), "kind": "edge"},
	"e_a5": {"pos": Vector2(2300, -175), "kind": "edge"},
	"e_a11": {"pos": Vector2(2300, 412), "kind": "edge"},
	"e_a12": {"pos": Vector2(1620, 1120), "kind": "edge"},
	"e_a10": {"pos": Vector2(-1080, 1120), "kind": "edge"},
	"x_no": {"pos": Vector2(-700, -700), "kind": "interchange", "shape": "ring"},
	"x_ne": {"pos": Vector2(1050, -596), "kind": "interchange", "shape": "ring"},
	"x_st": {"pos": Vector2(-380, 770), "kind": "interchange", "shape": "ring"},
	"x_se": {"pos": Vector2(686, 496), "kind": "interchange", "shape": "join"},
	"d_o172": {"pos": Vector2(-1028, -172), "kind": "diamond"},
	"d_o116": {"pos": Vector2(-1028, 116), "kind": "diamond"},
	"d_n9": {"pos": Vector2(60, -700), "kind": "diamond"},
	"d_e5": {"pos": Vector2(972, -232), "kind": "diamond"},
	"d_e8": {"pos": Vector2(752, 380), "kind": "diamond"},
	"d_s7": {"pos": Vector2(60, 780), "kind": "diamond"},
	"d_no13": {"pos": Vector2(-1416, -672), "kind": "diamond"},
	"d_so13": {"pos": Vector2(-1355, 543), "kind": "diamond"},
	"j_lake": {"pos": Vector2(-1578, -172), "kind": "junction", "lit": true},
	"j_bank": {"pos": Vector2(-1600, 156), "kind": "junction", "lit": true},
	"j_green": {"pos": Vector2(-393, -856), "kind": "junction", "lit": false},
	"j_safe": {"pos": Vector2(647, -284), "kind": "junction", "lit": false},
	"j_ranch": {"pos": Vector2(1648, -206), "kind": "junction", "lit": false},
	"j_hollow": {"pos": Vector2(1418, 403), "kind": "junction", "lit": false},
	"j_motel": {"pos": Vector2(-330, 590), "kind": "junction", "lit": false},
	"j_sw": {"pos": Vector2(40, 930), "kind": "junction", "lit": false},
	"r_echo": {"pos": Vector2(110, -316), "kind": "roundabout", "radius": 26.0},
	"n_a1": {"pos": Vector2(-1900, -205), "kind": "end"},
	"n_a2": {"pos": Vector2(-1760, 240), "kind": "end"},
	"n_a3": {"pos": Vector2(-1041, -1347), "kind": "end"},
	"n_a4": {"pos": Vector2(-291, -1305), "kind": "end"},
	"n_green": {"pos": Vector2(-440, -905), "kind": "end"},
	"n_air": {"pos": Vector2(470, -1195), "kind": "end"},
	"n_safe": {"pos": Vector2(647, -80), "kind": "end"},
	"n_ranch": {"pos": Vector2(1700, -120), "kind": "end"},
	"n_motel": {"pos": Vector2(-445, 595), "kind": "end"},
}

# Tronçons : classe (highway = 2×2 voies séparées, arterial = 2 voies, access = desserte, dirt = chemin de terre),
# noeuds extrémités et points de passage. axis : axe autoroutier (AXES) ; urban : trottoirs et éclairage.
const ROADS := [
	{"id": "an_o1", "class": "highway", "axis": "an", "from": "e_an_o", "to": "d_no13", "via": [Vector2(-2174, -544), Vector2(-1874, -588), Vector2(-1600, -630)]},
	{"id": "an_o2", "class": "highway", "axis": "an", "from": "d_no13", "to": "x_no", "via": [Vector2(-1230, -700), Vector2(-960, -700)]},
	{"id": "an_c1", "class": "highway", "axis": "an", "from": "x_no", "to": "d_n9", "via": [Vector2(-300, -700)]},
	{"id": "an_c2", "class": "highway", "axis": "an", "from": "d_n9", "to": "x_ne", "via": [Vector2(400, -690), Vector2(668, -663)]},
	{"id": "an_e", "class": "highway", "axis": "an", "from": "x_ne", "to": "e_an_e", "via": [Vector2(1334, -622), Vector2(1600, -650), Vector2(2173, -672)]},
	{"id": "vxo_n", "class": "highway", "axis": "vxo", "from": "e_vxo_n", "to": "x_no", "via": [Vector2(-700, -1480), Vector2(-700, -900)]},
	{"id": "vxo_s1", "class": "highway", "axis": "vxo", "from": "x_no", "to": "d_o172", "via": [Vector2(-738, -600), Vector2(-790, -545), Vector2(-880, -515), Vector2(-975, -490), Vector2(-1028, -400)]},
	{"id": "vxo_s2", "class": "highway", "axis": "vxo", "from": "d_o172", "to": "d_o116", "via": []},
	{"id": "vxo_s3", "class": "highway", "axis": "vxo", "from": "d_o116", "to": "x_st", "via": [Vector2(-1005, 240), Vector2(-890, 345), Vector2(-780, 420), Vector2(-680, 500), Vector2(-590, 610)]},
	{"id": "vxo_s5", "class": "highway", "axis": "vxo", "from": "x_st", "to": "e_vxo_s", "via": [Vector2(-340, 950)]},
	{"id": "as_o1", "class": "highway", "axis": "as", "from": "e_as_o", "to": "d_so13", "via": [Vector2(-2174, 574), Vector2(-1749, 553)]},
	{"id": "as_o2", "class": "highway", "axis": "as", "from": "d_so13", "to": "x_st", "via": [Vector2(-1150, 640), Vector2(-950, 760), Vector2(-800, 850), Vector2(-650, 870), Vector2(-560, 880)]},
	{"id": "as_e1", "class": "highway", "axis": "as", "from": "x_st", "to": "d_s7", "via": []},
	{"id": "as_e2", "class": "highway", "axis": "as", "from": "d_s7", "to": "x_se", "via": [Vector2(460, 691)]},
	{"id": "vxe_n", "class": "highway", "axis": "vxe", "from": "e_vxe_n", "to": "x_ne", "via": [Vector2(1180, -1480), Vector2(1150, -1000)]},
	{"id": "vxe_s1", "class": "highway", "axis": "vxe", "from": "x_ne", "to": "d_e5", "via": []},
	{"id": "vxe_s2", "class": "highway", "axis": "vxe", "from": "d_e5", "to": "d_e8", "via": [Vector2(894, 132)]},
	{"id": "vxe_s3", "class": "highway", "axis": "vxe", "from": "d_e8", "to": "x_se", "via": []},
	{"id": "a1_e", "class": "arterial", "urban": true, "from": "g_o172", "to": "d_o172", "via": []},
	{"id": "a1_w", "class": "arterial", "urban": false, "from": "d_o172", "to": "j_lake", "via": [Vector2(-1250, -172), Vector2(-1400, -172)]},
	{"id": "a1_x", "class": "arterial", "urban": false, "from": "j_lake", "to": "n_a1", "via": [Vector2(-1760, -190)]},
	{"id": "a2_e", "class": "arterial", "urban": true, "from": "g_o116", "to": "d_o116", "via": []},
	{"id": "a2_w", "class": "arterial", "urban": false, "from": "d_o116", "to": "j_bank", "via": [Vector2(-1240, 116), Vector2(-1420, 140)]},
	{"id": "a2_x", "class": "arterial", "urban": false, "from": "j_bank", "to": "n_a2", "via": []},
	{"id": "a13_n", "class": "arterial", "urban": false, "from": "d_no13", "to": "j_lake", "via": [Vector2(-1470, -500), Vector2(-1530, -300)]},
	{"id": "a13_m", "class": "arterial", "urban": true, "from": "j_lake", "to": "j_bank", "via": [Vector2(-1624, -55)]},
	{"id": "a13_s", "class": "arterial", "urban": false, "from": "j_bank", "to": "d_so13", "via": [Vector2(-1560, 300), Vector2(-1450, 450)]},
	{"id": "a3", "class": "arterial", "urban": false, "from": "g_n892", "to": "n_a3", "via": [Vector2(-892, -540), Vector2(-975, -620), Vector2(-1010, -760), Vector2(-960, -1000), Vector2(-916, -1159)]},
	{"id": "a4", "class": "arterial", "urban": true, "from": "g_n532", "to": "j_green", "via": [Vector2(-532, -610), Vector2(-527, -666), Vector2(-445, -666), Vector2(-408, -705), Vector2(-400, -790)]},
	{"id": "a4_n", "class": "arterial", "urban": false, "from": "j_green", "to": "n_a4", "via": [Vector2(-340, -1100)]},
	{"id": "green_access", "class": "access", "from": "j_green", "to": "n_green", "via": []},
	{"id": "a9_s", "class": "arterial", "urban": true, "from": "g_e460", "to": "d_n9", "via": [Vector2(64, -460), Vector2(74, -560)]},
	{"id": "a9_n", "class": "arterial", "urban": false, "from": "d_n9", "to": "n_air", "via": [Vector2(147, -888), Vector2(200, -1000), Vector2(260, -1180)]},
	{"id": "a5_w", "class": "arterial", "urban": true, "from": "g_e316", "to": "r_echo", "via": []},
	{"id": "a5_m", "class": "arterial", "urban": true, "from": "r_echo", "to": "j_safe", "via": [Vector2(334, -309)]},
	{"id": "a5_e", "class": "arterial", "urban": false, "from": "j_safe", "to": "d_e5", "via": []},
	{"id": "a5_x", "class": "arterial", "urban": false, "from": "d_e5", "to": "j_ranch", "via": [Vector2(1293, -213)]},
	{"id": "a5_z", "class": "arterial", "urban": false, "from": "j_ranch", "to": "e_a5", "via": [Vector2(2173, -180)]},
	{"id": "safe_lane", "class": "dirt", "from": "j_safe", "to": "n_safe", "via": []},
	{"id": "ranch_road", "class": "dirt", "from": "j_ranch", "to": "n_ranch", "via": [Vector2(1660, -160)]},
	{"id": "a7_n", "class": "arterial", "urban": true, "from": "g_s388", "to": "j_motel", "via": [Vector2(-388, 207), Vector2(-388, 403)]},
	{"id": "a7_s", "class": "arterial", "urban": true, "from": "j_motel", "to": "d_s7", "via": [Vector2(-150, 690)]},
	{"id": "a7_z", "class": "arterial", "urban": true, "from": "d_s7", "to": "j_sw", "via": []},
	{"id": "motel_access", "class": "access", "from": "j_motel", "to": "n_motel", "via": []},
	{"id": "a8", "class": "arterial", "urban": true, "from": "g_s100", "to": "d_e8", "via": [Vector2(-100, 320), Vector2(84, 403), Vector2(418, 445)]},
	{"id": "a11", "class": "arterial", "urban": false, "from": "d_e8", "to": "j_hollow", "via": [Vector2(1168, 390)]},
	{"id": "a11_e", "class": "arterial", "urban": false, "from": "j_hollow", "to": "e_a11", "via": [Vector2(1751, 445), Vector2(2173, 412)]},
	{"id": "a12", "class": "arterial", "urban": false, "from": "j_hollow", "to": "e_a12", "via": [Vector2(1501, 695)]},
	{"id": "a10", "class": "arterial", "urban": false, "from": "j_sw", "to": "e_a10", "via": [Vector2(-250, 935), Vector2(-400, 935), Vector2(-560, 930), Vector2(-672, 915), Vector2(-874, 960), Vector2(-999, 1003)]},
]
const AXES := {
	"an": "Autoroute Nord",           # équivalent de l'I-244
	"vxo": "Voie express Ouest",      # US-75
	"vxe": "Voie express Est",        # US-169
	"as": "Autoroute Sud",            # I-44
}
# Voie ferrée (décor, sans circulation) : d'est en ouest, franchit la rivière sur son propre pont.
const RAIL := [
	Vector2(2300, 190), Vector2(2173, 195), Vector2(1209, 278), Vector2(668, 295), Vector2(-100, 275),
	Vector2(-449, 262), Vector2(-610, 380), Vector2(-760, 520), Vector2(-900, 610), Vector2(-1100, 690),
	Vector2(-1416, 760), Vector2(-2174, 800), Vector2(-2300, 805),
]

# --- zones ------------------------------------------------------------------------------------------------------
# Types : downtown (existant), suburb, residential, mixed, industrial, airport, farmland, forest.
const ZONES := [
	{"id": "downtown", "name": "Centre-ville", "type": "downtown", "poly": [Vector2(-952, -469), Vector2(40, -469), Vector2(40, 207), Vector2(-952, 207)]},
	{"id": "bluffview", "name": "Bluffview Heights", "type": "suburb", "poly": [Vector2(-1416, -1480), Vector2(-760, -1480), Vector2(-760, -760), Vector2(-999, -760), Vector2(-1186, -763), Vector2(-1266, -972), Vector2(-1366, -1222)]},
	{"id": "midtown_nord", "name": "Midtown Nord", "type": "mixed", "poly": [Vector2(-640, -1430), Vector2(40, -1430), Vector2(40, -750), Vector2(-640, -750)]},
	{"id": "willow_lake", "name": "Willow Lake", "type": "suburb", "poly": [Vector2(-1728, -555), Vector2(-1416, -613), Vector2(-1266, -647), Vector2(-1249, -463), Vector2(-1232, -222), Vector2(-1220, -13), Vector2(-1215, 100), Vector2(-1741, 100), Vector2(-1741, 28), Vector2(-1707, -305)]},
	{"id": "westbank", "name": "Westbank", "type": "residential", "poly": [Vector2(-1215, 100), Vector2(-1207, 203), Vector2(-1099, 403), Vector2(-1282, 612), Vector2(-1541, 620), Vector2(-1724, 453), Vector2(-1741, 100)]},
	{"id": "eastside", "name": "Eastside", "type": "mixed", "poly": [Vector2(68, -655), Vector2(418, -647), Vector2(938, -572), Vector2(905, -180), Vector2(868, 195), Vector2(68, 212)]},
	{"id": "eastgate", "name": "Eastgate", "type": "suburb", "poly": [Vector2(1084, 245), Vector2(1501, 203), Vector2(1751, 328), Vector2(1730, 695), Vector2(1418, 762), Vector2(1084, 612)]},
	{"id": "railyard", "name": "Railyard", "type": "industrial", "poly": [Vector2(-449, 270), Vector2(668, 303), Vector2(693, 528), Vector2(438, 695), Vector2(-82, 745), Vector2(-449, 728)]},
	{"id": "southside", "name": "Southside", "type": "residential", "poly": [Vector2(-591, 853), Vector2(-82, 828), Vector2(418, 778), Vector2(668, 787), Vector2(759, 960), Vector2(-591, 960)]},
	{"id": "airport", "name": "Prairie Wind International Airport", "type": "airport", "poly": [Vector2(62, -1376), Vector2(1076, -1376), Vector2(1076, -934), Vector2(62, -934)]},
	{"id": "campagne_est", "name": "Campagne est", "type": "farmland", "poly": [Vector2(1084, -588), Vector2(2173, -742), Vector2(2173, 653), Vector2(1834, 716), Vector2(1501, 762), Vector2(1084, 612), Vector2(1043, 195)]},
	{"id": "cedar_gulch", "name": "Cedar Gulch", "type": "forest", "poly": [Vector2(-2174, -388), Vector2(-1957, -430), Vector2(-1757, -305), Vector2(-1728, 28), Vector2(-1791, 403), Vector2(-1741, 695), Vector2(-1916, 799), Vector2(-2174, 778)]},
	{"id": "foret_nord_ouest", "name": "Forêt nord-ouest", "type": "forest", "poly": [Vector2(-2174, -1480), Vector2(-1624, -1480), Vector2(-1562, -1305), Vector2(-1624, -1055), Vector2(-1541, -763), Vector2(-1791, -659), Vector2(-2174, -597)]},
	{"id": "bois_nord_est", "name": "Bois nord-est", "type": "forest", "poly": [Vector2(1251, -1480), Vector2(2173, -1480), Vector2(2173, -743), Vector2(1751, -784), Vector2(1418, -888), Vector2(1272, -1097)]},
	{"id": "hollow_creek", "name": "Hollow Creek", "type": "forest", "poly": [Vector2(1376, 967), Vector2(1501, 778), Vector2(1834, 716), Vector2(2173, 653), Vector2(2173, 967)]},
	{"id": "bois_sud_ouest", "name": "Bois sud-ouest", "type": "forest", "poly": [Vector2(-2174, 758), Vector2(-1749, 716), Vector2(-1332, 758), Vector2(-1124, 903), Vector2(-1082, 967), Vector2(-2174, 967)]},
	{"id": "bois_cedar_lane", "name": "Bois de Cedar Lane", "type": "forest", "poly": [Vector2(560, -170), Vector2(740, -170), Vector2(790, -60), Vector2(730, 40), Vector2(570, 40), Vector2(510, -60)]},
]

# --- lieux (noms validés) ---------------------------------------------------------------------------------------
const POIS := [
	{"id": "casino", "name": "Scarlet Jack Cabaret & Casino", "kind": "casino", "pos": Vector2(-568, -352), "size": Vector2(56, 56), "yaw": 0.0, "access": "grid"},
	{"id": "hotel", "name": "Ashford Grand Hotel", "kind": "hotel", "pos": Vector2(-922, -424), "size": Vector2(44, 70), "yaw": -90.0, "access": "grid"},
	{"id": "echo_circle", "name": "Echo Circle", "kind": "plaza", "pos": Vector2(110, -316), "size": Vector2(52, 52), "yaw": 0.0, "access": "r_echo"},
	{"id": "greenfield", "name": "Greenfield Botanicals", "kind": "complex", "pos": Vector2(-480, -960), "size": Vector2(120, 90), "yaw": 0.0, "access": "n_green"},
	{"id": "liberty_lot", "name": "Liberty Motors", "kind": "car_lot", "pos": Vector2(6, -400), "size": Vector2(50, 90), "yaw": 0.0, "access": "grid"},
	{"id": "safehouse", "name": "Planque de Cedar Lane", "kind": "safehouse", "pos": Vector2(647, -60), "size": Vector2(22, 16), "yaw": 180.0, "access": "n_safe"},
	{"id": "ranch", "name": "Coyote Creek Ranch", "kind": "ranch", "pos": Vector2(1720, -60), "size": Vector2(260, 220), "yaw": 0.0, "access": "n_ranch"},
	{"id": "airport", "name": "Prairie Wind International Airport", "kind": "airport", "pos": Vector2(569, -1155), "size": Vector2(1014, 442), "yaw": 0.0, "access": "n_air"},
	{"id": "motel", "name": "Starlite Motor Inn", "kind": "motel", "pos": Vector2(-470, 585), "size": Vector2(70, 40), "yaw": 90.0, "access": "n_motel"},
	{"id": "hospital", "name": "St. Anselm Medical Center", "kind": "hospital", "pos": Vector2(-280, 162), "size": Vector2(80, 64), "yaw": 180.0, "access": "grid"},
	{"id": "precinct", "name": "Central Precinct", "kind": "police", "pos": Vector2(-713, 162), "size": Vector2(60, 46), "yaw": 180.0, "access": "grid"},
]

# --- garde-fou --------------------------------------------------------------------------------------------------
# Points de contrôle de MapGateTest : le joueur y est posé puis marche (yaw en degrés, 0 = vers le nord).
const GATE_SPOTS := [
	{"name": "berge ouest, Willow Lake", "pos": Vector2(-1450, -260), "yaw": 180.0, "min_stage": 1.0},
	{"name": "collines de Bluffview Heights", "pos": Vector2(-1080, -1100), "yaw": 0.0, "min_stage": 1.0},
	{"name": "plateau de l'aéroport", "pos": Vector2(600, -1150), "yaw": -90.0, "min_stage": 1.0},
	{"name": "campagne est", "pos": Vector2(1500, -420), "yaw": -90.0, "min_stage": 1.0},
	{"name": "zone industrielle", "pos": Vector2(150, 520), "yaw": 90.0, "min_stage": 1.0},
	{"name": "au nord du bassin", "pos": Vector2(-250, -665), "yaw": -90.0, "min_stage": 1.0},
	{"name": "rive ouest, Westbank", "pos": Vector2(-1400, 300), "yaw": 180.0, "min_stage": 1.0},
	{"name": "forêt de Cedar Gulch", "pos": Vector2(-1950, 150), "yaw": 0.0, "min_stage": 1.0},
	{"name": "Eastgate", "pos": Vector2(1400, 520), "yaw": -90.0, "min_stage": 1.0},
	{"name": "viaduc de l'Autoroute Nord sur la rivière", "pos": Vector2(-1230, -693), "yaw": -90.0, "min_stage": 2.0},
	{"name": "tranchée de la Voie express Ouest sous l'échangeur nord-ouest", "pos": Vector2(-706.85, -780), "yaw": 180.0, "min_stage": 2.0},
	{"name": "anneau de l'échangeur sud-ouest", "pos": Vector2(-380, 698), "yaw": 90.0, "min_stage": 2.0},
	{"name": "approche du tunnel sud", "pos": Vector2(-347, 940), "yaw": 180.0, "min_stage": 2.0},
	{"name": "viaduc de la Voie express Ouest le long du centre-ville", "pos": Vector2(-1034.85, 116), "yaw": 180.0, "min_stage": 2.0},
]


# --- lecture ----------------------------------------------------------------------------------------------------
static func node_pos(node_id: String) -> Vector2:
	return NODES[node_id]["pos"]


# Polyligne de conception d'un tronçon : noeud de départ, points de passage, noeud d'arrivée.
static func road_polyline(road: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array([node_pos(road["from"])])
	for p: Vector2 in road["via"]:
		out.append(p)
	out.append(node_pos(road["to"]))
	return out


static func river_polyline() -> PackedVector2Array:
	var out := PackedVector2Array()
	for entry: Array in RIVER:
		out.append(entry[0])
	return out


static func find_road(road_id: String) -> Dictionary:
	for road: Dictionary in ROADS:
		if road["id"] == road_id:
			return road
	return {}


static func zone_polygon(zone: Dictionary) -> PackedVector2Array:
	return PackedVector2Array(zone["poly"])
