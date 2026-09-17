extends Node3D

# Optimisation du RENDU de la ville statique, appliquée au lancement : World.tscn reste éditable nœud par nœud (et
# re-bakable par les outils de district), rien de visible n'est retiré ; seul le travail du moteur baisse.
#
# Mesures (RenderPerfTest --breakdown, 2026-09-16 ; Intel UHD 750, d3d12, 1152x648, caméra du joueur au coin SE de la
# carte tournée vers la ville ; référence / contrôle de dérive, même machine avant et après) :
#  - avant : 9,5 / 9,5 FPS, GPU 102,5 / 103,0 ms, rendu CPU 5,7 / 5,0 ms, 1435 appels de dessin, 24 048 objets,
#    15,9 M primitives. Bâtiments masqués -> 82 FPS ; les 7904 trottoirs masqués -> +1 % seulement : Godot instancie
#    déjà automatiquement les surfaces identiques. Le goulot est la géométrie des bâtiments du kit (22,9 M triangles au
#    total ; au seuil de 1 px, leurs LOD utiles ne basculent qu'au-delà de 500 m à 3 km).
#  - matériaux des lampadaires et des feux partagés (LampPoleLayer, TrafficLight) : 717 appels, rendu CPU 4,6 ms,
#    GPU inchangé.
#  - + occlusion, tampon d'occultation par défaut (512 rayons par thread) : 16,3 / 16,3 FPS (1 % low 16,2), GPU 60,2 /
#    59,9 ms, rendu CPU 3,0 ms, 479 appels, 11 332 objets, 8,5 M primitives.
#  - + tampon 4 fois plus fin (rendering/occlusion_culling/occlusion_rays_per_thread = 2048, project.godot) :
#    20,2 / 20,4 FPS (1 % low 20,0), GPU 48,5 / 48,2 ms, rendu CPU 3,1 / 3,0 ms, 413 appels, 6,5 M primitives :
#    plus de bâtiments reconnus cachés, sans coût CPU mesurable. Le tampon compte ce nombre de rayons PAR thread
#    (16 threads logiques ici) : plus grossier sur un processeur à moins de threads.
#  - + LOD des bâtiments lointains (lod_bias 0,25 au-delà de 150 m, cf. 3 ; réglage actuel), avant / après remesurés
#    à la suite : 20,4 / 20,4 -> 31,7 / 31,7 FPS (1 % low 20,3 -> 30,2 / 28,7), GPU 48,1 / 48,0 -> 30,8 / 30,8 ms,
#    rendu CPU 3,0 -> 3,2 ms, 6,5 M -> 3,3 M primitives. Même lod_bias sur tous les bâtiments : 33,5 FPS à 0,25,
#    26,8 FPS à 0,5, mais les bâtiments proches changent aussi (cf. 3).
#  - + multimesh en plus (mesuré avec le tampon par défaut) : 15,4 / 16,1 FPS (1 % low 13,6 / 14,8), GPU 63,5 /
#    60,7 ms, rendu CPU 2,9 / 2,6 ms, 708 appels ; bâtiments masqués 78,9 FPS contre 85,9. Perte nette, donc
#    désactivé : l'instanciation automatique regroupait déjà ces maillages en quelques appels pour toute la vue, alors
#    que chacun des 480 MultiMesh coûte au moins le sien et n'est masqué que d'un bloc ; le gain CPU (~0,3 ms) ne
#    compense pas.
#
#  1. occlusion : une boîte d'occultation (OccluderInstance3D, BoxOccluder3D partagée par modèle) dans chaque
#     bâtiment du kit (BuildingKitBaker : Buildings/<bâtiment>/KitModel/Mesh), calée sur la face intérieure de ses
#     murs (surfaces "InteriorWall") et rentrée de `occluder_inset` : toujours derrière les façades opaques, jamais
#     devant une vitrine ou un perron. Ce qui est entièrement caché derrière les bâtiments n'est plus dessiné.
#     Nécessite rendering/occlusion_culling/use_occlusion_culling (project.godot) ; finesse du tampon réglée par
#     occlusion_culling/occlusion_rays_per_thread (cf. mesures). Les boutiques visitables
#     (ShopBuilding : vitrines, voitures exposées) n'ont pas de KitModel donc pas de boîte ; poser la meta
#     "no_occluder" sur un bâtiment si un intérieur visible depuis la rue y est un jour placé.
#     Vérifié pixel à pixel (RenderPerfTest --verify-occlusion : 34 vues fixes atteintes par coupe de caméra, 8 trajets
#     en mouvement) : aucun objet ne disparaît en vue stable. Limite propre au tampon d'occultation de Godot (basse
#     résolution, rayons décalés sur 9 frames) : un objet lointain aperçu par un interstice plus fin qu'un texel du
#     tampon peut manquer par intermittence, 1 à 5 px par frame en mouvement et jusqu'à 8 px sur la 1re frame après
#     une coupe (téléportation) ; mesuré le 2026-09-16 sur plusieurs passes à 512 et 2048 rayons par thread (à 2048 :
#     3 px par frame au plus), détail dans RenderPerfTest._verify_occlusion.
#  2. multimesh (désactivé, cf. mesures) : tuiles de trottoir, tuiles de route et poteaux de lampadaire (même
#     maillage, mêmes matériaux, mêmes réglages de rendu) regroupés par cellule de `cell_size` m en
#     MultiMeshInstance3D ; les MeshInstance3D d'origine sont libérés. La cellule garde un culling par frustum et
#     occlusion. Une instance à échelle non uniforme ou miroir reste telle quelle (un MultiMesh ne corrige pas les
#     normales / le sens des faces comme un MeshInstance3D). Image identique au pixel près en LOD0
#     (--verify-multimesh) ; au seuil de LOD normal, le LOD est choisi sur la boîte de la cellule (détail égal ou plus
#     fin sur quelques poteaux lointains).
#  3. LOD des bâtiments : au-delà de `lod_near_radius` (150 m) de la caméra active, les maillages des bâtiments du kit
#     passent à lod_bias `building_lod_bias` (0,25 : leurs LOD basculent 4 fois plus près) ; en deçà, lod_bias 1, le
#     réglage de Godot, inchangé. Mise à jour toutes les `lod_update_interval` s ; seuls les bâtiments qui franchissent
#     la limite sont touchés. Pas un lod_bias pour tous : Godot borne l'erreur d'un LOD en pixels à toute distance
#     (4 px à 0,25), les bâtiments proches changeaient donc aussi. RenderPerfTest --verify-lod, 34 vues : écart à
#     moins de 150 m de 47 778 px (0,25 partout) et 5 667 px (0,5 partout), 0 px avec la limite de distance.
#  4. portées de visibilité (carte 3D ouverte) : vu depuis la campagne, un pont ou une colline, rien ne masque la ville
#     et tout y était dessiné (MapShotsTest, campagne est vers la ville à 2 km : 884 appels, 24 481 objets). Au-delà
#     de `far_ranges` m de la caméra, trottoirs, tuiles de route, lampadaires et feux ne sont plus dessinés (coupure
#     nette, sans transparence) ; décalques de passage piéton et projecteurs de rue s'estompent au-delà de
#     `decal_fade_distance` et `light_fade_distance`. Les bâtiments restent : ce sont la silhouette de la ville.

