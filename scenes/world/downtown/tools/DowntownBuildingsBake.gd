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
# rentrée dans le volume plein du bâtiment quand sa forme le permet (gratte-ciels : hauteurs relevées à la main sous
# les retraits et jardins suspendus ; pack urbain : pavés ; EverythingLibrary : emprise projetée pleine à 95 %).
# Tirages déterministes (graine fixe).
#
# Lancer : Godot --headless --path <projet> --script res://scenes/world/downtown/tools/DowntownBuildingsBake.gd

const Layout := preload("res://scenes/world/downtown/DowntownLayout.gd")
const Spec := preload("res://scenes/world/downtown/DowntownSpec.gd")
const MapSpec := preload("res://scenes/world/map/MapSpec.gd")
const ELModels := preload("res://scenes/world/map/tools/BuildingModels.gd")

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
# gratte-ciels : [bas, haut] de la boîte d'occultation en fraction de la hauteur (sous les retraits, flèches et jardins)
const SKY_OCCLUDER := {"Mk1": [0.03, 0.42], "Mk2": [0.03, 0.55], "Mk3": [0.03, 0.9], "Mk4": [0.03, 0.9], "Mk5": [0.03, 0.78],
		"Mk6": [0.03, 0.88], "Scraper001": [0.02, 0.95]}
const SKY_ORDER := ["Mk1", "Mk2", "Mk6", "Scraper001", "Mk4", "Mk5"]
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
var models := {}                     # clé -> {"mesh", "aabb", "height", "front_fixed", "occluder": AABB, "triangles"}
var placements: Array[Dictionary] = []
var _sky_json := {}
var _pack_json := {}
var _pack_material: StandardMaterial3D
var _sky_material: StandardMaterial3D
var _shapes := {}
var _occluders := {}
var _stats := {"par_zone": {}, "par_famille": {}, "occulteurs": 0, "sans_place": 0}


func _initialize() -> void:
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
				models[key] = {"mesh": info["mesh"], "aabb": info["aabb"], "front_fixed": true, "triangles": info["triangles"],
						"occluder": _el_occluder(info["mesh"], info["aabb"])}
			"sky":
				models[key] = _glb_model(key, [String(_sky_json[name]["path"])], _sky_material, true)
				var aabb: AABB = models[key]["aabb"]
				var frac: Array = SKY_OCCLUDER[name]
				var box := AABB(Vector3(aabb.position.x + 2.0, maxf(3.5, aabb.size.y * float(frac[0])), aabb.position.z + 2.0),
						Vector3(aabb.size.x - 4.0, aabb.size.y * (float(frac[1]) - float(frac[0])), aabb.size.z - 4.0))
				models[key]["occluder"] = box
				models[key]["front_fixed"] = false
			"pack":
				var parts := name.split("x")   # building_01x3 : building_01 et deux étages building_01_top par-dessus
				var base := parts[0]
				var levels := int(parts[1]) if parts.size() > 1 else 1
				var paths: Array[String] = [String(_pack_json[base]["path"])]
				for k in levels - 1:
					paths.append(String(_pack_json[base + "_top"]["path"]))
				models[key] = _glb_model(key, paths, _pack_material, false)
				var aabb: AABB = models[key]["aabb"]
				models[key]["occluder"] = AABB(Vector3(aabb.position.x + 0.8, 2.5, aabb.position.z + 0.8),
						Vector3(aabb.size.x - 1.6, aabb.size.y * 0.9 - 2.5, aabb.size.z - 1.6)) if aabb.size.y > 6.0 else AABB()
				models[key]["front_fixed"] = false
		models[key]["height"] = (models[key]["aabb"] as AABB).end.y
		models[key]["hlod_color"] = _mean_color(models[key]["mesh"], family)
	return models[key]


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


# Boîte d'occultation d'un modèle EverythingLibrary : seulement si son emprise projetée couvre au moins 95 % de sa boîte
# (pas de forme en L ni de cour) ; rentrée de 1 m, de 2,5 m au-dessus du sol aux deux tiers de la hauteur.
func _el_occluder(mesh: Mesh, aabb: AABB) -> AABB:
	if aabb.size.y < 7.0 or aabb.size.x < 6.0 or aabb.size.z < 6.0:
		return AABB()
	var cell := 1.0
	var nx := int(ceil(aabb.size.x / cell))
	var nz := int(ceil(aabb.size.z / cell))
	var covered := PackedByteArray()
	covered.resize(nx * nz)
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for t in range(0, idx.size() - 2, 3):
			var a := Vector2(verts[idx[t]].x, verts[idx[t]].z)
			var b := Vector2(verts[idx[t + 1]].x, verts[idx[t + 1]].z)
			var c := Vector2(verts[idx[t + 2]].x, verts[idx[t + 2]].z)
			var lo := Vector2(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)))
			var hi := Vector2(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)))
			for gz in range(maxi(0, floori((lo.y - aabb.position.z) / cell)), mini(nz, ceili((hi.y - aabb.position.z) / cell))):
				for gx in range(maxi(0, floori((lo.x - aabb.position.x) / cell)), mini(nx, ceili((hi.x - aabb.position.x) / cell))):
					if covered[gz * nx + gx] == 1:
						continue
					var q := Vector2(aabb.position.x + (gx + 0.5) * cell, aabb.position.z + (gz + 0.5) * cell)
					if Geometry2D.point_is_inside_triangle(q, a, b, c):
						covered[gz * nx + gx] = 1
	var count := 0
	for k in covered.size():
		count += covered[k]
	if float(count) / covered.size() < 0.95:
		return AABB()
	return AABB(Vector3(aabb.position.x + 1.0, 2.5, aabb.position.z + 1.0), Vector3(aabb.size.x - 2.0, aabb.size.y * 0.66 - 2.5, aabb.size.z - 2.0))


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


# --- scène --------------------------------------------------------------------------------------------------------------

func _write_scene() -> String:
	var root := Node3D.new()
	root.name = "Buildings"
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
		var occ_box: AABB = mdl["occluder"]
		if occ_box.has_volume():
			if not _occluders.has(shape_key):
				var occ_shape := BoxOccluder3D.new()
				occ_shape.size = occ_box.size
				_occluders[shape_key] = occ_shape
			var occ := OccluderInstance3D.new()
			occ.name = "Occluder"
			occ.occluder = _occluders[shape_key]
			occ.position = occ_box.get_center()
			node.add_child(occ)
			occ.owner = root
			_stats["occulteurs"] += 1
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
