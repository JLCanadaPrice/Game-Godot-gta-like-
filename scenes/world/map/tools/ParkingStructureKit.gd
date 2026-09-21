extends RefCounted

# PARKING À ÉTAGES (Business_ParkingStructure, pack EverythingLibrary) rendu praticable — chantier du 2026-09-21.
# Utilisé par DowntownBuildingsBake (3 exemplaires au centre-ville) et par PlacesBake (l'exemplaire de l'aéroport).
#
# Relevé sur les sommets du modèle avant d'écrire une ligne (repère du modèle : origine au niveau du sol, entrée
# côté +Z) :
#  - 5 plateaux praticables, dessus à 0,35 / 4,95 / 9,50 / 14,05 / 18,60 m. Chaque étage est UNE pièce de
#    28 triangles, dalle de 0,40 m et muret de rive de 1,93 m d'un seul tenant ; intérieur x -21,76..21,76,
#    z -9,75..9,80 ; le rez-de-chaussée (76 triangles) porte aussi la fondation, jusqu'à -2,43 m ;
#  - une rangée de 5 poteaux au milieu (z ±0,54 ; x = 0, ±10, ±16), des montants de façade, 4 tours d'angle pleines
#    et une tour arrière pleine ; au bout est (et ouest), deux montants découpent trois travées (z ±2,46..3,54) ;
#  - la « cage vitrée » est une tour (x ±5,52, z 7,48..11,87) que chaque plateau traverse : une pièce de 11 x 2,3 m
#    par niveau, fermée côté parking ; au rez-de-chaussée un passage de 7,7 m la traverse (l'entrée des voitures) ;
#  - les boîtiers des plafonniers sont dans base_072 ; light_006 ne contient que les cônes, écartés à la fusion
#    (BuildingModels.EXCLUS) ;
#  - enroulement des faces : convention de Godot (faces avant en sens horaire vues du côté de leur normale).

const MODELE := "Business_ParkingStructure"
const CLE := "el:" + MODELE


# Collision EXACTE du parking : les triangles du maillage fusionné — dalles, murets, poteaux, tours — au lieu de la
# boîte pleine qui en faisait un bloc sur lequel on ne marchait que sur le toit. Une collision de triangles n'a
# qu'un côté : chaque triangle est orienté comme Godot l'attend (enroulement horaire vu du côté de la normale de
# sommet), et l'on compte ceux qu'il a fallu retourner.
static func collision(mesh: Mesh) -> ConcavePolygonShape3D:
	var faces := PackedVector3Array()
	var retournes := 0
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		for t in range(0, idx.size() - 2, 3):
			var p0 := v[idx[t]]
			var p1 := v[idx[t + 1]]
			var p2 := v[idx[t + 2]]
			var nn := n[idx[t]] + n[idx[t + 1]] + n[idx[t + 2]]
			if (p1 - p0).cross(p2 - p0).dot(nn) > 0.0:
				faces.append(p0)
				faces.append(p2)
				faces.append(p1)
				retournes += 1
			else:
				faces.append(p0)
				faces.append(p1)
				faces.append(p2)
	var forme := ConcavePolygonShape3D.new()
	forme.set_faces(faces)
	# Deux faces : le modèle a des cloisons SANS ÉPAISSEUR (la face intérieure de la tour vitrée, z = 7,48, est un
	# seul plan) ; d'un seul côté, on la traverserait depuis la pièce de l'escalier.
	forme.backface_collision = true
	forme.set_meta("triangles", faces.size() / 3)
	forme.set_meta("retournes", retournes)
	return forme


# Dessus des plateaux praticables, relevés sur le maillage : surfaces horizontales tournées vers le haut de plus de
# 500 m² à une même hauteur (le plancher de chaque niveau en fait 851).
static func planchers(mesh: Mesh) -> PackedFloat32Array:
	var aires := {}
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		for t in range(0, idx.size() - 2, 3):
			var nn := (n[idx[t]] + n[idx[t + 1]] + n[idx[t + 2]]).normalized()
			if nn.y < 0.99:
				continue
			var p0 := v[idx[t]]
			var y := snappedf((p0.y + v[idx[t + 1]].y + v[idx[t + 2]].y) / 3.0, 0.01)
			aires[y] = float(aires.get(y, 0.0)) + (v[idx[t + 1]] - p0).cross(v[idx[t + 2]] - p0).length() * 0.5
	var out := PackedFloat32Array()
	for y in aires:
		if float(aires[y]) > 500.0:
			out.append(y)
	out.sort()
	return out
