extends SceneTree

# Étape 5 : lieux de la carte 3D (MapSpec.POIS) en extérieur, accessibles à pied et par la route :
#  - Prairie Wind International Airport : 2 pistes balisées, voies de circulation, aire de trafic, aérogare, tour de
#    contrôle, hangars, parking, clôture du côté piste, biplans ;
#  - Starlite Motor Inn (motel à coursive, bureau, parking, enseigne sur mât), Coyote Creek Ranch (maison, grange,
#    abri, éolienne, cour en terre, pâture clôturée, portique), Planque de Cedar Lane (chalet isolé), Greenfield
#    Botanicals (serres, entrepôt, parking, clôture), Echo Circle (monument sur l'îlot du rond-point) ;
#  - centre-ville (sans rien remplacer) : Ashford Grand Hotel, St. Anselm Medical Center et Central Precinct sur des
#    lots vides, parc de Liberty Motors, enseigne du Scarlet Jack sur le toit du pâté de maisons existant ;
#  - ancres nommées (Map/Places/Place_<id>, métadonnées place_id, display_name, kind) et
#    generated/places/places.json (ancres, entrées, emprises pour le fond de carte et les tests) ;
#  - terrain : generated/terrain/heights_districts.res aplani sous les surfaces et bâtiments hors centre-ville ->
#    heights.res (TerrainBake --from-heights ensuite).
# Façades tournées vers l'accès réel (route ou trottoir relevés), l'orientation de MapSpec.POIS n'est qu'indicative.
#
# Lancer après DistrictsBake : Godot --headless --path <projet> --script res://scenes/world/map/tools/PlacesBake.gd

const Spec := preload("res://scenes/world/map/MapSpec.gd")
const Model := preload("res://scenes/world/map/tools/TerrainModel.gd")
const Network := preload("res://scenes/world/map/tools/RoadNetwork.gd")
const BuildingModels := preload("res://scenes/world/map/tools/BuildingModels.gd")
const GEN := "res://scenes/world/map/generated"
const OUT := "res://scenes/world/map/generated/places"
const SCENE := "res://scenes/world/map/generated/Places.tscn"
const MAP_SCENE := "res://scenes/world/map/Map.tscn"
const PLANE := "res://assets/Fbx/Fbx/Air Plane_1.fbx"
const TEX_LENGTH := 12.0
const PLAIN_U := 0.2246                  # colonne « median » de roads.png : enrobé sans marquage
const DIRT_U := 0.6015
const LIP := 0.3                         # surfaces hors centre-ville : 0,3 m au-dessus du terrain, rebord
const DOWNTOWN_GROUND := -0.03           # sol des marges du centre-ville autour du réseau de rues (sous la marge générée, -0,05)
const DOWNTOWN_BLOCK := 0.2              # sol des îlots du centre-ville reconstruit (DowntownSpec : chaussée + trottoir)
const BLEND := 10.0
const WHITE := Color(0.93, 0.93, 0.9)
const YELLOW := Color(0.95, 0.72, 0.1)
const STONE := Color(0.78, 0.75, 0.68)
const STEEL := Color(0.35, 0.36, 0.37)
const WOOD := Color(0.42, 0.3, 0.2)
const GLASS := Color(0.22, 0.3, 0.36)


class Batch:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()