const KIT_MODEL := &"KitModel"
const WALL_MATERIAL := "InteriorWall"

@export var occlusion := true
@export var occluder_inset := 0.5            # m retirés sur chaque face de la boîte des murs intérieurs
@export var multimesh := false               # perte nette mesurée sur UHD 750, cf. en-tête
@export var building_lod_bias := 0.25        # lod_bias des bâtiments du kit au-delà de lod_near_radius (1 = Godot)
@export var lod_near_radius := 150.0         # m de la caméra : en deçà, lod_bias 1, rien ne change de près
@export var lod_update_interval := 0.25      # s entre deux mises à jour des lod_bias
@export var cell_size := 72.0                # m : un pâté de maisons (pas du Circuit)
@export var batched_scenes: PackedStringArray = [
	"*/Sidewalk_Straight_3m.gltf",
	"res://assets/modular_roads/Road*.glb",
	"res://assets/modular_roads/lamp_*.glb",
]

@export var distance_culling := true
@export var far_ranges := {                   # famille -> m de la caméra au-delà desquels elle n'est plus dessinée
	"sidewalk": 380.0, "road": 1200.0, "lamp": 300.0, "traffic_light": 260.0,
}
@export var decal_fade_distance := 140.0
@export var light_fade_distance := 180.0

var occluders := 0                           # relevés par RenderPerfTest
var distance_culled := {}                    # famille -> nombre d'instances avec une portée
var batched_instances := 0
var multimesh_nodes := 0
var _mesh_copies := {}
var _lod_meshes: Array[MeshInstance3D] = []  # bâtiments du kit et leurs AABB globales (statiques)
var _lod_boxes: Array[AABB] = []
var _lod_far := PackedByteArray()            # 1 si building_lod_bias appliqué
var _lod_timer := 0.0


func _ready() -> void:
	# Différé : les lampadaires (LampPoleLayer) règlent calque et matériau dans leur propre _ready, quel que soit
	# l'ordre des nœuds.
	_optimize.call_deferred()


