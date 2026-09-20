extends RefCounted
class_name BuildingWindows

# Fenêtres allumées la nuit (chantier jour/nuit). Outil partagé par les deux cuissons de bâtiments :
# DowntownBuildingsBake (centre-ville) et DistrictsBake via BuildingModels (les 1 196 de la carte).
#
# CE QUI A ÉTÉ MESURÉ SUR LES MODÈLES, le 2026-09-19, avant de choisir la méthode :
#
#  - Gratte-ciels (`assets/skyscraper_bundle`) : les vitrages sont des SURFACES SÉPARÉES portant
#    leur propre matériau — `LightWindow` / `DarkWindow` sur Mk1, Mk4, Mk5, Mk6, `LightGlass` sur
#    Mk2. « Light » et « Dark » désignent la teinte du verre dans l'atlas, pas allumé/éteint.
#    Mk3 n'a que des matériaux génériques (`Material.001` à `.003`) dont les UV mêlent la bande
#    blanche et la zone vitrée de l'atlas : rien ne permet d'isoler ses fenêtres à coup sûr, il est
#    donc laissé de côté. Scraper001 est une boîte de 28 triangles, sans fenêtre du tout.
#  - Pack EverythingLibrary (carte ET centre-ville) : `Mat_ReflWindow` sur 111 modèles sur 215. Les
#    104 autres sont des granges, silos, phares et maisons du désert, sans vitrage à allumer.
#  - Pack lowpoly_city (71 bâtiments du centre-ville) : UNE seule surface `base_Material` sur un
#    atlas de palette. Les fenêtres n'y sont pas séparables, ces bâtiments restent éteints.
#
# D'où la règle : une surface est un vitrage si le nom de son matériau contient « window » ou
# « glass ». C'est une donnée du modèle, pas un nom de fichier ; et c'est la seule qui distingue le
# vitrage du reste sur ces packs.
#
# CHAQUE VITRAGE SE DÉCOUPE EN PANNEAUX : les triangles d'une surface de fenêtre forment des groupes
# connexes par sommets partagés, et ces groupes sont les carreaux — 900 sur Mk1, 1 800 sur Mk4,
# 1 100 sur Mk6, presque tous de 2 triangles (mesuré). C'est le grain auquel on allume : un carreau
# entier, jamais un demi-carreau.

const WINDOW_WORDS := ["window", "glass"]
const GLOW_MATERIAL := "res://scenes/world/window_glow_material.tres"

# Part des carreaux allumés. Ni trop (un immeuble entièrement allumé fait faux), ni trop peu.
const LIT_FRACTION := 0.28

# Décollement du carreau allumé devant la vitre, en m : sans lui les deux surfaces sont coplanaires
# et se battent en z. 2 cm ne se voit pas à hauteur d'homme et suffit à trancher.
const GLOW_OFFSET := 0.02

# Quantification de la position servant de graine, en m. Le tirage doit être STABLE d'une cuisson à
# l'autre : il ne dépend que de la position MONDE du carreau, arrondie à 2 cm, jamais d'un
# randomize() ni de l'ordre de parcours. Un bâtiment qui ne bouge pas garde donc exactement les
# mêmes fenêtres allumées, cuisson après cuisson et session après session.
const SEED_QUANTUM := 0.02

const MASK := 0xffffffff


# Carreaux d'un modèle, dans son repère : chacun est une soupe de triangles avec sa normale moyenne.
# `scene_root` est un .glb instancié ; `extra` permet d'ajouter des noms de matériaux au cas par cas.
static func panes(scene_root: Node, extra: Array = []) -> Array:
	var out: Array = []
	_walk(scene_root, Transform3D.IDENTITY, out, extra)
	return out


static func _walk(node: Node, parent: Transform3D, out: Array, extra: Array) -> void:
	var xform := parent
	if node is Node3D:
		xform = parent * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		for s in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var mat := mesh.surface_get_material(s)
			if not is_window(mat.resource_name if mat != null else "", extra):
				continue
			_split(mesh.surface_get_arrays(s), xform, out)
	for c in node.get_children():
		_walk(c, xform, out, extra)


static func is_window(nom: String, extra: Array = []) -> bool:
	var low := nom.to_lower()
	for w in WINDOW_WORDS:
		if low.contains(w):
			return true
	for w in extra:
		if low == String(w).to_lower():
			return true
	return false


