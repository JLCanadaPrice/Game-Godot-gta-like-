extends SceneTree

# Chantier centre-ville, étape D3 : bâtiments du centre-ville reconstruit (generated/Buildings.tscn), posés sur les îlots
# du plan (DowntownLayout) selon leur zone :
#  - cœur : un gratte-ciel du SkyScraperBundle par îlot, les plus hauts au plus près du croisement Main Street × Central
#    Boulevard, adossé à l'angle des grandes rues (le reste de l'îlot : parvis) ; Lincoln Plaza : la tour-lame Mk3 ;
#  - immeubles moyens et bas : lots en bande le long des rues (côtés nord et sud de l'îlot, ou côtés de la ruelle),
#    modèles tirés dans un panier par zone (tours et bureaux EverythingLibrary près du cœur, bâtiments empilés du
#    low_Poly_City_Pack, lofts ; commerces, maisons de ville, entrepôts en périphérie), façade vers la rue ;
#  - place (Founders Plaza) : kiosque à musique au centre ; îlot civique : église ; îlots des boutiques : emprise des
#    boutiques et une marge laissées libres ; îlot du casino : emprise du lieu (MapSpec.POIS, bâti par PlacesBake) libre.
# Un seul matériau par famille de modèles (couleurs de sommet EverythingLibrary partagées avec la carte, palette du
# pack urbain, façades des gratte-ciels), maillages à niveaux de détail ; collision en boîte ; boîte d'occultation
# rentrée dans le volume plein du bâtiment, descendue au plus près du sol, vérifiée par rayons sur le maillage du modèle
# (cf. _checked_occluders).
# Tirages déterministes (graine fixe).
#
# Lancer : Godot --headless --path <projet> --script res://scenes/world/downtown/tools/DowntownBuildingsBake.gd

const Layout := preload("res://scenes/world/downtown/DowntownLayout.gd")
const Spec := preload("res://scenes/world/downtown/DowntownSpec.gd")
const MapSpec := preload("res://scenes/world/map/MapSpec.gd")
const ELModels := preload("res://scenes/world/map/tools/BuildingModels.gd")
const Windows := preload("res://scenes/world/map/tools/BuildingWindows.gd")

const OUT := "res://scenes/world/downtown/generated"
const MODELS := OUT + "/buildings"
const SKY_JSON := "res://assets/skyscraper_bundle/models.json"
const PACK_JSON := "res://assets/lowpoly_city_pack/models.json"
const WALK_Y := Spec.ROAD_TOP + Spec.SIDEWALK_RISE
const SEED := 20260917
const CORE_CENTER := Vector2(-532, -172)
const LOT_DEPTH_MAX := 26.0
const GAP_MAX := 1.5
const SHOP_MARGIN := 3.0
# gratte-ciels : haut de la boîte d'occultation le plus haut essayé, en fraction de la hauteur (sous les retraits, flèches
# et jardins, relevé à la main ; vérifié par rayons comme les autres, cf. _checked_occluders)
# Scraper001 n'est plus pose (cf. SKY_ORDER) : son entree reste pour que le modele redevienne
# utilisable sans re-mesurer, mais elle n'est plus lue.
const SKY_OCCLUDER := {"Mk1": 0.42, "Mk2": 0.55, "Mk3": 0.9, "Mk4": 0.9, "Mk5": 0.78, "Mk6": 0.88, "Scraper001": 0.95}
# Scraper001 A ETE RETIRE le 2026-09-20 et remplace par un SECOND Mk6.
#
# Pourquoi : Scraper001 est une boite de 28 triangles, une seule surface, sans aucune fenetre
# modelisee et sans atlas ou en chercher. Il restait donc NOIR toutes les nuits, au milieu du
# coeur, a 153 m de haut. Mk6 est le remplacant exact : 33,0 x 33,0 m d'emprise contre 33,0 x
# 33,0, et 152,3 m de haut contre 153,0 — la silhouette du centre-ville ne bouge pas — et il
# porte un VRAI vitrage (surfaces LightWindow et DarkWindow), donc ses fenetres s'allument.
#
# Mk6 est donc pose DEUX FOIS. C'est assume : deux tours jumelles dans un coeur de ville est
# une situation banale, et c'etait le seul choix qui garde l'emprise et la hauteur. Les cinq
# autres Mk sont deja utilises une fois chacun (Mk3 par _lincoln), et Mk3 est le seul qui n'ait
# pas de vitrage separable — le reprendre aurait refait le probleme qu'on corrige.
#
# `towers.erase(name)` ne retire que la PREMIERE occurrence : la seconde reste disponible pour
# le bloc suivant, ce qui est exactement le comportement voulu.
const SKY_ORDER := ["Mk1", "Mk2", "Mk6", "Mk6", "Mk4", "Mk5"]

