extends RefCounted
class_name VehicleLightParts

# Découpe des OPTIQUES d'un modèle de véhicule : phares, feux arrière, gyrophare. On n'ajoute rien
# au modèle — on en extrait les triangles qui sont DÉJÀ les optiques, pour pouvoir les rendre
# émissifs sans toucher au reste de la carrosserie.
#
# CE QUI A ÉTÉ MESURÉ LE 2026-09-20, avant d'écrire une ligne :
#
#  - la famille city_* (65 modèles sur 72, toute la circulation) est une caisse et quatre roues
#    partageant UN SEUL matériau sur un atlas de palette. Les optiques y sont bien modélisées : ce
#    sont des triangles qui échantillonnent des pastilles précises de la palette — verre bleu pâle
#    #cfeaf3 pour les phares, rouge sombre #782225 pour les feux et les gyrophares, ambre #c47a4d
#    pour les clignotants ;
#  - AUCUN masque d'émission n'est livré avec ces packs, contrairement au pack de feux tricolores ;
#  - et surtout, UN MASQUE EN ESPACE TEXTURE EST IMPOSSIBLE ICI. Les phares de la berline tombent sur
#    les texels (997-1010, 487-495) ; la lunette arrière de la voiture de police tombe sur
#    (997-1002, 486-528). Ce sont les MÊMES texels : le verre est du verre, la palette ne distingue
#    pas une vitre d'un optique. Idem pour le rouge, partagé entre feux arrière et gyrophare.
#
# D'où la règle de tri : COULEUR **ET** POSITION. La couleur seule allumerait les vitres avec les
# phares. La position seule allumerait la tôle avec l'optique. Les deux ensemble lèvent l'ambiguïté,
# et c'est vérifié modèle par modèle avant d'être appliqué au catalogue.
#
# L'avant d'un modèle est son **+Z** : le catalogue applique model_yaw_deg = 180 pour le retourner
# vers l'avant du véhicule, donc le nez natif est du côté +Z.

# Fenêtres de tri, en fractions de l'emprise de la caisse (roues exclues).
const PHARE_Z := 0.88           # au-delà : la face avant
const FEU_Z := 0.12             # en deçà : la face arrière
const OPTIQUE_Y_MIN := 0.18     # au-dessus du bas de caisse : écarte le bas de pare-chocs
const OPTIQUE_Y_MAX := 0.62     # sous la ceinture de caisse : écarte pare-brise et lunette
const OPTIQUE_FLANC := 0.30     # écarté de l'axe : écarte plaque et calandre centrale
const GYRO_Y := 0.78            # hauteur de toit : c'est ce qui sépare le gyrophare des feux

# Les clignotants ambre sont RECONNUS mais volontairement PAS extraits comme optique allumable : il
# n'y a pas de système d'indicateurs dans le jeu, un clignotant allumé en permanence serait faux.
# L'ambre reste légitime sur un gyrophare, et il y est accepté.


# COULEURS D'OPTIQUE, relevées sur l'atlas le 2026-09-20 en histogrammant ce qui tombe dans chaque
# fenêtre de position sur les 72 modèles. Une liste exacte, pas un test de ratio : la palette est
# faite d'aplats, donc l'échantillon rend exactement la couleur de la pastille, et une liste ne
# confond rien.
#
# Un test de ratio a été essayé d'abord et REJETÉ par la vérification, qui est bien pour ça :
#   - « clair et bleuté » attrapait la carrosserie blanche #cccdc8 : la voiture de police sortait
#     avec 46 triangles de phare au lieu de 8, jusque sur l'axe de la calandre ;
#   - « rouge franc » attrapait la bande de livrée #ad3e2a de l'ambulance et lui allumait le flanc.
# Ces deux couleurs sont donc explicitement absentes des listes ci-dessous.
const COULEUR_PHARE := ["cfeaf3"]                        # verre d'optique clair
const COULEUR_FEU := ["782225"]                          # rouge de feu arrière (PAS #ad3e2a, livrée)
const COULEUR_GYRO := ["782225", "eba335", "cfeaf3"]     # rouge, ambre, lentille claire du bandeau


static func _est(col: Color, liste: Array) -> bool:
	return col.to_html(false) in liste


