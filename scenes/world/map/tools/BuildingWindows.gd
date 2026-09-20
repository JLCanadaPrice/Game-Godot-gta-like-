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
#    Mk3 n'a que des matériaux génériques (`Material.001` à `.003`). Son seul candidat sérieux,
#    `Material.002`, est 100 % vertical sur toute la hauteur — mais rendu en rouge le 2026-09-20 il
#    dessine un TREILLIS TRIANGULÉ sur toute la façade, pas un bandeau vitré. Confirmé non
#    séparable ; ne pas y revenir sans une nouvelle image. Scraper001 est une boîte de 28 triangles,
#    33 x 153 x 33 m, une seule surface `Material` : aucune fenêtre à allumer, et aucun atlas où en
#    chercher. Posé une seule fois sur la carte (core_002).
#  - Pack EverythingLibrary (carte ET centre-ville) : `Mat_ReflWindow` sur 111 modèles sur 215. Les
#    104 autres sont des granges, silos, phares et maisons du désert, sans vitrage à allumer.
#  - Pack lowpoly_city (71 bâtiments du centre-ville) : UNE seule surface `base_Material` sur un
#    atlas de palette. Première conclusion, le 2026-09-19 : « pas séparables ». ELLE ÉTAIT FAUSSE, et
#    corrigée le 2026-09-20. La palette fait 4 x 4 texels de couleurs plates, et chaque triangle en
#    vise un : les murs tombent sur #404040, les VITRAGES sur #68C0FF et #23A3FF, les encadrements
#    sur #808080. Vérifié en rendant trois bâtiments du pack en plein jour (murs gris foncé,
#    fenêtres bleues en grille sur les quatre façades), pas déduit d'un nom. D'où la deuxième règle
#    d'extraction : un triangle est un vitrage si son barycentre UV échantillonne une des couleurs
#    de vitrage de l'atlas. C'est la géométrie DU MODÈLE qu'on allume, au texel près.
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
# RÉGLABLE EN LIGNE DE COMMANDE : les cuiseurs acceptent --fraction=<0..1> et écrivent ici, ce qui
# permet de cuire la ville à plusieurs taux et de comparer les images depuis le même point de vue
# sans toucher au code. Le défaut est ce que la carte embarque.
const LIT_FRACTION := 0.28
static var fraction := LIT_FRACTION

# Décollement du carreau allumé devant la vitre, en m : sans lui les deux surfaces sont coplanaires
# et se battent en z. 2 cm ne se voit pas à hauteur d'homme et suffit à trancher.
const GLOW_OFFSET := 0.02

# Quantification de la position servant de graine, en m. Le tirage doit être STABLE d'une cuisson à
# l'autre : il ne dépend que de la position MONDE du carreau, arrondie à 2 cm, jamais d'un
# randomize() ni de l'ordre de parcours. Un bâtiment qui ne bouge pas garde donc exactement les
# mêmes fenêtres allumées, cuisson après cuisson et session après session.
const SEED_QUANTUM := 0.02

const MASK := 0xffffffff

# --- carreaux trop grands -------------------------------------------------------------------------
# Certains modèles ne vitrent pas façade par carreau : ils posent UN SEUL QUAD par façade, haut de
# 60 m. Mesuré le 2026-09-20 : Industrial_TraditionalSkyscraper_alt02, Industrial_ModernSkyscraper_
# alt06 et Industrial_WideOfficeBuilding_alt04 n'ont QUE 4 carreaux, un par façade. Le tirage à 28 %
# allumait donc une FAÇADE ENTIÈRE d'un coup, d'où le « une seule façade allumée » signalé.
#
# La réponse n'est pas de poser des rectangles par-dessus : c'est de re-mailler le vitrage DU MODÈLE
# au grain d'une fenêtre. Un quad plein est retaillé en grille dans SON PROPRE PLAN et sur SA PROPRE
# emprise — même surface, même position, juste découpée. On ne le fait QUE si le carreau est plan et
# qu'il est un rectangle plein (aire des triangles ≈ aire de sa boîte 2D), sinon on débordrait.
#
# ET UN CARREAU TROP GRAND QU'ON NE SAIT PAS RETAILLER N'EST PAS ALLUMÉ DU TOUT. Ce n'est pas une
# fenêtre, c'est un panneau de mur-rideau ou un pan de facette ; l'allumer entier fabriquait une
# NAPPE BLANCHE de plusieurs dizaines de mètres flottant entre les immeubles, vue à l'image sur le
# centre-ville de nuit le 2026-09-20. Mieux vaut un panneau éteint qu'une nappe.
const PANE_MAX := 4.0        # au-delà, en m, dans un sens ou dans l'autre : on retaille
const PANE_W := 2.6          # largeur d'une travée, m
const PANE_H := 3.2          # hauteur d'un étage, m
const PANE_MIN_AIRE := 0.05  # m² : en dessous, la rognure de bord de case ne se voit pas, on la jette
const PANE_MAX_CASES := 8192 # garde-fou : nombre de cases qu'un seul triangle peut recouvrir


