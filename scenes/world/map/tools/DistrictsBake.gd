extends SceneTree

# Étape 4 : quartiers de la carte 3D. Lots bâtis le long des rues locales (RoadNetwork.local_streets) et des artères de
# chaque zone : maisons, commerces, bureaux, entrepôts ou fermes selon le type de zone, modèles du pack EverythingLibrary
# (data/building_catalog.json, tailles réelles), façade (+Z du modèle, vérifiée au rendu) tournée vers la rue.
#  - lots : grille d'occupation de 4 m (routes et talus, eau, voie ferrée, centre-ville et lieux réservés avec marge, lots
#    déjà posés), emprise entière dans la zone, pente modérée, sol proche du niveau de la route ; maisons en éventail
#    autour des culs-de-sac ; teinte propre à chaque bâtiment (couleur d'instance) ;
#  - terrain : generated/terrain/heights_roads.res (écrit par RoadBake) aplani sous chaque lot -> heights.res, recuit
#    ensuite par TerrainBake --from-heights ; les cellules des routes ne sont jamais modifiées ;
#  - modèles : sous-maillages fusionnés avec leurs transformations en un seul maillage à niveaux de détail et un seul
#    matériau partagé (tous les matériaux du pack sont identiques : couleurs de sommet, rugosité 0,55) ;
#  - generated/Buildings.tscn : cellules de 256 m, BuildingField (instanciation GPU au démarrage, portée de visibilité par
#    modèle), collision en boîtes (maillage pour la station-service), occulteurs pour les grands volumes ; instanciée
#    dans Map.tscn ;
#  - generated/buildings/lots.json : emprises pour le fond de carte et les tests.
#
# Lancer après RoadBake et avant MapBackgroundBake puis TerrainBake --from-heights :
#   Godot --headless --path <projet> --script res://scenes/world/map/tools/DistrictsBake.gd

const Spec := preload("res://scenes/world/map/MapSpec.gd")
const Model := preload("res://scenes/world/map/tools/TerrainModel.gd")
const Network := preload("res://scenes/world/map/tools/RoadNetwork.gd")
const FIELD_SCRIPT := preload("res://scenes/world/map/BuildingField.gd")
const BuildingModels := preload("res://scenes/world/map/tools/BuildingModels.gd")
const GEN := "res://scenes/world/map/generated"
const OUT := "res://scenes/world/map/generated/buildings"
const SCENE := "res://scenes/world/map/generated/Buildings.tscn"
const MAP_SCENE := "res://scenes/world/map/Map.tscn"
const GRID := 4.0
const GROUP := 256.0

const HOUSES_SUBURB := ["Residential_FamilyHome_alt01", "Residential_FamilyHome_alt02", "Residential_FamilyHome_alt03", "Residential_FamilyHome_alt04",
		"Residential_LargeFamilyHome_alt01", "Residential_LargeFamilyHome_alt02", "Residential_LargeFamilyHome_alt03", "Residential_LargeFamilyHome_alt04",
		"Residential_OldCottage_alt01", "Residential_OldCottage_alt03"]
const HOUSES_TOWN := ["Residential_GeorgianHome_alt01", "Residential_GeorgianHome_alt02", "Residential_GeorgianHome_alt03", "Residential_GeorgianHome_alt04",
		"Residential_GeorgianHome_alt05", "Residential_FamilyHome_alt02", "Residential_FamilyHome_alt04", "Residential_Townhouse"]
const LOFTS := ["Residential_Loft_alt06", "Residential_Loft_alt03"]
const SHOPS := ["Business_ConvenienceStore_alt01", "Business_ConvenienceStore_alt02", "Business_GasStation", "Business_FastFoodRestaurant",
		"Business_PizzaRestaurant", "Business_SmallBusiness_alt01", "Business_SmallBusiness_alt02", "Business_Pub", "Business_GeneralStore", "Business_Restaurant"]
const CENTER := ["Business_CommercialBuilding_alt01", "Business_CommercialBuilding_alt02", "Business_CommercialBuilding_alt03", "Business_CommercialBuilding_alt04",
		"Business_CommercialBuilding_alt05", "Industrial_OfficeBuilding_alt02", "Industrial_OfficeBuilding_alt03", "Industrial_OfficeBuilding_alt04",
		"Industrial_OfficeBuilding_alt05", "Industrial_WideOfficeBuilding_alt02", "Industrial_WideOfficeBuilding_alt03", "Business_DoctorsOffice",
		"Business_Bank", "Business_Library", "Residential_Loft_alt06", "Residential_Loft_alt03"]
const INDUSTRY := ["Industrial_Warehouse_alt01", "Industrial_Warehouse_alt02", "Industrial_Warehouse_alt03", "Industrial_Warehouse_alt04",
		"Industrial_Factory_alt01", "Industrial_Factory_alt04", "Industrial_IndustrialBuilding_alt01", "Industrial_IndustrialBuilding_alt02",
		"Industrial_IndustrialBuilding_alt03", "Industrial_IndustrialBuilding_alt05", "Industrial_IndustrialBuilding_alt06", "Industrial_StorageFacility",
		"Industrial_SmallIndustrialStructure_alt01", "Industrial_SmallIndustrialStructure_alt05", "Industrial_SmallIndustrialStructure_alt07", "Industrial_DataCenter"]
