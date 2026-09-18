extends Node3D

# OUTIL DE TRI DES VÉHICULES — scène de test autonome, JETABLE.
#
# Elle n'est référencée nulle part : ni dans World.tscn, ni sur la carte, ni dans la chaîne de cuisson. Elle se lance
# seule et ne sert qu'à regarder le parc de véhicules côte à côte pour décider lesquels garder.
#
# Contenu : tous les véhicules ACTIFS du jeu, c'est-à-dire ceux du catalogue (resources/vehicle_models/*.tres), donc
# ceux que la circulation peut tirer ou que le joueur peut conduire. Ce qui dort dans les packs sans fiche de
# catalogue n'est PAS ici. Une case par modèle, avec sa PREMIÈRE variante de couleur (les 205 variantes seraient
# illisibles) ; les modèles de rôle "police" sont mis à part, sur leur propre rangée étiquetée, parce qu'ils ne sont
# jamais tirés par la circulation civile.
#
# Commandes : ZQSD/WASD pour se déplacer, souris pour regarder, Espace monter, Ctrl descendre, Maj accélérer,
# molette pour changer la vitesse, Échap pour libérer la souris, Entrée pour la reprendre.
#
# Lancer : Godot --path <projet> res://scenes/tests/VehicleSortTest.tscn

const Catalog := preload("res://scripts/data/VehicleCatalog.gd")

const COLS := 8                  # colonnes de la grille civile
const GAP_X := 6.5               # m libres entre deux véhicules côte à côte : assez pour que deux étiquettes
                                 # voisines ne se recouvrent pas
const GAP_Z := 7.0               # m libres entre deux rangées
const ROLE_GAP := 18.0           # m entre le bloc civil et une rangée d'un autre rôle
const LABEL_RISE := 1.2          # m au-dessus du toit du véhicule
const LABEL_STAGGER := 1.0       # m : une colonne sur deux est relevée, sinon les noms longs se touchent
const GROUND := Color(0.34, 0.36, 0.34)

var _cell := Vector2(12.0, 16.0)   # pas de la grille, calculé sur la plus grande boîte mesurée
var _extent := Vector2(120.0, 120.0)


func _ready() -> void:
	print("VEHICLE_SORT_BEGIN")
	_environment()
	var civil: Array = []
	var others := {}
	for m in Catalog.models():
		if (m.model_paths as PackedStringArray).is_empty():
			continue
		if String(m.role) == "civil":
			civil.append(m)
		else:
			var role := String(m.role)
			if not others.has(role):
				others[role] = []
			(others[role] as Array).append(m)
	civil.sort_custom(func(a, b) -> bool: return String(a.id) < String(b.id))
	# première passe : instancier tout hors écran pour MESURER les boîtes, puis en déduire le pas de la grille
	var built: Array = []
	for m in civil:
		built.append(_build(m))
	for role: String in others:
		(others[role] as Array).sort_custom(func(a, b) -> bool: return String(a.id) < String(b.id))
		for m in others[role]:
			built.append(_build(m))
	var widest := 0.0
	var longest := 0.0
	for b: Dictionary in built:
		var size: Vector3 = b["size"]
		widest = maxf(widest, size.x)
		longest = maxf(longest, size.z)
	_cell = Vector2(widest + GAP_X, longest + GAP_Z)
	# deuxième passe : poser la grille
	var rows := int(ceil(float(civil.size()) / COLS))
	var z := 0.0
	var placed := 0
	for i in civil.size():
		var col := i % COLS
		var row := i / COLS
		_place(built[i], Vector3((col - (COLS - 1) * 0.5) * _cell.x, 0.0, row * _cell.y),
				LABEL_STAGGER if col % 2 == 1 else 0.0)
		placed += 1
	z = rows * _cell.y + ROLE_GAP
	var roles: Array = others.keys()
	roles.sort()
	for role: String in roles:
		var list: Array = others[role]
		# bandeau haut placé : à hauteur d'yeux il masquerait la rangée qu'il annonce
		_banner(role.to_upper(), Vector3(0.0, 7.5, z - _cell.y * 0.55))
		for j in list.size():
			_place(built[placed], Vector3((j - (list.size() - 1) * 0.5) * _cell.x, 0.0, z),
					LABEL_STAGGER if j % 2 == 1 else 0.0)
			placed += 1
		z += _cell.y + ROLE_GAP
	_extent = Vector2(maxf(COLS * _cell.x, 60.0) + 40.0, z + 40.0)
	_ground()
	_banner("CIRCULATION CIVILE", Vector3(0.0, 7.5, -_cell.y * 0.55))
	var cam := _camera()
	add_child(cam)
	cam.global_position = Vector3(0.0, 14.0, -_cell.y * 1.6)
	cam.look_at(Vector3(0.0, 1.5, _cell.y * 1.2), Vector3.UP)
	_hud(civil.size(), others, widest, longest)
	print("VEHICLE_SORT_GRID %d modeles poses : %d civils sur %d colonnes, %s | pas %.1f x %.1f m (plus grande boite %.2f x %.2f m)"
			% [placed, civil.size(), COLS, _roles_line(others), _cell.x, _cell.y, widest, longest])
	print("VEHICLE_SORT_RESULT OK")