# Fenêtres allumées la nuit, et jusqu'où elles portent. La question mérite d'être posée : au-delà de
# 650 m DowntownHLOD remplace chaque bâtiment par une boîte de silhouette, et si les fenêtres
# s'arrêtaient là, la ville serait noire de loin alors qu'elle est éclairée de près.
#
# ESSAYÉ ET MESURÉ le 2026-09-19, depuis les collines du nord-ouest à 1,1 km : porter les carreaux
# des bâtiments ORDINAIRES jusqu'à 4 000 m coûte 23 appels de dessin de plus (513 -> 536) et ne
# change RIEN à l'image. La raison se lit sur la vue de jour : à cette distance le bas de la ville
# est un tapis de boîtes qui se masquent les unes les autres, et seules les tours dépassent. Les
# carreaux du bas sont donc payés sans être vus. Ils s'arrêtent à la bascule HLOD.
#
# Les GRATTE-CIELS, eux, sont marqués no_hlod : ils gardent leur maillage à toute distance, ce sont
# eux qu'on voit du bout de la carte, et ce sont eux qui doivent porter la skyline. D'où deux
# portées, et pas une.
const WINDOW_GLOW_RANGE := 650.0
const WINDOW_GLOW_RANGE_SKY := 4000.0
const WINDOW_CELL := 160.0            # côté de la cellule de fusion, aligné sur chunk_size de DowntownHLOD
# paniers par zone : [modèle, poids] ; "el:" EverythingLibrary, "pack:" low_Poly_City_Pack (xN : étages empilés)
const POOLS := {
	"core_fill": [["el:Industrial_ModernSkyscraper_alt01", 1], ["el:Industrial_ModernSkyscraper_alt03", 1], ["el:Industrial_ModernSkyscraper_alt05", 1],
			["el:Industrial_ModernSkyscraper_alt07", 1], ["el:Industrial_TraditionalSkyscraper_alt01", 1], ["el:Industrial_TraditionalSkyscraper_alt05", 1]],
	"midrise_near": [["el:Industrial_ModernSkyscraper_alt02", 2], ["el:Industrial_ModernSkyscraper_alt04", 2], ["el:Industrial_ModernSkyscraper_alt06", 2],
			["el:Industrial_TraditionalSkyscraper_alt02", 2], ["el:Industrial_TraditionalSkyscraper_alt03", 2], ["el:Industrial_TraditionalSkyscraper_alt04", 2],
			["el:Industrial_TraditionalSkyscraper_alt06", 2], ["el:Industrial_TraditionalSkyscraper_alt07", 2], ["el:Industrial_TraditionalSkyscraper_alt08", 2],
			["pack:building_03", 3], ["pack:building_04", 3], ["pack:building_01x3", 2], ["pack:building_02x3", 2],
			["el:Industrial_OfficeBuilding_alt01", 2], ["el:Industrial_OfficeBuilding_alt05", 2], ["el:Industrial_WideOfficeBuilding_alt01", 1]],
	"midrise": [["el:Industrial_OfficeBuilding_alt01", 2], ["el:Industrial_OfficeBuilding_alt02", 2], ["el:Industrial_OfficeBuilding_alt03", 2],
			["el:Industrial_OfficeBuilding_alt04", 2], ["el:Industrial_OfficeBuilding_alt05", 2], ["el:Industrial_WideOfficeBuilding_alt02", 1],
			["el:Industrial_WideOfficeBuilding_alt03", 1], ["el:Industrial_WideOfficeBuilding_alt04", 1],
			["pack:building_03", 2], ["pack:building_04", 2], ["pack:building_01x2", 2], ["pack:building_02x2", 2], ["pack:building_01x3", 1],
			["pack:building_02x3", 1], ["pack:building_05", 2], ["el:Residential_Loft_alt01", 2], ["el:Residential_Loft_alt02", 2],
			["el:Residential_Loft_alt03", 2], ["el:Business_CommercialBuilding_alt01", 1], ["el:Business_CommercialBuilding_alt02", 1],
			["el:Business_ParkingStructure", 1], ["el:Industrial_TraditionalSkyscraper_alt03", 1]],
	"lowrise": [["el:Business_CommercialBuilding_alt03", 3], ["el:Business_CommercialBuilding_alt04", 3], ["el:Business_CommercialBuilding_alt05", 3],
			["el:Residential_Loft_alt04", 2], ["el:Residential_Loft_alt05", 2], ["el:Residential_Loft_alt06", 2], ["el:Residential_Townhouse", 3],
			["el:Residential_GeorgianHome_alt01", 2], ["el:Residential_GeorgianHome_alt02", 2], ["el:Residential_GeorgianHome_alt03", 2],
			["el:Residential_GeorgianHome_alt04", 2], ["el:Residential_GeorgianHome_alt05", 2], ["pack:building_01", 2], ["pack:building_02", 2],
			["pack:building_05", 2], ["pack:building_06", 2], ["el:Business_SmallBusiness_alt01", 2], ["el:Business_SmallBusiness_alt02", 2],
			["el:Business_Pub", 1], ["el:Business_Restaurant", 1], ["el:Business_PizzaRestaurant", 1], ["el:Business_ConvenienceStore_alt01", 1],
			["el:Business_GeneralStore", 1], ["el:Business_FastFoodRestaurant", 1], ["el:Business_DoctorsOffice", 1], ["el:Business_Library", 1],
			["el:Business_FireStation", 1], ["el:Industrial_Warehouse_alt01", 1], ["el:Industrial_Warehouse_alt03", 1], ["el:Business_ParkingStructure", 1],
			["pack:building_02x2", 1], ["el:Business_Courthouse", 1]],
}

var layout: Layout
var el: ELModels
var rng := RandomNumberGenerator.new()
var models := {}                     # clé -> {"mesh", "aabb", "height", "front_fixed", "occluders": Array[AABB], "triangles"}
var placements: Array[Dictionary] = []
var _sky_json := {}
var _pack_json := {}
var _pack_material: StandardMaterial3D
var _sky_material: StandardMaterial3D
var _shapes := {}
var _occluders := {}
var _stats := {"par_zone": {}, "par_famille": {}, "occulteurs": 0, "occulteurs_au_sol": 0, "boites_occultation": 0, "sans_place": 0}


