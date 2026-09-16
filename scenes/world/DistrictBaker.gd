@tool
extends Node3D

# Bake du quartier NO (grille d'avenues + rond-point approximé + quai/port).
# Génère les tuiles assets/modular_roads/ et assets/dock_models/ par calcul
# (grille régulière 72m / tuiles 12m) puis les FIGE dans la scène (owner =
# racine) — aucune génération au runtime, même principe que BuildingKitBaker.
#
# Coche "Bake Now" dans l'Inspecteur (node "DistrictBaker"), puis Ctrl+S.
#
# Grille validée : colonnes A-G (x), lignes 1-5 (z), bloc = 72m (6 tuiles).
# Carrefour D3 : VRAI rond-point circulaire, anneau fermé de 4x
# Road1_Curve3 (voir _bake_roundabout_ring pour la géométrie de raccord,
# mesurée par sommets réels, pas devinée). Place/parc en bloc E-F / 2-3 :
# aucune tuile de route n'est posée à l'intérieur de ce bloc (réservé pour un
# PathGraph piéton dans une étape suivante).

const ROAD_DIR := "res://assets/modular_roads/"
const ROAD1 := ROAD_DIR + "Road1.glb"
const ROAD2_X := ROAD_DIR + "Road2_X.glb"
const ROAD2_T := ROAD_DIR + "Road2_T.glb"
const CURVE3 := ROAD_DIR + "Road1_Curve3.glb"
const DIAG_L := ROAD_DIR + "Road12_Diagonal_Splitter_L.glb"
const DIAG_R := ROAD_DIR + "Road12_Diagonal_Splitter_R.glb"

const DOCK_DIR := "res://assets/dock_models/FBX/"
const DOCK_WIDE := DOCK_DIR + "Dock_Wide.fbx"

const TILE := 12.0
const BLOCK := 72.0

const COLS := ["A", "B", "C", "D", "E", "F", "G"]
const ROWS := [1, 2, 3, 4, 5]
const COL_X := {"A": -460.0, "B": -388.0, "C": -316.0, "D": -244.0, "E": -172.0, "F": -100.0, "G": -28.0}
const ROW_Z := {1: -460.0, 2: -388.0, 3: -316.0, 4: -244.0, 5: -172.0}

const RB_COL := "D"
const RB_ROW := 3

# --- ÉTAPE "variété" (5 modifications limitées, plan validé avant bake) ---
# 1-2. Diagonales : Road12_Diagonal_Splitter_L/R mesuré par sommets réels
#    (entrée fiable z=-6 comme toutes les autres pièces ; le "fork" est une
#    VRAIE face plane à 45°, plan x-z=7 pour L / x+z=-7 pour R, ~18m de long,
#    confirmé par recherche de plan diagonal sur le nuage de sommets complet
#    — pas une déduction depuis l'AABB). Portée réelle du fork : seulement
#    ~18-20m depuis l'entrée, donc c'est un COURT ÉPERON décoratif qui coupe
#    le coin du bloc, PAS une vraie liaison continue jusqu'à l'avenue
#    diagonalement opposée (aucune pièce de route diagonale droite n'existe
#    dans le pack pour prolonger plus loin).
#    Diagonale A (L) : colonne B, lignes 1-2, remplace les tuiles t=4,5
#      (les 2 plus proches de B2) -> entrée raccordée à la tuile t=3.
#    Diagonale B (R, miroir X de L) : colonne G, lignes 3-4, remplace les
#      tuiles t=1,2 (les 2 plus proches de G3) -> entrée raccordée à t=3.
const DIAG_A_COL := "B"
const DIAG_A_ROWS := [1, 2]
const DIAG_B_COL := "G"
const DIAG_B_ROWS := [3, 4]

# 3-4. Blocs fusionnés : segment retiré entièrement + les 2 carrefours aux
#    extrémités passent de Road2_X à Road2_T (bras manquant fermé proprement
#    au lieu d'un moignon visuel). Rotations du T réutilisées telles que
#    VÉRIFIÉES visuellement sur le rond-point (through=axe Z / pied=+X ->
#    270°, through=axe Z / pied=-X -> 90°), pas re-devinées.
#    Fusion A : ligne 2, colonnes B-C -> B2 (pied vers l'ouest, 90°),
#      C2 (pied vers l'est, 270°).
#    Fusion B : ligne 4, colonnes E-F -> E4 (pied vers l'ouest, 90°),
#      F4 (pied vers l'est, 270°).
const FUSION_A_ROW := 2
const FUSION_A_COLS := ["B", "C"]
const FUSION_B_ROW := 4
const FUSION_B_COLS := ["E", "F"]
const INTERSECTION_T_OVERRIDE := {
	"B2": 90.0, "C2": 270.0,
	"E4": 90.0, "F4": 270.0,
}