var model: Model
var net: Network
var models: BuildingModels
var heights := PackedFloat32Array()
var locked := PackedByteArray()
var road_buckets := {}
var mats := {}
var root_node: Node3D
var place: Node3D
var parts := {}
var faces := PackedVector3Array()
var body: StaticBody3D
var places: Array[Dictionary] = []
var footprints: Array = []
# Maillages de pack FBX déjà fusionnés et enregistrés, rangés par chemin de fichier : deux camions partagent un .res
var fbx_cache := {}
var stats := {"lieux": 0, "modèles": 0, "étiquettes": 0, "triangles": 0, "sommets_aplanis": 0}


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	model = Model.new()
	net = Network.new(model)
	net.build()
	if not net.errors.is_empty():
		print("PLACES_ERROR réseau routier en erreur")
		quit(1)
		return
	var source := GEN + "/terrain/heights_districts.res"
	if not ResourceLoader.exists(source):
		print("PLACES_ERROR %s absent : lancer DistrictsBake d'abord" % source)
		quit(1)
		return
	heights = (load(source) as Image).get_data().to_float32_array()
	models = BuildingModels.new()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_index_roads()
	mats = {"paint": models.material, "asphalt": load(GEN + "/roads/asphalt_material.tres"), "concrete": load(GEN + "/roads/concrete_material.tres"),
			"steel": load(GEN + "/roads/steel_material.tres")}
	root_node = Node3D.new()
	root_node.name = "Places"
	_airport()
	_motel()
	_ranch()
	_safehouse()
	_greenfield()
	_chantier()
	_echo_circle()
	_hotel()
	_hospital()
	_precinct()
	_liberty_lot()
	_casino()
	ResourceSaver.save(Image.create_from_data(model.width, model.depth, false, Image.FORMAT_RF, heights.to_byte_array()), GEN + "/terrain/heights.res")
	_pack(root_node, SCENE)
	var f := FileAccess.open(OUT.path_join("places.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"places": places, "footprints": footprints}, "\t"))
	f.close()
	_ensure_in_map()
	print("PLACES_BAKE %s en %.1f s" % [stats, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0)


# --- lieux hors centre-ville ------------------------------------------------------------------------------------
func _airport() -> void:
	var pad := _pad("n_air")
	var top: float = pad.y
	_begin("airport", Vector3(pad.x, top, pad.z))
	# pistes (09/27 principale au nord, secondaire au sud-est), voies de circulation, aire de trafic
	var ra := _runway(Vector2(590, -1350), 900.0, 45.0, top, "09", "27")
	var rb := _runway(Vector2(830, -1020), 420.0, 30.0, top, "", "")
	_paved(Vector2(590, -1300), Vector2(820, 18), top, "plain", YELLOW)
	for x: float in [180.0, 590.0, 1000.0]:
		_paved(Vector2(x, -1318.25), Vector2(18, 18.5), top, "plain", YELLOW, true)
	_paved(Vector2(660, -1163), Vector2(18, 256), top, "plain", YELLOW, true)
	_paved(Vector2(490, -1267.5), Vector2(320, 47), top, "concrete")
	_paved(Vector2(800, -1289.25), Vector2(240, 3.5), top, "concrete")
	footprints.append_array([ra, rb])
	# aérogare : façade côté ville face à la fin de l'artère, vitrage sur les deux grandes faces, auvent d'entrée
	var terminal := Vector3(470, top, -1229)
	_box("paint", terminal, Vector3(200, 12, 30), Color(0.82, 0.82, 0.8), true)
	for side: float in [-1.0, 1.0]:
		var z := terminal.z + side * 15.05
		_quad("paint", Vector3(372, top + 1.0, z), Vector3(568, top + 1.0, z), Vector3(568, top + 10.2, z), Vector3(372, top + 1.0 + 9.2, z), Vector3(0, 0, side), [], GLASS, false)
		for x in range(375, 570, 6):
			_quad("paint", Vector3(x - 0.15, top + 1.0, z + side * 0.02), Vector3(x + 0.15, top + 1.0, z + side * 0.02), Vector3(x + 0.15, top + 10.2, z + side * 0.02), Vector3(x - 0.15, top + 10.2, z + side * 0.02), Vector3(0, 0, side), [], Color(0.75, 0.76, 0.76), false)
	_box("paint", Vector3(470, top + 5.0, -1210), Vector3(60, 0.4, 8), Color(0.9, 0.9, 0.88), true)
	for x: float in [442.0, 470.0, 498.0]:
		_box("steel", Vector3(x, top, -1207), Vector3(0.35, 5.0, 0.35), STEEL, true)
	_label("PRAIRIE WIND INTERNATIONAL AIRPORT", Vector3(470, top + 8.3, -1213.8), 0.0, 0.028, Color(0.95, 0.95, 0.95), 1500.0)
	_label("PRAIRIE WIND", Vector3(470, top + 8.3, -1244.2), PI, 0.035, Color(0.95, 0.95, 0.95), 1500.0)
	footprints.append(_rect_footprint("building", Vector2(470, -1229), Vector2(200, 30)))
	# tour de contrôle
	var tower := Vector3(620, top, -1205)
	_box("paint", tower, Vector3(14, 6, 14), Color(0.8, 0.8, 0.78), true)
	_box("paint", tower + Vector3(0, 6, 0), Vector3(5, 28, 5), Color(0.86, 0.86, 0.84), true)
	_box("paint", tower + Vector3(0, 34, 0), Vector3(11, 6, 11), GLASS, true)
	_box("paint", tower + Vector3(0, 40, 0), Vector3(12, 0.8, 12), Color(0.7, 0.7, 0.7), true)
	_box("steel", tower + Vector3(2, 40.8, 2), Vector3(0.3, 6, 0.3), Color(0.8, 0.15, 0.1), false)
	footprints.append(_rect_footprint("building", Vector2(620, -1205), Vector2(14, 14)))
	# hangars face à la voie de circulation, biplans sur l'aire de trafic
	for x: float in [705.0, 750.0, 795.0, 840.0, 885.0]:
		_model("Industrial_Warehouse_alt02", Vector2(x, -1265), PI, top, 1.6)
		footprints.append(_rect_footprint("building", Vector2(x, -1265), Vector2(38, 38)))
	_prop(PLANE, Vector3(612, top, -1277), -PI * 0.5)
	_prop(PLANE, Vector3(630, top, -1256), -PI * 0.5)
	# parking de l'aérogare
	_parking(Vector2(537, -1173.5), Vector2(126, 47), top - 0.02, true)   # 2 cm sous le plateau de fin d'artère qu'il recoupe
	# clôture du côté piste, l'aérogare fait la limite
	_fence(PackedVector2Array([Vector2(370, -1214), Vector2(70, -1214), Vector2(70, -1372), Vector2(1070, -1372), Vector2(1070, -970),
			Vector2(640, -970), Vector2(640, -1214), Vector2(570, -1214)]), 2.4, STEEL, "chain")
	_sign_board("PRAIRIE WIND INTERNATIONAL AIRPORT", Vector2(330, -1176), -PI * 0.5, 9.0)
	_end("Prairie Wind International Airport", "airport")


func _motel() -> void:
	var pad := _pad("n_motel")
	var top: float = pad.y
	_begin("motel", pad)
	_parking(Vector2(-467, 575), Vector2(30, 46), top - 0.02, false)
	# motel à deux niveaux, chambres ouvertes sur une coursive côté parking (est)
	var base := Vector3(-490, top, 582)
	_flatten_rect(Vector2(base.x, base.z), Vector2(1, 0), Vector2(0, 1), Vector2(8, 34), top - LIP)
	_box("paint", base, Vector3(12, 7, 64), Color(0.93, 0.86, 0.72), true)
	_box("paint", base + Vector3(0, 7, 0), Vector3(13, 0.4, 65), Color(0.35, 0.3, 0.28), false)
	_box("paint", base + Vector3(7, 3.3, 0), Vector3(2, 0.3, 64), Color(0.7, 0.68, 0.64), true)
	for z in range(551, 615, 8):
		_box("paint", Vector3(-482.2, top, z), Vector3(0.25, 3.3, 0.25), Color(0.85, 0.85, 0.82), false)
	_box("steel", Vector3(-482.1, top + 4.5, 582), Vector3(0.08, 0.08, 64), Color(0.2, 0.3, 0.35), false)
	for floor_y: float in [0.0, 3.6]:
		for z in range(553, 613, 4):
			_quad("paint", Vector3(-483.98, top + floor_y + 0.1, z - 0.5), Vector3(-483.98, top + floor_y + 0.1, z + 0.5), Vector3(-483.98, top + floor_y + 2.2, z + 0.5), Vector3(-483.98, top + floor_y + 2.2, z - 0.5), Vector3(1, 0, 0), [], Color(0.12, 0.36, 0.42), false)
			_quad("paint", Vector3(-483.98, top + floor_y + 1.0, z + 0.9), Vector3(-483.98, top + floor_y + 1.0, z + 2.4), Vector3(-483.98, top + floor_y + 2.1, z + 2.4), Vector3(-483.98, top + floor_y + 2.1, z + 0.9), Vector3(1, 0, 0), [], Color(0.55, 0.7, 0.78), false)
	footprints.append(_rect_footprint("building", Vector2(-490, 582), Vector2(12, 64)))
	# bureau d'accueil et enseigne sur mât
	var office := Vector3(-468, top, 605)
	_flatten_rect(Vector2(office.x, office.z), Vector2(1, 0), Vector2(0, 1), Vector2(8, 7), top - LIP)
	_box("paint", office, Vector3(12, 4.5, 10), Color(0.95, 0.78, 0.72), true)
	_quad("paint", Vector3(-461.98, top + 0.8, 601), Vector3(-461.98, top + 0.8, 609), Vector3(-461.98, top + 3.6, 609), Vector3(-461.98, top + 3.6, 601), Vector3(1, 0, 0), [], GLASS, false)
	_label("OFFICE", Vector3(-461.9, top + 4.0, 605), PI * 0.5, 0.012, Color(0.95, 0.3, 0.3), 300.0)
	footprints.append(_rect_footprint("building", Vector2(-468, 605), Vector2(12, 10)))
	var sign_at := _free_spot(Vector2(-447, 547), 3.0)
	var ground := _height(sign_at)
	_box("steel", Vector3(sign_at.x, ground, sign_at.y), Vector3(0.35, 9.0, 0.35), STEEL, true)
	_box("paint", Vector3(sign_at.x, ground + 9.0, sign_at.y), Vector3(0.6, 3.2, 7.0), Color(0.08, 0.12, 0.3), false)
	for side: float in [-1.0, 1.0]:
		_label("STARLITE", Vector3(sign_at.x + side * 0.32, ground + 11.4, sign_at.y), PI * 0.5 * side, 0.02, Color(1.0, 0.85, 0.2), 500.0)
		_label("MOTOR INN", Vector3(sign_at.x + side * 0.32, ground + 10.0, sign_at.y), PI * 0.5 * side, 0.014, Color(0.95, 0.95, 0.95), 500.0)
	_end("Starlite Motor Inn", "motel")


func _ranch() -> void:
	var pad := _pad("n_ranch")
	var top: float = pad.y
	_begin("ranch", pad)
	_paved(Vector2(1712, -97.5), Vector2(44, 41), top - 0.02, "dirt")
	_model("Residential_LargeFamilyHome_alt04", Vector2(1688, -62), PI, top)
	_model("Farm_Barn", Vector2(1753, -95), -PI * 0.5, top)
	_model("Farm_GardenShed", Vector2(1729, -64), PI, top)
	var mill := Vector2(1797, -28)
	_model("Farm_MetalWindmill", mill, 0.0, _height(mill))
	footprints.append_array([_rect_footprint("building", Vector2(1688, -62), Vector2(18, 15)), _rect_footprint("building", Vector2(1753, -95), Vector2(19, 14))])
	_fence(PackedVector2Array([Vector2(1600, -160), Vector2(1840, -160), Vector2(1840, 40), Vector2(1600, 40), Vector2(1600, -160)]), 1.3, WOOD, "rail")
	# portique d'entrée au-dessus du chemin, là où il franchit la clôture
	var gate := _crossing(PackedVector2Array([Vector2(1600, -160), Vector2(1840, -160)]))
	if gate != Vector2.INF:
		var g := _height(gate) + 0.3
		for side: float in [-1.0, 1.0]:
			_box("paint", Vector3(gate.x + side * 4.5, g - 0.3, gate.y), Vector3(0.45, 6.2, 0.45), WOOD, true)
		_box("paint", Vector3(gate.x, g + 5.3, gate.y), Vector3(10.5, 0.6, 0.5), WOOD, false)
		for side: float in [-1.0, 1.0]:
			_label("COYOTE CREEK RANCH", Vector3(gate.x, g + 5.6, gate.y + side * 0.3), 0.0 if side > 0.0 else PI, 0.014, Color(0.95, 0.9, 0.75), 400.0)
	_end("Coyote Creek Ranch", "ranch")


func _safehouse() -> void:
	var pad := _pad("n_safe")
	var top: float = pad.y
	_begin("safehouse", pad)
	_paved(Vector2(647, -68.5), Vector2(14, 15), top - 0.02, "dirt")
	_model("Residential_LogCabin_alt01", Vector2(647, -50), PI, top)
	_model("Farm_GardenShed", Vector2(661, -50), -PI * 0.5, top)
	footprints.append(_rect_footprint("building", Vector2(647, -50), Vector2(10, 18)))
	var box_at := _free_spot(Vector2(640, -86), 2.0)
	var ground := _height(box_at)
	_box("paint", Vector3(box_at.x, ground, box_at.y), Vector3(0.12, 1.1, 0.12), WOOD, false)
	_box("steel", Vector3(box_at.x, ground + 1.1, box_at.y), Vector3(0.3, 0.25, 0.5), Color(0.2, 0.22, 0.25), false)
	_end("Planque de Cedar Lane", "safehouse")


func _greenfield() -> void:
	var pad := _pad("n_green")
	var top: float = pad.y
	_begin("greenfield", pad)
	_flatten_rect(Vector2(-480, -960), Vector2(1, 0), Vector2(0, 1), Vector2(60, 45), top - LIP)
	_parking(Vector2(-447.5, -924), Vector2(45, 24), top - 0.02, true)
	_model("Industrial_Warehouse_alt03", Vector2(-446, -962), 0.0, top)
	footprints.append(_rect_footprint("building", Vector2(-446, -962), Vector2(24, 24)))
	for x: float in [-530.0, -516.0, -502.0, -488.0]:
		_greenhouse(Vector3(x, top, -965), 9.0, 60.0)
		footprints.append(_rect_footprint("building", Vector2(x, -965), Vector2(9, 60)))
	_fence(PackedVector2Array([Vector2(-540, -940), Vector2(-540, -1005), Vector2(-420, -1005), Vector2(-420, -940), Vector2(-540, -940)]), 2.2, STEEL, "chain", INF, [Vector2(-447, -940)])
	_sign_board("GREENFIELD BOTANICALS", Vector2(-462, -911), 0.0, 5.0)
	_end("Greenfield Botanicals", "complex")


# Chantier de Northgate Rise : immeuble en cours de construction, grue, baraques de chantier, camions et matériaux du
# pack LowPoly-House-Construction-Site, à leur échelle d'origine (mesurée : camion 7,2 m, conteneur 8,4 m, grue 54 m de
# haut). Dernière parcelle libre de Midtown Nord, relevée sans aucun ruban ni bâtiment dans l'emprise : la rue passe à
# 53,7 m du centre, soit 14 m du portail, donc ni chaussée ni trottoir sous le chantier, et aucune voiture ni PNJ n'a
# de trajet qui le traverse. Grillage tout autour avec une seule ouverture, côté rue.
const CHANTIER := Vector2(-240, -1310)
const CHANTIER_TOP := 9.2                # plateforme : entre les 7,5 m du coin ouest et les 10,3 m du coin est
const CHANTIER_PACK := "res://assets/LowPoly-House-Construction-Site-By-Majadroid/fbx files/"


func _chantier() -> void:
	var gate := Vector2(CHANTIER.x - 40.0, CHANTIER.y + 10.0)
	_begin("chantier", Vector3(gate.x - 4.0, CHANTIER_TOP, gate.y))
	_flatten_rect(CHANTIER, Vector2(1, 0), Vector2(0, 1), Vector2(41, 41), CHANTIER_TOP - LIP)
	_paved(CHANTIER, Vector2(80, 80), CHANTIER_TOP - 0.02, "dirt")
	# piste d'accès jusqu'à la rue, arrêtée à 6 m de la chaussée pour ne rien poser dessus
	_paved(Vector2(gate.x - 7.0, gate.y), Vector2(14, 7), CHANTIER_TOP - 0.02, "dirt", Color(), false, 0.0)
	var shell := _fbx_model(CHANTIER_PACK + "Building.fbx", CHANTIER + Vector2(2, 0), 0.0, CHANTIER_TOP)
	footprints.append(_rect_footprint("building", CHANTIER + Vector2(2, 0), Vector2(shell.size.x, shell.size.z)))
	_fbx_model(CHANTIER_PACK + "Crane-On-Ground.fbx", CHANTIER + Vector2(-24, 26), -PI * 0.25, CHANTIER_TOP, "embase", Vector2(2.5, 2.5))
	_fbx_model(CHANTIER_PACK + "Containers-Office.fbx", CHANTIER + Vector2(-33, 4), PI * 0.5, CHANTIER_TOP)
	_fbx_model(CHANTIER_PACK + "Containers.fbx", CHANTIER + Vector2(-33, -14), 0.0, CHANTIER_TOP)
	_fbx_model(CHANTIER_PACK + "Containers-Cargo.fbx", CHANTIER + Vector2(-33, -24), 0.0, CHANTIER_TOP)
	_fbx_model(CHANTIER_PACK + "Construction-Materials.fbx", CHANTIER + Vector2(14, -32), 0.0, CHANTIER_TOP)
	_fbx_model(CHANTIER_PACK + "Construction-Materials.fbx", CHANTIER + Vector2(22, -32), 0.0, CHANTIER_TOP)
	_fbx_model(CHANTIER_PACK + "Trucks.fbx", CHANTIER + Vector2(-30, 20), PI * 0.5, CHANTIER_TOP)
	_fbx_model(CHANTIER_PACK + "Trucks.fbx", CHANTIER + Vector2(10, 33), PI, CHANTIER_TOP)
	_fbx_model(CHANTIER_PACK + "Ramp.fbx", CHANTIER + Vector2(30, 26), -PI * 0.5, CHANTIER_TOP, "aucune")
	var f := 40.0
	_fence(PackedVector2Array([CHANTIER + Vector2(-f, -f), CHANTIER + Vector2(f, -f), CHANTIER + Vector2(f, f),
			CHANTIER + Vector2(-f, f), CHANTIER + Vector2(-f, -f)]), 2.4, STEEL, "chain", CHANTIER_TOP, [gate])
	_sign_board("NORTHGATE RISE", Vector2(gate.x + 3.0, gate.y - 9.0), PI * 0.5, 4.5, CHANTIER_TOP)
	_end("Northgate Rise Construction Site", "construction")


func _echo_circle() -> void:
	var pad := _pad("r_echo")
	var top: float = pad.y + 0.25
	_begin("echo_circle", Vector3(pad.x, pad.y, pad.z + 32.0))   # entrée sur l'anneau, au sud de l'îlot
	var c := Vector3(pad.x, top, pad.z)
	_box("paint", c, Vector3(9, 0.5, 9), STONE, true)
	_box("paint", c + Vector3(0, 0.5, 0), Vector3(6.5, 0.5, 6.5), STONE.darkened(0.05), true)
	_box("paint", c + Vector3(0, 1.0, 0), Vector3(4, 0.6, 4), STONE, true)
	_obelisk(c + Vector3(0, 1.6, 0), 1.4, 0.7, 13.0)
	for k in 4:
		var yaw := PI * 0.5 * k
		var out := Vector3(sin(yaw), 0, cos(yaw))
		_label("ECHO CIRCLE", c + Vector3(0, 1.3, 0) + out * 2.03, yaw, 0.006, Color(0.25, 0.2, 0.12), 200.0)
	_end("Echo Circle", "plaza")


# --- centre-ville ---------------------------------------------------------------------------------------------------
func _hotel() -> void:
	var y := DOWNTOWN_GROUND
	_begin("hotel", Vector3(-902, 0.41, -424))
	_model("Industrial_TraditionalSkyscraper_alt05", Vector2(-929, -424), PI * 0.5, y)
	_box("paint", Vector3(-912.2, y, -424), Vector3(12.4, 7, 32), Color(0.72, 0.64, 0.52), true)
	_box("paint", Vector3(-912.2, y + 7, -424), Vector3(12.8, 0.5, 32.4), Color(0.5, 0.45, 0.38), false)
	_quad("paint", Vector3(-905.98, y + 0.3, -432), Vector3(-905.98, y + 0.3, -416), Vector3(-905.98, y + 3.4, -416), Vector3(-905.98, y + 3.4, -432), Vector3(1, 0, 0), [], GLASS, false)
	_box("paint", Vector3(-904.5, y + 3.6, -424), Vector3(3.0, 0.35, 10), Color(0.55, 0.12, 0.12), false)
	for z: float in [-428.5, -419.5]:
		_box("steel", Vector3(-903.4, y, z), Vector3(0.18, 3.6, 0.18), Color(0.75, 0.65, 0.3), false)
	_label("ASHFORD GRAND HOTEL", Vector3(-905.9, y + 5.2, -424), PI * 0.5, 0.012, Color(0.95, 0.85, 0.55), 400.0)
	_label("ASHFORD GRAND", Vector3(-918.2, y + 66.0, -424), PI * 0.5, 0.05, Color(0.95, 0.85, 0.55), 1500.0)
	footprints.append_array([_rect_footprint("building", Vector2(-929, -424), Vector2(21, 21)), _rect_footprint("building", Vector2(-912, -424), Vector2(12, 32))])
	_end("Ashford Grand Hotel", "hotel")


func _hospital() -> void:
	var y := DOWNTOWN_GROUND
	_begin("hospital", Vector3(-280, 0.41, 125))
	_model("Business_Hospital", Vector2(-280, 168), PI, y)
	_paved(Vector2(-280, 137), Vector2(50, 14), y + 0.05, "concrete", Color(), false, 0.0)
	for x: float in [-312.5, -247.5]:
		_parking(Vector2(x, 169), Vector2(13, 46), y + 0.05, false, 0.0)
	_sign_board("ST. ANSELM MEDICAL CENTER", Vector2(-310, 133), 0.0, 5.0, y)
	# Ambulances rangées sur le parvis, nez vers la rue, prêtes à sortir. Le parvis fait 50 x 14 m et la caisse
	# 6,16 x 2,48 m : elles tiennent dans la profondeur et sont espacées de 7 m. Relevé d'emprise : 1 870 cases
	# posables, sol plat à 0,02 m, à plus de 5 m de tout segment de CircuitPath et 2,5 m de tout segment de PedGraph.
	# Décalées vers l'est : le point de contrôle du garde-fou « parvis du St. Anselm Medical Center » est en
	# (-290, 137) et MapGateTest y fait marcher le joueur sur 10 m. Une ambulance à x -287 le bloquait au bout de
	# 1,4 m. Même règle que la végétation : rien à moins de 12 m d'un point de contrôle.
	for x: float in [-278.0, -271.0, -264.0]:
		_parked_vehicle(VEH + "Emergency/Veh_Ambulance.glb", Vector2(x, 137), PI, y + 0.05)
	_hospital_liaisons(y)
	footprints.append(_rect_footprint("building", Vector2(-280, 168), Vector2(48, 47)))
	_end("St. Anselm Medical Center", "hospital")


func _precinct() -> void:
	var y := DOWNTOWN_GROUND
	_begin("precinct", Vector3(-713, 0.41, 125))
	_model("Business_Bank", Vector2(-713, 158), PI, y)
	_paved(Vector2(-713, 136.25), Vector2(18, 18.5), y + 0.05, "concrete", Color(), false, 0.0)
	_parking(Vector2(-690.5, 165), Vector2(13, 36), y + 0.05, false, 0.0)
	# portail sur l'allée qui descend vers la rue : _fence ouvre 5 m de part et d'autre d'un point de portail
	_fence(PackedVector2Array([Vector2(-697, 147), Vector2(-684, 147), Vector2(-684, 183), Vector2(-697, 183)]), 2.2, STEEL, "chain", y, [Vector2(-690.5, 147)])
	if not AVANT:
		_precinct_liaisons(y)
	var pole := Vector3(-726, y, 141)
	_box("steel", pole, Vector3(0.16, 11, 0.16), Color(0.8, 0.8, 0.8), true)
	_quad("paint", pole + Vector3(0.1, 9.2, 0), pole + Vector3(2.5, 9.2, 0), pole + Vector3(2.5, 10.7, 0), pole + Vector3(0.1, 10.7, 0), Vector3(0, 0, -1), [], Color(0.12, 0.2, 0.5), false)
	_label("CENTRAL PRECINCT", Vector3(-713, y + 12.2, 145.4), PI, 0.02, Color(0.92, 0.92, 0.9), 500.0)
	_label("POLICE", Vector3(-713, y + 10.6, 145.4), PI, 0.016, Color(0.3, 0.45, 0.95), 500.0)
	# Voitures de patrouille dans la COUR CLÔTURÉE du commissariat (x -697 à -684, z 147 à 183), pas sur le parvis :
	# le parvis porte le point de contrôle « allée du Central Precinct » en (-713, 132) et il est trop petit
	# (18 x 18,5 m) pour garder les 12 m de dégagement exigés. La cour est de toute façon l'endroit où vivent des
	# voitures de police.
	#
	# DANS LES PLACES, et non en travers. _parking trace ici une rangée unique de traits de 5,2 m orientés selon X,
	# espacés de 2,8 m selon Z, centrés sur x -694,25 : une place fait donc 5,2 m de profondeur (x -696,85 à
	# -691,65) et 2,8 m de large (Z), et l'allée de manoeuvre est le reste, x -691,65 à -684. Une voiture posée à
	# x -690,5 avec un cap de 180° était couchée en long au milieu de l'allée, en travers des places.
	# Les traits tombent sur z = 148,5 + 2,8 k : les centres de place sont donc à 149,9 + 2,8 k.
	# Cap PI/2 : le nez des modèles est sur +Z, une rotation de +90° autour de Y l'envoie sur +X, vers l'allée.
	for z: float in ([153.0, 160.0, 167.0] if AVANT else [155.5, 158.3, 161.1]):
		var model := "Police/Veh_Police_SUV.glb" if z > (166.0 if AVANT else 160.0) else "Police/Veh_Police_Sedan.glb"
		if AVANT:
			_parked_vehicle(VEH + model, Vector2(-690.5, z), PI, y + 0.05)
		else:
			_parked_vehicle(VEH + model, Vector2(-694.25, z), PI * 0.5, y + 0.05)
	footprints.append(_rect_footprint("building", Vector2(-713, 158), Vector2(26, 25)))
	_end("Central Precinct", "police")


# --- liaisons bitumées : plus une seule bande d'herbe entre deux surfaces dures --------------------------------------
#
# Le parvis, le parking et la rue étaient trois dalles posées sur la pelouse de l'îlot. Mesuré au rayon, au pas de
# 0,25 m : la pelouse d'îlot est à -0,050 m, les dalles des lieux à +0,020 m, la chaussée à +0,050 m et le trottoir
# à +0,200 m. Les liaisons sont donc posées au MÊME dessus que les dalles existantes (y + 0,05) et avec le même
# revêtement, si bien qu'il n'y a aucune marche d'une dalle à l'autre : la seule marche est celle que les dalles
# existantes avaient déjà sur la pelouse, 7 cm.
# Chaque liaison mord de 0,5 m sur la dalle qu'elle rejoint, pour qu'aucune couture ne laisse passer un filet d'herbe.

func _precinct_liaisons(y: float) -> void:
	var top := y + 0.05
	# Un premier découpage en trois bandes (parvis -> trottoir, allée, cheminement) laissait un îlot d'herbe de
	# 10 x 10,5 m enclavé entre elles, c'est-à-dire exactement le défaut qu'on corrige. D'où ce découpage-ci, en
	# deux morceaux seulement :
	#  - le PARVIS s'étend du trottoir (z 125) jusqu'à la façade sud du bâtiment (z 145,5) et de x -722 à -694 ;
	#  - l'ALLÉE goudronnée occupe les 7 m restants à l'est, de la rue jusqu'à la cour (z 147,5), à l'est du
	#    bâtiment (dont la face est est à x -700), donc sans jamais passer dessous.
	# Les deux se touchent sur toute leur longueur en x -694 : aucune couture ne laisse passer un filet d'herbe.
	_paved(Vector2(-708, 135.25), Vector2(28, 20.5), top, "concrete", Color(), false, 0.0)
	_paved(Vector2(-690.5, 136.25), Vector2(7, 22.5), top, "plain", Color(), false, 0.0)
	# Coin entre l'allée et la face est du bâtiment, pour rejoindre le bord sud de la cour sans laisser de pointe
	# d'herbe entre les deux.
	_paved(Vector2(-697, 146.5), Vector2(6.0, 2.0), top, "concrete", Color(), false, 0.0)


func _hospital_liaisons(y: float) -> void:
	var top := y + 0.05
	# Parvis des ambulances (x -305..-255, z 130..144) -> trottoir (z 123..125) : il restait 4,5 m d'herbe, de
	# z 125,25 à 129,75. L'extension reprend la LARGEUR ENTIÈRE du parvis et pas seulement celle des ambulances :
	# une allée plus étroite aurait laissé de part et d'autre deux bandes d'herbe coincées entre le parvis et le
	# trottoir, c'est-à-dire le défaut qu'on corrige (leçon du parvis du commissariat).
	_paved(Vector2(-280, 127.5), Vector2(50, 5.0), top, "concrete", Color(), false, 0.0)
	# Parkings latéraux (x -319..-306 et -254..-241, z 146..192) -> parvis. Les deux liaisons passent au sud du
	# bâtiment (x -304..-256, z 144,5..191,5) sans le toucher, et mordent de 0,5 m sur le parvis. Le reste de la
	# pelouse latérale reste ouvert vers l'extérieur de l'îlot : il n'est enclavé nulle part.
	_paved(Vector2(-311.5, 142.0), Vector2(15.0, 8.0), top, "concrete", Color(), false, 0.0)
	_paved(Vector2(-248.75, 142.0), Vector2(15.5, 8.0), top, "concrete", Color(), false, 0.0)
	# Les parkings latéraux s'arrêtaient à 2 m des murs du bâtiment : il restait de chaque côté une lisière
	# d'herbe de 2 x 46 m le long de la façade, mesurée au balayage. Comblée jusqu'au mur.
	_paved(Vector2(-305, 169.0), Vector2(2.0, 46.0), top, "concrete", Color(), false, 0.0)
	# côté est, la lisière est prise 0,5 m sous le mur : posée pile sur la face (x -256), il restait au balayage
	# une case d'herbe d'épaisseur nulle entre les deux quads
	_paved(Vector2(-255.25, 169.0), Vector2(2.5, 46.0), top, "concrete", Color(), false, 0.0)
	_hospital_esplanade(top)


# Esplanade continue : plus un brin d'herbe entre le trottoir et les murs, sur toute la largeur du site.
#
# Limites mesurées au balayage : le trottoir court de z 123 à 125 sur toute la façade ; à l'ouest de x -319 et à
# l'est de x -241 la pelouse continue sur 40 m sans route ni bâtiment, l'emprise de l'hôpital est donc bornée par
# ses deux parkings, x -319 à -241. Le sol y est plat, pelouse à -0,050 m et dalles à +0,020 m : il n'y a rien à
# aplanir, et poser au même dessus que les dalles existantes ne crée aucune marche.
#
# Pour que 78 x 21 m ne fassent pas une nappe grise uniforme, l'esplanade est découpée en trois : deux parkings
# visiteurs en enrobé avec leurs places de part et d'autre, et au centre le parvis des ambulances en béton, tramé
# de joints de dallage et desservi par un passage piéton depuis le trottoir. Tout est en matériaux déjà présents.
func _hospital_esplanade(top: float) -> void:
	# Lisière de 0,5 m restée en herbe entre le bord nord du parvis (z 144) et la façade sud (z 144,5), sur les
	# 48 m du bâtiment. Relevée au balayage sur la ligne x = -280 : « pelouse de 144,25 à 144,25 ».
	_paved(Vector2(-280, 144.5), Vector2(50, 2.0), top, "concrete", Color(), false, 0.0)
	# Parkings visiteurs : ils remplacent les deux pelouses latérales, x -319..-305 et -255..-241, z 125..138.
	# Deux rangées de places chacun, ce qui donne une allée centrale et du marquage plutôt qu'un aplat.
	_parking(Vector2(-312, 131.5), Vector2(14, 13), top, true, 0.0)
	_parking(Vector2(-248, 131.5), Vector2(14, 13), top, true, 0.0)
	# Joints de dallage sur le béton central (x -305..-255, z 125..144), un ton plus sombre que la dalle.
	var joint := Color(0.62, 0.62, 0.6)
	for x: float in [-295.0, -285.0, -275.0, -265.0]:
		_stripe(Vector2(x, 134.5), Vector2(0, 1), 19.0, 0.10, top + 0.012, joint)
	for z: float in [131.0, 137.0]:
		_stripe(Vector2(-280, z), Vector2(1, 0), 50.0, 0.10, top + 0.012, joint)
	# Passage piéton du trottoir vers l'entrée, en face des portes (x -280).
	var b := -283.0
	while b <= -277.0:
		_stripe(Vector2(b, 127.5), Vector2(0, 1), 5.0, 0.55, top + 0.015, WHITE)
		b += 1.2


func _liberty_lot() -> void:
	var y := DOWNTOWN_GROUND
	_begin("liberty_lot", Vector3(-1, 0.41, -400))
	_parking(Vector2(17.5, -408), Vector2(27, 70), y + 0.05, true, 0.0)
	var office := Vector3(22, y + 0.05, -364)
	_box("paint", office, Vector3(14, 4, 8), Color(0.82, 0.86, 0.9), true)
	_quad("paint", Vector3(15, y + 1.0, -368.02), Vector3(29, y + 1.0, -368.02), Vector3(29, y + 3.2, -368.02), Vector3(15, y + 3.2, -368.02), Vector3(0, 0, -1), [], GLASS, false)
	_label("LIBERTY MOTORS", Vector3(22, y + 4.9, -368.1), PI, 0.012, Color(0.85, 0.12, 0.12), 400.0)
	var pole := Vector3(2, y, -408)
	_box("steel", pole, Vector3(0.45, 10, 0.45), STEEL, true)
	_box("paint", pole + Vector3(0, 10, 0), Vector3(0.6, 2.4, 7.0), Color(0.1, 0.18, 0.45), false)
	for side: float in [-1.0, 1.0]:
		_label("LIBERTY MOTORS", pole + Vector3(side * 0.32, 11.2, 0), PI * 0.5 * side, 0.016, Color(0.95, 0.95, 0.95), 600.0)
	footprints.append(_rect_footprint("building", Vector2(22, -364), Vector2(14, 8)))
	_end("Liberty Motors", "car_lot")


# Scarlet Jack : immeuble large sur son îlot du centre-ville reconstruit, façade sur Jackson Avenue, marquise rouge et
# enseigne de façade au-dessus de l'entrée, panneau double face sur le toit.
const CASINO_MODEL := "Industrial_WideOfficeBuilding_alt02"
const CASINO_CENTER := Vector2(-570, -338.7)

func _casino() -> void:
	var y := DOWNTOWN_BLOCK
	_begin("casino", Vector3(CASINO_CENTER.x, y, -325.0))
	_model(CASINO_MODEL, CASINO_CENTER, 0.0, y)
	var front := CASINO_CENTER.y + (models.get_model(CASINO_MODEL)["aabb"] as AABB).size.z * 0.5
	_box("paint", Vector3(CASINO_CENTER.x, y + 3.6, front + 1.4), Vector3(18, 0.4, 2.8), Color(0.55, 0.05, 0.08), false)
	for x: float in [-8.5, 8.5]:
		_box("steel", Vector3(CASINO_CENTER.x + x, y, front + 2.6), Vector3(0.2, 3.6, 0.2), Color(0.8, 0.65, 0.3), false)
	_label("SCARLET JACK", Vector3(CASINO_CENTER.x, y + 6.4, front + 0.06), 0.0, 0.022, Color(1.0, 0.12, 0.1), 700.0)
	var c := Vector3(CASINO_CENTER.x, y + (models.get_model(CASINO_MODEL)["aabb"] as AABB).end.y, CASINO_CENTER.y)
	for x: float in [-6.0, 6.0]:
		_box("steel", c + Vector3(x, 0, 0), Vector3(0.3, 6.5, 0.3), STEEL, false)
	_box("paint", c + Vector3(0, 2.0, 0), Vector3(15, 4.6, 0.5), Color(0.1, 0.02, 0.03), false)
	for side: float in [-1.0, 1.0]:
		_label("SCARLET JACK", c + Vector3(0, 5.0, side * 0.27), 0.0 if side > 0.0 else PI, 0.03, Color(1.0, 0.12, 0.1), 1200.0)
		_label("CABARET & CASINO", c + Vector3(0, 3.1, side * 0.27), 0.0 if side > 0.0 else PI, 0.018, Color(1.0, 0.8, 0.35), 900.0)
	var aabb: AABB = models.get_model(CASINO_MODEL)["aabb"]
	footprints.append(_rect_footprint("building", CASINO_CENTER, Vector2(aabb.size.x, aabb.size.z)))
	_end("Scarlet Jack Cabaret & Casino", "casino")


# --- éléments -------------------------------------------------------------------------------------------------------
func _pad(node_id: String) -> Vector3:
	for pad: Dictionary in net.pads:
		if String(pad["id"]) == node_id:
			return pad["center"]
	var p := Spec.node_pos(node_id)
	return Vector3(p.x, _height(p) + 0.3, p.y)


# Piste : surface, bords, axe en tirets, seuils, zones de toucher, numéros couchés ; emprise pour le fond de carte.
func _runway(center: Vector2, length: float, width: float, top: float, west_number: String, east_number: String) -> Dictionary:
	_paved(center, Vector2(length, width), top, "plain")
	var half := length * 0.5
	var y := top + 0.015
	for side: float in [-1.0, 1.0]:
		_stripe(Vector2(center.x, center.y + side * (width * 0.5 - 1.2)), Vector2(1, 0), length - 4.0, 0.9, y, WHITE)
	var x := center.x - half + 60.0
	while x < center.x + half - 90.0:
		_stripe(Vector2(x + 15.0, center.y), Vector2(1, 0), 30.0, 0.9, y, WHITE)
		x += 50.0
	for end_sign: float in [-1.0, 1.0]:
		var edge := center.x + end_sign * (half - 21.0)
		var bars := int(width / 7.5)
		for k in bars:
			var offset := (k - (bars - 1) * 0.5) * 3.6
			if absf(offset) < 2.0:
				continue
			_stripe(Vector2(edge, center.y + offset), Vector2(1, 0), 30.0, 1.8, y, WHITE)
		if width >= 40.0:
			for dz: float in [-9.0, 9.0]:
				_stripe(Vector2(center.x + end_sign * (half - 300.0), center.y + dz), Vector2(1, 0), 22.0, 3.0, y, WHITE)
	if west_number != "":
		_flat_label(west_number, Vector3(center.x - half + 60.0, y + 0.01, center.y), -PI * 0.5)
		_flat_label(east_number, Vector3(center.x + half - 60.0, y + 0.01, center.y), PI * 0.5)
	return _rect_footprint("runway", center, Vector2(length, width))


# Surface pavée rectangulaire (axes du monde) : dessus, rebord de 0,3 m hors centre-ville, terrain aplani dessous.
func _paved(center: Vector2, size: Vector2, top: float, surface: String, line_color := Color(), center_line := false, lip := LIP) -> void:
	var h := size * 0.5
	var a := Vector3(center.x - h.x, top, center.y - h.y)
	var b := Vector3(center.x + h.x, top, center.y - h.y)
	var c := Vector3(center.x + h.x, top, center.y + h.y)
	var d := Vector3(center.x - h.x, top, center.y + h.y)
	match surface:
		"concrete":
			_quad("concrete", a, b, c, d, Vector3.UP)
		_:
			var u := DIRT_U if surface == "dirt" else PLAIN_U
			_quad("asphalt", a, b, c, d, Vector3.UP, [Vector2(u, a.z / TEX_LENGTH), Vector2(u + 0.004, b.z / TEX_LENGTH), Vector2(u + 0.004, c.z / TEX_LENGTH), Vector2(u, d.z / TEX_LENGTH)])
	if lip > 0.0:
		for edge: Array in [[a, b, Vector3(0, 0, -1)], [b, c, Vector3(1, 0, 0)], [c, d, Vector3(0, 0, 1)], [d, a, Vector3(-1, 0, 0)]]:
			var e1: Vector3 = edge[0]
			var e2: Vector3 = edge[1]
			_quad("concrete", e1, e2, e2 - Vector3(0, lip + 0.1, 0), e1 - Vector3(0, lip + 0.1, 0), edge[2])
		_flatten_rect(center, Vector2(1, 0), Vector2(0, 1), h + Vector2(0.5, 0.5), top - lip)
	if line_color != Color():
		var along := Vector2(1, 0) if size.x >= size.y else Vector2(0, 1)
		_stripe(center, along, maxf(size.x, size.y) - 2.0, 0.3, top + 0.015, line_color)
	footprints.append(_rect_footprint("paved", center, size))


# Parking : surface pavée et places perpendiculaires au grand côté, en une rangée (côté -travers) ou deux.
func _parking(center: Vector2, size: Vector2, top: float, two_rows := true, lip := LIP) -> void:
	_paved(center, size, top, "plain", Color(), false, lip)
	var along := Vector2(1, 0) if size.x >= size.y else Vector2(0, 1)
	var across := Vector2(0, 1) if size.x >= size.y else Vector2(1, 0)
	var length := absf(size.dot(along))
	var depth := absf(size.dot(across))
	var rows: Array[float] = [-1.0]
	if two_rows:
		rows.append(1.0)
	for row: float in rows:
		var line_center := center + across * row * (depth * 0.5 - 2.75)
		var s := -length * 0.5 + 1.5
		while s <= length * 0.5 - 1.5:
			_stripe(line_center + along * s, across, 5.2, 0.12, top + 0.015, WHITE)
			s += 2.8


func _stripe(center: Vector2, dir: Vector2, length: float, width: float, y: float, color: Color) -> void:
	var u := dir.normalized() * length * 0.5
	var v := Vector2(-dir.y, dir.x).normalized() * width * 0.5
	_quad("paint", Vector3(center.x - u.x - v.x, y, center.y - u.y - v.y), Vector3(center.x + u.x - v.x, y, center.y + u.y - v.y),
			Vector3(center.x + u.x + v.x, y, center.y + u.y + v.y), Vector3(center.x - u.x + v.x, y, center.y - u.y + v.y), Vector3.UP, [], color, false)


# Boîte posée (centre de la base), faces verticales et dessus ; collision en boîte si demandé.
func _box(part: String, base: Vector3, size: Vector3, color: Color, collide: bool, basis := Basis.IDENTITY) -> void:
	var hx := basis.x * size.x * 0.5
	var hz := basis.z * size.z * 0.5
	var up := Vector3(0, size.y, 0)
	var corners := [base - hx - hz, base + hx - hz, base + hx + hz, base - hx + hz]
	for k in 4:
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[(k + 1) % 4]
		var out := (a + b) * 0.5 - base
		_quad(part, a, b, b + up, a + up, Vector3(out.x, 0, out.z).normalized(), [], color, false)
	_quad(part, corners[0] + up, corners[1] + up, corners[2] + up, corners[3] + up, Vector3.UP, [], color, false)
	if collide:
		var cs := CollisionShape3D.new()
		cs.name = "Box_%d" % body.get_child_count()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		cs.transform = Transform3D(basis, base + Vector3(0, size.y * 0.5, 0))
		body.add_child(cs)


func _obelisk(base: Vector3, bottom: float, top_width: float, height: float) -> void:
	var b := bottom * 0.5
	var t := top_width * 0.5
	var lo := [Vector3(-b, 0, -b), Vector3(b, 0, -b), Vector3(b, 0, b), Vector3(-b, 0, b)]
	var hi := [Vector3(-t, height, -t), Vector3(t, height, -t), Vector3(t, height, t), Vector3(-t, height, t)]
	var apex := base + Vector3(0, height + t * 2.2, 0)
	for k in 4:
		var n := (k + 1) % 4
		var mid: Vector3 = (lo[k] + lo[n]) * 0.5
		_quad("paint", base + lo[k], base + lo[n], base + hi[n], base + hi[k], Vector3(mid.x, 0, mid.z).normalized(), [], STONE, false)
		_quad("paint", base + hi[k], base + hi[n], apex, apex, Vector3(mid.x, 0.5, mid.z).normalized(), [], STONE.lightened(0.05), false)
	var cs := CollisionShape3D.new()
	cs.name = "Obelisk"
	var shape := BoxShape3D.new()
	shape.size = Vector3(bottom, height, bottom)
	cs.shape = shape
	cs.position = base + Vector3(0, height * 0.5, 0)
	body.add_child(cs)


# Serre : soubassement, parois et toit à deux pans vitrés, pignons, arceaux blancs tous les 3 m.
func _greenhouse(base: Vector3, width: float, length: float) -> void:
	var w := width * 0.5
	var l := length * 0.5
	var wall := 3.2
	var ridge := 5.0
	var glass := Color(0.7, 0.83, 0.8)
	_box("paint", base, Vector3(width, 0.8, length), Color(0.72, 0.72, 0.7), false)
	for side: float in [-1.0, 1.0]:
		var x := base.x + side * w
		_quad("paint", Vector3(x, base.y + 0.8, base.z - l), Vector3(x, base.y + 0.8, base.z + l), Vector3(x, base.y + wall, base.z + l), Vector3(x, base.y + wall, base.z - l), Vector3(side, 0, 0), [], glass, false)
		_quad("paint", Vector3(x, base.y + wall, base.z - l), Vector3(x, base.y + wall, base.z + l), Vector3(base.x, base.y + ridge, base.z + l), Vector3(base.x, base.y + ridge, base.z - l), Vector3(side, 1.6, 0).normalized(), [], glass.lightened(0.08), false)
	for end_sign: float in [-1.0, 1.0]:
		var z := base.z + end_sign * l
		_quad("paint", Vector3(base.x - w, base.y + 0.8, z), Vector3(base.x + w, base.y + 0.8, z), Vector3(base.x + w, base.y + wall, z), Vector3(base.x - w, base.y + wall, z), Vector3(0, 0, end_sign), [], glass, false)
		_quad("paint", Vector3(base.x - w, base.y + wall, z), Vector3(base.x + w, base.y + wall, z), Vector3(base.x, base.y + ridge, z), Vector3(base.x, base.y + ridge, z), Vector3(0, 0, end_sign), [], glass, false)
	var s := -l
	while s <= l + 0.01:
		for side: float in [-1.0, 1.0]:
			var x := base.x + side * (w + 0.03)
			_quad("paint", Vector3(x, base.y + 0.8, base.z + s - 0.06), Vector3(x, base.y + 0.8, base.z + s + 0.06), Vector3(x, base.y + wall, base.z + s + 0.06), Vector3(x, base.y + wall, base.z + s - 0.06), Vector3(side, 0, 0), [], WHITE, false)
		s += 3.0
	var cs := CollisionShape3D.new()
	cs.name = "Greenhouse_%d" % body.get_child_count()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, wall, length)
	cs.shape = shape
	cs.position = base + Vector3(0, wall * 0.5, 0)
	body.add_child(cs)
	_flatten_rect(Vector2(base.x, base.z), Vector2(1, 0), Vector2(0, 1), Vector2(w + 1.0, l + 1.0), base.y - 0.1)


# Clôture le long d'une polyligne : poteaux tous les 3 m (grillage : fils et lisse ; ranch : deux lisses en bois),
# interrompue près des routes ; collision en panneaux minces. `ground_y` : sol imposé (centre-ville).
func _fence(line: PackedVector2Array, height: float, color: Color, style: String, ground_y := INF, gates: Array = []) -> void:
	var spacing := 3.0 if style == "chain" else 4.0
	for k in line.size() - 1:
		var a := line[k]
		var b := line[k + 1]
		var n := maxi(1, ceili(a.distance_to(b) / spacing))
		var run_start := -1
		for s in n + 1:
			var p := a.lerp(b, float(s) / n)
			var open := _near_road(p, 2.5)
			for gate: Vector2 in gates:
				open = open or p.distance_to(gate) < 5.0
			if not open:
				var g := _height(p) if ground_y == INF else ground_y
				_box("steel" if style == "chain" else "paint", Vector3(p.x, g - 0.3, p.y), Vector3(0.09, height + 0.3, 0.09) if style == "chain" else Vector3(0.16, height + 0.3, 0.16), color, false)
				if run_start < 0:
					run_start = s
			if (open or s == n) and run_start >= 0:
				var last := s - 1 if open else s
				if last > run_start:
					_fence_run(a.lerp(b, float(run_start) / n), a.lerp(b, float(last) / n), height, color, style, ground_y)
				run_start = -1


func _fence_run(a: Vector2, b: Vector2, height: float, color: Color, style: String, ground_y: float) -> void:
	var levels: Array[float] = [0.55, 1.1]
	if style == "chain":
		levels = [0.9, 1.7, height - 0.05]
	var steps := maxi(1, ceili(a.distance_to(b) / 8.0))
	for s in steps:
		var p1 := a.lerp(b, float(s) / steps)
		var p2 := a.lerp(b, float(s + 1) / steps)
		var g1 := _height(p1) if ground_y == INF else ground_y
		var g2 := _height(p2) if ground_y == INF else ground_y
		for lv: float in levels:
			var thick := 0.03 if style == "chain" else 0.1
			var dir := Vector3(p2.x - p1.x, 0, p2.y - p1.y).normalized()
			var side := Vector3(-dir.z, 0, dir.x) * thick
			var q1 := Vector3(p1.x, g1 + lv, p1.y)
			var q2 := Vector3(p2.x, g2 + lv, p2.y)
			_quad("steel" if style == "chain" else "paint", q1 + side, q2 + side, q2 - side, q1 - side, Vector3.UP, [], color, false)
			_quad("steel" if style == "chain" else "paint", q1 + side, q2 + side, q2 + side + Vector3(0, -thick * 2.0, 0), q1 + side + Vector3(0, -thick * 2.0, 0), side.normalized(), [], color, false)
	# collision : panneau mince de la hauteur de la clôture
	var mid := (a + b) * 0.5
	var cs := CollisionShape3D.new()
	cs.name = "Fence_%d" % body.get_child_count()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.12, height, a.distance_to(b))
	cs.shape = shape
	var g := (_height(a) + _height(b)) * 0.5 if ground_y == INF else ground_y
	var yaw := atan2(b.x - a.x, b.y - a.y)
	cs.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, g + height * 0.5, mid.y))
	body.add_child(cs)