func _initialize() -> void:
	# Taux de fenetres allumees impose en ligne de commande, pour comparer plusieurs reglages sur
	# la meme vue sans toucher au code (cf. BuildingWindows.fraction).
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fraction="):
			Windows.fraction = clampf(a.substr(11).to_float(), 0.0, 1.0)
			print("WINDOW_FRACTION %.2f" % Windows.fraction)
	rng.seed = SEED
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MODELS.path_join("models")))
	layout = Layout.new()
	el = ELModels.new()
	for entry: Dictionary in JSON.parse_string(FileAccess.get_file_as_string(SKY_JSON))["models"]:
		_sky_json[entry["name"]] = entry
	for entry: Dictionary in JSON.parse_string(FileAccess.get_file_as_string(PACK_JSON))["models"]:
		_pack_json[entry["name"]] = entry
	_materials()
	var casino := Rect2()
	for poi: Dictionary in MapSpec.POIS:
		if poi["id"] == "casino":
			casino = Rect2(poi["pos"] - poi["size"] * 0.5, poi["size"])
	# gratte-ciels : îlots du cœur (hors Lincoln Plaza) du plus proche au plus lointain du croisement central
	var core: Array[int] = []
	for b in layout.blocks.size():
		if layout.blocks[b]["zone"] == "core" and not layout.blocks[b]["plaza"]:
			core.append(b)
	core.sort_custom(func(x: int, y: int) -> bool: return _dist(x) < _dist(y))
	var towers := SKY_ORDER.duplicate()
	for b in core:
		_core_block(b, towers)
	for b in layout.blocks.size():
		var block: Dictionary = layout.blocks[b]
		match String(block["zone"]):
			"core":
				if block["plaza"]:
					_lincoln(b)
			"plaza":
				_single(b, "el:Historical_Bandstand", Vector2.ZERO, 0.0)
			"civic":
				_single(b, "el:Historical_ChurchOld", Vector2(0, 0), PI)
			"casino":
				_frontage_block(b, "lowrise", [casino.grow(4.0)])
			"shops":
				var holes: Array[Rect2] = []
				for shop: Dictionary in Spec.SHOPS:
					holes.append((shop["rect"] as Rect2).grow(SHOP_MARGIN))
				_frontage_block(b, "lowrise", holes)
			"midrise":
				_frontage_block(b, "midrise_near" if _dist(b) < 230.0 else "midrise", [])
			"lowrise":
				_frontage_block(b, "lowrise", [])
	var problems := _check_overlaps(casino)
	var scene := _write_scene()
	_stats["batiments"] = placements.size()
	_stats["scene"] = scene
	var tris := 0
	for p: Dictionary in placements:
		tris += int(models[p["model"]]["triangles"])
	_stats["triangles"] = tris
	_stats["modeles_distincts"] = _distinct()
	print("DOWNTOWN_BUILDINGS " + JSON.stringify(_stats))
	var boxes := {}
	for key: String in models:
		var a: AABB = models[key]["aabb"]
		var parts := []
		for b: AABB in models[key]["occluders"]:
			parts.append("base %.1f, haut %.0f/%.0f m, emprise %.0f%%" % [b.position.y, b.end.y, a.end.y, 100.0 * b.size.x * b.size.z / (a.size.x * a.size.z)])
		boxes[key] = " + ".join(parts) if not parts.is_empty() else "aucune"
	print("DOWNTOWN_BUILDINGS_OCCLUDERS " + JSON.stringify(boxes))
	if not problems.is_empty():
		print("DOWNTOWN_BUILDINGS_ERROR " + " | ".join(problems))
	quit(0 if problems.is_empty() and scene == "OK" else 1)


func _dist(b: int) -> float:
	return (layout.blocks[b]["outer"] as Rect2).get_center().distance_to(CORE_CENTER)


func _distinct() -> int:
	var keys := {}
	for p: Dictionary in placements:
		keys[p["model"]] = true
	return keys.size()


# --- modèles ------------------------------------------------------------------------------------------------------------

func _materials() -> void:
	var pack := StandardMaterial3D.new()
	pack.resource_name = "CentreVillePackUrbain"
	pack.albedo_texture = load("res://assets/lowpoly_city_pack/lowpoly_city_palette.png")
	pack.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	pack.roughness = 0.8
	ResourceSaver.save(pack, MODELS.path_join("lowpoly_material.tres"))
	_pack_material = load(MODELS.path_join("lowpoly_material.tres"))
	var sky := StandardMaterial3D.new()
	sky.resource_name = "CentreVilleGratteCiels"
	sky.albedo_texture = load("res://assets/skyscraper_bundle/SkyScraperUVEdit.png")
	sky.vertex_color_use_as_albedo = true
	sky.vertex_color_is_srgb = true
	sky.roughness = 0.35
	sky.metallic = 0.25
	sky.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	ResourceSaver.save(sky, MODELS.path_join("skyscraper_material.tres"))
	_sky_material = load(MODELS.path_join("skyscraper_material.tres"))


func model(key: String) -> Dictionary:
	if not models.has(key):
		var family := key.get_slice(":", 0)
		var name := key.get_slice(":", 1)
		match family:
			"el":
				var info := el.get_model(name)
				# matériau EverythingLibrary sans élimination des faces arrière
				models[key] = {"mesh": info["mesh"], "aabb": info["aabb"], "front_fixed": true, "triangles": info["triangles"],
						"occluders": _checked_occluders(info["mesh"], info["aabb"], [0.9, 0.66, 0.45], true)}
			"sky":
				models[key] = _glb_model(key, [String(_sky_json[name]["path"])], _sky_material, true)
				var top: float = SKY_OCCLUDER[name]
				models[key]["occluders"] = _checked_occluders(models[key]["mesh"], models[key]["aabb"], [top, top * 0.75, top * 0.5, 0.25], false)
				models[key]["front_fixed"] = false
			"pack":
				var parts := name.split("x")   # building_01x3 : building_01 et deux étages building_01_top par-dessus
				var base := parts[0]
				var levels := int(parts[1]) if parts.size() > 1 else 1
				var paths: Array[String] = [String(_pack_json[base]["path"])]
				for k in levels - 1:
					paths.append(String(_pack_json[base + "_top"]["path"]))
				models[key] = _glb_model(key, paths, _pack_material, false)
				models[key]["occluders"] = _checked_occluders(models[key]["mesh"], models[key]["aabb"], [0.9, 0.66, 0.45], false)
				models[key]["front_fixed"] = false
		models[key]["height"] = (models[key]["aabb"] as AABB).end.y
		models[key]["hlod_color"] = _mean_color(models[key]["mesh"], family)
		models[key]["windows"] = _window_panes(family, name)
	return models[key]


# Carreaux vitrés d'un modèle, dans son repère. Relus sur le .glb d'origine parce que la fusion en a
# perdu la trace : _glb_model et BuildingModels écrasent toutes les surfaces en une seule, donc le
# maillage cuit ne dit plus quel triangle était une vitre. Les deux fusionnent sans transformation
# supplémentaire pour la première pièce, le repère est donc le même.
#
# La famille "pack" (lowpoly_city) n'a qu'une surface texturée sur un atlas de palette de 4 x 4
# texels. On l'a d'abord crue « pas séparable » ; c'était faux. Chaque triangle vise un texel précis,
# et les vitrages visent les deux bleus. On passe donc l'atlas à BuildingWindows, qui trie les
# triangles au texel. Vérifié en rendant le pack en plein jour avant de coder : murs gris foncé,
# fenêtres bleues en grille sur les quatre façades.
const PACK_PALETTE := "res://assets/lowpoly_city_pack/lowpoly_city_palette.png"
const PACK_WINDOW_COLORS := ["#68C0FF", "#23A3FF"]
var _pack_atlas := {}