# 5. Chicane en S : colonne B, lignes 4-5, remplace les tuiles t=2,3,4 par
#    2x Road1_Curve3 (géométrie déjà validée sur le rond-point). Calculé par
#    chaînage (entrée/sortie réelles mesurées, pas devinées) : la paire de
#    courbes avance net de 36m (= 3 tuiles) et revient exactement sur l'axe
#    de la colonne B -> s'insère pile entre les tuiles t=1 et t=5 existantes,
#    sans rien modifier d'autre.
const CHICANE_COL := "B"
const CHICANE_ROWS := [4, 5]

const PIER_X := [-388.0, -244.0, -100.0]
# bord proche (côté quai) du ponton pile sur la limite eau/quai z=-500 :
# centre = -500 - (demi-longueur du plancher mesuré 21.68m x échelle 0.6)/1
const PIER_Z := -506.504

@export var bake_now := false:
	set(value):
		if not value:
			return
		bake_now = false
		if Engine.is_editor_hint():
			call_deferred("_bake")

func _ready() -> void:
	pass   # aucune génération runtime : le baker ne sert qu'en éditeur

func _bake() -> void:
	var root: Node = owner
	if root == null:
		root = get_tree().edited_scene_root
	if root == null:
		push_error("[DistrictBaker] racine de scène introuvable")
		return

	var old_roads := root.get_node_or_null("Roads")
	if old_roads != null:
		old_roads.free()
	var old_quay := root.get_node_or_null("Quay")
	if old_quay != null:
		old_quay.free()

	var roads := Node3D.new()
	roads.name = "Roads"
	root.add_child(roads)
	roads.owner = root

	var quay := Node3D.new()
	quay.name = "Quay"
	root.add_child(quay)
	quay.owner = root

	var n_inter := _bake_intersections(roads, root)
	var n_seg := _bake_segments(roads, root)
	var n_rb := _bake_roundabout_ring(roads, root)
	_bake_diagonal_a(roads, root)
	_bake_diagonal_b(roads, root)
	_bake_chicane(roads, root)
	_bake_quay(quay, root)

	print("[DistrictBaker] BAKE : %d intersections, %d tuiles droites, %d pièces rond-point (4 courbes + 4 Road2_T), 2 diagonales, 1 chicane (2 courbes), quai construit." % [n_inter, n_seg, n_rb])

func _place(parent: Node, root: Node, path: String, node_name: String, pos: Vector3, rot_y_deg: float) -> Node3D:
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("[DistrictBaker] modèle introuvable : " + path)
		return null
	var inst := scene.instantiate() as Node3D
	inst.name = node_name
	parent.add_child(inst)
	inst.position = pos
	inst.rotation_degrees.y = rot_y_deg
	inst.owner = root
	return inst

func _bake_intersections(parent: Node, root: Node) -> int:
	var count := 0
	for col in COLS:
		for row in ROWS:
			if col == RB_COL and row == RB_ROW:
				continue   # D3 remplacé par l'anneau du rond-point (_bake_roundabout_ring)
			var key: String = col + str(row)
			var nm := "X_%s%d" % [col, row]
			if INTERSECTION_T_OVERRIDE.has(key):
				_place(parent, root, ROAD2_T, nm, Vector3(COL_X[col], 0, ROW_Z[row]), INTERSECTION_T_OVERRIDE[key])
			else:
				_place(parent, root, ROAD2_X, nm, Vector3(COL_X[col], 0, ROW_Z[row]), 0.0)
			count += 1
	return count