func _optimize() -> void:
	var world := get_parent()
	if occlusion:
		_add_building_occluders(world)
	if building_lod_bias != 1.0:
		_lod_meshes = building_meshes(world)
		for mi in _lod_meshes:
			_lod_boxes.append(mi.global_transform * mi.get_aabb())
		_lod_far.resize(_lod_meshes.size())
		update_building_lods(true)
	if distance_culling:
		apply_distance_culling(world)
	if multimesh:
		for mi in batch_static_meshes(world):
			mi.queue_free()


func apply_distance_culling(world: Node) -> void:
	for node in world.find_children("*", "", true, false):
		if node is Decal:
			var decal := node as Decal
			decal.distance_fade_enabled = true
			decal.distance_fade_begin = decal_fade_distance
			decal.distance_fade_length = 25.0
			distance_culled["decal"] = int(distance_culled.get("decal", 0)) + 1
		elif node is Light3D and not node is DirectionalLight3D:
			var light := node as Light3D
			light.distance_fade_enabled = true
			light.distance_fade_begin = light_fade_distance
			light.distance_fade_length = 30.0
			distance_culled["light"] = int(distance_culled.get("light", 0)) + 1
		elif node is GeometryInstance3D and node.owner != null:
			var family := _family(node.owner.scene_file_path)
			if family != "" and far_ranges.has(family):
				(node as GeometryInstance3D).visibility_range_end = far_ranges[family]
				distance_culled[family] = int(distance_culled.get(family, 0)) + 1


func _family(scene: String) -> String:
	if scene.match("*/Sidewalk_Straight_3m.gltf"):
		return "sidewalk"
	if scene.match("res://assets/modular_roads/Road*.glb"):
		return "road"
	if scene.match("res://assets/modular_roads/lamp_*.glb"):
		return "lamp"
	if scene.begins_with("res://assets/traffic_light/"):
		return "traffic_light"
	return ""


func _process(delta: float) -> void:
	if _lod_meshes.is_empty():
		return
	_lod_timer -= delta
	if _lod_timer <= 0.0:
		_lod_timer = lod_update_interval
		update_building_lods()


# lod_bias 1 (réglage de Godot, inchangé) pour les bâtiments à moins de lod_near_radius de la caméra active,
# building_lod_bias au-delà. Seuls les bâtiments qui changent de côté sont touchés, sauf `force`.
func update_building_lods(force := false) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	for i in _lod_meshes.size():
		var far := eye.distance_to(eye.clamp(_lod_boxes[i].position, _lod_boxes[i].end)) > lod_near_radius
		if (force or int(far) != _lod_far[i]) and is_instance_valid(_lod_meshes[i]):
			_lod_far[i] = int(far)
			_lod_meshes[i].lod_bias = building_lod_bias if far else 1.0