func _roles_line(others: Dictionary) -> String:
	var parts: Array[String] = []
	for role: String in others:
		parts.append("%d %s" % [(others[role] as Array).size(), role])
	return "aucun autre role" if parts.is_empty() else ", ".join(parts)


# Instancie un modèle, le redresse, mesure sa boîte, et renvoie de quoi le poser ensuite.
func _build(m) -> Dictionary:
	var paths: PackedStringArray = m.model_paths
	var path := String(paths[0])
	var holder := Node3D.new()
	holder.name = String(m.id)
	add_child(holder)
	var size := Vector3.ONE
	var bottom := 0.0
	if ResourceLoader.exists(path):
		var model := (load(path) as PackedScene).instantiate() as Node3D
		model.scale = Vector3.ONE * float(m.model_scale)
		model.rotation_degrees = Vector3(0.0, float(m.model_yaw_deg), 0.0)
		holder.add_child(model)
		# boîte mesurée dans le repère du SUPPORT, pas dans celui du modèle : sinon l'échelle du catalogue
		# (1,65 pour toute la famille city_*) n'est pas comptée et les cases de la grille sont trop petites.
		var box := _bounds(holder, model)
		size = box.size
		bottom = box.position.y
		model.position = Vector3(-box.get_center().x, -bottom, -box.get_center().z)
	else:
		push_warning("modèle introuvable : %s" % path)
	return {"holder": holder, "size": size, "nom": path.get_file(), "id": String(m.id),
			"poids": float(m.traffic_weight), "variantes": paths.size(), "role": String(m.role)}


func _place(entry: Dictionary, pos: Vector3, lift := 0.0) -> void:
	var holder: Node3D = entry["holder"]
	holder.position = pos
	var size: Vector3 = entry["size"]
	var top := size.y + LABEL_RISE + lift
	var title := Label3D.new()
	title.text = String(entry["nom"])
	title.font_size = 64
	title.pixel_size = 0.006          # ~0,38 m de haut : lisible à 10 m sans déborder sur la case voisine
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.double_sided = true
	title.outline_size = 12
	title.outline_modulate = Color(0, 0, 0, 0.85)
	title.modulate = Color(1, 1, 1)
	title.position = Vector3(0.0, top, 0.0)
	holder.add_child(title)
	var sub := Label3D.new()
	sub.text = "%s · %d variante(s) · poids %.2f" % [entry["id"], entry["variantes"], entry["poids"]]
	sub.font_size = 48
	sub.pixel_size = 0.0045
	sub.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sub.double_sided = true
	sub.outline_size = 10
	sub.outline_modulate = Color(0, 0, 0, 0.8)
	sub.modulate = Color(0.85, 0.88, 0.95)
	sub.position = Vector3(0.0, top - 0.42, 0.0)
	holder.add_child(sub)


func _banner(text: String, pos: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 96
	label.pixel_size = 0.05
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.double_sided = true
	label.outline_size = 18
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.modulate = Color(1.0, 0.85, 0.35)
	label.position = pos
	add_child(label)


func _bounds(ref: Node3D, n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var to_ref := ref.global_transform.affine_inverse()
	var meshes: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		meshes.append(n as MeshInstance3D)     # certains .glb ont un MeshInstance3D pour racine
	meshes.append_array(n.find_children("*", "MeshInstance3D", true, false))
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null:
			continue
		var a := to_ref * mi.global_transform * mi.mesh.get_aabb()
		out = a if first else out.merge(a)
		first = false
	if first:
		return AABB(Vector3(-1, 0, -2), Vector3(2, 1.5, 4))
	return out


func _ground() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = _extent
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GROUND
	mat.roughness = 1.0
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Sol"
	mi.mesh = mesh
	mi.position = Vector3(0.0, -0.01, _extent.y * 0.5 - _cell.y * 2.0)
	add_child(mi)


func _environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.50, 0.62, 0.74)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.55
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, 38.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)


func _camera() -> Camera3D:
	var cam := Camera3D.new()
	cam.name = "CameraLibre"
	cam.far = 2000.0
	cam.fov = 70.0
	cam.set_script(load("res://scenes/tests/VehicleSortCamera.gd"))
	return cam


func _hud(civil: int, others: Dictionary, widest: float, longest: float) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.position = Vector2(16, 12)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 6)
	label.text = "TRI DES VÉHICULES — %d modèles actifs (%d civils, %s)\n" % [civil + _count(others), civil, _roles_line(others)] \
			+ "une case par modèle, première variante de couleur · plus grande boîte %.2f x %.2f m\n" % [widest, longest] \
			+ "ZQSD/WASD se déplacer · souris regarder · Espace monter · Ctrl descendre · Maj accélérer\n" \
			+ "molette vitesse · Échap libérer la souris · Entrée la reprendre"
	layer.add_child(label)


func _count(others: Dictionary) -> int:
	var n := 0
	for role: String in others:
		n += (others[role] as Array).size()
	return n