# Segments droits entre deux carrefours adjacents. Cas normal : 5 tuiles
# (72/12 - 1, cf. commentaire const BLOCK/TILE). Sur les 4 segments qui
# touchent D3 (le rond-point : anneau de courbes + 4x Road2_T insérés aux
# jonctions, rayon utile 30m depuis le centre au lieu des 6m d'un carrefour
# simple), les 2 tuiles les plus proches du centre chevaucheraient
# l'anneau/le T -> on les retire (skip_first si D3 est au DÉBUT du segment,
# skip_last si D3 est à la FIN). Vérifié par calcul : la tuile restante la
# plus proche touche pile le pied du T (voir _bake_roundabout_ring).
func _bake_segments(parent: Node, root: Node) -> int:
	var count := 0
	var n_tiles := int(BLOCK / TILE) - 1   # 72/12 - 1 = 5 tuiles entre deux carrefours adjacents

	# segments Nord-Sud (une colonne, entre deux lignes consécutives) -> rotation 0
	for col in COLS:
		for i in ROWS.size() - 1:
			var r0: int = ROWS[i]
			var r1: int = ROWS[i + 1]
			var z0: float = ROW_Z[r0]
			var skip_first: bool = col == RB_COL and r0 == RB_ROW
			var skip_last: bool = col == RB_COL and r1 == RB_ROW
			var extra_skip: Array = []
			if col == DIAG_A_COL and r0 == DIAG_A_ROWS[0] and r1 == DIAG_A_ROWS[1]:
				extra_skip = [4, 5]   # remplacées par la diagonale A
			elif col == DIAG_B_COL and r0 == DIAG_B_ROWS[0] and r1 == DIAG_B_ROWS[1]:
				extra_skip = [1, 2]   # remplacées par la diagonale B
			elif col == CHICANE_COL and r0 == CHICANE_ROWS[0] and r1 == CHICANE_ROWS[1]:
				extra_skip = [2, 3, 4]   # remplacées par la chicane en S
			for t in range(1, n_tiles + 1):
				if skip_first and t <= 2:
					continue
				if skip_last and t >= n_tiles - 1:
					continue
				if extra_skip.has(t):
					continue
				var nm := "NS_%s_%d-%d_%d" % [col, r0, r1, t]
				_place(parent, root, ROAD1, nm, Vector3(COL_X[col], 0, z0 + t * TILE), 0.0)
				count += 1
				if count % 50 == 0:
					print("[DistrictBaker] ... %d tuiles placées" % count)

	# segments Est-Ouest (une ligne, entre deux colonnes consécutives) -> rotation 90
	for row in ROWS:
		for i in COLS.size() - 1:
			var c0: String = COLS[i]
			var c1: String = COLS[i + 1]
			var x0: float = COL_X[c0]
			var skip_first: bool = row == RB_ROW and c0 == RB_COL
			var skip_last: bool = row == RB_ROW and c1 == RB_COL
			var full_remove: bool = (row == FUSION_A_ROW and c0 == FUSION_A_COLS[0] and c1 == FUSION_A_COLS[1]) \
				or (row == FUSION_B_ROW and c0 == FUSION_B_COLS[0] and c1 == FUSION_B_COLS[1])
			if full_remove:
				continue   # bloc fusionné : segment retiré entièrement (Fusion A/B)
			for t in range(1, n_tiles + 1):
				if skip_first and t <= 2:
					continue
				if skip_last and t >= n_tiles - 1:
					continue
				var nm := "EW_%d_%s-%s_%d" % [row, c0, c1, t]
				_place(parent, root, ROAD1, nm, Vector3(x0 + t * TILE, 0, ROW_Z[row]), 90.0)
				count += 1
				if count % 50 == 0:
					print("[DistrictBaker] ... %d tuiles placées" % count)

	return count