# Panneau monument sur deux poteaux, face vers `yaw` (0 = +Z).
func _sign_board(text: String, at: Vector2, yaw: float, width: float, ground_y := INF) -> void:
	var p := _free_spot(at, width * 0.5 + 1.5)
	var g := _height(p) if ground_y == INF else ground_y
	var basis := Basis(Vector3.UP, yaw)
	for side: float in [-1.0, 1.0]:
		var post := Vector3(p.x, g, p.y) + basis.x * side * (width * 0.5 - 0.3)
		_box("paint", post, Vector3(0.25, 3.0, 0.25), Color(0.3, 0.28, 0.26), false)
	_box("paint", Vector3(p.x, g + 1.2, p.y), Vector3(width, 1.6, 0.35), Color(0.15, 0.3, 0.22), true, basis)
	# largeur du texte ≈ nombre de caractères × 0,6 corps : réduit pour tenir dans le panneau
	var pixel := minf(0.012, (width - 0.8) / (text.length() * 64.0 * 0.62))
	_label(text, Vector3(p.x, g + 2.0, p.y) + basis.z * 0.19, yaw, pixel, Color(0.95, 0.95, 0.9), 350.0)
	_label(text, Vector3(p.x, g + 2.0, p.y) - basis.z * 0.19, yaw + PI, pixel, Color(0.95, 0.95, 0.9), 350.0)


