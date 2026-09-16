extends Node3D

# Étape 7 : silhouettes lointaines du centre-ville existant (HLOD), sans toucher à ses scènes. Au lancement, les
# bâtiments des districts (World/District*/Buildings) sont regroupés par blocs de `chunk_size` m ; chaque bloc reçoit
# une silhouette fusionnée (une boîte par bâtiment, façade brique ou béton selon ses matériaux, toit plus sombre)
# visible au-delà de `hlod_distance` m du centre du bloc. Les maillages des bâtiments du bloc prennent la silhouette
# pour visibility_parent : ils sont dessinés en deçà, la silhouette au-delà, jamais les deux ni aucun des deux.
# Collisions, occulteurs, boutiques et scripts des bâtiments restent tels quels. Sans districts (carte seule) : rien.

@export var enabled := true
@export var hlod_distance := 650.0
@export var chunk_size := 160.0

const BRICK := Color(0.47, 0.3, 0.24)
const CONCRETE := Color(0.58, 0.56, 0.53)
const ROOF := Color(0.24, 0.24, 0.25)

var chunks := 0
var buildings := 0
var linked := 0


func _ready() -> void:
	if enabled:
		call_deferred("_build")


func _build() -> void:
	var map: Node = get_parent()
	var world: Node = map.get_parent() if map != null else null
	if world == null:
		return
	var groups := {}   # Vector2i -> [[aabb, couleur, [GeometryInstance3D...]], ...]
	for district in world.get_children():
		if not String(district.name).begins_with("District"):
			continue
		var holder := district.get_node_or_null("Buildings")
		if holder == null:
			continue
		for building in holder.get_children():
			if not building is Node3D or not (building as Node3D).visible:
				continue
			var box := AABB()
			var has_box := false
			var brick := false
			var instances: Array = []
			for node in building.find_children("*", "GeometryInstance3D", true, false):
				instances.append(node)
				var mi := node as MeshInstance3D
				if mi == null or mi.mesh == null:
					continue
				var b := mi.global_transform * mi.get_aabb()
				if b.size.x > 200.0 or b.size.z > 200.0:
					continue
				box = box.merge(b) if has_box else b
				has_box = true
				brick = brick or _is_brick(mi)
			if not has_box or box.size.y < 3.0:
				continue
			var key := Vector2i(floori(box.get_center().x / chunk_size), floori(box.get_center().z / chunk_size))
			if not groups.has(key):
				groups[key] = []
			groups[key].append([box, BRICK if brick else CONCRETE, instances])
			buildings += 1
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true   # couleurs choisies à la main (sRGB)
	material.roughness = 0.9
	for key: Vector2i in groups:
		var verts := PackedVector3Array()
		var normals := PackedVector3Array()
		var colors := PackedColorArray()
		for entry: Array in groups[key]:
			_box(verts, normals, colors, entry[0], entry[1])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, material)
		var silhouette := MeshInstance3D.new()
		silhouette.name = "Silhouette_%d_%d" % [key.x, key.y]
		silhouette.mesh = mesh
		silhouette.visibility_range_begin = hlod_distance
		silhouette.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(silhouette)
		chunks += 1
		for entry: Array in groups[key]:
			for gi: GeometryInstance3D in entry[2]:
				gi.visibility_parent = gi.get_path_to(silhouette)
				linked += 1


# Façade en brique si un matériau du bâtiment en porte la texture (kit de la ville), béton sinon.
func _is_brick(mi: MeshInstance3D) -> bool:
	for s in mi.mesh.get_surface_count():
		var m := mi.get_active_material(s)
		if m == null:
			continue
		var texts: PackedStringArray = [m.resource_name, m.resource_path]
		if m is BaseMaterial3D and (m as BaseMaterial3D).albedo_texture != null:
			texts.append((m as BaseMaterial3D).albedo_texture.resource_path)
		elif m is ShaderMaterial and (m as ShaderMaterial).shader != null:
			for param in (m as ShaderMaterial).shader.get_shader_uniform_list():
				var value: Variant = (m as ShaderMaterial).get_shader_parameter(param["name"])
				if value is Texture2D:
					texts.append((value as Texture2D).resource_path)
		for t in texts:
			if t.contains("Brick"):
				return true
	return false


# Boîte d'un bâtiment : quatre façades et le toit (sens horaire vu de l'extérieur, convention de Godot).
func _box(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, box: AABB, color: Color) -> void:
	var a := box.position
	var b := box.end
	var c := [Vector3(a.x, 0, a.z), Vector3(b.x, 0, a.z), Vector3(b.x, 0, b.z), Vector3(a.x, 0, b.z)]
	var outs := [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]
	for k in 4:
		var p0: Vector3 = c[k]
		var p1: Vector3 = c[(k + 1) % 4]
		var lo0 := Vector3(p0.x, a.y, p0.z)
		var lo1 := Vector3(p1.x, a.y, p1.z)
		var hi0 := Vector3(p0.x, b.y, p0.z)
		var hi1 := Vector3(p1.x, b.y, p1.z)
		_quad(verts, normals, colors, lo0, lo1, hi1, hi0, outs[k], color)
	_quad(verts, normals, colors, Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z), Vector3.UP, ROOF)


func _quad(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, normal: Vector3, color: Color) -> void:
	var order := [p0, p1, p2, p3]
	if (p1 - p0).cross(p2 - p0).dot(normal) > 0.0:
		order = [p0, p3, p2, p1]
	for i: int in [0, 1, 2, 0, 2, 3]:
		verts.append(order[i])
		normals.append(normal)
		colors.append(color)