const FARMS := ["Farm_Barn", "Residential_FamilyHome_alt01", "Residential_OldCottage_alt02", "Residential_LargeFamilyHome_alt04", "Farm_MetalWindmill"]
# par type de zone : groupes pondérés [modèles, poids] des rues locales et des artères, facteur d'écart entre lots
const MIX := {
	"suburb": {"street": [[HOUSES_SUBURB, 1.0]], "arterial": [[HOUSES_SUBURB, 0.75], [SHOPS, 0.25]], "gap": 1.0},
	"residential": {"street": [[HOUSES_TOWN, 1.0]], "arterial": [[HOUSES_TOWN, 0.6], [SHOPS, 0.4]], "gap": 0.7},
	"mixed": {"street": [[HOUSES_TOWN, 0.8], [LOFTS, 0.2]], "arterial": [[CENTER, 0.65], [SHOPS, 0.35]], "gap": 0.8},
	"industrial": {"street": [[INDUSTRY, 1.0]], "arterial": [[INDUSTRY, 1.0]], "gap": 0.8},
	"farmland": {"street": [], "arterial": [[FARMS, 1.0]], "gap": 8.0},
}
const SETBACK := {"house": 8.0, "commerce": 12.0, "office": 12.0, "service": 12.0, "industry": 14.0, "farm": 16.0}
const LOT_GAP := {"house": 8.0, "commerce": 12.0, "office": 12.0, "service": 12.0, "industry": 14.0, "farm": 20.0}
const MAX_DROP := {"house": 2.6, "commerce": 2.2, "office": 2.2, "service": 2.2, "industry": 2.0, "farm": 3.0}
const RANGE := {"house": 600.0, "commerce": 800.0, "office": 1100.0, "service": 900.0, "industry": 1000.0, "farm": 800.0}
const ROAD_STEP := 3.0                      # écart max entre le sol du lot et la chaussée en face
const HIGHWAY_MARGIN := 14.0                # recul des lots par rapport aux autoroutes et bretelles
const ROAD_MARGIN := 3.0
const BLEND := 8.0                          # raccord du terrain aplani
const OCCLUDER_FAMILIES := ["CommercialBuilding", "OfficeBuilding", "Warehouse", "Loft", "IndustrialBuilding", "StorageFacility"]
const OCCLUDER_MIN_HEIGHT := 10.0
const OCCLUDER_MIN_AREA := 250.0
const TRIMESH_MODELS := ["Business_GasStation"]

# --- allées d'accès ---------------------------------------------------------------------------------------------
# Chantier « relier les bâtiments à la route ». Rien n'est deviné : _try_lot pose le centre du lot à
# at.point + normal * (offset + SETBACK[use] + size.z / 2), où `offset` mène au BORD DUR (bord extérieur du
# trottoir sur une artère urbaine, bord de chaussée sur une rue locale). La distance de la face avant du
# bâtiment à ce bord vaut donc exactement SETBACK[use], et `yaw = atan2(front.x, front.y)` donne la direction.
# Relevé sur les 1 196 lots : 487 déjà au contact du dur, 689 franchissables d'une allée droite, 20 barrés par
# un autre bâtiment, aucun trop long ni trop pentu (dénivelé médian 0,30 m, maxi 1,32 m).
const DRIVE_ZONES := ["southside"]          # zones traitées ; tableau vide = toutes
const DRIVE_STOP := 0.0                     # AU CONTACT du bord dur : laisser 0,5 m rendait un liseré d'herbe
                                            # visible à hauteur d'homme sur les rues locales, alors que le contact
                                            # n'empiète pas (vérifié allée par allée, cf. probe_allees_ok)
const DRIVE_WIDTH := {"house": 3.0, "commerce": 5.0, "office": 5.0, "service": 5.0, "industry": 6.0, "farm": 6.0}
const DRIVE_SURFACE := {"house": "gravier", "commerce": "enrobe", "office": "enrobe", "service": "enrobe",
		"industry": "beton", "farm": "gravier"}
# Colonnes de roads.png : « median » (enrobé sans marquage) et « dirt ». Deux aspects pour UN seul matériau, donc
# sans appel de dessin supplémentaire ; seul le béton en ajoute un, et uniquement dans les cellules industrielles.
const DRIVE_U := {"enrobe": 0.2246, "gravier": 0.6015}
# L'allée n'a PAS de collision : c'est le terrain aplani dessous qui porte le joueur. La dalle doit donc être
# posée au ras de ce terrain, sinon on s'y enfonce à pied. _flatten creuse de DRIVE_SINK sous la cote visée,
# comme _flatten le fait pour les lots, et le quad se pose DRIVE_CLEAR au-dessus du terrain ainsi obtenu —
# juste de quoi éviter la lutte de profondeur. Un premier essai posait le quad 10 cm plus haut : mesuré sur les
# sommets cuits, écart médian 0,081 m, c'est-à-dire une dalle qui flotte.
const DRIVE_SINK := 0.05
const DRIVE_CLEAR := 0.055
const DRIVE_TEX := 12.0                     # m couverts par la hauteur de texture, cf. RoadTexturesBake
const DRIVE_RANGE := 700.0
const MAT_ASPHALT := GEN + "/roads/asphalt_material.tres"
const MAT_CONCRETE := GEN + "/roads/concrete_material.tres"