func _label(text: String, pos: Vector3, yaw: float, pixel_size: float, color: Color, range_end: float) -> void:
	var label := Label3D.new()
	label.name = "Label_%d" % place.get_child_count()
	label.text = text
	label.font_size = 64
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0, 0.6)
	label.shaded = false
	label.double_sided = false
	label.visibility_range_end = range_end
	label.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	place.add_child(label)
	stats["étiquettes"] += 1


# Numéro de piste couché sur la surface, lisible par un avion qui arrive dans le sens `yaw` (0 = +Z).
func _flat_label(text: String, pos: Vector3, yaw: float) -> void:
	var label := Label3D.new()
	label.name = "Runway_%s" % text
	label.text = text
	label.font_size = 256
	label.pixel_size = 0.06
	label.modulate = WHITE
	label.shaded = true
	label.visibility_range_end = 900.0
	label.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI * 0.5), pos)
	place.add_child(label)
	stats["étiquettes"] += 1


# Bâtiment du pack posé au sol (centre de l'emprise en `center`), façade vers `yaw`, collision en boîte.
func _model(name: String, center: Vector2, yaw: float, base_y: float, scale := 1.0) -> void:
	var info := models.get_model(name)
	var aabb: AABB = info["aabb"]
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
	var origin := Vector3(center.x, base_y, center.y) - basis * Vector3(aabb.get_center().x, 0.0, aabb.get_center().z)
	var mi := MeshInstance3D.new()
	mi.name = "%s_%d" % [name, place.get_child_count()]
	mi.mesh = info["mesh"]
	mi.transform = Transform3D(basis, origin)
	mi.visibility_range_end = 2500.0 if scale > 1.2 or aabb.size.y > 30.0 else 1200.0
	place.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.name = "Model_%d" % body.get_child_count()
	var shape := BoxShape3D.new()
	shape.size = Vector3(aabb.size.x, aabb.end.y, aabb.size.z) * scale
	cs.shape = shape
	cs.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(center.x, base_y + aabb.end.y * scale * 0.5, center.y))
	body.add_child(cs)
	_flatten_rect(center, Vector2(cos(yaw), -sin(yaw)), Vector2(sin(yaw), cos(yaw)), Vector2(aabb.size.x, aabb.size.z) * scale * 0.5 + Vector2(1, 1), base_y - 0.05)
	stats["modèles"] += 1
	stats["triangles"] += int(info["triangles"])


