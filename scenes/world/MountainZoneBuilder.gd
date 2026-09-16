extends Node3D
class_name MountainZoneBuilder

## Zone montagne + chalet + lac + route en lacets.
##
## Terrain généré en Blender headless (bpy, script hors-projet) : grille
## bas-poly, hauteur = pics (cosinus-falloff) + bruit fractal organique,
## creux de lac irrégulier (rayon perturbé par bruit angulaire, PAS un
## rectangle) et plateau aplani pour le chalet, tous les deux INTÉGRÉS dans
## le relief (pas des formes posées à côté). Décimation planaire pour rester
## bas-poly (2054 tris sur 270x270m) + shading plat, cohérent avec le style
## à facettes du reste du monde. Route en lacets construite dans le MÊME
## script Blender par échantillonnage direct de la fonction de hauteur du
## terrain (pas de raycast approximatif) -> exportés ensemble dans
## assets/mountain_terrain/MountainTerrain.glb (2 MeshInstance3D : terrain +
## route). Remplace l'ancien mesh procédural (3 cônes à facettes + lac
## rectangulaire + chalet posé à côté, cf. git history / ancienne version).
##
## Repère LOCAL de ce node = CENTRE de la zone (270x270 m, marge incluse).
## À intégrer dans World.tscn en instanciant ce node à Vector3(-250, 0, -250)
## (zone NO validée, cf. plan). Ici testé à l'origine dans une scène séparée.
##
## Le terrain couvre TOUTE la zone (bords ramenés à hauteur 0 par un
## affaiblissement radial dans le script Blender) -> plus besoin des 4
## bandes d'herbe séparées de l'ancienne version, le mesh terrain fait tout.

const COLL_LAYER := 1   # calque du décor statique (voitures mask=5, joueur mask=7)

const TERRAIN_GLB := "res://assets/mountain_terrain/MountainTerrain.glb"

# --- lac : creusé dans le terrain (irrégulier, cf. script Blender) ; ici on
# ne pose que la SURFACE d'eau (plane, comme toute étendue d'eau au repos) à
# l'intérieur du bassin déjà sculpté. Valeurs mesurées dans Blender :
# hauteur naturelle au centre du lac = 18.653, fond du bassin (après creux de
# 4.5m) = 14.153 -> surface d'eau calée à 17.3 (bassin rempli aux 3/4, laisse
# une berge visible avant la rive naturelle).
const LAKE_CENTER := Vector2(-5.0, -55.0)
const LAKE_WATER_Y := 16.3   # baissé de 1.0 (visuellement plus bas dans le bassin)
const LAKE_WATER_RADIUS := 11.0   # < LAKE_RADIUS Blender (15, rive irrégulière ±40%) -> reste dans le bassin
const LAKEBED_Y := 14.6
const LAKEBED_COLOR := Color(0.1, 0.13, 0.16)
const WATER_SHADER_MATERIAL := "res://assets/water_shader/materials/WaterShader.tres"
const OCEAN_MESH_PATH := "res://assets/water_shader/assets/ocean_mesh.glb"

const CHALET_MODEL := "res://assets/building_pack/2Story_GableRoof_Mat.fbx"
const CHALET_CENTER := Vector2(-32.0, -68.0)
const CHALET_TARGET_H := 29.543   # plateau aplani mesuré dans Blender (chalet_target_h)
const CHALET_YAW_DEG := -35.0     # orienté vers le lac

# noms de matériaux RÉELS du modèle (vérifiés) -> palette chalet/bois. "Wood",
# "DarkWood" et "Glass" ne sont PAS dans cette table : déjà bois/vitre, non touchés.
const CHALET_RECOLOR := {
	"bricks": Color(0.42, 0.28, 0.16),
	"main": Color(0.38, 0.25, 0.14),
	"light": Color(0.60, 0.46, 0.30),
	"dark": Color(0.30, 0.18, 0.10),
	"roofbricks": Color(0.22, 0.10, 0.08),
	"white": Color(0.82, 0.77, 0.68),
}

# Rochers de détail (nature_kit) : PAS ENCORE importables (dossier source
# nature_kit/glTF/ marqué .gdignore ce soir, 0 référence). À isoler dans
# nature_kit/rocks/ (même geste que pour les 15 arbres) puis repasser ce flag
# à true. Laissé à false pour ce premier build -> zéro nouvel import.
@export var build_rocks := false
const ROCK_MODELS := [
	"res://assets/nature_kit/rocks/Rock_Medium_1.gltf",
	"res://assets/nature_kit/rocks/Rock_Medium_2.gltf",
	"res://assets/nature_kit/rocks/Rock_Medium_3.gltf",
]
# centres approximatifs des 3 pics du terrain Blender (cf. generate_mountain.py
# PEAKS), pour disperser les rochers au même endroit qu'avant
const PEAK_CENTERS := [Vector2(-40, -40), Vector2(-15, 30), Vector2(25, -45)]
const PEAK_RADII := [70.0, 40.0, 38.0]
const ROCKS_PER_PEAK := 8

