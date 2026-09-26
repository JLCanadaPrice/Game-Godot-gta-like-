extends SceneTree

# CONVERSION DE TROIS PACKS D'ACCESSOIRES (2026-09-23) — AirportGroundVehicles, Farm Buildings by Quaternius, Low Poly
# Construction, reçus en FBX (avec des .blend, .obj et un .cs Unity, ignorés). Une scène PRÊTE À POSER par modèle.
#
# Les FBX ne sont PAS dans le dépôt du jeu : ce sont des sources brutes, gardées dans le dépôt privé des sources
# (D:/p-recree/sources-brutes/assets/<pack>/). Pour relancer cette conversion :
#   1. copier les FBX de chaque pack dans res://assets/_fbx_import/<airport|farm|construction>/ ;
#   2. Godot --headless --path <projet> --import ;
#   3. Godot --headless --path <projet> --script res://scenes/world/props/tools/ConversionPacks.gd ;
#   4. supprimer res://assets/_fbx_import/ (FBX et .import).
#
# Pour chaque modèle, dans res://assets/<pack>/ :
#  - models/<Nom>.res : un maillage fusionné, toutes ses pièces dans le repère du modèle, les couleurs des matériaux du
#    pack en couleurs de sommet (sRGB) sur UN matériau partagé par pack — un appel de dessin par objet —, niveaux de
#    détail générés ;
#  - à l'ÉCHELLE RÉELLE, cuite dans les sommets (jamais par Node3D.scale) : facteur relevé modèle par modèle sur les
#    sommets, contre une dimension réelle connue (cf. les tables : le pack de chantier est incohérent, ses murs de 3 m
#    sont justes mais ses outils 1,5 à 4 fois trop gros) ;
#  - posé au sol (bas du modèle à y = 0), centré en x et z ; l'avant des véhicules vers +Z, la convention des modèles
#    du catalogue de véhicules ;
#  - <Nom>.tscn : StaticBody3D (fixe, mobile) ou Node3D (outil), avec un MeshInstance3D « Mesh » dont la portée de
#    visibilité vaut 75 fois sa TAILLE APPARENTE — la moyenne géométrique de ses deux plus grandes dimensions, pour
#    qu'une clôture de 1,10 m de haut sur 5,89 m ne porte pas comme un objet de 5,89 m —, entre 25 et 2 500 m : la
#    règle des véhicules garés (4 m -> 300 m) ; tout objet posé en permanence sur la carte a besoin d'une portée
#    (CLAUDE.md §6) ;
#  - la collision selon la catégorie :
#      fixe   : la forme EXACTE, triangles du modèle à deux faces (ConcavePolygonShape3D), comme les bâtiments (§12) ;
#      mobile : une enveloppe CONVEXE par pièce du modèle (ConvexPolygonShape3D). Jolt ne fait pas se toucher deux formes
#               concaves (§12) : c'est ce qui permet d'en faire un RigidBody3D en changeant seulement la racine ;
#      outil  : aucune — outils à main et petits objets posés par terre, on marche dessus sans buter.

const SOURCE := "res://assets/_fbx_import/"
const PORTEE_PAR_METRE := 75.0
const PORTEE_MIN := 25.0
const PORTEE_MAX := 2500.0
const PIECE_MIN := 0.05            # m : une pièce plus petite n'a pas d'enveloppe à elle

# [dossier d'import, dossier de destination, titre du pack]
const PACKS := [
	["airport", "res://assets/airport_ground_vehicles/", "AirportGroundVehicles"],
	["farm", "res://assets/farm_buildings_quaternius/", "Farm Buildings by Quaternius"],
	["construction", "res://assets/low_poly_construction/", "Low Poly Construction"],
]

# VÉHICULES D'AÉROPORT : à l'échelle réelle telle quelle. Relevé : roues de camion de 0,92 m, caisse du camion-citerne
# de 2,46 m au réservoir et 2,70 m aux roues (3,13 m rétroviseurs compris) pour 10,08 m de long, tracteur à bagages
# 1,74 x 2,92 m ; une voiture du jeu fait 2,0 à 2,1 m de large. Avant vers +Z (roues avant du côté des z croissants).
# L'escabeau (Stairs) est entièrement peint par une texture palette ABSENTE du pack (airportpalette.png, ni dans les
# FBX ni empaquetée dans le .blend) : couleurs unies choisies ici, cf. COULEURS_SANS_TEXTURE.
const AEROPORT := {
	"BaggageTug": ["BaggageTug", 1.0, "mobile"],
	"Cart": ["BaggageCart", 1.0, "mobile"],
	"FuelTruck": ["FuelTruck", 1.0, "mobile"],
	"Stairs": ["StairsTruck", 1.0, "mobile"],
}
const COULEURS_SANS_TEXTURE := {"Stairs": Color(0.85, 0.85, 0.82), "StairsTop": Color(0.62, 0.62, 0.60), "roue": Color(0.16, 0.16, 0.16)}