# Modèle d'un pack FBX hors catalogue EverythingLibrary (le catalogue ne couvre que ce pack-là). Les maillages de la
# scène importée sont FUSIONNÉS en un seul, enregistré en .res comme les surfaces des lieux, puis posés en un
# MeshInstance3D par exemplaire. Deux raisons mesurées le 2026-09-18 : sur une scène instanciée, _own() ne descend pas
# dans les enfants, donc tout réglage posé dessus est perdu à la cuisson (les distances de disparition ressortaient à 0,
# soit 47 maillages de chantier encore dessinés à 1,1 km) ; et le pack n'a qu'un matériau par fichier, donc la fusion ne
# coûte rien et un camion revient à un appel de dessin au lieu de six. La boîte est MESURÉE sur les maillages, le modèle
# est posé base au sol et centré sur `center`.
# `collide` : "boite" pour un volume plein (un bâtiment arrête un rayon, cf. MapPlacesTest), "embase" pour une grue
# dont seule la base est un obstacle (sinon son bras poserait un mur invisible de 40 m), "aucune" pour un décor plat.
func _fbx_model(path: String, center: Vector2, yaw: float, base_y: float, collide := "boite", base_half := Vector2(2.0, 2.0), scale := 1.0) -> AABB:
	if not fbx_cache.has(path):
		var packed := load(path) as PackedScene
		if packed == null:
			push_warning("PlacesBake : %s non importé" % path)
			return AABB()
		var inst := packed.instantiate() as Node3D
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var mat: Material = null
		var tris := 0
		var sources: Array[MeshInstance3D] = []
		if inst is MeshInstance3D and (inst as MeshInstance3D).mesh != null:
			sources.append(inst as MeshInstance3D)
		sources.append_array(inst.find_children("*", "MeshInstance3D", true, false))
		for mi: MeshInstance3D in sources:
			if mi.mesh == null:
				continue
			# transform RELATIF À LA RACINE, pas le transform local : un .glb dont les maillages sont sous un noeud
			# mis à l'échelle sortait fusionné à une taille délirante (une ambulance à 225 m de long).
			var xf := _relative_to(mi, inst)
			for s in mi.mesh.get_surface_count():
				st.append_from(mi.mesh, s, xf)
				if mat == null:
					mat = mi.get_active_material(s)
			tris += mi.mesh.get_faces().size() / 3
		var merged := st.commit()
		merged.surface_set_material(0, mat)
		var mesh_path := OUT.path_join("pack_%s.res" % path.get_file().get_basename().to_lower().replace("-", "_"))
		ResourceSaver.save(merged, mesh_path)
		fbx_cache[path] = {"mesh": load(mesh_path), "aabb": merged.get_aabb(), "triangles": tris}
		inst.free()
	var entry: Dictionary = fbx_cache[path]
	var aabb: AABB = entry["aabb"]
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale, scale))
	var sized := aabb.size * scale          # encombrement réel, échelle comprise
	var node := MeshInstance3D.new()
	node.name = "%s_%d" % [path.get_file().get_basename(), place.get_child_count()]
	node.mesh = entry["mesh"]
	# Distance de disparition mesurée sur la hauteur du modèle : on le garde tant qu'il couvre plus de trois pixels
	# (450 px pour 75° de champ, soit 0,0029 rad par pixel, donc hauteur x 115), borné à 1500 m. Une grue de 54 m reste
	# un repère de loin, une palette de 1,2 m disparaît à 250 m.
	node.visibility_range_end = clampf(sized.y * 115.0, 250.0, 1500.0)
	node.transform = Transform3D(basis, Vector3(center.x, base_y - aabb.position.y * scale, center.y) - basis * Vector3(aabb.get_center().x, 0.0, aabb.get_center().z))
	place.add_child(node)
	var half := Vector2(sized.x, sized.z) * 0.5 if collide == "boite" else base_half
	if collide != "aucune":
		var cs := CollisionShape3D.new()
		cs.name = "Chantier_%d" % body.get_child_count()
		var shape := BoxShape3D.new()
		var height: float = sized.y if collide == "boite" else minf(sized.y, 8.0)
		shape.size = Vector3(half.x * 2.0, height, half.y * 2.0)
		cs.shape = shape
		# la boîte n'est pas mise à l'échelle par la base : sa taille l'est déjà
		cs.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(center.x, base_y + height * 0.5, center.y))
		body.add_child(cs)
	_flatten_rect(center, Vector2(cos(yaw), -sin(yaw)), Vector2(sin(yaw), cos(yaw)), Vector2(sized.x, sized.z) * 0.5 + Vector2(1, 1), base_y - 0.05)
	stats["modèles"] += 1
	stats["triangles"] += int(entry["triangles"])
	return aabb
	return aabb


