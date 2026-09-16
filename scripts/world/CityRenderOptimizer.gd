extends Node3D

# Optimisation du RENDU de la ville statique, appliquée au lancement : World.tscn reste éditable nœud par nœud (et
# re-bakable par les outils de district), rien de visible n'est retiré ; seul le travail du moteur baisse.
#
# Mesures (RenderPerfTest --breakdown, 2026-09-16 ; Intel UHD 750, d3d12, 1152x648, caméra du joueur au coin SE de la
# carte tournée vers la ville ; référence / contrôle de dérive, même machine avant et après) :
#  - avant : 9,5 / 9,5 FPS, GPU 102,5 / 103,0 ms, rendu CPU 5,7 / 5,0 ms, 1435 appels de dessin, 24 048 objets,
#    15,9 M primitives. Bâtiments masqués -> 82 FPS ; les 7904 trottoirs masqués -> +1 % seulement : Godot instancie
#    déjà automatiquement les surfaces identiques. Le goulot est la géométrie des bâtiments du kit (22,9 M triangles au
#    total, LOD0 partout : leurs LOD ne basculent qu'au-delà de 500 m à 3 km avec le seuil de 1 px).
#  - matériaux des lampadaires et des feux partagés (LampPoleLayer, TrafficLight) : 717 appels, rendu CPU 4,6 ms,
#    GPU inchangé.
#  - + occlusion, tampon d'occultation par défaut (512 rayons par thread) : 16,3 / 16,3 FPS (1 % low 16,2), GPU 60,2 /
#    59,9 ms, rendu CPU 3,0 ms, 479 appels, 11 332 objets, 8,5 M primitives.
#  - + tampon 4 fois plus fin (rendering/occlusion_culling/occlusion_rays_per_thread = 2048, project.godot ; réglage
#    actuel) : 20,2 / 20,4 FPS (1 % low 20,0), GPU 48,5 / 48,2 ms, rendu CPU 3,1 / 3,0 ms, 413 appels, 6,5 M
#    primitives : plus de bâtiments reconnus cachés, sans coût CPU mesurable. Le tampon compte ce nombre de rayons PAR
#    thread (16 threads logiques ici) : plus grossier sur un processeur à moins de threads.
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

const KIT_MODEL := &"KitModel"
const WALL_MATERIAL := "InteriorWall"

@export var occlusion := true
@export var occluder_inset := 0.5            # m retirés sur chaque face de la boîte des murs intérieurs
@export var multimesh := false               # perte nette mesurée sur UHD 750, cf. en-tête
@export var cell_size := 72.0                # m : un pâté de maisons (pas du Circuit)
@export var batched_scenes: PackedStringArray = [
	"*/Sidewalk_Straight_3m.gltf",
	"res://assets/modular_roads/Road*.glb",
	"res://assets/modular_roads/lamp_*.glb",
]

var occluders := 0                           # relevés par RenderPerfTest
var batched_instances := 0
var multimesh_nodes := 0
var _mesh_copies := {}


func _ready() -> void:
	# Différé : les lampadaires (LampPoleLayer) règlent calque et matériau dans leur propre _ready, quel que soit
	# l'ordre des nœuds.
	_optimize.call_deferred()


func _optimize() -> void:
	var world := get_parent()
	if occlusion:
		_add_building_occluders(world)
	if multimesh:
		for mi in batch_static_meshes(world):
			mi.queue_free()


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