# Carreaux d'un modèle, dans son repère : chacun est une soupe de triangles avec sa normale moyenne.
# `scene_root` est un .glb instancié ; `extra` permet d'ajouter des noms de matériaux au cas par cas.
# `atlas`, quand il est fourni, est {"image": Image, "couleurs": Array[String] en "#RRGGBB"} : les
# triangles dont le barycentre UV échantillonne une de ces couleurs sont du vitrage, quel que soit le
# nom du matériau. C'est ce qui rattrape les modèles à surface unique sur palette (pack lowpoly_city).
static func panes(scene_root: Node, extra: Array = [], atlas: Dictionary = {}) -> Array:
	var out: Array = []
	_walk(scene_root, Transform3D.IDENTITY, out, extra, atlas)
	return out


static func _walk(node: Node, parent: Transform3D, out: Array, extra: Array, atlas: Dictionary = {}) -> void:
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
			var arrays := mesh.surface_get_arrays(s)
			if is_window(mat.resource_name if mat != null else "", extra):
				_split(arrays, xform, out)
			elif not atlas.is_empty():
				var filtre := _by_atlas(arrays, atlas)
				if not filtre.is_empty():
					_split(filtre, xform, out)
	for c in node.get_children():
		_walk(c, xform, out, extra, atlas)


# Ne garde que les triangles dont le barycentre UV tombe sur une couleur de vitrage de l'atlas.
# Rend un jeu d'arrays au même format, ou vide si aucun triangle ne correspond.
static func _by_atlas(arrays: Array, atlas: Dictionary) -> Array:
	var img: Image = atlas.get("image")
	var couleurs: Array = atlas.get("couleurs", [])
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	if img == null or couleurs.is_empty() or uv.is_empty():
		return []
	var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		idx.resize(vs.size())
		for k in vs.size():
			idx[k] = k
	var w := img.get_width() - 1
	var h := img.get_height() - 1
	var gardes := PackedInt32Array()
	for t in idx.size() / 3:
		var a := idx[t * 3]
		var b := idx[t * 3 + 1]
		var c := idx[t * 3 + 2]
		if maxi(a, maxi(b, c)) >= uv.size():
			continue
		var mid := (uv[a] + uv[b] + uv[c]) / 3.0
		var col := img.get_pixel(clampi(roundi(mid.x * w), 0, w), clampi(roundi(mid.y * h), 0, h))
		if not couleurs.has("#%02X%02X%02X" % [roundi(col.r * 255.0), roundi(col.g * 255.0), roundi(col.b * 255.0)]):
			continue
		gardes.append_array([a, b, c])
	if gardes.is_empty():
		return []
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = vs
	if not ns.is_empty():
		out[Mesh.ARRAY_NORMAL] = ns
	out[Mesh.ARRAY_INDEX] = gardes
	return out


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
		_emettre(tris, normale.normalized(), out)