func _window_panes(family: String, name: String) -> Array:
	var chemin := ""
	var atlas := {}
	match family:
		"el":
			if el.catalog.has(name):
				chemin = String(el.catalog[name]["path"])
		"sky":
			chemin = String(_sky_json[name]["path"])
		"pack":
			# building_01x3 = la base plus deux étages empilés ; les carreaux doivent suivre le même
			# empilement que _glb_model, sinon seul le rez-de-chaussée s'allumerait.
			return _pack_panes(name)
		_:
			return []
	if chemin == "" or not ResourceLoader.exists(chemin):
		return []
	var inst: Node = (load(chemin) as PackedScene).instantiate()
	var out := Windows.panes(inst, [], atlas)
	inst.free()
	return out


# Carreaux d'un modèle du pack, étage par étage, avec le MÊME décalage vertical que _glb_model :
# chaque pièce est posée au sommet de la précédente.
func _pack_panes(name: String) -> Array:
	var parts := name.split("x")
	var base: String = parts[0]
	var levels := int(parts[1]) if parts.size() > 1 else 1
	if not _pack_json.has(base):
		return []
	var chemins: Array[String] = [String(_pack_json[base]["path"])]
	for k in levels - 1:
		if _pack_json.has(base + "_top"):
			chemins.append(String(_pack_json[base + "_top"]["path"]))
	var atlas := _atlas_pack()
	var out: Array = []
	var y := 0.0
	for chemin in chemins:
		if not ResourceLoader.exists(chemin):
			continue
		var inst: Node = (load(chemin) as PackedScene).instantiate()
		var etage := Windows.panes(inst, [], atlas)
		var sommet := _sommet(inst, Transform3D.IDENTITY)
		inst.free()
		for pane: Dictionary in etage:
			var tris: PackedVector3Array = pane["tris"]
			var decales := PackedVector3Array()
			for v in tris:
				decales.append(v + Vector3(0, y, 0))
			out.append({"tris": decales, "n": pane["n"]})
		y = sommet
	return out


func _sommet(n: Node, parent: Transform3D) -> float:
	var x := parent
	if n is Node3D:
		x = parent * (n as Node3D).transform
	var top := -INF
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var m := (n as MeshInstance3D).mesh
		for s in m.get_surface_count():
			for v in (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				top = maxf(top, (x * v).y)
	for c in n.get_children():
		top = maxf(top, _sommet(c, x))
	return top


func _atlas_pack() -> Dictionary:
	if _pack_atlas.is_empty() and ResourceLoader.exists(PACK_PALETTE):
		_pack_atlas = {"image": (load(PACK_PALETTE) as Texture2D).get_image(), "couleurs": PACK_WINDOW_COLORS}
	return _pack_atlas


# Couleur de silhouette lointaine (DowntownHLOD, sRGB) : moyenne des couleurs de sommet (EverythingLibrary, en linéaire),
# ou teinte moyenne relevée à l'œil pour les familles texturées.
func _mean_color(mesh: Mesh, family: String) -> Color:
	if family == "pack":
		return Color(0.52, 0.55, 0.6)
	if family == "sky":
		return Color(0.55, 0.62, 0.72)
	var cols: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	if cols.is_empty():
		return Color(0.58, 0.56, 0.53)
	var sum := Color(0, 0, 0)
	var step := maxi(1, cols.size() / 500)
	var n := 0
	for k in range(0, cols.size(), step):
		sum += cols[k]
		n += 1
	return Color(sum.r / n, sum.g / n, sum.b / n).linear_to_srgb()


# Maillage fusionné d'un ou plusieurs .glb empilés (chaque pièce posée sur la précédente), un seul matériau ; façades des
# gratte-ciels : les parties sans texture gardent leur couleur en couleur de sommet, avec des UV sur un texel blanc.
class Mesher:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()


func _glb_model(key: String, paths: Array[String], material: Material, flat_colors: bool) -> Dictionary:
	var m := Mesher.new()
	var y := 0.0
	for path in paths:
		var inst := (load(path) as PackedScene).instantiate()
		var before := m.v.size()
		_collect(inst, Transform3D(Basis.IDENTITY, Vector3(0, y, 0)), m, flat_colors)
		inst.free()
		var top := -INF
		for k in range(before, m.v.size()):
			top = maxf(top, m.v[k].y)
		y = top
	var aabb := AABB(m.v[0], Vector3.ZERO)
	for p in m.v:
		aabb = aabb.expand(p)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = m.v
	arrays[Mesh.ARRAY_NORMAL] = m.n
	arrays[Mesh.ARRAY_TEX_UV] = m.uv
	arrays[Mesh.ARRAY_COLOR] = m.c
	arrays[Mesh.ARRAY_INDEX] = m.i
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, material, key.replace(":", "_"))
	importer.generate_lods(25.0, 60.0, [])
	var path := MODELS.path_join("models/%s.res" % key.replace(":", "_"))
	ResourceSaver.save(importer.get_mesh(), path)
	return {"mesh": load(path), "aabb": aabb, "triangles": m.i.size() / 3}


const WHITE_TEXEL := Vector2(0.4, 0.03)   # bande blanche en haut de SkyScraperUVEdit.png


func _collect(node: Node, parent: Transform3D, m: Mesher, flat_colors: bool) -> void:
	var xform := parent
	if node is Node3D:
		xform = parent * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		var normal_basis := xform.basis.inverse().transposed()
		for s in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var mat := mi.get_active_material(s) as BaseMaterial3D
			var textured := mat != null and mat.albedo_texture != null
			var tint := mat.albedo_color if mat != null and not textured else Color.WHITE
			var arrays: Array = mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if indices.is_empty():
				indices.resize(verts.size())
				for k in verts.size():
					indices[k] = k
			var first := m.v.size()
			for k in verts.size():
				m.v.append(xform * verts[k])
				m.n.append((normal_basis * (normals[k] if k < normals.size() else Vector3.UP)).normalized())
				if flat_colors and not textured:
					m.uv.append(WHITE_TEXEL)
				else:
					m.uv.append(uvs[k] if k < uvs.size() else Vector2.ZERO)
				m.c.append(tint)
			var mirrored := xform.basis.determinant() < 0.0
			for t in range(0, indices.size() - 2, 3):
				m.i.append(first + indices[t])
				m.i.append(first + indices[t + 2] if mirrored else first + indices[t + 1])
				m.i.append(first + indices[t + 1] if mirrored else first + indices[t + 2])
	for child in node.get_children():
		_collect(child, xform, m, flat_colors)


