extends RefCounted

# VERRE DES LAMPADAIRES (2026-09-21). La nuit, chaque luminaire portait un « halo » : une boîte non éclairée
# de 0,46 x 0,30 x 0,44 m posée autour de la tête. Vue de près elle débordait du capot en un gros hexagone
# jaune, plat, qui n'avait rien d'une lampe (photo du joueur). On allume maintenant LA GÉOMÉTRIE DE LA LAMPE
# ELLE-MÊME, son verre, exactement comme les optiques des véhicules : on extrait du modèle les triangles qui
# SONT le verre, repérés par la couleur qu'ils échantillonnent ET par leur position dans la tête, et on les
# redessine dans un sous-maillage fusionné sur UN matériau partagé, allumé la nuit.
#
# INVENTAIRE, relevé triangle par triangle sur les quatre modèles avant d'écrire une ligne (sonde jetable).
# Chacun n'a qu'un MeshInstance3D, à l'identité : repère du maillage = repère du modèle.
#  - carte, pack modular_roads, lamp_1 (une crosse) et lamp_2 (deux) : atlas 1024 x 1024. Le verre est une
#    PLAQUE HORIZONTALE sous la tête, 6 triangles par tête, face avant vers le BAS, qui échantillonnent deux
#    jaunes pâles de l'atlas, #efd094 et #efce94, à 6,134 m (lamp_1) et 6,051 m (lamp_2), de 0,47 x 0,26 m ;
#  - centre-ville, pack lowpoly_city, lamp_single et lamp_double : palette de 4 x 4 texels. Le verre est le
#    jaune #ffd800, un diffuseur de 16 triangles par tête sous la crosse : un fond à 6,116 m et quatre pans
#    inclinés jusqu'à 6,246 m, de 1,15 x 0,29 m, faces avant vers l'extérieur.
# Aucun autre triangle de ces couleurs dans ces modèles, et tous sont au-dessus de 6 m : le filtre de hauteur
# n'est qu'une garde, au cas où un modèle réutiliserait la couleur plus bas.
const VERRES := {
	"res://assets/modular_roads/lamp_1.glb": ["efd094", "efce94"],
	"res://assets/modular_roads/lamp_2.glb": ["efd094", "efce94"],
	"res://assets/lowpoly_city_pack/lighting/lamp_single.glb": ["ffd800"],
	"res://assets/lowpoly_city_pack/lighting/lamp_double.glb": ["ffd800"],
}
const TETE_Y_MIN := 5.0
# « L'INTÉRIEUR DE LA TÊTE » : sur les deux modèles de la carte, la plaque est en RETRAIT de 5,8 cm dans le
# capot (bas du capot à 6,076 m, plaque à 6,134 m pour lamp_1). Au-delà d'une trentaine de mètres, vue sous
# une dizaine de degrés, le rebord masque toute la plaque et le lampadaire paraît éteint. On allume donc aussi
# les PAROIS INTÉRIEURES du rebord, comme le réflecteur d'une vraie tête : relevées triangle par triangle,
# ~16 par tête, toutes de hauteur comprise entre le bas du capot et la plaque, sous l'emprise de la plaque
# et tournées vers son axe. La règle est de position, pas de couleur (le rebord a la couleur du capot).
# Le diffuseur du centre-ville dépasse sous la crosse, il se voit de côté : pas de rebord à y chercher.
const REBORD := ["res://assets/modular_roads/lamp_1.glb", "res://assets/modular_roads/lamp_2.glb"]
const REBORD_PROFONDEUR := 0.08      # m sous la plaque (le capot descend 5,8 cm plus bas)
const REBORD_MARGE := 0.06           # m autour de l'emprise de la plaque
const PLAQUE_RAYON := 0.5            # m : deux triangles de verre à moins de ça sont la même plaque
# Le verre allumé est une copie du verre du modèle, poussée de 6 mm vers l'extérieur de chaque face (le
# long de sa face avant) : elle passe devant l'original sans combat en z et ne déborde de rien.
const DECALAGE := 0.006

static var _cache := {}