# Ajoute un carreau. S'il couvre plus qu'une fenêtre, il est SUBDIVISÉ jusqu'au grain d'une travée.
#
# La première réponse, le 2026-09-20 au matin, était de retailler le carreau en grille sur sa boîte
# 2D, et de ne PAS l'allumer quand ce n'était pas possible (carreau non plan, ou qui ne remplit pas
# sa boîte). Ça marchait sur un quad de façade bien carré et ça ÉTEIGNAIT tout le reste : un modèle
# est tombé de 42 carreaux à 6, et des tours entières se sont retrouvées sans lumière d'un côté.
#
# La bonne réponse ne fabrique aucune géométrie nouvelle : on DÉCOUPE LES TRIANGLES DU MODÈLE sur la
# GRILLE DE TRAVÉES elle-même. Chaque triangle est rogné (Sutherland-Hodgman) contre les quatre plans
# de la case PANE_W x PANE_H qu'il recouvre, case par case ; le morceau gardé est re-triangulé. Une
# case = un carreau. Aucune contrainte de planéité — les plans de coupe sont ceux de la grille, pas
# celui du carreau — et aucun débordement, puisqu'on ne fait que redécouper ce qui existe.
#
# CE QUI A ÉTÉ ESSAYÉ ET REJETÉ PAR L'IMAGE, le 2026-09-21 : couper chaque triangle au milieu de son
# plus long côté jusqu'au grain d'une travée, puis ranger chaque morceau dans la case de son
# BARYCENTRE. Les comptes étaient bons et la carte s'allumait, mais un morceau dont le barycentre
# tombe dans une case déborde dans la voisine : au sol, devant une tour à mur-rideau, les fenêtres
# allumées sortaient en TACHES IRRÉGULIÈRES — des L, des drapeaux, des découpes en dents de scie —
# au lieu d'une grille. Vu à l'image, jamais dans un compteur. Le rognage exact coûte quelques
# triangles de plus et rend des rectangles.
# Point d'entree public du decoupage : sert aux vitrages dessines a la main (lieux batis en
# primitives), qui n'ont pas de modele a extraire mais doivent etre decoupes au meme grain.
static func decouper(tris: PackedVector3Array, n: Vector3, out: Array) -> void:
	_emettre(tris, n, out)


static func _emettre(tris: PackedVector3Array, n: Vector3, out: Array) -> void:
	var droite := Vector3.UP.cross(n)
	if droite.length_squared() < 1e-9:
		out.append({"tris": tris, "n": n})
		return
	droite = droite.normalized()
	var haut := n.cross(droite).normalized()
	var o := tris[0]
	var umin := 1e30
	var umax := -1e30
	var vmin := 1e30
	var vmax := -1e30
	for p in tris:
		var d := p - o
		var u := d.dot(droite)
		var v := d.dot(haut)
		umin = minf(umin, u); umax = maxf(umax, u)
		vmin = minf(vmin, v); vmax = maxf(vmax, v)
	if umax - umin <= PANE_MAX and vmax - vmin <= PANE_MAX:
		out.append({"tris": tris, "n": n})
		return
	# Rognage exact sur la grille : chaque triangle contre chaque case qu'il recouvre.
	var cases := {}
	for t in tris.size() / 3:
		var a := tris[t * 3]
		var b := tris[t * 3 + 1]
		var c := tris[t * 3 + 2]
		var ua := (a - o).dot(droite); var ub := (b - o).dot(droite); var uc := (c - o).dot(droite)
		var va := (a - o).dot(haut); var vb := (b - o).dot(haut); var vc := (c - o).dot(haut)
		var i0 := floori(minf(ua, minf(ub, uc)) / PANE_W)
		var i1 := floori(maxf(ua, maxf(ub, uc)) / PANE_W)
		var j0 := floori(minf(va, minf(vb, vc)) / PANE_H)
		var j1 := floori(maxf(va, maxf(vb, vc)) / PANE_H)
		if (i1 - i0 + 1) * (j1 - j0 + 1) > PANE_MAX_CASES:
			continue
		for i in range(i0, i1 + 1):
			for j in range(j0, j1 + 1):
				var poly := PackedVector3Array([a, b, c])
				poly = _demi(poly, droite, o, float(i) * PANE_W, true)
				poly = _demi(poly, droite, o, float(i + 1) * PANE_W, false)
				poly = _demi(poly, haut, o, float(j) * PANE_H, true)
				poly = _demi(poly, haut, o, float(j + 1) * PANE_H, false)
				if poly.size() < 3:
					continue
				var aire := 0.0
				for k in range(1, poly.size() - 1):
					aire += (poly[k] - poly[0]).cross(poly[k + 1] - poly[0]).length() * 0.5
				if aire < PANE_MIN_AIRE:
					continue
				var cle := "%d|%d" % [i, j]
				var acc: PackedVector3Array = cases[cle] if cases.has(cle) else PackedVector3Array()
				for k in range(1, poly.size() - 1):
					acc.append(poly[0])
					acc.append(poly[k])
					acc.append(poly[k + 1])
				cases[cle] = acc
	for cle in cases:
		out.append({"tris": cases[cle], "n": n})