# FERME : les BÂTIMENTS à 1,3. Relevé sur les sommets : la porte de la petite grange fait 1,69 m de haut, sous la
# capsule du joueur (1,80 m) ; celles des granges 2,15 m, une porte de maison et pas de grange. À 1,3 : 2,20 m et
# 2,80 m, et une grange de 7,8 m de haut sur 10 x 10,7 m, une petite grange réelle. Les petits objets restent à 1 :
# clôture de 1,10 m, puits de 2,15 m, poulailler de 1,85 m, déjà justes. Les pales des moulins restent une pièce à part,
# posée sur son moyeu, pour pouvoir les faire tourner (autour de leur Z).
const FERME := {
	"Barn": ["Barn", 1.3, "fixe"],
	"BigBarn": ["BigBarn", 1.3, "fixe"],
	"SmallBarn": ["SmallBarn", 1.3, "fixe"],
	"OpenBarn": ["OpenBarn", 1.3, "fixe"],
	"Silo": ["Silo", 1.3, "fixe"],
	"Silo_House": ["SiloHouse", 1.3, "fixe"],
	"WaterTower": ["WaterTower", 1.3, "fixe"],
	"Windmill": ["Windmill", 1.3, "fixe", "Windmill_Blades"],
	"TowerWindmill": ["TowerWindmill", 1.3, "fixe", "TowerWindmill_Blades"],
	"ChickenCoop": ["ChickenCoop", 1.0, "fixe"],
	"Fence": ["Fence", 1.0, "fixe"],
	"Fence2": ["Fence2", 1.0, "fixe"],
	"Well": ["Well", 1.0, "fixe"],
}