func building_meshes(world: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for mi: MeshInstance3D in world.find_children("*", "MeshInstance3D", true, false):
		if mi.get_parent().name == KIT_MODEL:
			out.append(mi)
	return out


func _add_building_occluders(world: Node) -> void:
	var shapes := {}                         # Mesh -> [BoxOccluder3D, centre] ; [] si pas de mur intérieur
	for mi: MeshInstance3D in world.find_children("*", "MeshInstance3D", true, false):
		if mi.get_parent().name != KIT_MODEL or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		if mi.get_parent().get_parent().has_meta(&"no_occluder"):
			continue
		if not shapes.has(mi.mesh):
			var box := _wall_box(mi)
			shapes[mi.mesh] = []
			if box.has_volume():
				var shape := BoxOccluder3D.new()
				shape.size = box.size
				shapes[mi.mesh] = [shape, box.get_center()]
		var entry: Array = shapes[mi.mesh]
		if entry.is_empty():
			continue
		var occ := OccluderInstance3D.new()
		occ.occluder = entry[0]
		occ.position = entry[1]
		mi.add_child(occ)
		occluders += 1


# Boîte englobant les surfaces "InteriorWall" du modèle (face intérieure des murs extérieurs), rentrée de
# occluder_inset. AABB vide si le modèle n'en a pas : pas de boîte plutôt qu'une boîte qui dépasserait.
func _wall_box(mi: MeshInstance3D) -> AABB:
	var box := AABB()
	var found := false
	for i in mi.mesh.get_surface_count():
		var mat := mi.get_active_material(i)
		if mat == null or not mat.resource_name.contains(WALL_MATERIAL):
			continue
		for v: Vector3 in mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
			box = box.expand(v) if found else AABB(v, Vector3.ZERO)
			found = true
	return box.grow(-occluder_inset) if found else AABB()


# Renvoie les MeshInstance3D remplacées, laissées en place : à libérer par l'appelant (RenderPerfTest
# --verify-multimesh les garde le temps de comparer les deux rendus).
func batch_static_meshes(world: Node) -> Array[MeshInstance3D]:
	var groups := {}                         # clé de rendu + cellule -> [source, transforms]
	var sources: Array[MeshInstance3D] = []
	var to_local := global_transform.affine_inverse()
	for mi: MeshInstance3D in world.find_children("*", "MeshInstance3D", true, false):
		if not _batchable(mi):
			continue
		var origin := mi.global_position
		var key := "%s|%d|%d" % [_render_key(mi), floori(origin.x / cell_size), floori(origin.z / cell_size)]
		if not groups.has(key):
			groups[key] = [mi, []]
		groups[key][1].append(to_local * mi.global_transform)
		sources.append(mi)
	for key: String in groups:
		_add_multimesh(groups[key][0], groups[key][1])
	return sources


func _batchable(mi: MeshInstance3D) -> bool:
	if mi.mesh == null or mi.owner == null or mi.get_child_count() > 0 or mi.skin != null or mi.get_script() != null:
		return false
	var array_mesh := mi.mesh as ArrayMesh
	if not mi.is_visible_in_tree() or (array_mesh != null and array_mesh.get_blend_shape_count() > 0):
		return false
	var b := mi.global_transform.basis
	var s := b.get_scale()
	if b.determinant() <= 0.0 or not is_equal_approx(s.x, s.y) or not is_equal_approx(s.y, s.z) \
			or absf(b.x.dot(b.y)) > 0.001 * s.x * s.y or absf(b.y.dot(b.z)) > 0.001 * s.y * s.z or absf(b.x.dot(b.z)) > 0.001 * s.x * s.z:
		return false
	var scene := mi.owner.scene_file_path
	if scene.is_empty():
		return false
	for pattern in batched_scenes:
		if scene.match(pattern):
			return true
	return false


# Tout ce qui change le rendu d'une instance : même clé = interchangeables dans un MultiMesh.
func _render_key(mi: MeshInstance3D) -> String:
	var parts := [mi.mesh.get_instance_id(), mi.layers, mi.cast_shadow, mi.gi_mode, mi.transparency, mi.lod_bias,
			mi.extra_cull_margin, mi.ignore_occlusion_culling, mi.visibility_range_begin, mi.visibility_range_begin_margin,
			mi.visibility_range_end, mi.visibility_range_end_margin, mi.visibility_range_fade_mode,
			mi.material_overlay.get_instance_id() if mi.material_overlay != null else 0]
	for i in mi.mesh.get_surface_count():
		var mat := mi.get_active_material(i)
		parts.append(mat.get_instance_id() if mat != null else 0)
	return str(parts)


func _add_multimesh(source: MeshInstance3D, xforms: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = source.mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = source.material_override
	if source.material_override == null:
		var overridden := false
		for i in source.mesh.get_surface_count():
			overridden = overridden or source.get_surface_override_material(i) != null
		if overridden and source.mesh.get_surface_count() == 1:
			mmi.material_override = source.get_active_material(0)
		elif overridden:
			mm.mesh = _mesh_with_active_materials(source)
	mmi.material_overlay = source.material_overlay
	mmi.layers = source.layers
	mmi.cast_shadow = source.cast_shadow
	mmi.gi_mode = source.gi_mode
	mmi.transparency = source.transparency
	mmi.lod_bias = source.lod_bias
	mmi.extra_cull_margin = source.extra_cull_margin
	mmi.ignore_occlusion_culling = source.ignore_occlusion_culling
	mmi.visibility_range_begin = source.visibility_range_begin
	mmi.visibility_range_begin_margin = source.visibility_range_begin_margin
	mmi.visibility_range_end = source.visibility_range_end
	mmi.visibility_range_end_margin = source.visibility_range_end_margin
	mmi.visibility_range_fade_mode = source.visibility_range_fade_mode
	mmi.set_meta(&"batched_scene", source.owner.scene_file_path)
	mmi.name = "%s_%d" % [source.owner.scene_file_path.get_file().get_basename(), multimesh_nodes]
	add_child(mmi)
	multimesh_nodes += 1
	batched_instances += xforms.size()


# Maillage à plusieurs surfaces dont les matériaux sont surchargés sur l'instance : copie (données partagées) portant
# les matériaux actifs, une seule par combinaison.
func _mesh_with_active_materials(source: MeshInstance3D) -> Mesh:
	var key := _render_key(source)
	if not _mesh_copies.has(key):
		var copy := source.mesh.duplicate() as Mesh
		for i in copy.get_surface_count():
			copy.surface_set_material(i, source.get_active_material(i))
		_mesh_copies[key] = copy
	return _mesh_copies[key]