func _ready() -> void:
	_build_terrain()
	_build_lake()
	_build_chalet()
	var rock_count := 0
	if build_rocks:
		rock_count = _scatter_rocks()
	print("[MountainZone] prêt : terrain Blender (glb), lac, chalet, route en lacets, %d rochers (build_rocks=%s)" % [
		rock_count, build_rocks])

# --- terrain : instancie le glb généré par Blender (terrain + route en
# lacets) et ajoute une collision trimesh calée sur le mesh terrain réel
# (pas une primitive englobante -> nécessaire pour un sol qui varie autant).
func _build_terrain() -> void:
	var scene := load(TERRAIN_GLB) as PackedScene
	if scene == null:
		push_error("[MountainZone] terrain introuvable : " + TERRAIN_GLB)
		return
	var inst := scene.instantiate() as Node3D
	inst.name = "Terrain"
	add_child(inst)

	var terrain_mesh_node := inst.get_node_or_null("MountainTerrain") as MeshInstance3D
	if terrain_mesh_node == null:
		push_warning("[MountainZone] noeud MountainTerrain introuvable dans le glb")
		return

	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	body.collision_layer = COLL_LAYER
	body.collision_mask = 0
	add_child(body)
	var cs := CollisionShape3D.new()
	cs.shape = terrain_mesh_node.mesh.create_trimesh_shape()
	body.add_child(cs)

# --- lac : surface d'eau plane posée DANS le bassin déjà sculpté dans le
# terrain (pas un bloc rectangulaire séparé comme avant). Un disque bas-poly
# (cylindre aplati) plutôt qu'une boîte, pour amorcer une silhouette moins
# géométrique en plus de la rive déjà irrégulière du terrain lui-même.
func _build_lake() -> void:
	var bed := MeshInstance3D.new()
	bed.name = "Lakebed"
	var bed_mesh := CylinderMesh.new()
	bed_mesh.top_radius = LAKE_WATER_RADIUS * 1.05
	bed_mesh.bottom_radius = LAKE_WATER_RADIUS * 0.7
	bed_mesh.height = 2.0
	bed_mesh.radial_segments = 12
	bed.mesh = bed_mesh
	var bed_mat := StandardMaterial3D.new()
	bed_mat.albedo_color = LAKEBED_COLOR
	bed.material_override = bed_mat
	bed.position = Vector3(LAKE_CENTER.x, LAKEBED_Y, LAKE_CENTER.y)
	add_child(bed)

	var water := StaticBody3D.new()
	water.name = "Lake"
	water.collision_layer = COLL_LAYER
	water.collision_mask = 0
	water.position = Vector3(LAKE_CENTER.x, LAKE_WATER_Y, LAKE_CENTER.y)
	add_child(water)

	# Mesh d'océan pré-subdivisé (332929 sommets) au lieu d'un CylinderMesh à
	# 4 coins sur le dessus : nécessaire pour que le déplacement de vertex du
	# shader d'eau dessine de vraies crêtes/creux au lieu de faire monter et
	# descendre une plaque rigide. Footprint source mesuré (AABB) ~56.17355 x
	# 57.02143 -> mis à l'échelle pour couvrir le diamètre du lac.
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var ocean_scene := load(OCEAN_MESH_PATH) as PackedScene
	var ocean_inst := ocean_scene.instantiate() as Node3D
	var ocean_plane: MeshInstance3D = null
	for c in ocean_inst.get_children():
		if c is MeshInstance3D:
			ocean_plane = c
			break
	mi.mesh = ocean_plane.mesh
	ocean_inst.queue_free()
	var ocean_scale_x := (LAKE_WATER_RADIUS * 2.0) / 56.17355
	var ocean_scale_z := (LAKE_WATER_RADIUS * 2.0) / 57.02143
	mi.scale = Vector3(ocean_scale_x, 1.0, ocean_scale_z)
	mi.material_override = load(WATER_SHADER_MATERIAL) as ShaderMaterial
	water.add_child(mi)

	var shape := CylinderShape3D.new()
	shape.radius = LAKE_WATER_RADIUS
	shape.height = 0.4
	var cs := CollisionShape3D.new()
	cs.shape = shape
	water.add_child(cs)

	# Zone de nage (en plus de la collision solide ci-dessus, pas un
	# remplacement) : même rayon que le lac, mais plus haute pour capter le
	# joueur qui s'approche par au-dessus ou par en dessous de la surface.
	var swim_zone := Area3D.new()
	swim_zone.name = "WaterZone"
	swim_zone.set_script(load("res://scenes/world/WaterZone.gd"))
	var swim_shape := CylinderShape3D.new()
	swim_shape.radius = LAKE_WATER_RADIUS
	swim_shape.height = 6.0
	var swim_cs := CollisionShape3D.new()
	swim_cs.shape = swim_shape
	swim_zone.add_child(swim_cs)
	water.add_child(swim_zone)