# CHANTIER : facteur par modèle, contre une dimension réelle (entre parenthèses : mesuré -> réel). Les pièces de
# structure sont justes à 1 (mur, fenêtre, poteaux, escalier : 3,00 m ; dalle 2,40 m ; poutrelles, tuyaux et râteliers
# qui vont avec ; grue de 36,7 m). Le reste est 1,5 à 4 fois trop gros.
const CHANTIER := {
	"Barrel A": ["BarrelA", 0.595, "mobile"],        # fût de 208 l : haut 1,48 -> 0,88
	"Barrel B": ["BarrelB", 0.595, "mobile"],        # groupe de fûts, même facteur
	"Barrier A": ["BarrierA", 0.8, "mobile"],        # barrière plastique : haut 1,25 -> 1,00
	"Barrier B": ["BarrierB", 0.8, "mobile"],
	"Barrier C": ["BarrierC", 0.7, "mobile"],        # chevalet : 1,58 -> 1,10
	"Barrier D": ["BarrierD", 0.89, "mobile"],       # panneau de palissade : 2,25 -> 2,00
	"Bin": ["Bin", 1.0, "mobile"],                   # poubelle : 0,99, juste
	"Bolts": ["Bolts", 0.6, "outil"],
	"Box A": ["BoxA", 0.6, "mobile"],                # caisse : 1,02 -> 0,61
	"Box B": ["BoxB", 0.5, "mobile"],                # grande caisse : 2,39 -> 1,20
	"Box C": ["BoxC", 0.5, "mobile"],
	"Brick A": ["BrickA", 0.5, "mobile"],            # petite pile de briques
	"Brick B": ["BrickB", 0.5, "fixe"],              # palette de briques : 2,39 -> 1,20 (palette réelle)
	"Brick C": ["BrickC", 0.5, "mobile"],
	"Bucket": ["Bucket", 0.6, "mobile"],             # seau : 0,52 -> 0,31
	"Cement Bag A": ["CementBagA", 0.5, "mobile"],   # sac de 35 kg : 1,39 -> 0,70
	"Cement Bag B": ["CementBagB", 0.5, "fixe"],     # palette de sacs
	"Cement Mixer": ["CementMixer", 0.9, "mobile"],  # bétonnière : 1,56 -> 1,40
	"Cinderblock": ["Cinderblock", 0.6, "mobile"],   # parpaing : 0,61 -> 0,37
	"Clipboard": ["Clipboard", 0.4, "outil"],        # porte-bloc : 0,78 -> 0,31
	"Cone A": ["ConeA", 0.6, "mobile"],              # cône : 0,60 -> 0,36
	"Cone B": ["ConeB", 0.6, "mobile"],              # grand cône : 1,48 -> 0,89
	"Container": ["Container", 0.86, "fixe"],        # conteneur 20 pieds : 7,05 -> 6,06
	"Crane": ["Crane", 1.0, "fixe"],                 # grue à tour : 36,7 m
	"Drill": ["Drill", 0.4, "outil"],                # perceuse : 0,72 -> 0,29
	"Fence A": ["FenceA", 0.66, "fixe"],             # clôture de chantier : 3,03 -> 2,00
	"Fence B": ["FenceB", 0.66, "fixe"],
	"Fence Gate ": ["FenceGate", 0.66, "fixe"],
	"Floor": ["Floor", 1.0, "fixe"],
	"Fuel Can": ["FuelCan", 0.5, "mobile"],          # jerrican : 0,91 -> 0,46
	"Fuel Tank": ["FuelTank", 0.8, "fixe"],          # cuve de chantier : 6,26 -> 5,00
	"Gas Tank A": ["GasTankA", 0.6, "mobile"],       # bouteille de gaz : 0,64 -> 0,38
	"Gas Tanks B": ["GasTankB", 0.6, "mobile"],      # bouteille de soudure : 1,56 -> 0,94
	"Goggles": ["Goggles", 0.3, "outil"],            # lunettes : 0,60 -> 0,18
	"Hammer": ["Hammer", 0.66, "outil"],             # marteau : 0,50 -> 0,33
	"Headphones": ["Headphones", 0.35, "outil"],     # casque antibruit : 0,58 -> 0,20
	"Helmet": ["Helmet", 0.33, "outil"],             # casque de chantier : 0,90 -> 0,30
	"Ladder A": ["LadderA", 0.8, "mobile"],          # escabeau : 2,98 -> 2,38
	"Ladder B": ["LadderB", 0.8, "mobile"],
	"Ladder C": ["LadderC", 0.8, "mobile"],          # échelle : 3,44 -> 2,75
	"Level": ["Level", 0.6, "outil"],                # niveau : 1,39 -> 0,83
	"Mallet": ["Mallet", 0.6, "outil"],
	"Nails": ["Nails", 0.6, "outil"],
	"Paint Bucket": ["PaintBucket", 0.6, "mobile"],
	"Pallet": ["Pallet", 0.5, "mobile"],             # palette : 2,39 x 2,32 -> 1,20 x 1,16
	"Pillar A": ["PillarA", 1.0, "fixe"],
	"Pillar B": ["PillarB", 1.0, "fixe"],
	"Pipe A": ["PipeA", 1.0, "mobile"],
	"Pipe B": ["PipeB", 1.0, "fixe"],                # pile de tuyaux
	"Pipe Holder A": ["PipeHolderA", 1.0, "fixe"],
	"Pipe Holder B": ["PipeHolderB", 1.0, "fixe"],
	"Plank A": ["PlankA", 1.0, "mobile"],
	"Plank B": ["PlankB", 1.0, "fixe"],              # pile de planches
	"Plank Holder": ["PlankHolder", 1.0, "fixe"],
	"Radio": ["Radio", 0.5, "outil"],                # talkie-walkie : 0,46 -> 0,23
	"Rake": ["Rake", 0.9, "outil"],                  # râteau : 1,70 -> 1,53
	"Saw": ["Saw", 0.6, "outil"],                    # scie : 1,05 -> 0,63
	"Scaffolding A": ["ScaffoldingA", 0.6, "fixe"],  # échafaudage : levée 3,90 -> 2,34, travée 4,76 -> 2,86
	"Scaffolding B": ["ScaffoldingB", 0.6, "fixe"],
	"Screwdriver": ["Screwdriver", 0.4, "outil"],    # tournevis : 0,60 -> 0,24
	"Shovel": ["Shovel", 0.9, "outil"],              # pelle : 1,52 -> 1,37
	"Skip": ["Skip", 0.8, "fixe"],                   # benne : 5,79 -> 4,63
	"Sledgehammer": ["Sledgehammer", 0.6, "outil"],  # masse : 1,47 -> 0,88
	"Spanner A": ["SpannerA", 0.5, "outil"],         # clé : 0,50 -> 0,25
	"Spanner B": ["SpannerB", 0.5, "outil"],
	"Spool A": ["SpoolA", 0.8, "mobile"],            # touret de câble : 1,99 -> 1,59
	"Spool B": ["SpoolB", 0.8, "mobile"],
	"Stairs": ["Stairs", 1.0, "fixe"],
	"Steel A": ["SteelA", 1.0, "mobile"],
	"Steel B": ["SteelB", 1.0, "fixe"],              # pile de poutrelles
	"Steel Holder ": ["SteelHolder", 1.0, "fixe"],
	"Tape Measure": ["TapeMeasure", 0.3, "outil"],   # mètre ruban : 0,32 -> 0,10
	"Toilet A": ["ToiletA", 0.78, "fixe"],           # toilettes de chantier : 2,92 -> 2,28
	"Toilet B": ["ToiletB", 0.78, "fixe"],
	"Toolbox": ["Toolbox", 0.7, "mobile"],           # caisse à outils : 0,67 -> 0,47
	"Wall": ["Wall", 1.0, "fixe"],
	"Wheelbarrow": ["Wheelbarrow", 0.6, "mobile"],   # brouette : 2,46 -> 1,48
	"Window": ["Window", 1.0, "fixe"],
	"Wood Stand": ["WoodStand", 0.6, "mobile"],      # tréteau : 2,45 -> 1,47
	"Work Light A": ["WorkLightA", 0.6, "mobile"],   # projecteur sur pied bas
	"Work Light B": ["WorkLightB", 1.0, "mobile"],   # projecteur sur trépied : 1,95, juste
}