# Véhicule garé sur le parvis d'un lieu. Il passe par _fbx_model, et pas par _prop : _prop pose la scène importée
# telle quelle, dont les enfants n'ont pas de propriétaire et perdent donc leur visibility_range_end (le piège du
# §6 du CLAUDE.md, qui laissait des modèles visibles à 1,1 km). _fbx_model fusionne le modèle en un maillage
# enregistré en .res, pose un MeshInstance3D et règle la portée dessus, à quoi s'ajoutent une boîte de collision et
# l'aplanissement du sol.
# L'ÉCHELLE du pack (1,65, la même que dans le catalogue des véhicules) est appliquée ici aussi : sans elle une
# ambulance ferait 3,71 m de long au lieu de 6,12 m.
const VEH := "res://assets/vehicle_models_extra/city_vehicles_UNVERIFIED_LICENSE/"
const VEH_SCALE := 1.65
# Interrupteur de CAPTURE seulement : à true, la cuisson reproduit l'état d'avant le chantier des liaisons, le
# temps de reprendre les captures « avant » au même point de vue. Doit rester à false dans tout commit.
const AVANT := false


# Transform d'un noeud dans le repère de `top`, en remontant la chaîne des parents.
func _relative_to(n: Node3D, top: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != top:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _parked_vehicle(path: String, center: Vector2, yaw: float, base_y: float) -> void:
	var aabb := _fbx_model(path, center, yaw, base_y, "boite", Vector2.ZERO, VEH_SCALE)
	stats["vehicules_gares"] = int(stats.get("vehicules_gares", 0)) + 1
	if aabb.size.x > 0.0:
		print("PLACES_VEHICLE %-26s en (%.1f, %.1f) cap %.0f deg : %.2f x %.2f x %.2f m"
				% [path.get_file(), center.x, center.y, rad_to_deg(yaw), aabb.size.z * VEH_SCALE, aabb.size.x * VEH_SCALE, aabb.size.y * VEH_SCALE])


func _prop(path: String, pos: Vector3, yaw: float) -> void:
	var inst := (load(path) as PackedScene).instantiate() as Node3D
	inst.name = "Prop_%d" % place.get_child_count()
	inst.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	for gi in inst.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).visibility_range_end = 700.0
	place.add_child(inst)