# VRAI rond-point circulaire en D3 : anneau fermé de 4x Road1_Curve3, avec un
# Road2_T inséré à chacune des 4 jonctions (N/S/E/O) pour une transition
# propre entre l'anneau et chaque bras d'avenue (remplace le raccord abrupt
# courbe-contre-courbe d'avant). Remplace l'ancien Road2_X central (retiré de
# _bake_intersections).
#
# Géométrie Road1_Curve3 réutilisée telle que mesurée par sommets réels sur
# le tronçon test (entrée réelle = plan local z=-6, sortie réelle = plan
# local x=+18, cf. commentaire précédent). Géométrie Road2_T mesurée par
# filtrage Y (chaussée basse) sur ce chantier : à rotation 0, face fermée =
# z=-6, traversée (through) = x=-6/x=+6, pied du T (stem) = z=+6.
#
# J'ai rechaîné tout l'anneau en alternant courbe -> T -> courbe -> T (au
# lieu de courbe -> courbe directement) : chaque T occupe l'ESPACE entre deux
# courbes adjacentes (12m de large sur l'axe de traversée), donc les 4
# courbes doivent s'écarter du centre pour lui faire de la place. Chaînage
# vérifié par calcul (la boucle se referme exactement, symétrie à 4 branches
# confirmée : les 4 courbes sont à égale distance du centre, 26.83m, à 90°
# de rotation les unes des autres).
#   décalage local (x,z) / rotation, relatif au centre du carrefour D3 :
#     RB_1 : (+12, +24) / 90°   RB_2 : (+24, -12) / 180°
#     RB_3 : (-12, -24) / 270°  RB_4 : (-24, +12) / 0°
#     T_Nord  : (0,-24) / 0°    T_Sud   : (0,24) / 180°
#     T_Est   : (24,0)  / 270°  T_Ouest : (-24,0) / 90°
#   jonctions bras<->T (pied du T), local relatif D3 :
#     Nord=(0,-30)  Est=(30,0)  Sud=(0,30)  Ouest=(-30,0)
#
# Rotations des 4 Road2_T CORRIGÉES À LA MAIN dans l'éditeur (+180° chacune
# par rapport à mon calcul initial) après retour visuel du 12/09 — mon calcul
# analytique du sens du pied du T avait une erreur de signe (vérifiée en
# comparant à la convention réelle de rotation_degrees.y de Godot, opposée à
# ma dérivation manuelle). Les valeurs ci-dessous reflètent la correction
# manuelle confirmée ; les 4 courbes, elles, n'ont pas été touchées (déjà
# bonnes). Le chaînage/positionnement (offsets, fermeture de boucle) reste
# validé par calcul et n'a pas changé.
func _bake_roundabout_ring(parent: Node, root: Node) -> int:
	var cx: float = COL_X[RB_COL]
	var cz: float = ROW_Z[RB_ROW]
	var pieces := [
		{"name": "RB_1", "path": CURVE3, "rot": 90.0, "off": Vector2(12.0, 24.0)},
		{"name": "RB_2", "path": CURVE3, "rot": 180.0, "off": Vector2(24.0, -12.0)},
		{"name": "RB_3", "path": CURVE3, "rot": 270.0, "off": Vector2(-12.0, -24.0)},
		{"name": "RB_4", "path": CURVE3, "rot": 0.0, "off": Vector2(-24.0, 12.0)},
		{"name": "T_North", "path": ROAD2_T, "rot": 0.0, "off": Vector2(0.0, -24.0)},
		{"name": "T_South", "path": ROAD2_T, "rot": 180.0, "off": Vector2(0.0, 24.0)},
		{"name": "T_East", "path": ROAD2_T, "rot": 270.0, "off": Vector2(24.0, 0.0)},
		{"name": "T_West", "path": ROAD2_T, "rot": 90.0, "off": Vector2(-24.0, 0.0)},
	]
	var count := 0
	for p in pieces:
		var off: Vector2 = p["off"]
		var path: String = p["path"]
		_place(parent, root, path, p["name"], Vector3(cx + off.x, 0, cz + off.y), p["rot"])
		count += 1
	return count

# Diagonale A (L) : colonne B, lignes 1-2. Entrée (local z=-6) raccordée à la
# tuile t=3 (la dernière tuile droite gardée), qui se termine à z=-418 ->
# position.z = -418 + 6 = -412. Pas de rotation (l'entrée par défaut de la
# pièce reçoit déjà depuis -Z, comme une tuile Road1 non tournée).
func _bake_diagonal_a(parent: Node, root: Node) -> void:
	_place(parent, root, DIAG_L, "Diag_A", Vector3(COL_X[DIAG_A_COL], 0, -412.0), 0.0)

# Diagonale B (R, miroir X de L) : colonne G, lignes 3-4. Entrée raccordée à
# la tuile t=3, qui commence à z=-310 (côté G3) -> position.z = -310 + 6 = -304.
func _bake_diagonal_b(parent: Node, root: Node) -> void:
	_place(parent, root, DIAG_R, "Diag_B", Vector3(COL_X[DIAG_B_COL], 0, -304.0), 0.0)