# Rogne un polygone CONVEXE par un demi-espace de la grille de travées : garde ce qui est au-delà du
# seuil le long de `axe` (`sup`), ou en deçà. Sutherland-Hodgman, mené en 3D — les plans de coupe
# sont ceux de la grille, verticaux et parallèles entre eux, donc un carreau non plan (un vitrage qui
# enjambe l'angle d'un immeuble) se rogne aussi bien qu'un quad plat.
static func _demi(poly: PackedVector3Array, axe: Vector3, o: Vector3, seuil: float, sup: bool) -> PackedVector3Array:
	var out := PackedVector3Array()
	var m := poly.size()
	if m < 3:
		return out
	var sens := 1.0 if sup else -1.0
	for i in m:
		var p := poly[i]
		var q := poly[(i + 1) % m]
		var dp := ((p - o).dot(axe) - seuil) * sens
		var dq := ((q - o).dot(axe) - seuil) * sens
		if dp >= 0.0:
			out.append(p)
		if (dp >= 0.0) != (dq >= 0.0):
			out.append(p.lerp(q, dp / (dp - dq)))
	return out


static func _find(parent: PackedInt32Array, a: int) -> int:
	while parent[a] != a:
		parent[a] = parent[parent[a]]
		a = parent[a]
	return a


# Le tirage stable. Mélangeur entier (murmur3 fmix32) sur la position monde quantifiée : aucune
# dépendance à l'ordre de parcours, au compteur d'objets ni à une graine globale, donc le même
# carreau retombe toujours du même côté. Voir SEED_QUANTUM.
static func lit(centre: Vector3, part := -1.0) -> bool:
	return float(cle(centre) % 100000) < (fraction if part < 0.0 else part) * 100000.0


# La clé de tirage d'un carreau : c'est elle qu'on compare au seuil, et c'est elle qui sert à
# désigner LE carreau à allumer quand un bâtiment n'en a aucun (cf. emit).
static func cle(centre: Vector3) -> int:
	var a := _mix(roundi(centre.x / SEED_QUANTUM))
	var b := _mix(roundi(centre.y / SEED_QUANTUM) ^ 0x9e3779b9)
	var c := _mix(roundi(centre.z / SEED_QUANTUM) ^ 0x85ebca6b)
	return _mix(a ^ b ^ c)


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
# AU MOINS UNE FENÊTRE ALLUMÉE par bâtiment qui a des carreaux. Sans cette garantie, une maison de
# 7 carreaux a 0,72^7 = 10 % de chances de ressortir entièrement noire : sur la carte, 41 maisons
# l'étaient, et c'était la cause n°1 des bâtiments éteints du recensement du 2026-09-20. Une maison
# habitée a une lumière quelque part. Le carreau choisi est celui de clé maximale : c'est stable
# d'une cuisson à l'autre, comme tout le reste du tirage.
static func emit(panes_of_model: Array, xform: Transform3D, verts: PackedVector3Array,
		normals: PackedVector3Array, indices: PackedInt32Array, part := -1.0) -> int:
	var nb := xform.basis.inverse().transposed()
	var allumes := 0
	var meilleur := -1
	var meilleure_cle := -1
	for i in panes_of_model.size():
		var centre := center(panes_of_model[i], xform)
		var k := cle(centre)
		if k > meilleure_cle:
			meilleure_cle = k
			meilleur = i
		if not lit(centre, part):
			continue
		allumes += 1
		_poser(panes_of_model[i], xform, nb, verts, normals, indices)
	if allumes == 0 and meilleur >= 0:
		_poser(panes_of_model[meilleur], xform, nb, verts, normals, indices)
		allumes = 1
	return allumes


static func _poser(pane: Dictionary, xform: Transform3D, nb: Basis, verts: PackedVector3Array,
		normals: PackedVector3Array, indices: PackedInt32Array) -> void:
	var n: Vector3 = (nb * (pane["n"] as Vector3)).normalized()
	var tris: PackedVector3Array = pane["tris"]
	var base := verts.size()
	for p in tris:
		verts.append(xform * p + n * GLOW_OFFSET)
		normals.append(n)
	for k in tris.size():
		indices.append(base + k)


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