var model: Model
var net: Network
var heights := PackedFloat32Array()
# décalage, en m, entre la ligne de référence de _frontage et le vrai bord dur : 1 m d'accotement sur une artère
var _front_extra := 0.0
var drives: Array = []
var drive_skipped: Array = []
var locked := PackedByteArray()          # grille du terrain : 1 sous une emprise déjà aplanie
var mask := PackedByteArray()            # grille de 4 m calée sur PLAYABLE : 1 route / eau / réservé, 2 lot
var mask_w := 0
var mask_h := 0
var models: BuildingModels
var catalog := {}
var baked := {}                          # nom -> {"mesh": Mesh, "aabb": AABB, "triangles": int, "shape": Shape3D}
var lots: Array[Dictionary] = []
var refused := {"zone": 0, "occupation": 0, "pente": 0, "route": 0}
var tint_rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	model = Model.new()
	net = Network.new(model)
	net.build()
	if not net.errors.is_empty():
		for line in net.errors:
			print("DISTRICTS_ERROR réseau : " + line)
		quit(1)
		return
	var source := GEN + "/terrain/heights_roads.res"
	if not ResourceLoader.exists(source):
		print("DISTRICTS_ERROR %s absent : lancer RoadBake d'abord" % source)
		quit(1)
		return
	heights = (load(source) as Image).get_data().to_float32_array()
	locked.resize(heights.size())
	models = BuildingModels.new()
	catalog = models.catalog
	for group: Array in [HOUSES_SUBURB, HOUSES_TOWN, LOFTS, SHOPS, CENTER, INDUSTRY, FARMS]:
		for name: String in group:
			if not catalog.has(name):
				print("DISTRICTS_ERROR modèle absent du catalogue : " + name)
				quit(1)
				return
	_build_mask()
	print("DISTRICTS masque %dx%d en %.1f s" % [mask_w, mask_h, (Time.get_ticks_msec() - t0) / 1000.0])
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	tint_rng.seed = 777
	for zone: Dictionary in Spec.ZONES:
		var mix: Dictionary = MIX.get(zone["type"], {})
		if mix.is_empty():
			continue
		var poly := Spec.zone_polygon(zone)
		# grands axes d'abord (commerces, bureaux), puis rues locales (maisons, entrepôts)
		for rb in net.ribbons:
			if rb.kind != "arterial" or not rb.mesh or String(rb.id).begins_with("rue_") or rb.style == "dirt":
				continue
			var offset: float = float(rb.width) * 0.5 + (Network.SIDEWALK_WIDTH if rb.style == "urban" else 1.0)
			for side_sign: float in [-1.0, 1.0]:
				_frontage(rb.points, side_sign, offset, mix["arterial"], float(mix["gap"]), poly, zone, rng, 30.0, 0.0 if rb.style == "urban" else 1.0)
		for street: Dictionary in net.local_streets:
			if street["zone"] != zone["id"] or (mix["street"] as Array).is_empty():
				continue
			var srb = street["ribbon"]
			_cul_de_sac(srb, mix["street"], poly, zone, rng)
			for side_sign: float in [-1.0, 1.0]:
				_frontage(srb.points, side_sign, float(srb.width) * 0.5, mix["street"], float(mix["gap"]), poly, zone, rng, 14.0)
	_driveways()
	ResourceSaver.save(Image.create_from_data(model.width, model.depth, false, Image.FORMAT_RF, heights.to_byte_array()), GEN + "/terrain/heights.res")
	# copie « routes et quartiers » : PlacesBake repart de celle-ci (cuisson rejouable)
	ResourceSaver.save(Image.create_from_data(model.width, model.depth, false, Image.FORMAT_RF, heights.to_byte_array()), GEN + "/terrain/heights_districts.res")
	var scene_stats := _write_scene()
	_write_json()
	_ensure_in_map()
	var per_zone := {}
	var per_use := {}
	for lot in lots:
		per_zone[lot["zone"]] = int(per_zone.get(lot["zone"], 0)) + 1
		per_use[lot["use"]] = int(per_use.get(lot["use"], 0)) + 1
	print("DISTRICTS_ALLEES %d posee(s), %d sautee(s) | zones traitees %s" % [drives.size(), drive_skipped.size(), str(DRIVE_ZONES)])
	for s: Dictionary in drive_skipped:
		print("DISTRICTS_ALLEE_SAUTEE zone %-14s %-34s en (%.1f, %.1f) : %s" % [s["zone"], s["lot"], s["x"], s["z"], s["cause"]])
	print("DISTRICTS_ZONES %s" % per_zone)
	print("DISTRICTS_USES %s | refus %s" % [per_use, refused])
	print("DISTRICTS_BAKE %d bâtiments, %d modèles, %s en %.1f s" % [lots.size(), baked.size(), scene_stats, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0)


# --- occupation ---------------------------------------------------------------------------------------------------
func _build_mask() -> void:
	mask_w = ceili(Spec.PLAYABLE.size.x / GRID)
	mask_h = ceili(Spec.PLAYABLE.size.y / GRID)
	mask.resize(mask_w * mask_h)
	var inner := Spec.PLAYABLE.grow(-40.0)
	var downtown := Spec.DOWNTOWN.grow(30.0)
	for j in mask_h:
		for i in mask_w:
			var p := _cell_center(i, j)
			var blocked := not inner.has_point(p) or downtown.has_point(p) or model.is_excluded(p) or model.river_info(p).x < 14.0
			if not blocked:
				for lake: Dictionary in Spec.LAKES:
					if ((p - lake["center"]) / (lake["radii"] * 1.3 + Vector2(10.0, 10.0))).length() < 1.0:
						blocked = true
						break
			if not blocked:
				for poi: Dictionary in Spec.POIS:
					var half: Vector2 = poi["size"] * 0.5 + Vector2(25.0, 25.0)
					var d: Vector2 = p - poi["pos"]
					if absf(d.x) < half.x and absf(d.y) < half.y:
						blocked = true
						break
			if blocked:
				mask[j * mask_w + i] = 1
	for rb in net.ribbons:
		var margin := ROAD_MARGIN if rb.kind in ["arterial", "sidewalk"] else HIGHWAY_MARGIN
		var pts: PackedVector3Array = rb.points
		for k in pts.size():
			_stamp_disc(Vector2(pts[k].x, pts[k].z), float(rb.width) * 0.5 + margin)
	for pad: Dictionary in net.pads:
		var c: Vector3 = pad["center"]
		var radius := 0.0
		for p: Vector3 in pad["rim"]:
			radius = maxf(radius, Vector2(p.x - c.x, p.z - c.z).length())
		_stamp_disc(Vector2(c.x, c.z), radius + 4.0)
	var rail := PackedVector2Array(Spec.RAIL)
	for k in rail.size() - 1:
		var n := maxi(1, ceili(rail[k].distance_to(rail[k + 1]) / 4.0))
		for s in n + 1:
			_stamp_disc(rail[k].lerp(rail[k + 1], float(s) / n), 12.0)


func _cell_center(i: int, j: int) -> Vector2:
	return Spec.PLAYABLE.position + Vector2(i + 0.5, j + 0.5) * GRID


func _stamp_disc(p: Vector2, radius: float) -> void:
	var c := (p - Spec.PLAYABLE.position) / GRID
	var r := radius / GRID
	for j in range(maxi(0, floori(c.y - r)), mini(mask_h - 1, ceili(c.y + r)) + 1):
		for i in range(maxi(0, floori(c.x - r)), mini(mask_w - 1, ceili(c.x + r)) + 1):
			if Vector2(i + 0.5, j + 0.5).distance_squared_to(c) <= r * r:
				mask[j * mask_w + i] = 1


# --- lots -----------------------------------------------------------------------------------------------------------
# Lots le long d'une polyligne, côté side_sign, à partir de `offset` m de l'axe, façade vers la polyligne.
# `hard_gap` : distance entre cette ligne de référence et le vrai bord dur, reportée sur chaque lot pour que son
# allée d'accès aille jusqu'au bord et pas jusqu'à la ligne de référence.
func _frontage(points: PackedVector3Array, side_sign: float, offset: float, groups: Array, gap_scale: float, poly: PackedVector2Array,
		zone: Dictionary, rng: RandomNumberGenerator, end_margin: float, hard_gap := 0.0) -> void:
	_front_extra = hard_gap
	var line := PackedVector2Array()
	for p in points:
		line.append(Vector2(p.x, p.z))
	var total := Network.polyline_length(line)
	var s := end_margin + rng.randf_range(0.0, 10.0)
	var previous := ""
	while s < total - end_margin:
		var name := _pick(groups, rng)
		if name == previous:
			name = _pick(groups, rng)
		var entry: Dictionary = catalog[name]
		var use: String = entry["use"]
		var size := Vector3(float(entry["size"][0]), float(entry["size"][1]), float(entry["size"][2]))
		var mid := s + size.x * 0.5
		if mid >= total - end_margin:
			break
		var at := _point_at(line, points, mid)
		var dir: Vector2 = at["dir"]
		var normal := Vector2(-dir.y, dir.x) * side_sign
		var center: Vector2 = at["point"] + normal * (offset + float(SETBACK[use]) + size.z * 0.5)
		if _try_lot(center, -normal, entry, size, poly, zone, float(at["y"])):
			s += size.x + float(LOT_GAP[use]) * gap_scale
			previous = name
		else:
			s += 6.0


func _pick(groups: Array, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for g: Array in groups:
		total += float(g[1])
	var roll := rng.randf() * total
	var names: Array = groups[groups.size() - 1][0]
	for g: Array in groups:
		roll -= float(g[1])
		if roll <= 0.0:
			names = g[0]
			break
	return names[rng.randi() % names.size()]


static func _point_at(line: PackedVector2Array, points: PackedVector3Array, s: float) -> Dictionary:
	var walked := 0.0
	for k in line.size() - 1:
		var seg := line[k].distance_to(line[k + 1])
		if walked + seg >= s:
			var t := (s - walked) / maxf(seg, 0.001)
			return {"point": line[k].lerp(line[k + 1], t), "dir": (line[k + 1] - line[k]).normalized(), "y": lerpf(points[k].y, points[k + 1].y, t)}
		walked += seg
	var n := line.size()
	return {"point": line[n - 1], "dir": (line[n - 1] - line[n - 2]).normalized(), "y": points[n - 1].y}


func _try_lot(center: Vector2, front: Vector2, entry: Dictionary, size: Vector3, poly: PackedVector2Array, zone: Dictionary, road_y: float) -> bool:
	var right := Vector2(-front.y, front.x)
	var half := Vector2(size.x * 0.5 + 2.0, size.z * 0.5 + 2.0)
	var samples: Array[Vector2] = [center]
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			samples.append(center + right * half.x * sx + front * half.y * sz)
	for k in range(1, samples.size()):
		if not Geometry2D.is_point_in_polygon(samples[k], poly):
			refused["zone"] += 1
			return false
	if not _mask_free(center, right, front, half):
		refused["occupation"] += 1
		return false
	var lo := INF
	var hi := -INF
	var total := 0.0
	for q in samples:
		var h := _height(q)
		lo = minf(lo, h)
		hi = maxf(hi, h)
		total += h
	var use: String = entry["use"]
	var base := total / samples.size()
	if hi - lo > float(MAX_DROP[use]) or lo < Spec.WATER_LEVEL + 0.8:
		refused["pente"] += 1
		return false
	if absf(base - road_y) > ROAD_STEP:
		refused["route"] += 1
		return false
	_mask_mark(center, right, front, half + Vector2(2.0, 2.0))
	_flatten(center, right, front, Vector2(size.x * 0.5, size.z * 0.5), base)
	lots.append({"name": entry["name"], "use": use, "zone": zone["id"], "x": snappedf(center.x, 0.01), "z": snappedf(center.y, 0.01),
			"base": snappedf(base, 0.01), "yaw": snappedf(atan2(front.x, front.y), 0.0001), "size": [size.x, size.y, size.z], "tint": _tint(use),
			# portée d'allée : distance de la face avant au BORD DUR. Elle vaut SETBACK plus le décalage que
			# _frontage a mis entre sa ligne de référence et ce bord — 1 m d'accotement sur une artère non
			# urbaine, rien ailleurs. Sans ce terme l'allée s'arrêtait 1 m trop tôt et laissait de l'herbe.
			"reach": snappedf(float(SETBACK[use]) + _front_extra, 0.01),
			# hauteur de la ROUTE en face (celle du ruban, pas du terrain creusé à côté) : l'allée doit y monter,
			# sinon elle finit sur une marche. Mesuré avant correction : 0,33 m de marche en médiane, 0,50 m au pire.
			"road_y": snappedf(road_y, 0.01)})
	return true


# Teinte par bâtiment (multipliée aux couleurs de sommet) : luminosité et nuance chaude ou froide, plus marquées sur
# les maisons, pour que deux modèles identiques voisins ne se ressemblent pas.
func _tint(use: String) -> Array:
	var light := tint_rng.randf_range(0.86, 1.06) if use == "house" else tint_rng.randf_range(0.92, 1.04)
	var shade := tint_rng.randf_range(-0.04, 0.04) if use == "house" else 0.0
	return [snappedf(light * (1.0 + shade), 0.001), snappedf(light, 0.001), snappedf(light * (1.0 - shade), 0.001)]


# Maisons autour du plateau de demi-tour d'une rue locale : dans l'axe de la rue et de part et d'autre, façade vers le
# centre du plateau.
func _cul_de_sac(rb, groups: Array, poly: PackedVector2Array, zone: Dictionary, rng: RandomNumberGenerator) -> void:
	_front_extra = 0.0                       # le bulbe est sa propre reference : pas d'accotement a rattraper
	var pts: PackedVector3Array = rb.points
	var n := pts.size()
	var tip := Vector2(pts[n - 1].x, pts[n - 1].z)
	var dir := (tip - Vector2(pts[n - 2].x, pts[n - 2].z)).normalized()
	for angle: float in [0.0, -1.15, 1.15]:
		var entry: Dictionary = catalog[_pick(groups, rng)]
		var size := Vector3(float(entry["size"][0]), float(entry["size"][1]), float(entry["size"][2]))
		var out := dir.rotated(angle)
		var center := tip + out * (float(rb.width) * 0.5 + 5.0 + 9.0 + size.z * 0.5)
		_try_lot(center, -out, entry, size, poly, zone, pts[n - 1].y)


# Cellules de la grille d'occupation dont le centre tombe dans le rectangle orienté (élargi d'une demi-cellule).
func _rect_cells(center: Vector2, right: Vector2, front: Vector2, half: Vector2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var c := (center - Spec.PLAYABLE.position) / GRID
	var r := half.length() / GRID + 1.0
	for j in range(floori(c.y - r), ceili(c.y + r) + 1):
		for i in range(floori(c.x - r), ceili(c.x + r) + 1):
			var d := _cell_center(i, j) - center
			if absf(d.dot(right)) <= half.x + GRID * 0.5 and absf(d.dot(front)) <= half.y + GRID * 0.5:
				out.append(Vector2i(i, j))
	return out


func _mask_free(center: Vector2, right: Vector2, front: Vector2, half: Vector2) -> bool:
	for cell in _rect_cells(center, right, front, half):
		if cell.x < 0 or cell.y < 0 or cell.x >= mask_w or cell.y >= mask_h or mask[cell.y * mask_w + cell.x] != 0:
			return false
	return true


func _mask_mark(center: Vector2, right: Vector2, front: Vector2, half: Vector2) -> void:
	for cell in _rect_cells(center, right, front, half):
		if cell.x >= 0 and cell.y >= 0 and cell.x < mask_w and cell.y < mask_h and mask[cell.y * mask_w + cell.x] == 0:
			mask[cell.y * mask_w + cell.x] = 2


func _height(p: Vector2) -> float:
	var fx := (p.x - Spec.TERRAIN.position.x) / Model.CELL
	var fz := (p.y - Spec.TERRAIN.position.y) / Model.CELL
	var i := clampi(floori(fx), 0, model.width - 2)
	var j := clampi(floori(fz), 0, model.depth - 2)
	var tx := clampf(fx - i, 0.0, 1.0)
	var tz := clampf(fz - j, 0.0, 1.0)
	var w := model.width
	return lerpf(lerpf(heights[j * w + i], heights[j * w + i + 1], tx), lerpf(heights[(j + 1) * w + i], heights[(j + 1) * w + i + 1], tx), tz)


# Terrain au niveau du lot sous l'emprise (+1,5 m), raccordé sur BLEND m ; routes et emprises voisines intactes.
func _flatten(center: Vector2, right: Vector2, front: Vector2, half: Vector2, base: float) -> void:
	var origin := Spec.TERRAIN.position
	var c := (center - origin) / Model.CELL
	var r := (half.length() + BLEND + 2.0) / Model.CELL
	var footprint := PackedInt32Array()
	for j in range(maxi(0, floori(c.y - r)), mini(model.depth - 1, ceili(c.y + r)) + 1):
		for i in range(maxi(0, floori(c.x - r)), mini(model.width - 1, ceili(c.x + r)) + 1):
			var idx := j * model.width + i
			if locked[idx] != 0:
				continue
			var p := origin + Vector2(i, j) * Model.CELL
			if model.is_excluded(p):
				continue
			var d := p - center
			var outside := Vector2(maxf(0.0, absf(d.dot(right)) - half.x - 1.5), maxf(0.0, absf(d.dot(front)) - half.y - 1.5)).length()
			if outside >= BLEND:
				continue
			if outside > 0.0:
				var mi := _mask_index(p)
				if mi < 0 or mask[mi] == 1:
					continue
			heights[idx] = lerpf(base - 0.05, heights[idx], smoothstep(0.0, BLEND, outside))
			if outside == 0.0:
				footprint.append(idx)
	for idx in footprint:
		locked[idx] = 1


# --- allées d'accès ---------------------------------------------------------------------------------------------

# Une allée droite de la face avant du bâtiment jusqu'à DRIVE_STOP du bord dur. Posée APRÈS tous les lots, pour
# pouvoir écarter celles qu'un autre bâtiment barre, et AVANT l'écriture de heights.res, pour que le terrain
# aplani parte dans la cuisson du terrain.
func _driveways() -> void:
	for k in lots.size():
		var lot: Dictionary = lots[k]
		if not DRIVE_ZONES.is_empty() and not (String(lot["zone"]) in DRIVE_ZONES):
			continue
		var use := String(lot["use"])
		var yaw := float(lot["yaw"])
		var front := Vector2(sin(yaw), cos(yaw))       # du lot VERS la route, cf. _try_lot
		var right := Vector2(-front.y, front.x)
		var centre := Vector2(float(lot["x"]), float(lot["z"]))
		var depart := centre + front * (float(lot["size"][2]) * 0.5)
		var longueur: float = float(lot.get("reach", SETBACK[use])) - DRIVE_STOP
		var largeur: float = float(DRIVE_WIDTH[use])
		if longueur <= 1.0:
			continue
		var milieu := depart + front * (longueur * 0.5)
		var barre := _drive_blocked(k, milieu, right, front, Vector2(largeur * 0.5, longueur * 0.5))
		if barre != "":
			drive_skipped.append({"x": centre.x, "z": centre.y, "zone": lot["zone"], "lot": lot["name"], "cause": barre})
			continue
		var y0 := float(lot["base"])
		var y1 := float(lot.get("road_y", _height(depart + front * longueur)))
		_flatten_ramp(depart, right, front, largeur * 0.5, longueur, y0, y1)
		drives.append({"x": depart.x, "z": depart.y, "yaw": yaw, "l": longueur, "w": largeur,
				"s": String(DRIVE_SURFACE[use]), "y0": y0, "y1": y1})
		lot["drive"] = [snappedf(longueur, 0.01), snappedf(largeur, 0.01)]


# Un autre bâtiment entre la façade et la route : on saute, on ne force pas.
func _drive_blocked(self_index: int, centre: Vector2, right: Vector2, front: Vector2, half: Vector2) -> String:
	for k in lots.size():
		if k == self_index:
			continue
		var other: Dictionary = lots[k]
		var oy := float(other["yaw"])
		var of := Vector2(sin(oy), cos(oy))
		var half_o := Vector2(float(other["size"][0]), float(other["size"][2])) * 0.5
		if _rect_overlap(centre, right, front, half, Vector2(float(other["x"]), float(other["z"])),
				Vector2(-of.y, of.x), of, half_o):
			return "%s" % other["name"]
	return ""


# Recouvrement de deux rectangles orientés, par axes séparateurs (les 4 axes des deux repères suffisent).
func _rect_overlap(ca: Vector2, ra: Vector2, fa: Vector2, ha: Vector2, cb: Vector2, rb: Vector2, fb: Vector2, hb: Vector2) -> bool:
	var d := cb - ca
	for axe: Vector2 in [ra, fa, rb, fb]:
		var ea := absf(ra.dot(axe)) * ha.x + absf(fa.dot(axe)) * ha.y
		var eb := absf(rb.dot(axe)) * hb.x + absf(fb.dot(axe)) * hb.y
		if absf(d.dot(axe)) > ea + eb:
			return false
	return true


# Terrain mis en rampe sous l'allée : la hauteur cible va de y0 (assiette du lot) à y1 (bord de la route), et se
# raccorde au terrain sur BLEND m. On ne verrouille RIEN : les cases déjà verrouillées par _flatten (l'emprise du
# lot) sont sautées, donc la jonction avec le bâtiment garde exactement son niveau.
func _flatten_ramp(depart: Vector2, right: Vector2, front: Vector2, half_w: float, longueur: float, y0: float, y1: float) -> void:
	var origin := Spec.TERRAIN.position
	var centre := depart + front * (longueur * 0.5)
	var half := Vector2(half_w, longueur * 0.5)
	var c := (centre - origin) / Model.CELL
	var r := (half.length() + BLEND + 2.0) / Model.CELL
	for j in range(maxi(0, floori(c.y - r)), mini(model.depth - 1, ceili(c.y + r)) + 1):
		for i in range(maxi(0, floori(c.x - r)), mini(model.width - 1, ceili(c.x + r)) + 1):
			var idx := j * model.width + i
			if locked[idx] != 0:
				continue
			var p := origin + Vector2(i, j) * Model.CELL
			if model.is_excluded(p):
				continue
			var d := p - centre
			var le := d.dot(front)
			var outside := Vector2(maxf(0.0, absf(d.dot(right)) - half.x - 0.5), maxf(0.0, absf(le) - half.y - 0.5)).length()
			if outside >= BLEND:
				continue
			if outside > 0.0:
				var mi := _mask_index(p)
				if mi < 0 or mask[mi] == 1:
					continue
			var cible := lerpf(y0, y1, clampf((le + half.y) / longueur, 0.0, 1.0)) - DRIVE_SINK
			heights[idx] = lerpf(cible, heights[idx], smoothstep(0.0, BLEND, outside))


# L'allée ÉPOUSE le terrain, en tronçons de DRIVE_SEG m, au lieu d'être une rampe droite d'un seul quad.
#
# Une rampe droite tenait tant que _flatten_ramp pouvait mettre le terrain à la même pente. Ce n'est pas le cas
# près de la route : les cases du couloir routier sont exclues de l'aplanissement, et le dernier mètre de dalle
# se retrouvait en l'air — mesuré sur les sommets cuits, jusqu'à 0,343 m au-dessus du sol. En relisant la hauteur
# du terrain tous les DRIVE_SEG m, la dalle reste à DRIVE_CLEAR du sol sur toute sa longueur, y compris là où
# l'aplanissement n'a pas pu passer.
const DRIVE_SEG := 2.0


func _drive_quad(st: SurfaceTool, d: Dictionary) -> void:
	var yaw := float(d["yaw"])
	var front := Vector3(sin(yaw), 0.0, cos(yaw))
	var right := Vector3(-front.z, 0.0, front.x)
	var l := float(d["l"])
	var hw := float(d["w"]) * 0.5
	var u: float = float(DRIVE_U.get(String(d["s"]), 0.2246))
	var depart := Vector2(float(d["x"]), float(d["z"]))
	var av := Vector2(front.x, front.z)
	var n_seg := maxi(1, ceili(l / DRIVE_SEG))
	for k in n_seg:
		var d0 := l * float(k) / n_seg
		var d1 := l * float(k + 1) / n_seg
		_drive_segment(st, depart, av, front, right, hw, d0, d1, u)


func _drive_segment(st: SurfaceTool, depart: Vector2, av: Vector2, front: Vector3, right: Vector3, hw: float,
		d0: float, d1: float, u: float) -> void:
	var y0 := _height(depart + av * d0) + DRIVE_CLEAR
	var y1 := _height(depart + av * d1) + DRIVE_CLEAR
	var a := Vector3(depart.x, y0, depart.y) + front * d0
	var b := Vector3(depart.x, y1, depart.y) + front * d1
	var coins := [a - right * hw, a + right * hw, b + right * hw, b - right * hw]
	var uvs := [Vector2(u, d0 / DRIVE_TEX), Vector2(u + 0.004, d0 / DRIVE_TEX),
			Vector2(u + 0.004, d1 / DRIVE_TEX), Vector2(u, d1 / DRIVE_TEX)]
	# même convention que PlacesBake._quad : on ordonne pour que la normale géométrique s'oppose à la normale voulue
	var geom: Vector3 = (coins[1] - coins[0]).cross(coins[2] - coins[0]) + (coins[2] - coins[0]).cross(coins[3] - coins[0])
	if geom.dot(Vector3.UP) >= 0.0:
		coins = [coins[0], coins[3], coins[2], coins[1]]
		uvs = [uvs[0], uvs[3], uvs[2], uvs[1]]
	for t: Array in [[0, 1, 2], [0, 2, 3]]:
		for n: int in t:
			st.set_normal(Vector3.UP)
			st.set_uv(uvs[n])
			st.add_vertex(coins[n])


func _mask_index(p: Vector2) -> int:
	var i := floori((p.x - Spec.PLAYABLE.position.x) / GRID)
	var j := floori((p.y - Spec.PLAYABLE.position.y) / GRID)
	if i < 0 or j < 0 or i >= mask_w or j >= mask_h:
		return -1
	return j * mask_w + i


# --- modèles ------------------------------------------------------------------------------------------------------
# Modèle fusionné (BuildingModels) ; forme de collision exacte pour les modèles ouverts (station-service).
func _baked_model(name: String) -> Dictionary:
	if baked.has(name):
		return baked[name]
	var source := models.get_model(name, name in TRIMESH_MODELS)
	baked[name] = {"mesh": source["mesh"], "aabb": source["aabb"], "triangles": source["triangles"], "shape": source["trimesh"]}
	return baked[name]


# --- scène ----------------------------------------------------------------------------------------------------------
func _write_scene() -> Dictionary:
	var root := Node3D.new()
	root.name = "Buildings"
	var cells := {}
	for lot in lots:
		var key := Vector2i(floori(float(lot["x"]) / GROUP), floori(float(lot["z"]) / GROUP))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(lot)
	var boxes := {}
	var keys := cells.keys()
	keys.sort()
	var stats := {"cellules": keys.size(), "boîtes": 0, "occulteurs": 0, "triangles": 0}
	for key: Vector2i in keys:
		var cell := Node3D.new()
		cell.name = "BuildingCell_%02d_%02d" % [key.x + 10, key.y + 10]
		root.add_child(cell)
		var field := Node3D.new()
		field.name = "Field"
		field.set_script(FIELD_SCRIPT)
		cell.add_child(field)
		var body := StaticBody3D.new()
		body.name = "Collision"
		cell.add_child(body)
		var meshes: Array[Mesh] = []
		var names: Array[String] = []
		var data: Array[PackedFloat32Array] = []
		var ranges := PackedFloat32Array()
		var bounds: Array[Rect2] = []
		for lot: Dictionary in cells[key]:
			var name: String = lot["name"]
			var info := _baked_model(name)
			var aabb: AABB = info["aabb"]
			var basis := Basis(Vector3.UP, float(lot["yaw"]))
			var center := Vector3(float(lot["x"]), float(lot["base"]), float(lot["z"]))
			# origine du modèle au niveau du sol (fondations sous l'origine), centre de l'emprise sur le centre du lot
			var origin := center - basis * Vector3(aabb.get_center().x, 0.0, aabb.get_center().z)
			var m := names.find(name)
			if m < 0:
				m = names.size()
				names.append(name)
				meshes.append(info["mesh"])
				data.append(PackedFloat32Array())
				ranges.append(float(RANGE[lot["use"]]))
				bounds.append(Rect2(Vector2(center.x, center.z), Vector2.ZERO))
			var buffer := data[m]
			var tint: Array = lot["tint"]
			buffer.append_array(PackedFloat32Array([basis.x.x, basis.x.y, basis.x.z, basis.y.x, basis.y.y, basis.y.z,
					basis.z.x, basis.z.y, basis.z.z, origin.x, origin.y, origin.z, tint[0], tint[1], tint[2], 1.0]))
			data[m] = buffer
			bounds[m] = bounds[m].expand(Vector2(center.x, center.z))
			stats["triangles"] += int(info["triangles"])
			var above := aabb.end.y
			var cs := CollisionShape3D.new()
			cs.name = "Shape_%d" % body.get_child_count()
			if info["shape"] != null:
				cs.shape = info["shape"]
				cs.transform = Transform3D(basis, origin)
			else:
				var size := Vector3(aabb.size.x, above, aabb.size.z)
				var shape_key := "%.2f_%.2f_%.2f" % [size.x, size.y, size.z]
				if not boxes.has(shape_key):
					var box := BoxShape3D.new()
					box.size = size
					boxes[shape_key] = box
				cs.shape = boxes[shape_key]
				cs.transform = Transform3D(basis, center + Vector3(0.0, above * 0.5, 0.0))
				stats["boîtes"] += 1
			body.add_child(cs)
			var family := name.get_slice("_", 1)
			if above >= OCCLUDER_MIN_HEIGHT and aabb.size.x * aabb.size.z >= OCCLUDER_MIN_AREA and family in OCCLUDER_FAMILIES:
				var occluder := OccluderInstance3D.new()
				occluder.name = "Occluder_%d" % cell.get_child_count()
				var shape := BoxOccluder3D.new()
				shape.size = Vector3(aabb.size.x * 0.8, above * 0.85, aabb.size.z * 0.8)
				occluder.occluder = shape
				occluder.transform = Transform3D(basis, center + Vector3(0.0, above * 0.425, 0.0))
				cell.add_child(occluder)
				stats["occulteurs"] += 1
		# portée mesurée jusqu'au centre de la boîte englobante des instances d'un modèle : marge = demi-diagonale
		for m in names.size():
			var model_aabb: AABB = baked[names[m]]["aabb"]
			ranges[m] += bounds[m].size.length() * 0.5 + Vector2(model_aabb.size.x, model_aabb.size.z).length() * 0.5 + 20.0
		field.set("meshes", meshes)
		field.set("instance_data", data)
		field.set("ranges", ranges)
		# allées de la cellule, fusionnées par matériau : un appel de dessin par matériau et par cellule
		var tools := {}
		for d: Dictionary in drives:
			if Vector2i(floori(float(d["x"]) / GROUP), floori(float(d["z"]) / GROUP)) != key:
				continue
			var mat: String = MAT_CONCRETE if String(d["s"]) == "beton" else MAT_ASPHALT
			if not tools.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[mat] = st
			_drive_quad(tools[mat], d)
			stats["allees"] = int(stats.get("allees", 0)) + 1
			stats["triangles"] += 2
		if not tools.is_empty():
			var mesh := ArrayMesh.new()
			for mat: String in tools:
				var st: SurfaceTool = tools[mat]
				st.set_material(load(mat))
				st.commit(mesh)
			var mi := MeshInstance3D.new()
			mi.name = "Allees"
			mi.mesh = mesh
			mi.visibility_range_end = DRIVE_RANGE
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cell.add_child(mi)
	_pack(root, SCENE)
	return stats


func _write_json() -> void:
	var f := FileAccess.open(OUT.path_join("lots.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(lots))
	f.close()
	# points de contrôle candidats (milieu de rue locale, face au fond de la rue) pour MapSpec.GATE_SPOTS
	var seen := {}
	for street: Dictionary in net.local_streets:
		if seen.has(street["zone"]):
			continue
		seen[street["zone"]] = true
		var pts: PackedVector3Array = street["ribbon"].points
		var a := pts[pts.size() / 2]
		var b := pts[pts.size() / 2 + 1]
		var dir := Vector2(b.x - a.x, b.z - a.z).normalized()
		print("DISTRICTS_SPOT %s : Vector2(%.1f, %.1f) yaw %.1f" % [street["id"], a.x, a.z, rad_to_deg(atan2(-dir.x, -dir.y))])


func _ensure_in_map() -> void:
	var text := FileAccess.get_file_as_string(MAP_SCENE)
	if text.contains(SCENE):
		return
	var last_ext := text.rfind("[ext_resource")
	var insert_at := text.find("\n", last_ext) + 1
	text = text.substr(0, insert_at) + '[ext_resource type="PackedScene" path="%s" id="5_buildings"]\n' % SCENE + text.substr(insert_at)
	text = text.strip_edges() + '\n\n[node name="Buildings" type="Node3D" parent="." unique_id=1812030455 instance=ExtResource("5_buildings")]\n'
	var f := FileAccess.open(MAP_SCENE, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("DISTRICTS_BAKE Map.tscn : Buildings ajoutée")


func _pack(root: Node, path: String) -> void:
	_own(root, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	print("DISTRICTS_SCENE %s : %s" % [path, error_string(err)])
	root.free()


func _own(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_own(child, root)