# --- boîtes d'occultation -----------------------------------------------------------------------------------------------
#
# Une boîte ne doit jamais dépasser du volume plein du bâtiment (elle masquerait ce qu'on voit à travers une arcade, une
# cour, un rez-de-chaussée ouvert). Elle est donc vérifiée par rayons sur le maillage du modèle : chaque point
# échantillonné sur ses côtés (de face, de biais, d'en haut en plongée) et sur son dessus (à la verticale et de biais)
# doit être caché derrière une face opaque vue de l'extérieur (faces arrière ignorées si le matériau les élimine).
# Candidats, pour chaque base (OCC_BOTTOMS) : boîte du modèle rentrée de 0,8 / 1,6 / 3 m à la plus grande hauteur
# valable (`tops`, fractions de la hauteur), et deux ajustements progressifs (partie rentrée de 0,5 m, chaque face
# atteinte par un rayon, le dessus compris, recule de 5 % jusqu'à ce que plus aucun ne l'atteigne ; dessus reculé en
# premier, ou côtés en premier) qui écartent dalle du terrain, perron, auvent, angles coupés, enseigne, étages en retrait.
# Retenues : la boîte « rue » qui couvre le mieux les 4 premiers mètres parmi celles qui descendent près du sol (vu de la
# rue, un PNJ ou une voiture derrière le bâtiment n'est masqué que si la boîte descend près du sol ; une base à 2,5 m
# laissait voir le bas de tout ce qui est derrière), et la boîte « silhouette » de plus grande façade si elle n'est pas
# déjà presque contenue dans la première (tour sur socle, rez-de-chaussée ouvert).
const OCC_BOTTOMS := [0.1, 0.8, 2.0, 3.5]    # m au-dessus de l'origine du modèle (niveau du sol)
const OCC_INSETS := [0.8, 1.6, 3.0]
const OCC_MIN_SIZE := 3.0                    # m : côté minimal de la boîte ; hauteur minimale 2,5 m
const OCC_SIDES := [["+X", Vector3.RIGHT, Vector3.BACK], ["-X", Vector3.LEFT, Vector3.BACK], ["+Z", Vector3.BACK, Vector3.RIGHT], ["-Z", Vector3.FORWARD, Vector3.RIGHT]]


func _checked_occluders(mesh: Mesh, aabb: AABB, tops: Array, double_sided: bool) -> Array[AABB]:
	var tm := mesh.generate_triangle_mesh()
	var candidates: Array[AABB] = []
	for bottom: float in OCC_BOTTOMS:
		for inset: float in OCC_INSETS:
			for top: float in tops:
				var box := AABB(Vector3(aabb.position.x + inset, bottom, aabb.position.z + inset),
						Vector3(aabb.size.x - 2.0 * inset, aabb.end.y * top - bottom, aabb.size.z - 2.0 * inset))
				if box.size.x < OCC_MIN_SIZE or box.size.z < OCC_MIN_SIZE or box.size.y < OCC_MIN_SIZE - 0.5:
					continue
				if _failures(tm, box, aabb, double_sided, false, true).is_empty() and _failures(tm, box, aabb, double_sided, true, true).is_empty():
					candidates.append(box)
					break
		for sides_first: bool in [false, true]:
			var fitted := _fit_box(tm, aabb, bottom, tops[0], double_sided, sides_first)
			if fitted.has_volume():
				candidates.append(fitted)
	var street := AABB()
	var street_score := 0.0
	var skyline := AABB()
	var skyline_score := 0.0
	for b in candidates:
		var s := (b.size.x + b.size.z) * (minf(b.end.y, 4.0) - b.position.y)
		if b.position.y <= 0.8 and (s > street_score + 0.01 or (s > street_score - 0.01 and _volume(b) > _volume(street))):
			street = b
			street_score = s
		var f := (b.size.x + b.size.z) * b.size.y
		if f > skyline_score:
			skyline = b
			skyline_score = f
	var boxes: Array[AABB] = []
	if street.has_volume():
		boxes.append(street)
	if skyline.has_volume() and (boxes.is_empty() or _overlap(street, skyline) < 0.8):
		boxes.append(skyline)
	return boxes


func _volume(b: AABB) -> float:
	return b.size.x * b.size.y * b.size.z


# Part du volume de la plus petite des deux boîtes contenue dans l'autre.
func _overlap(a: AABB, b: AABB) -> float:
	var inter := a.intersection(b)
	return _volume(inter) / minf(_volume(a), _volume(b)) if inter.has_volume() else 0.0


func _fit_box(tm: TriangleMesh, aabb: AABB, bottom: float, top_max: float, double_sided: bool, sides_first: bool) -> AABB:
	var box := AABB(Vector3(aabb.position.x + 0.5, bottom, aabb.position.z + 0.5), Vector3(aabb.size.x - 1.0, aabb.end.y * top_max - bottom, aabb.size.z - 1.0))
	var fine := false
	for iter in 120:
		if box.size.x < OCC_MIN_SIZE or box.size.z < OCC_MIN_SIZE or box.size.y < OCC_MIN_SIZE - 0.5:
			return AABB()
		var fails := _failures(tm, box, aabb, double_sided, fine, false)
		if fails.is_empty():
			if fine:
				return box
			fine = true
			continue
		var side_fail := fails.size() > (1 if fails.has("top") else 0)
		if fails.has("top") and not (sides_first and side_fail):
			box.size.y -= maxf(0.5, box.size.y * 0.05)
			if not sides_first:
				continue
		var sx := maxf(0.4, box.size.x * 0.05)
		var sz := maxf(0.4, box.size.z * 0.05)
		if fails.has("+X"):
			box.size.x -= sx
		if fails.has("-X"):
			box.position.x += sx
			box.size.x -= sx
		if fails.has("+Z"):
			box.size.z -= sz
		if fails.has("-Z"):
			box.position.z += sz
			box.size.z -= sz
	return AABB()


