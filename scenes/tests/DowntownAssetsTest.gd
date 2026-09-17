extends Node

# Test des assets du nouveau centre-ville (étape D0) : chaque modèle Godot des packs SkyScraperBundle
# (assets/skyscraper_bundle) et low_Poly_City_Pack (assets/lowpoly_city_pack) se charge, a la taille de son inventaire
# (models.json : échelle intégrée aux sommets, aucun nœud mis à l'échelle), repose sur le sol (fondation des gratte-ciels
# comprise) et ses matériaux texturés pointent la texture partagée du pack ; la palette 4×4 est importée sans
# compression ni mipmaps (sinon ses couleurs se mélangent), la texture des façades avec compression GPU et mipmaps
# (sinon moiré au loin). Hauteur du personnage du joueur relevée pour comparaison.
# Avec --out=<dossier> (fenêtré) : vues de contrôle d'échelle (gratte-ciels alignés, mobilier à côté du personnage du
# joueur et d'une porte de 2,2 m).
#
# Lancer : Godot --headless --path <projet> res://scenes/tests/DowntownAssetsTest.tscn
#          Godot --path <projet> --resolution 1152x648 res://scenes/tests/DowntownAssetsTest.tscn -- --out=<dossier>

const PACKS := ["res://assets/skyscraper_bundle/models.json", "res://assets/lowpoly_city_pack/models.json"]
const PLAYER_MODEL := "res://assets/player_model/Suit.gltf"
const PALETTE_IMPORT := "res://assets/lowpoly_city_pack/lowpoly_city_palette.png.import"
const SKYSCRAPER_IMPORT := "res://assets/skyscraper_bundle/SkyScraperUVEdit.png.import"
const SIZE_TOLERANCE := 0.01          # part de la dimension (au moins 2 cm)
const LINEUP := ["street_furniture/bench", "street_furniture/bin", "street_furniture/chair", "street_furniture/table",
		"street_furniture/parasol_open", "street_furniture/bus_stop", "lighting/lamp_single", "signage/traffic_sign_01",
		"signage/traffic_lights", "structures/fence_03", "structures/stairs_01", "street_furniture/fountain",
		"structures/garage_closed", "buildings/building_06", "buildings/building_02"]

var _errors: Array[String] = []
var _models := {}                      # nom -> entrée de l'inventaire


func _ready() -> void:
	print("DOWNTOWN_ASSETS_BEGIN")
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	var counts := []
	for pack_path: String in PACKS:
		var pack: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(pack_path))
		var texture := load(String(pack["texture"])) as Texture2D
		if texture == null:
			_errors.append("texture %s absente" % pack["texture"])
		var triangles := 0
		for model: Dictionary in pack["models"]:
			_models[String(model["path"]).trim_prefix("res://assets/").get_basename()] = model
			triangles += _check_model(model, String(pack["texture"]))
		counts.append("%s : %d modèles, %d triangles" % [pack["pack"], pack["models"].size(), triangles])
	_check_textures()
	var player_model := load(PLAYER_MODEL).instantiate() as Node3D
	var player := _bounds(player_model)
	player_model.free()
	print("DOWNTOWN_ASSETS_PACKS %s | personnage du joueur %.2f m de haut" % [" ; ".join(counts), player.size.y])
	if out != "":
		await _shots(out)
	print("DOWNTOWN_ASSETS_RESULT %s %s" % ["OK" if _errors.is_empty() else "FAIL", " | ".join(_errors)])
	get_tree().quit(0 if _errors.is_empty() else 1)


# Renvoie le nombre de triangles du modèle.
func _check_model(model: Dictionary, texture_path: String) -> int:
	var path := String(model["path"])
	var scene := load(path) as PackedScene
	if scene == null:
		_errors.append("%s ne se charge pas" % path)
		return 0
	var root := scene.instantiate() as Node3D
	var box := _bounds(root)
	var triangles := 0
	var textured := 0
	var surfaces := 0
	var scaled := false
	var filters := {}
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if not _local(root, mi).basis.get_scale().is_equal_approx(Vector3.ONE):
			scaled = true
		for s in mi.mesh.get_surface_count():
			surfaces += 1
			triangles += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			var mat := mi.get_active_material(s) as BaseMaterial3D
			if mat == null or mat.albedo_texture == null:
				continue
			textured += 1
			filters[mat.texture_filter] = true
			if mat.albedo_texture.resource_path != texture_path:
				_errors.append("%s : texture %s au lieu de %s" % [path, mat.albedo_texture.resource_path, texture_path])
	root.free()
	var expected := Vector3(model["size"][0], model["size"][1], model["size"][2])
	var below := float(model.get("below_ground", 0.0))
	for axis in 3:
		if absf(box.size[axis] - expected[axis]) > maxf(0.02, expected[axis] * SIZE_TOLERANCE):
			_errors.append("%s : taille %s au lieu de %s" % [path, box.size, expected])
			break
	if absf(box.position.y + below) > 0.06:   # quelques cm de fondation d'origine tolérés
		_errors.append("%s : pied à %.2f m au lieu de %.2f" % [path, box.position.y, -below])
	if scaled:
		_errors.append("%s : nœud mis à l'échelle (l'échelle doit être dans les sommets)" % path)
	if model.has("materials_textured"):
		# l'export glTF fusionne les matériaux identiques : au moins une surface texturée, pas plus que de matériaux
		if textured < 1 or textured > (model["materials_textured"] as Array).size():
			_errors.append("%s : %d surfaces texturées pour %d matériaux" % [path, textured, (model["materials_textured"] as Array).size()])
	elif textured != surfaces:
		_errors.append("%s : %d surfaces sur %d sans palette" % [path, surfaces - textured, surfaces])
	elif not (filters.has(BaseMaterial3D.TEXTURE_FILTER_NEAREST) or filters.has(BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS)) or filters.size() != 1:
		_errors.append("%s : filtrage de la palette %s (au plus proche attendu)" % [path, filters.keys()])
	if absi(triangles - int(model["triangles"])) > int(model["triangles"]) / 50:
		_errors.append("%s : %d triangles au lieu de %d" % [path, triangles, model["triangles"]])
	return triangles