# Emprise de la CAISSE d'un modèle instancié, roues exclues, dans le repère de sa racine, et la
# liste des maillages avec leur transformation relative. Les roues sont exclues parce qu'elles
# débordent en bas et fausseraient toutes les fractions de hauteur.
static func caisse(racine: Node) -> Dictionary:
	var boite := AABB()
	var premier := true
	var corps: Array = []
	for mi_n in racine.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_n as MeshInstance3D
		if mi.mesh == null or String(mi.name).begins_with("Wheel"):
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != racine:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		corps.append([mi, xf])
		var b: AABB = xf * mi.mesh.get_aabb()
		boite = b if premier else boite.merge(b)
		premier = false
	return {"aabb": boite, "corps": corps}


# Extrait les optiques d'un modèle instancié. `avec_gyro` n'est vrai que pour les véhicules dont le
# rôle en porte un : sur une voiture civile, la peinture sombre du toit passerait le test de
# couleur et on allumerait un toit.
#
# Rend {"phares": [triangles], "feux": [...], "gyro": [...]} en coordonnées du MODÈLE, chaque entrée
# étant un PackedVector3Array de sommets par paquets de 3, plus les normales correspondantes.
static func extraire(racine: Node, avec_gyro: bool) -> Dictionary:
	var info := caisse(racine)
	var boite: AABB = info["aabb"]
	var out := {
		"phares": {"v": PackedVector3Array(), "n": PackedVector3Array()},
		"feux": {"v": PackedVector3Array(), "n": PackedVector3Array()},
		"gyro": {"v": PackedVector3Array(), "n": PackedVector3Array()},
	}
	if boite.size.z <= 0.0 or boite.size.y <= 0.0 or boite.size.x <= 0.0:
		return out
	for e in info["corps"]:
		var mi: MeshInstance3D = e[0]
		var xf: Transform3D = e[1]
		var nb := xf.basis.inverse().transposed()
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null or mat.albedo_texture == null:
				continue
			var img: Image = mat.albedo_texture.get_image()
			if img == null:
				continue
			img.decompress()
			var arr := mi.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if vs.is_empty() or uvs.is_empty() or idx.is_empty():
				continue
			for t in idx.size() / 3:
				var i0 := idx[t * 3]
				var i1 := idx[t * 3 + 1]
				var i2 := idx[t * 3 + 2]
				var a: Vector3 = xf * vs[i0]
				var b: Vector3 = xf * vs[i1]
				var c: Vector3 = xf * vs[i2]
				var ctr := (a + b + c) / 3.0
				var uv := (uvs[i0] + uvs[i1] + uvs[i2]) / 3.0
				var col := img.get_pixel(
						clampi(int(uv.x * img.get_width()), 0, img.get_width() - 1),
						clampi(int(uv.y * img.get_height()), 0, img.get_height() - 1))
				var fz := (ctr.z - boite.position.z) / boite.size.z
				var fy := (ctr.y - boite.position.y) / boite.size.y
				var fx := absf(ctr.x - boite.get_center().x) / (boite.size.x * 0.5)
				var famille := ""
				if avec_gyro and fy > GYRO_Y and _est(col, COULEUR_GYRO):
					famille = "gyro"
				elif fy > OPTIQUE_Y_MIN and fy < OPTIQUE_Y_MAX and fx > OPTIQUE_FLANC:
					if fz > PHARE_Z and _est(col, COULEUR_PHARE):
						famille = "phares"
					elif fz < FEU_Z and _est(col, COULEUR_FEU):
						famille = "feux"
				if famille == "":
					continue
				var d: Dictionary = out[famille]
				var v: PackedVector3Array = d["v"]
				var nn: PackedVector3Array = d["n"]
				for k in [i0, i1, i2]:
					v.append(xf * vs[k])
					nn.append((nb * (ns[k] if k < ns.size() else Vector3.UP)).normalized())
				d["v"] = v
				d["n"] = nn
	return out


# Maillage d'une famille d'optiques, sur le matériau PARTAGÉ passé en paramètre. Rend null si la
# famille est vide, pour qu'un modèle sans phare ne fabrique pas un maillage de zéro triangle.
static func maillage(part: Dictionary, materiau: Material) -> ArrayMesh:
	var v: PackedVector3Array = part["v"]
	if v.is_empty():
		return null
	var idx := PackedInt32Array()
	idx.resize(v.size())
	for k in v.size():
		idx[k] = k
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = part["n"]
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.surface_set_material(0, materiau)
	return m