# --- terrain et routes --------------------------------------------------------------------------------------------
func _index_roads() -> void:
	for rb in net.ribbons:
		for p: Vector3 in rb.points:
			_bucket(Vector2(p.x, p.z), float(rb.width) * 0.5)
	for pad: Dictionary in net.pads:
		var c: Vector3 = pad["center"]
		var radius := 0.0
		for p: Vector3 in pad["rim"]:
			radius = maxf(radius, Vector2(p.x - c.x, p.z - c.z).length())
		_bucket(Vector2(c.x, c.z), radius)


func _bucket(p: Vector2, half: float) -> void:
	var key := Vector2i(floori(p.x / 32.0), floori(p.y / 32.0))
	if not road_buckets.has(key):
		road_buckets[key] = []
	road_buckets[key].append(Vector3(p.x, p.y, half))


func _near_road(p: Vector2, margin: float) -> bool:
	var key := Vector2i(floori(p.x / 32.0), floori(p.y / 32.0))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for e: Vector3 in road_buckets.get(key + Vector2i(dx, dz), []):
				if Vector2(e.x, e.y).distance_to(p) < e.z + margin:
					return true
	return false


# Premier point libre (hors chaussée) en partant de `p` et en s'éloignant en spirale.
func _free_spot(p: Vector2, margin: float) -> Vector2:
	if not _near_road(p, margin):
		return p
	for r in range(2, 40, 2):
		for k in 12:
			var q := p + Vector2(cos(TAU * k / 12.0), sin(TAU * k / 12.0)) * r
			if not _near_road(q, margin):
				return q
	return p