var _materiaux := {}
var _bilan: Array[String] = []


func _initialize() -> void:
	var tables := {"airport": AEROPORT, "farm": FERME, "construction": CHANTIER}
	var fautes := 0
	for p: Array in PACKS:
		var dossier: String = SOURCE + String(p[0]) + "/"
		var dest: String = p[1]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest.path_join("models")))
		var materiau := _materiau(dest, String(p[2]))
		var table: Dictionary = tables[p[0]]
		var vus := 0
		for fichier in DirAccess.get_files_at(dossier):
			if not fichier.ends_with(".fbx"):
				continue
			var base := fichier.get_basename()
			if not table.has(base):
				push_error("CONVERSION %s : %s absent des tables" % [p[0], fichier])
				fautes += 1
				continue
			vus += 1
			if not _convertir(dossier + fichier, dest, table[base], materiau):
				fautes += 1
		if vus != table.size():
			push_error("CONVERSION %s : %d FBX pour %d modèles dans la table" % [p[0], vus, table.size()])
			fautes += 1
	for l in _bilan:
		print(l)
	print("CONVERSION_PACKS %d modèle(s), %d faute(s)" % [_bilan.size(), fautes])
	quit(0 if fautes == 0 else 1)


# Le matériau partagé d'un pack : couleurs de sommet (sRGB, comme les bâtiments), deux faces (les packs ont des pièces
# plates et fines, qu'on ne veut pas voir disparaître de dos).
func _materiau(dest: String, titre: String) -> StandardMaterial3D:
	var chemin := dest.path_join("materiau.tres")
	var m := StandardMaterial3D.new()
	m.resource_name = titre
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.75
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	ResourceSaver.save(m, chemin)
	return load(chemin)


func _xf(n: Node, racine: Node) -> Transform3D:
	var xf := Transform3D()
	var c: Node = n
	while c != null and c != racine.get_parent():
		if c is Node3D:
			xf = (c as Node3D).transform * xf
		c = c.get_parent()
	return xf