# Faces de la boîte ("+X", "-X", "+Z", "-Z", "top") atteintes par au moins un rayon venu de l'extérieur (`stop` : dès
# la première).
func _failures(tm: TriangleMesh, box: AABB, aabb: AABB, double_sided: bool, fine: bool, stop: bool) -> Dictionary:
	var out := {}
	var reach := aabb.size.length() + 4.0
	var c := box.get_center()
	var div := 16.0 if fine else 6.0
	var heights := _steps(box.position.y + 0.02, box.end.y - 0.02, clampf(box.size.y / div, 1.0, 16.0))
	for side: Array in OCC_SIDES:
		var n: Vector3 = side[1]
		var t: Vector3 = side[2]
		var half := absf(t.dot(box.size)) * 0.5 - 0.02
		var dirs := [n, (n + t * 0.84).normalized(), (n - t * 0.84).normalized(), (n + Vector3.UP).normalized(), (n + Vector3.UP * 1.73).normalized()]
		var along := _steps(-half, half, clampf(half / (div * 0.6), 0.75, 4.0))
		for h: float in heights:
			var face := Vector3(c.x + n.x * box.size.x * 0.5, h, c.z + n.z * box.size.z * 0.5)
			for s: float in along:
				var p := face + t * s
				for d: Vector3 in dirs:
					if not _blocked(tm, p + d * reach, p, double_sided):
						out[side[0]] = true
						break
				if out.has(side[0]):
					break
			if out.has(side[0]):
				break
		if stop and not out.is_empty():
			return out
	var step := clampf(maxf(box.size.x, box.size.z) / (div * 1.25), 0.75, 4.0)
	for x: float in _steps(box.position.x + 0.02, box.end.x - 0.02, step):
		for z: float in _steps(box.position.z + 0.02, box.end.z - 0.02, step):
			var p := Vector3(x, box.end.y, z)
			for d: Vector3 in [Vector3.UP, Vector3(1, 1, 0).normalized(), Vector3(-1, 1, 0).normalized(), Vector3(0, 1, 1).normalized(), Vector3(0, 1, -1).normalized()]:
				if not _blocked(tm, p + d * reach, p, double_sided):
					out["top"] = true
					return out
	return out


# Le segment de `from` (dehors) à `to` (sur la boîte) traverse-t-il une face dessinée tournée vers `from` ? Un segment
# qui passe pile sur une arête du maillage peut la manquer (arrondi du test) : il n'est compté ouvert que si deux
# voisins décalés de 1 à 2 cm passent aussi.
func _blocked(tm: TriangleMesh, from: Vector3, to: Vector3, double_sided: bool) -> bool:
	if _blocked_once(tm, from, to, double_sided):
		return true
	return _blocked_once(tm, from, to + Vector3(0.013, 0.007, 0.011), double_sided) and _blocked_once(tm, from, to + Vector3(-0.009, -0.012, -0.006), double_sided)


func _blocked_once(tm: TriangleMesh, from: Vector3, to: Vector3, double_sided: bool) -> bool:
	var dir := (to - from).normalized()
	var start := from
	for k in 16:
		var hit := tm.intersect_segment(start, to)
		if hit.is_empty():
			return false
		if double_sided or (hit["normal"] as Vector3).dot(dir) < 0.0:
			return true
		start = (hit["position"] as Vector3) + dir * 0.01
	return false