# Point où une route (ruban maillé) croise la polyligne, Vector2.INF sinon.
func _crossing(line: PackedVector2Array) -> Vector2:
	for rb in net.ribbons:
		if not rb.mesh:
			continue
		var pts := PackedVector2Array()
		for p: Vector3 in rb.points:
			pts.append(Vector2(p.x, p.z))
		var hits := Network.polyline_intersections(line, pts)
		if not hits.is_empty():
			return hits[0]
	return Vector2.INF


func _height(p: Vector2) -> float:
	var fx := (p.x - Spec.TERRAIN.position.x) / Model.CELL
	var fz := (p.y - Spec.TERRAIN.position.y) / Model.CELL
	var i := clampi(floori(fx), 0, model.width - 2)
	var j := clampi(floori(fz), 0, model.depth - 2)
	var tx := clampf(fx - i, 0.0, 1.0)
	var tz := clampf(fz - j, 0.0, 1.0)
	var w := model.width
	return lerpf(lerpf(heights[j * w + i], heights[j * w + i + 1], tx), lerpf(heights[(j + 1) * w + i], heights[(j + 1) * w + i + 1], tx), tz)


# Terrain à `level` sous le rectangle orienté, raccordé sur BLEND m ; jamais sous une chaussée, dans l'eau, au
# centre-ville, ni sous une emprise déjà aplanie (le raccord d'un élément voisin ne la déforme pas).
func _flatten_rect(center: Vector2, right: Vector2, front: Vector2, half: Vector2, level: float) -> void:
	if locked.is_empty():
		locked.resize(heights.size())
	var origin := Spec.TERRAIN.position
	var c := (center - origin) / Model.CELL
	var r := (half.length() + BLEND + 2.0) / Model.CELL
	var inner := PackedInt32Array()
	for j in range(maxi(0, floori(c.y - r)), mini(model.depth - 1, ceili(c.y + r)) + 1):
		for i in range(maxi(0, floori(c.x - r)), mini(model.width - 1, ceili(c.x + r)) + 1):
			var idx := j * model.width + i
			if locked[idx] != 0:
				continue
			var p := origin + Vector2(i, j) * Model.CELL
			if model.is_excluded(p) or net.is_water(p) or _near_road(p, 1.5):
				continue
			var d := p - center
			var outside := Vector2(maxf(0.0, absf(d.dot(right)) - half.x), maxf(0.0, absf(d.dot(front)) - half.y)).length()
			if outside >= BLEND:
				continue
			if outside <= 0.0:
				heights[idx] = level
				inner.append(idx)
			else:
				heights[idx] = lerpf(level, heights[idx], smoothstep(0.0, BLEND, outside))
			stats["sommets_aplanis"] += 1
	for idx in inner:
		locked[idx] = 1


func _rect_footprint(kind: String, center: Vector2, size: Vector2) -> Dictionary:
	var h := size * 0.5
	return {"kind": kind, "poly": [[center.x - h.x, center.y - h.y], [center.x + h.x, center.y - h.y], [center.x + h.x, center.y + h.y], [center.x - h.x, center.y + h.y]]}


# --- assemblage ---------------------------------------------------------------------------------------------------
func _begin(id: String, entrance: Vector3) -> void:
	place = Node3D.new()
	place.name = "Place_" + id
	var poi: Dictionary = {}
	for p: Dictionary in Spec.POIS:
		if p["id"] == id:
			poi = p
	place.set_meta("place_id", id)
	place.set_meta("display_name", poi.get("name", id))
	place.set_meta("kind", poi.get("kind", ""))
	var center: Vector2 = poi.get("pos", Vector2(entrance.x, entrance.z))
	place.position = Vector3(0, 0, 0)
	var marker := Marker3D.new()
	marker.name = "Entrance"
	marker.position = entrance
	place.add_child(marker)
	root_node.add_child(place)
	parts = {}
	faces = PackedVector3Array()
	body = StaticBody3D.new()
	body.name = "Collision"
	place.add_child(body)
	places.append({"id": id, "name": poi.get("name", id), "kind": poi.get("kind", ""), "center": [center.x, center.y],
			"entrance": [snappedf(entrance.x, 0.01), snappedf(entrance.y, 0.01), snappedf(entrance.z, 0.01)]})


func _end(display_name: String, kind: String) -> void:
	for part: String in parts:
		var batch: Batch = parts[part]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = batch.verts
		arrays[Mesh.ARRAY_NORMAL] = batch.normals
		arrays[Mesh.ARRAY_TEX_UV] = batch.uvs
		if part == "paint" or part == "steel":
			arrays[Mesh.ARRAY_COLOR] = batch.colors
		arrays[Mesh.ARRAY_INDEX] = batch.indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, mats[part])
		var path := OUT.path_join("%s_%s.res" % [String(place.get_meta("place_id")), part])
		ResourceSaver.save(mesh, path)
		var mi := MeshInstance3D.new()
		mi.name = part.capitalize()
		mi.mesh = load(path)
		mi.visibility_range_end = 2500.0 if part != "steel" else 700.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if part == "paint" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		place.add_child(mi)
		stats["triangles"] += batch.indices.size() / 3
	if not faces.is_empty():
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = true
		var shape_path := OUT.path_join("%s_shape.res" % String(place.get_meta("place_id")))
		ResourceSaver.save(shape, shape_path)
		var cs := CollisionShape3D.new()
		cs.name = "Surfaces"
		cs.shape = load(shape_path)
		body.add_child(cs)
	stats["lieux"] += 1
	print("PLACES_PLACE %s (%s) : %d parties, %d formes de collision" % [display_name, kind, parts.size(), body.get_child_count()])


# Quadrilatère a-b-c-d, face visible du côté de `normal` ; collision (surfaces porteuses) si `collide`.
func _quad(part: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, uv: Array = [], color := Color.WHITE, collide := true) -> void:
	if not parts.has(part):
		parts[part] = Batch.new()
	var batch: Batch = parts[part]
	var geometric := (b - a).cross(c - a) + (c - a).cross(d - a)
	if geometric.length_squared() < 0.000001:
		geometric = (b - a).cross(d - a)
	var order := [a, b, c, d] if geometric.dot(normal) < 0.0 else [a, d, c, b]
	var uv_order := uv
	if not uv.is_empty() and geometric.dot(normal) >= 0.0:
		uv_order = [uv[0], uv[3], uv[2], uv[1]]
	var nrm := normal.normalized()
	var base := batch.verts.size()
	for i in 4:
		batch.verts.append(order[i])
		batch.normals.append(nrm)
		batch.uvs.append(uv_order[i] if not uv_order.is_empty() else Vector2.ZERO)
		batch.colors.append(color)
	batch.indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	if collide:
		faces.append_array(PackedVector3Array([order[0], order[1], order[2], order[0], order[2], order[3]]))


func _ensure_in_map() -> void:
	var text := FileAccess.get_file_as_string(MAP_SCENE)
	if text.contains(SCENE):
		return
	var last_ext := text.rfind("[ext_resource")
	var insert_at := text.find("\n", last_ext) + 1
	text = text.substr(0, insert_at) + '[ext_resource type="PackedScene" path="%s" id="6_places"]\n' % SCENE + text.substr(insert_at)
	text = text.strip_edges() + '\n\n[node name="Places" type="Node3D" parent="." unique_id=1522739407 instance=ExtResource("6_places")]\n'
	var f := FileAccess.open(MAP_SCENE, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("PLACES_BAKE Map.tscn : Places ajoutée")


func _pack(root: Node, path: String) -> void:
	_own(root, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	print("PLACES_SCENE %s : %s" % [path, error_string(err)])
	root.free()


func _own(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		if child.scene_file_path == "":
			_own(child, root)