# Une pièce : sommets, normales, couleurs, indices, déjà mis à l'échelle et dans le repère du modèle (avant recentrage).
func _piece(mi: MeshInstance3D, xf: Transform3D, echelle: float, modele: String) -> Dictionary:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()
	var nb := xf.basis.inverse().transposed()
	var miroir := xf.basis.determinant() < 0.0
	for s in mi.mesh.get_surface_count():
		if mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var a := mi.mesh.surface_get_arrays(s)
		var sv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var sn: PackedVector3Array = a[Mesh.ARRAY_NORMAL] if a[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var sc: PackedColorArray = a[Mesh.ARRAY_COLOR] if a[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var si: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if si.is_empty():
			for k in sv.size():
				si.append(k)
		var teinte := _teinte(mi.get_active_material(s), String(mi.name), modele)
		var base := v.size()
		for k in sv.size():
			v.append((xf * sv[k]) * echelle)
			n.append((nb * sn[k]).normalized() if k < sn.size() else Vector3.UP)
			var vc: Color = sc[k] if k < sc.size() else Color.WHITE
			c.append(Color(teinte.r * vc.r, teinte.g * vc.g, teinte.b * vc.b))
		for t in range(0, si.size() - 2, 3):
			if miroir:
				idx.append_array(PackedInt32Array([base + si[t], base + si[t + 2], base + si[t + 1]]))
			else:
				idx.append_array(PackedInt32Array([base + si[t], base + si[t + 1], base + si[t + 2]]))
	return {"v": v, "n": n, "c": c, "i": idx, "nom": String(mi.name)}


# Couleur d'une surface : l'albédo de son matériau ; pour les surfaces dont la texture manque au pack (ColorMaterial de
# l'escabeau), la couleur choisie dans COULEURS_SANS_TEXTURE.
func _teinte(mat: Material, piece: String, modele: String) -> Color:
	if mat is BaseMaterial3D:
		var bm := mat as BaseMaterial3D
		if String(bm.resource_name) == "ColorMaterial" and modele == "Stairs":
			if COULEURS_SANS_TEXTURE.has(piece):
				return COULEURS_SANS_TEXTURE[piece]
			return COULEURS_SANS_TEXTURE["roue"]
		return bm.albedo_color
	return Color(0.7, 0.7, 0.7)


func _maillage(pieces: Array, decalage: Vector3, materiau: Material, nom: String) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()
	for p: Dictionary in pieces:
		var base := v.size()
		for q in (p["v"] as PackedVector3Array):
			v.append(q + decalage)
		n.append_array(p["n"])
		c.append_array(p["c"])
		for k in (p["i"] as PackedInt32Array):
			idx.append(base + k)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = c
	arrays[Mesh.ARRAY_INDEX] = idx
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, materiau, nom)
	importer.generate_lods(25.0, 60.0, [])
	return importer.get_mesh()


func _convertir(chemin: String, dest: String, spec: Array, materiau: Material) -> bool:
	var nom: String = spec[0]
	var echelle: float = spec[1]
	var categorie: String = spec[2]
	var nom_pales: String = spec[3] if spec.size() > 3 else ""
	var modele := chemin.get_file().get_basename()
	var sc := load(chemin) as PackedScene
	if sc == null:
		push_error("CONVERSION %s : FBX illisible" % chemin)
		return false
	var racine: Node3D = sc.instantiate()
	var pieces: Array = []
	var pales: Dictionary = {}
	var pivot := Vector3.ZERO
	for m in racine.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := _xf(mi, racine)
		if nom_pales != "" and String(mi.name) == nom_pales:
			# pales : sommets relatifs au moyeu (l'origine de leur noeud), le noeud posé au moyeu
			pivot = xf.origin * echelle
			pales = _piece(mi, Transform3D(xf.basis, Vector3.ZERO), echelle, modele)
			continue
		pieces.append(_piece(mi, xf, echelle, modele))
	racine.free()
	if pieces.is_empty():
		push_error("CONVERSION %s : aucun maillage" % chemin)
		return false
	# boîte de l'ensemble (pales comprises) : bas à y = 0, centré en x et z
	var boite := AABB((pieces[0]["v"] as PackedVector3Array)[0], Vector3.ZERO)
	for p: Dictionary in pieces:
		for q in (p["v"] as PackedVector3Array):
			boite = boite.expand(q)
	if not pales.is_empty():
		for q in (pales["v"] as PackedVector3Array):
			boite = boite.expand(q + pivot)
	var decalage := Vector3(-boite.get_center().x, -boite.position.y, -boite.get_center().z)
	var taille := boite.size
	var mesh := _maillage(pieces, decalage, materiau, nom)
	var chemin_mesh := dest.path_join("models/%s.res" % nom)
	ResourceSaver.save(mesh, chemin_mesh)
	var dims := [taille.x, taille.y, taille.z]
	dims.sort()
	var portee := clampf(sqrt(float(dims[2]) * float(dims[1])) * PORTEE_PAR_METRE, PORTEE_MIN, PORTEE_MAX)
	var noeud: Node3D = Node3D.new() if categorie == "outil" else StaticBody3D.new()
	noeud.name = nom
	noeud.set_meta("taille", taille)
	noeud.set_meta("echelle", echelle)
	noeud.set_meta("categorie", categorie)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = load(chemin_mesh)
	mi.visibility_range_end = portee
	noeud.add_child(mi)
	mi.owner = noeud
	var formes := 0
	var triangles_collision := 0
	if categorie == "fixe":
		var faces := PackedVector3Array()
		for p: Dictionary in pieces:
			var pv: PackedVector3Array = p["v"]
			for k in (p["i"] as PackedInt32Array):
				faces.append(pv[k] + decalage)
		var forme := ConcavePolygonShape3D.new()
		forme.set_faces(faces)
		forme.backface_collision = true
		var chemin_forme := dest.path_join("models/%s_collision.res" % nom)
		ResourceSaver.save(forme, chemin_forme)
		var cs := CollisionShape3D.new()
		cs.name = "Collision"
		cs.shape = load(chemin_forme)
		noeud.add_child(cs)
		cs.owner = noeud
		formes = 1
		triangles_collision = faces.size() / 3
	elif categorie == "mobile":
		for p: Dictionary in pieces:
			var pv: PackedVector3Array = p["v"]
			var bp := AABB(pv[0], Vector3.ZERO)
			for q in pv:
				bp = bp.expand(q)
			if maxf(bp.size.x, maxf(bp.size.y, bp.size.z)) < PIECE_MIN:
				continue
			var tmp := ArrayMesh.new()
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			var decale := PackedVector3Array()
			for q in pv:
				decale.append(q + decalage)
			arr[Mesh.ARRAY_VERTEX] = decale
			arr[Mesh.ARRAY_INDEX] = p["i"]
			tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var enveloppe := tmp.create_convex_shape(true, true)
			if enveloppe == null or enveloppe.points.size() < 4:
				continue
			var cs := CollisionShape3D.new()
			cs.name = "Collision" if formes == 0 else "Collision%d" % (formes + 1)
			cs.shape = enveloppe
			noeud.add_child(cs)
			cs.owner = noeud
			formes += 1
		if formes == 0:
			push_error("CONVERSION %s : aucune enveloppe convexe" % chemin)
			noeud.free()
			return false
	var tri_pales := 0
	if not pales.is_empty():
		var mp := _maillage([pales], Vector3.ZERO, materiau, nom + "_pales")
		var chemin_pales := dest.path_join("models/%s_pales.res" % nom)
		ResourceSaver.save(mp, chemin_pales)
		var mip := MeshInstance3D.new()
		mip.name = "Pales"
		mip.mesh = load(chemin_pales)
		mip.position = pivot + decalage
		mip.visibility_range_end = portee
		noeud.add_child(mip)
		mip.owner = noeud
		tri_pales = (pales["i"] as PackedInt32Array).size() / 3
	var scene := PackedScene.new()
	var err := scene.pack(noeud)
	noeud.free()
	if err != OK:
		push_error("CONVERSION %s : pack %d" % [chemin, err])
		return false
	var chemin_scene := dest.path_join("%s.tscn" % nom)
	ResourceSaver.save(scene, chemin_scene)
	var triangles := 0
	for p: Dictionary in pieces:
		triangles += (p["i"] as PackedInt32Array).size() / 3
	_bilan.append("PACK_MODELE %-38s x%-5.3f %-6s %6.2f x %6.2f x %6.2f m  %6d tri%s  %s  portee %4.0f m" % [
			chemin_scene.trim_prefix("res://assets/"), echelle, categorie, taille.x, taille.y, taille.z, triangles,
			(" + %d (pales)" % tri_pales) if tri_pales > 0 else "",
			("exacte %d tri" % triangles_collision) if categorie == "fixe" else (("%d enveloppe(s)" % formes) if categorie == "mobile" else "sans collision"),
			portee])
	return true
