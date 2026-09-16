extends RefCounted

# Modèles de bâtiments du pack EverythingLibrary prêts pour la carte 3D (DistrictsBake, PlacesBake) : sous-maillages
# fusionnés avec leurs transformations en un seul maillage à niveaux de détail, avec un seul matériau partagé (tous les
# matériaux du pack sont identiques : couleurs de sommet, rugosité 0,55). Origine du modèle au niveau du sol, fondations
# dessous ; façade du côté +Z.

const CATALOG := "res://scenes/world/map/data/building_catalog.json"
const PACK := "res://assets/building_pack_everythinglibrary/"
const OUT := "res://scenes/world/map/generated/buildings"

var catalog := {}                        # nom -> entrée du catalogue
var material: StandardMaterial3D
var _baked := {}                         # nom -> {"mesh": Mesh, "aabb": AABB, "triangles": int, "trimesh": Shape3D}
var _mv := PackedVector3Array()
var _mn := PackedVector3Array()
var _mc := PackedColorArray()
var _mi := PackedInt32Array()


func _init() -> void:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	for entry: Dictionary in parsed["models"]:
		if entry["allowed"] and String(entry["path"]).begins_with(PACK):
			catalog[entry["name"]] = entry
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.path_join("models")))
	var m := StandardMaterial3D.new()
	m.resource_name = "Batiments"
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.55
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var path := OUT.path_join("building_material.tres")
	ResourceSaver.save(m, path)
	material = load(path)


func size_of(name: String) -> Vector3:
	var entry: Dictionary = catalog[name]
	return Vector3(float(entry["size"][0]), float(entry["size"][1]), float(entry["size"][2]))


# {"mesh", "aabb" (repère du modèle), "triangles", "trimesh" (forme de collision exacte, sur demande)}
func get_model(name: String, with_trimesh := false) -> Dictionary:
	if not _baked.has(name):
		_bake(name)
	var info: Dictionary = _baked[name]
	if with_trimesh and info["trimesh"] == null:
		info["trimesh"] = (info["mesh"] as Mesh).create_trimesh_shape()
	return info


func _bake(name: String) -> void:
	var entry: Dictionary = catalog[name]
	var inst: Node = (load(entry["path"]) as PackedScene).instantiate()
	_mv = PackedVector3Array()
	_mn = PackedVector3Array()
	_mc = PackedColorArray()
	_mi = PackedInt32Array()
	_collect(inst, Transform3D.IDENTITY)
	inst.free()
	var aabb := AABB(_mv[0], Vector3.ZERO)
	for v in _mv:
		aabb = aabb.expand(v)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _mv
	arrays[Mesh.ARRAY_NORMAL] = _mn
	arrays[Mesh.ARRAY_COLOR] = _mc
	arrays[Mesh.ARRAY_INDEX] = _mi
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, material, name)
	importer.generate_lods(25.0, 60.0, [])
	var path := OUT.path_join("models/%s.res" % name)
	ResourceSaver.save(importer.get_mesh(), path)
	_baked[name] = {"mesh": load(path), "aabb": aabb, "triangles": _mi.size() / 3, "trimesh": null}


func _collect(node: Node, parent: Transform3D) -> void:
	var xform := parent
	if node is Node3D:
		xform = parent * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh := (node as MeshInstance3D).mesh
		var mirrored := xform.basis.determinant() < 0.0
		var normal_basis := xform.basis.inverse().transposed()
		for s in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays: Array = mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals := PackedVector3Array()
			if arrays[Mesh.ARRAY_NORMAL] != null:
				normals = arrays[Mesh.ARRAY_NORMAL]
			var colors := PackedColorArray()
			if arrays[Mesh.ARRAY_COLOR] != null:
				colors = arrays[Mesh.ARRAY_COLOR]
			var indices := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null:
				indices = arrays[Mesh.ARRAY_INDEX]
			else:
				indices.resize(verts.size())
				for k in verts.size():
					indices[k] = k
			var first := _mv.size()
			for k in verts.size():
				_mv.append(xform * verts[k])
				_mn.append((normal_basis * (normals[k] if k < normals.size() else Vector3.UP)).normalized())
				_mc.append(colors[k] if k < colors.size() else Color.WHITE)
			for t in range(0, indices.size() - 2, 3):
				_mi.append(first + indices[t])
				if mirrored:
					_mi.append(first + indices[t + 2])
					_mi.append(first + indices[t + 1])
				else:
					_mi.append(first + indices[t + 1])
					_mi.append(first + indices[t + 2])
	for child in node.get_children():
		_collect(child, xform)