# Triangles du verre d'un maillage de lampadaire (et des parois intérieures du rebord pour les modèles de
# REBORD), dans le repère du maillage : {"v", "n", "verre", "rebord"}, sommets par trois, dans l'ordre du
# modèle (même face avant), décalés de DECALAGE. `chemin` : le modèle, clé de VERRES.
static func verre(mesh: Mesh, chemin: String) -> Dictionary:
	var cle := "%d|%s" % [mesh.get_instance_id(), chemin]
	if _cache.has(cle):
		return _cache[cle]
	var couleurs: Array = VERRES.get(chemin, [])
	var plaques: Array = []              # [{"somme": Vector3, "n": int, "min": Vector3, "max": Vector3}]
	var candidats: Array = []            # triangles hors verre : [a, b, c]
	# tableaux LOCAUX : un PackedVector3Array est une valeur, `(out["v"] as PackedVector3Array).append()`
	# ajouterait dans une copie et laisserait le dictionnaire vide (payé à la première cuisson)
	var sv := PackedVector3Array()
	var sn := PackedVector3Array()
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s) as BaseMaterial3D
		if mat == null or mat.albedo_texture == null:
			continue
		var img: Image = mat.albedo_texture.get_image()
		if img == null:
			continue
		if img.is_compressed():
			img.decompress()
		var arr := mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vs.size()))
		if uvs.is_empty():
			continue
		for t in idx.size() / 3:
			var i0 := idx[t * 3]
			var i1 := idx[t * 3 + 1]
			var i2 := idx[t * 3 + 2]
			var uv := (uvs[i0] + uvs[i1] + uvs[i2]) / 3.0
			var col := img.get_pixel(clampi(int(uv.x * img.get_width()), 0, img.get_width() - 1),
					clampi(int(uv.y * img.get_height()), 0, img.get_height() - 1)).to_html(false)
			var a := vs[i0]
			var b := vs[i1]
			var c := vs[i2]
			if not col in couleurs:
				candidats.append([a, b, c])
				continue
			if (a.y + b.y + c.y) / 3.0 < TETE_Y_MIN:
				continue
			_ajouter_plaque(plaques, a, b, c)
			# face avant (Godot : sens horaire vu de face, donc la normale géométrique est -(b-a)x(c-a))
			var n := -((b - a).cross(c - a))
			if n.length_squared() < 1e-12:
				continue
			n = n.normalized()
			for p: Vector3 in [a, b, c]:
				sv.append(p + n * DECALAGE)
				sn.append(n)
	var nb_verre := sv.size() / 3
	if chemin in REBORD:
		for tri: Array in candidats:
			var n := _paroi_interieure(plaques, tri[0], tri[1], tri[2])
			if n == Vector3.ZERO:
				continue
			for p: Vector3 in tri:
				sv.append(p + n * DECALAGE)
				sn.append(n)
	var out := {"v": sv, "n": sn, "verre": nb_verre, "rebord": sv.size() / 3 - nb_verre}
	_cache[cle] = out
	return out


# Regroupe les triangles de verre en plaques (une par tête) : emprise et hauteur moyenne.
static func _ajouter_plaque(plaques: Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	var g := (a + b + c) / 3.0
	for pl: Dictionary in plaques:
		var centre: Vector3 = pl["somme"] / float(pl["n"])
		if Vector2(g.x - centre.x, g.z - centre.z).length() < PLAQUE_RAYON:
			pl["somme"] += g
			pl["n"] += 1
			for p: Vector3 in [a, b, c]:
				pl["min"] = (pl["min"] as Vector3).min(p)
				pl["max"] = (pl["max"] as Vector3).max(p)
			return
	plaques.append({"somme": g, "n": 1, "min": a.min(b).min(c), "max": a.max(b).max(c)})


# Face avant (normale) d'une paroi intérieure du rebord d'une plaque, Vector3.ZERO sinon : entièrement entre
# le dessous du capot et la plaque, sous l'emprise de la plaque, paroi (ni le fond ni le dessous du capot)
# tournée vers l'axe de la plaque.
static func _paroi_interieure(plaques: Array, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var n := -((b - a).cross(c - a))
	if n.length_squared() < 1e-12:
		return Vector3.ZERO
	n = n.normalized()
	if n.y <= -0.95 or n.y >= 0.5:
		return Vector3.ZERO
	var g := (a + b + c) / 3.0
	for pl: Dictionary in plaques:
		var bas: Vector3 = pl["min"]
		var haut: Vector3 = pl["max"]
		var y_plaque := (bas.y + haut.y) * 0.5
		if minf(a.y, minf(b.y, c.y)) < y_plaque - REBORD_PROFONDEUR or maxf(a.y, maxf(b.y, c.y)) > haut.y + 0.012:
			continue
		if g.x < bas.x - REBORD_MARGE or g.x > haut.x + REBORD_MARGE or g.z < bas.z - REBORD_MARGE or g.z > haut.z + REBORD_MARGE:
			continue
		var centre: Vector3 = pl["somme"] / float(pl["n"])
		if Vector2(n.x, n.z).dot(Vector2(centre.x - g.x, centre.z - g.z)) > 0.0:
			return n
	return Vector3.ZERO


# Maillage fusionné du verre de plusieurs lampadaires. `poses` = [[verre (cf. verre()), [Transform3D...]], ...]
# (transformations MONDE des lampadaires, rotations pures), sur le matériau partagé passé en paramètre.
# null si aucun verre.
static func maillage(poses: Array, materiau: Material) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	for pose: Array in poses:
		var src: Dictionary = pose[0]
		var sv: PackedVector3Array = src["v"]
		var sn: PackedVector3Array = src["n"]
		for t: Transform3D in pose[1]:
			for k in sv.size():
				v.append(t * sv[k])
				n.append((t.basis * sn[k]).normalized())
	if v.is_empty():
		return null
	var idx := PackedInt32Array()
	idx.resize(v.size())
	for k in v.size():
		idx[k] = k
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, materiau)
	return mesh