# Palette : sans compression ni mipmaps (couleurs exactes à toute distance). Façades des gratte-ciels : compression
# GPU et mipmaps (sans mipmaps, moiré au loin). Réglages figés (pas de conversion automatique à la détection 3D).
func _check_textures() -> void:
	for entry: Array in [[PALETTE_IMPORT, 0, false], [SKYSCRAPER_IMPORT, 2, true]]:
		var config := ConfigFile.new()
		if config.load(entry[0]) != OK:
			_errors.append("%s illisible" % entry[0])
			continue
		if int(config.get_value("params", "compress/mode", -1)) != entry[1] \
				or bool(config.get_value("params", "mipmaps/generate", false)) != entry[2] \
				or int(config.get_value("params", "detect_3d/compress_to", -1)) != 0:
			_errors.append("%s : compression %s, mipmaps %s (attendu %d, %s)" % [entry[0], config.get_value("params", "compress/mode"),
					config.get_value("params", "mipmaps/generate"), entry[1], entry[2]])


func _local(root: Node, node: Node3D) -> Transform3D:
	var t := node.transform
	var parent := node.get_parent()
	while parent != null and parent != root:
		if parent is Node3D:
			t = (parent as Node3D).transform * t
		parent = parent.get_parent()
	return t


# Boîte des maillages dans le repère de `root` (nœuds hors de l'arbre).
func _bounds(root: Node) -> AABB:
	var box := AABB()
	var has := false
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var b := _local(root, mi) * mi.mesh.get_aabb()
		box = box.merge(b) if has else b
		has = true
	return box


func _shots(out: String) -> void:
	var stage := Node3D.new()
	add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.72, 0.84)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.57, 0.6)
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2000, 2000)
	ground.mesh = plane
	stage.add_child(ground)
	var cam := Camera3D.new()
	cam.far = 3000.0
	stage.add_child(cam)
	cam.make_current()
	# gratte-ciels côte à côte, pieds alignés sur une ligne
	var x := 0.0
	for model: Dictionary in _models.values():
		if not model.has("below_ground"):
			continue
		var tower := (load(model["path"]) as PackedScene).instantiate() as Node3D
		stage.add_child(tower)
		tower.position = Vector3(x + float(model["size"][0]) * 0.5, 0, 0)
		x += float(model["size"][0]) + 25.0
	_place_reference(stage, Vector3(-4, 0, 30))
	await _shot(cam, out, "gratte_ciels", Vector3(x * 0.5, 120, 560), Vector3(x * 0.5, 110, 0))
	await _shot(cam, out, "gratte_ciels_pied", Vector3(12, 1.7, 48), Vector3(20, 6, 0))
	# mobilier et petits bâtiments à côté du personnage et d'une porte, rangée à z = 200
	x = 3.0
	for key: String in LINEUP:
		var model: Dictionary = _models["lowpoly_city_pack/" + key]
		var item := (load(model["path"]) as PackedScene).instantiate() as Node3D
		stage.add_child(item)
		item.position = Vector3(x + float(model["size"][0]) * 0.5, 0, 200)
		x += float(model["size"][0]) + 1.2
	_place_reference(stage, Vector3(0, 0, 200))
	await _shot(cam, out, "mobilier_gauche", Vector3(6, 1.6, 211), Vector3(6, 1.2, 200))
	await _shot(cam, out, "mobilier_droite", Vector3(24, 3.5, 228), Vector3(24, 3, 200))
	stage.queue_free()


func _place_reference(stage: Node3D, at: Vector3) -> void:
	var player := load(PLAYER_MODEL).instantiate() as Node3D
	stage.add_child(player)
	player.position = at
	var door := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 2.2, 0.1)
	door.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.3, 0.9)
	door.material_override = mat
	stage.add_child(door)
	door.position = at + Vector3(-1.3, 1.1, 0)


func _shot(cam: Camera3D, out: String, shot_name: String, from: Vector3, to: Vector3) -> void:
	cam.global_position = from
	cam.look_at(to, Vector3.UP)
	for k in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(shot_name + ".png"))
	print("DOWNTOWN_ASSETS_SHOT %s" % shot_name)