# --- chalet : 2Story_GableRoof_Mat.fbx recoloré (bois), posé sur le plateau
# aplani du terrain (hauteur mesurée dans Blender, CHALET_TARGET_H) ---
func _build_chalet() -> void:
	var scene := load(CHALET_MODEL) as PackedScene
	if scene == null:
		push_warning("[MountainZone] Chalet introuvable : " + CHALET_MODEL)
		return

	var root := Node3D.new()
	root.name = "Chalet"
	root.position = Vector3(CHALET_CENTER.x, CHALET_TARGET_H, CHALET_CENTER.y)
	root.rotation_degrees.y = CHALET_YAW_DEG
	add_child(root)

	var model := scene.instantiate() as Node3D
	model.name = "Model"
	root.add_child(model)
	_recolor_chalet(model)

	var aabb := _local_aabb(model, root)
	# recale la base du modèle à y=0 dans le repère de `root` (le pack
	# building_pack n'a pas forcément son origine au pied du bâtiment, cf.
	# BuildingKitBaker._bake_one qui fait la même correction)
	model.position.y -= aabb.position.y

	var body := StaticBody3D.new()
	body.name = "ChaletCollision"
	body.collision_layer = COLL_LAYER
	body.collision_mask = 0
	root.add_child(body)
	var shape := BoxShape3D.new()
	shape.size = aabb.size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(aabb.get_center().x, aabb.size.y * 0.5 - aabb.position.y, aabb.get_center().z)
	body.add_child(cs)

func _recolor_chalet(model: Node3D) -> void:
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i)
			if src == null:
				continue
			var mat_name := src.resource_name.to_lower()
			if not CHALET_RECOLOR.has(mat_name):
				continue
			var dup := src.duplicate() as Material
			if dup is BaseMaterial3D:
				(dup as BaseMaterial3D).albedo_color = CHALET_RECOLOR[mat_name]
				mi.set_surface_override_material(i, dup)

# AABB de `model`, exprimée dans le repère de `relative_to` (déjà tourné/positionné) —
# même logique que BuildingKitBaker._model_aabb, paramétrée sur le repère de référence.
func _local_aabb(model: Node3D, relative_to: Node3D) -> AABB:
	var to_local := relative_to.global_transform.affine_inverse()
	var acc := AABB()
	var has := false
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var bb := (to_local * mi.global_transform) * mi.mesh.get_aabb()
		if has:
			acc = acc.merge(bb)
		else:
			acc = bb
			has = true
	return acc if has else AABB(Vector3(-5, 0, -5), Vector3(10, 10, 10))

# --- rochers de détail : désactivé tant que nature_kit/rocks/ n'est pas isolé ---
func _scatter_rocks() -> int:
	var cache: Array = []
	for path in ROCK_MODELS:
		var s := load(path) as PackedScene
		if s == null:
			push_warning("[MountainZone] Rocher introuvable (nature_kit/rocks/ isolé ?) : " + path)
			return 0
		cache.append(s)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var placed := 0
	for pi in PEAK_CENTERS.size():
		var center: Vector2 = PEAK_CENTERS[pi]
		var radius: float = PEAK_RADII[pi]
		for i in ROCKS_PER_PEAK:
			var ang := rng.randf() * TAU
			var r := radius * rng.randf_range(0.65, 1.05)
			var pos := Vector3(center.x + cos(ang) * r, 0.0, center.y + sin(ang) * r)
			var scene: PackedScene = cache[rng.randi() % cache.size()]
			var inst := scene.instantiate() as Node3D
			add_child(inst)
			inst.position = pos
			inst.rotate_y(rng.randf() * TAU)
			inst.scale = Vector3.ONE * rng.randf_range(1.8, 3.2)
			placed += 1
	return placed