# Chicane en S : colonne B, lignes 4-5. Remplace les tuiles t=2,3,4 (entre les
# tuiles t=1 et t=5 gardées) par 2x Road1_Curve3 chaînées (sud -> est -> sud),
# géométrie de raccord identique à celle validée sur le rond-point :
#   Courbe1 (rot 0)   : entrée reçoit depuis le nord (tuile t=1, finit à
#     z=-226) -> position (COL_B, -220). Sortie -> (COL_B+18, -220+12)=(-370,-208).
#   Courbe2 (rot 270) : entrée = sortie de Courbe1 -> position (-376,-208).
#     Sortie -> (-388,-190), qui raccorde pile à la tuile t=5 (commence à
#     z=-190, côté nord).
# Vérifié par calcul : la paire avance net de 36m et revient exactement sur
# x=-388 (axe de la colonne B), donc aucune tuile intermédiaire n'est requise.
func _bake_chicane(parent: Node, root: Node) -> void:
	_place(parent, root, CURVE3, "Chicane_1", Vector3(COL_X[CHICANE_COL], 0, -220.0), 0.0)
	_place(parent, root, CURVE3, "Chicane_2", Vector3(-376.0, 0, -208.0), 270.0)

func _bake_quay(parent: Node, root: Node) -> void:
	# bande quai (pavage) : x[-460,-28] z[-500,-460], centre (-244,-480)
	_make_box(parent, root, "QuayPavement",
		Vector3(-244, -0.5, -480), Vector3(432, 1, 40),
		Color(0.55, 0.53, 0.5, 1), true)

	# plan d'eau : x[-500,0] z[-500,-650], centre (-250,-575)
	_make_box(parent, root, "Water",
		Vector3(-250, -0.3, -575), Vector3(500, 0.4, 150),
		Color(0.14, 0.34, 0.55, 0.55), true, true)

	# fond marin, sous l'eau, pas de collision
	_make_box(parent, root, "Seabed",
		Vector3(-250, -3.0, -575), Vector3(500, 1, 150),
		Color(0.1, 0.13, 0.16, 1), false)

	# 3 pontons (Dock_Wide), alignés sur les avenues B / D / F.
	# Échelle et hauteur corrigées par mesure réelle : histogramme des sommets
	# du mesh par tranche de Y -> le plancher (plus grosse concentration,
	# ~55% des sommets, étalée sur quasi toute l'emprise X/Z) est à Y local
	# ≈ 3.6, pas à Y=0 (ce qui faisait flotter tout le ponton ~3.6m au-dessus
	# de l'eau). Le reste (Y<3.4) = pilotis/poteaux sous le plancher.
	const PIER_SCALE := 0.6
	const DECK_LOCAL_Y := 3.6   # mesuré (centre de la tranche [3.4, 3.8])
	for x in PIER_X:
		var pier := Node3D.new()
		pier.name = "Pier_x%d" % int(x)
		parent.add_child(pier)
		pier.owner = root
		pier.position = Vector3(x, 0, PIER_Z)

		var model := _place(pier, root, DOCK_WIDE, "DockModel",
			Vector3(0, -DECK_LOCAL_Y * PIER_SCALE, 0), 0.0)
		if model != null:
			model.scale = Vector3(PIER_SCALE, PIER_SCALE, PIER_SCALE)

		var body := StaticBody3D.new()
		body.name = "StaticBody3D"
		pier.add_child(body)
		body.owner = root
		var shape := CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		body.add_child(shape)
		shape.owner = root
		var box := BoxShape3D.new()
		# dalle fine au niveau du plancher réel (pas toute la hauteur du mesh,
		# pilotis compris) : empreinte mesurée x/z du plancher, mise à l'échelle
		box.size = Vector3(13.44 * PIER_SCALE, 0.5, 21.69 * PIER_SCALE)
		shape.shape = box
		shape.position = Vector3(0, 0, 0)   # centré sur le plancher (niveau quai/eau)

func _make_box(parent: Node, root: Node, node_name: String, pos: Vector3, size: Vector3, color: Color, with_collision: bool, transparent: bool = false) -> void:
	var body: Node3D
	if with_collision:
		var sb := StaticBody3D.new()
		body = sb
	else:
		body = Node3D.new()
	body.name = node_name
	parent.add_child(body)
	body.owner = root
	body.position = pos

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Mesh"
	body.add_child(mesh_inst)
	mesh_inst.owner = root
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh_inst.mesh = box_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.metallic = 0.2
	mesh_inst.set_surface_override_material(0, mat)

	if with_collision:
		var coll := CollisionShape3D.new()
		coll.name = "CollisionShape3D"
		body.add_child(coll)
		coll.owner = root
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		coll.shape = box_shape