# Découpe une surface vitrée en carreaux : composantes connexes par sommets partagés (union-find).
static func _split(arrays: Array, xform: Transform3D, out: Array) -> void:
	var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if vs.is_empty():
		return
	if idx.is_empty():
		idx.resize(vs.size())
		for k in vs.size():
			idx[k] = k
	var parent := PackedInt32Array()
	parent.resize(vs.size())
	for k in vs.size():
		parent[k] = k
	for t in idx.size() / 3:
		var a := _find(parent, idx[t * 3])
		var b := _find(parent, idx[t * 3 + 1])
		var c := _find(parent, idx[t * 3 + 2])
		if a != b:
			parent[b] = a
		if a != c:
			parent[c] = a
	var groupes := {}
	for t in idx.size() / 3:
		var r := _find(parent, idx[t * 3])
		if not groupes.has(r):
			groupes[r] = []
		groupes[r].append(t)
	var nb := xform.basis.inverse().transposed()
	for r in groupes:
		var tris := PackedVector3Array()
		var normale := Vector3.ZERO
		for t: int in groupes[r]:
			for j in 3:
				tris.append(xform * vs[idx[t * 3 + j]])
				if idx[t * 3 + j] < ns.size():
					normale += nb * ns[idx[t * 3 + j]]
		if normale.length_squared() < 1e-12:
			# pas de normale utilisable : on la reconstruit sur le premier triangle
			normale = (tris[1] - tris[0]).cross(tris[2] - tris[0])
		if normale.length_squared() < 1e-12:
			continue
		out.append({"tris": tris, "n": normale.normalized()})


static func _find(parent: PackedInt32Array, a: int) -> int:
	while parent[a] != a:
		parent[a] = parent[parent[a]]
		a = parent[a]
	return a


# Le tirage stable. Mélangeur entier (murmur3 fmix32) sur la position monde quantifiée : aucune
# dépendance à l'ordre de parcours, au compteur d'objets ni à une graine globale, donc le même
# carreau retombe toujours du même côté. Voir SEED_QUANTUM.
static func lit(centre: Vector3, fraction := LIT_FRACTION) -> bool:
	var a := _mix(roundi(centre.x / SEED_QUANTUM))
	var b := _mix(roundi(centre.y / SEED_QUANTUM) ^ 0x9e3779b9)
	var c := _mix(roundi(centre.z / SEED_QUANTUM) ^ 0x85ebca6b)
	return float(_mix(a ^ b ^ c) % 100000) < fraction * 100000.0


static func _mix(v: int) -> int:
	var x := v & MASK
	x = ((x ^ (x >> 16)) * 0x7feb352d) & MASK
	x = ((x ^ (x >> 15)) * 0x846ca68b) & MASK
	return (x ^ (x >> 16)) & MASK


# Centre d'un carreau, en monde, une fois le bâtiment posé.
static func center(pane: Dictionary, xform: Transform3D) -> Vector3:
	var tris: PackedVector3Array = pane["tris"]
	var s := Vector3.ZERO
	for p in tris:
		s += p
	return xform * (s / float(tris.size()))


# Ajoute à `verts`/`normals`/`indices` les carreaux allumés d'un bâtiment posé en `xform`.
# Retourne le nombre de carreaux allumés. Les carreaux sont décollés de GLOW_OFFSET devant la vitre.
static func emit(panes_of_model: Array, xform: Transform3D, verts: PackedVector3Array,
		normals: PackedVector3Array, indices: PackedInt32Array, fraction := LIT_FRACTION) -> int:
	var nb := xform.basis.inverse().transposed()
	var allumes := 0
	for pane: Dictionary in panes_of_model:
		if not lit(center(pane, xform), fraction):
			continue
		allumes += 1
		var n: Vector3 = (nb * (pane["n"] as Vector3)).normalized()
		var tris: PackedVector3Array = pane["tris"]
		var base := verts.size()
		for p in tris:
			verts.append(xform * p + n * GLOW_OFFSET)
			normals.append(n)
		for k in tris.size():
			indices.append(base + k)
	return allumes


# Maillage d'une cellule : une seule surface, le matériau PARTAGÉ, donc un appel de dessin.
static func build_mesh(verts: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, load(GLOW_MATERIAL))
	return mesh