func _steps(a: float, b: float, step: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if b <= a:
		out.append((a + b) * 0.5)
		return out
	var n := int(ceil((b - a) / step))
	for k in n + 1:
		out.append(lerpf(a, b, float(k) / n))
	return out


# --- îlots --------------------------------------------------------------------------------------------------------------

# Gratte-ciel du SkyScraperBundle le plus haut qui tient dans l'îlot (2 m de marge), adossé à l'angle le plus proche du
# croisement central ; à défaut deux tours EverythingLibrary.
func _core_block(b: int, towers: Array) -> void:
	var inner: Rect2 = layout.blocks[b]["interior"]
	for name: String in towers:
		var mdl := model("sky:" + name)
		var aabb: AABB = mdl["aabb"]
		for yaw: float in [0.0, PI * 0.5]:
			var size := _rotated_size(aabb, yaw)
			if size.x <= inner.size.x - 2.0 and size.y <= inner.size.y - 2.0:
				var toward := (CORE_CENTER - inner.get_center()).sign()
				var center := inner.get_center() + Vector2(toward.x * (inner.size.x - size.x) * 0.5 - toward.x, toward.y * (inner.size.y - size.y) * 0.5 - toward.y)
				_place(b, "sky:" + name, center, yaw, "core")
				towers.erase(name)
				return
	var half := inner.size.x * 0.25
	_place(b, _pick("core_fill", Vector2(inner.size.x * 0.45, inner.size.y - 2.0)), inner.get_center() + Vector2(-half, 0), 0.0, "core")
	_place(b, _pick("core_fill", Vector2(inner.size.x * 0.45, inner.size.y - 2.0)), inner.get_center() + Vector2(half, 0), PI, "core")


func _lincoln(b: int) -> void:
	var inner: Rect2 = layout.blocks[b]["interior"]
	var mdl := model("sky:Mk3")
	var size := _rotated_size(mdl["aabb"], PI * 0.5)
	# tour-lame dans la moitié nord, parvis au sud
	_place(b, "sky:Mk3", Vector2(inner.get_center().x, inner.position.y + size.y * 0.5 + 6.0), PI * 0.5, "core")


func _single(b: int, key: String, offset: Vector2, yaw: float) -> void:
	var inner: Rect2 = layout.blocks[b]["interior"]
	_place(b, key, inner.get_center() + offset, yaw, layout.blocks[b]["zone"])


# Lots en bande : de part et d'autre de la ruelle, ou le long des rues nord et sud (puis ouest et est dans la bande du
# milieu s'il en reste une) ; bâtiments tirés dans le panier, façade vers la rue, sans chevaucher les trous.
func _frontage_block(b: int, pool: String, holes: Array[Rect2]) -> void:
	var block: Dictionary = layout.blocks[b]
	var inner: Rect2 = block["interior"]
	var alley_axis := ""
	if block.has("alley"):
		alley_axis = layout.alleys[block["alley"]]["axis"]
	if alley_axis == "x":
		var depth := minf((inner.size.x - Spec.ALLEY_WIDTH) * 0.5, LOT_DEPTH_MAX)
		_frontage(b, pool, inner, "W", depth, inner.position.y, inner.end.y, holes)
		_frontage(b, pool, inner, "E", depth, inner.position.y, inner.end.y, holes)
		return
	var depth_ns := minf((inner.size.y - (Spec.ALLEY_WIDTH if alley_axis == "z" else 0.0)) * 0.5, LOT_DEPTH_MAX)
	_frontage(b, pool, inner, "N", depth_ns, inner.position.x, inner.end.x, holes)
	_frontage(b, pool, inner, "S", depth_ns, inner.position.x, inner.end.x, holes)
	var band := inner.size.y - depth_ns * 2.0 - (Spec.ALLEY_WIDTH if alley_axis == "z" else 0.0)
	if alley_axis == "" and band >= 12.0:
		var depth_we := minf(inner.size.x * 0.5, LOT_DEPTH_MAX)
		_frontage(b, pool, inner, "W", depth_we, inner.position.y + depth_ns, inner.end.y - depth_ns, holes)
		_frontage(b, pool, inner, "E", depth_we, inner.position.y + depth_ns, inner.end.y - depth_ns, holes)


func _frontage(b: int, pool: String, inner: Rect2, side: String, depth: float, from: float, to: float, holes: Array[Rect2]) -> void:
	# yaw : la façade (+Z du modèle) regarde la rue du côté `side`
	var yaw: float = {"S": 0.0, "N": PI, "E": PI * 0.5, "W": -PI * 0.5}[side]
	var along := from
	var tries := 0
	while along < to - 8.0 and tries < 60:
		tries += 1
		var remaining := to - along
		var key := _pick(pool, Vector2(remaining, depth))
		if key == "":
			break
		var size := _rotated_size(model(key)["aabb"], yaw)
		var w := size.x if side == "N" or side == "S" else size.y
		var d := size.y if side == "N" or side == "S" else size.x
		var center: Vector2
		match side:
			"N":
				center = Vector2(along + w * 0.5, inner.position.y + d * 0.5)
			"S":
				center = Vector2(along + w * 0.5, inner.end.y - d * 0.5)
			"W":
				center = Vector2(inner.position.x + d * 0.5, along + w * 0.5)
			_:
				center = Vector2(inner.end.x - d * 0.5, along + w * 0.5)
		var foot := Rect2(center - size * 0.5, size)
		var blocked := false
		for h in holes:
			if h.intersects(foot):
				blocked = true
				along = (h.end.x if side == "N" or side == "S" else h.end.y) + 0.5
				break
		if blocked:
			continue
		_place(b, key, center, yaw, layout.blocks[b]["zone"])
		along += w + rng.randf_range(0.0, GAP_MAX)


# Modèle du panier qui tient dans `room` (largeur le long de la rue, profondeur) : tirage pondéré parmi ceux qui tiennent,
# en favorisant ceux qui remplissent au moins 60 % de la profondeur.
func _pick(pool: String, room: Vector2) -> String:
	var fits: Array = []
	var total := 0.0
	for entry: Array in POOLS[pool]:
		var key: String = entry[0]
		var aabb: AABB = model(key)["aabb"]
		if aabb.size.x > room.x or aabb.size.z > room.y:
			continue
		var weight := float(entry[1]) * (2.0 if aabb.size.z >= room.y * 0.6 else 1.0)
		fits.append([key, weight])
		total += weight
	if fits.is_empty():
		return ""
	var roll := rng.randf() * total
	for entry: Array in fits:
		roll -= float(entry[1])
		if roll <= 0.0:
			return entry[0]
	return fits[fits.size() - 1][0]


# Taille (x, z) monde de la boîte d'un modèle tourné de `yaw` (multiples de 90°).
func _rotated_size(aabb: AABB, yaw: float) -> Vector2:
	var quarter := posmod(roundi(yaw / (PI * 0.5)), 2) == 1
	return Vector2(aabb.size.z, aabb.size.x) if quarter else Vector2(aabb.size.x, aabb.size.z)


# Pose : centre de la boîte du modèle au point `center` (x, z), pied au niveau du sol de l'îlot.
func _place(b: int, key: String, center: Vector2, yaw: float, zone: String) -> void:
	var mdl := model(key)
	var aabb: AABB = mdl["aabb"]
	var basis := Basis(Vector3.UP, yaw)
	var local_center := Vector3(aabb.get_center().x, 0.0, aabb.get_center().z)
	var origin := Vector3(center.x, WALK_Y, center.y) - basis * local_center
	var size := _rotated_size(aabb, yaw)
	placements.append({"model": key, "transform": Transform3D(basis, origin), "footprint": Rect2(center - size * 0.5, size),
			"height": float(mdl["height"]), "zone": zone, "block": b})
	_stats["par_zone"][zone] = int(_stats["par_zone"].get(zone, 0)) + 1
	_stats["par_famille"][key.get_slice(":", 0)] = int(_stats["par_famille"].get(key.get_slice(":", 0), 0)) + 1


# Chevauchements entre bâtiments, avec les rues (hors intérieur de l'îlot), les boutiques et le lieu du casino.
func _check_overlaps(casino: Rect2) -> Array[String]:
	var out: Array[String] = []
	var clashes := 0
	for i in placements.size():
		var fi: Rect2 = placements[i]["footprint"]
		var inner: Rect2 = layout.blocks[placements[i]["block"]]["interior"]
		if not inner.grow(0.05).encloses(fi):
			out.append("%s hors de son îlot %s" % [placements[i]["model"], fi])
		for shop: Dictionary in Spec.SHOPS:
			if (shop["rect"] as Rect2).intersects(fi):
				out.append("%s sur la boutique %s" % [placements[i]["model"], shop["name"]])
		if casino.intersects(fi):
			out.append("%s sur le lieu du casino" % placements[i]["model"])
		for j in range(i + 1, placements.size()):
			if fi.grow(-0.05).intersects(placements[j]["footprint"]):
				clashes += 1
	if clashes > 0:
		out.append("%d chevauchements entre bâtiments" % clashes)
	return out


# --- fenêtres allumées ------------------------------------------------------------------------------------------------

# Range les carreaux ALLUMÉS d'un bâtiment dans la cellule de 160 m où il se trouve. Le tri allumé /
# éteint est fait par BuildingWindows.lit sur la position MONDE du carreau : stable d'une cuisson à
# l'autre, et sans le moindre appel à rng, pour que la ville ne clignote pas entre deux cuissons.
func _collect_windows(p: Dictionary, mdl: Dictionary, cells: Dictionary, sky_cells: Dictionary) -> void:
	var panes: Array = mdl.get("windows", [])
	if panes.is_empty():
		return
	var xform: Transform3D = p["transform"]
	var sky := String(p["model"]).begins_with("sky:")
	var dest: Dictionary = sky_cells if sky else cells
	var key := Vector2i(floori(xform.origin.x / WINDOW_CELL), floori(xform.origin.z / WINDOW_CELL))
	if not dest.has(key):
		dest[key] = [PackedVector3Array(), PackedVector3Array(), PackedInt32Array()]
	var acc: Array = dest[key]
	var allumes := Windows.emit(panes, xform, acc[0], acc[1], acc[2])
	_stats["fenetres_posees"] = int(_stats.get("fenetres_posees", 0)) + panes.size()
	_stats["fenetres_allumees"] = int(_stats.get("fenetres_allumees", 0)) + allumes


# Un maillage de carreaux allumés par cellule, tous sur le matériau PARTAGÉ : un appel de dessin par
# cellule visible la nuit, zéro le jour puisque les noeuds naissent cachés. C'est StreetLights qui
# les allume, par le groupe window_glow, en même temps que les halos de lampadaire.
func _write_window_glow(root: Node3D, cells: Dictionary, portee: float, prefixe: String) -> void:
	var keys := cells.keys()
	keys.sort_custom(func(a, b): return a.y * 1000 + a.x < b.y * 1000 + b.x)
	for key: Vector2i in keys:
		var acc: Array = cells[key]
		if (acc[2] as PackedInt32Array).is_empty():
			continue
		var mesh := Windows.build_mesh(acc[0], acc[1], acc[2])
		var chemin := MODELS.path_join("%s_%02d_%02d.res" % [prefixe.to_lower(), key.x + 20, key.y + 20])
		ResourceSaver.save(mesh, chemin)
		var mi := MeshInstance3D.new()
		mi.name = "%s_%02d_%02d" % [prefixe, key.x + 20, key.y + 20]
		mi.mesh = load(chemin)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = portee
		mi.visible = false
		mi.add_to_group(&"window_glow", true)
		root.add_child(mi)
		mi.owner = root
		_stats["cellules_fenetres"] = int(_stats.get("cellules_fenetres", 0)) + 1


# --- scène --------------------------------------------------------------------------------------------------------------

func _write_scene() -> String:
	var root := Node3D.new()
	root.name = "Buildings"
	var cells := {}       # Vector2i -> [sommets, normales, indices] des carreaux allumes ordinaires
	var sky_cells := {}   # idem pour les gratte-ciels, qui portent beaucoup plus loin
	for k in placements.size():
		var p: Dictionary = placements[k]
		var mdl := model(p["model"])
		var node := Node3D.new()
		node.name = "%s_%03d_%s" % [p["zone"], k, String(p["model"]).get_slice(":", 1)]
		node.transform = p["transform"]
		node.set_meta("model", p["model"])
		node.set_meta("zone", p["zone"])
		node.set_meta("hlod_color", mdl["hlod_color"])
		if String(p["model"]).begins_with("sky:"):
			node.set_meta("no_hlod", true)   # silhouette propre (niveaux de détail), pas de boîte lointaine
		root.add_child(node)
		node.owner = root
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = mdl["mesh"]
		mi.add_to_group(&"city_building", true)
		node.add_child(mi)
		mi.owner = root
		var aabb: AABB = mdl["aabb"]
		var shape_key: String = p["model"]
		if not _shapes.has(shape_key):
			var box := BoxShape3D.new()
			box.size = Vector3(aabb.size.x, aabb.end.y, aabb.size.z)
			_shapes[shape_key] = box
		var body := StaticBody3D.new()
		body.name = "StaticBody3D"
		node.add_child(body)
		body.owner = root
		var cs := CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		cs.shape = _shapes[shape_key]
		cs.position = Vector3(aabb.get_center().x, aabb.end.y * 0.5, aabb.get_center().z)
		body.add_child(cs)
		cs.owner = root
		_collect_windows(p, mdl, cells, sky_cells)
		var boxes: Array[AABB] = mdl["occluders"]
		var low := false
		for i in boxes.size():
			var occ_key := "%s|%d" % [shape_key, i]
			if not _occluders.has(occ_key):
				var occ_shape := BoxOccluder3D.new()
				occ_shape.size = boxes[i].size
				_occluders[occ_key] = occ_shape
			var occ := OccluderInstance3D.new()
			occ.name = "Occluder" if i == 0 else "Occluder%d" % (i + 1)
			occ.occluder = _occluders[occ_key]
			occ.position = boxes[i].get_center()
			node.add_child(occ)
			occ.owner = root
			_stats["boites_occultation"] += 1
			low = low or boxes[i].position.y <= 1.0
		if not boxes.is_empty():
			_stats["occulteurs"] += 1
			if low:
				_stats["occulteurs_au_sol"] += 1
	_write_window_glow(root, cells, WINDOW_GLOW_RANGE, "WindowGlow")
	_write_window_glow(root, sky_cells, WINDOW_GLOW_RANGE_SKY, "WindowGlowSky")
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, OUT.path_join("Buildings.tscn"))
	root.free()
	# emprises pour le mobilier (D4) et les contrôles
	var list := []
	for p: Dictionary in placements:
		var f: Rect2 = p["footprint"]
		list.append({"model": p["model"], "zone": p["zone"], "block": p["block"], "height": snappedf(float(p["height"]), 0.1),
				"rect": [snappedf(f.position.x, 0.01), snappedf(f.position.y, 0.01), snappedf(f.size.x, 0.01), snappedf(f.size.y, 0.01)]})
	var file := FileAccess.open(OUT.path_join("buildings.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"buildings": list}, " "))
	file.close()
	return error_string(err)
