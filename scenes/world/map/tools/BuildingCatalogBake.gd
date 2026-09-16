extends SceneTree

# Étape 0 : catalogue mesuré des modèles de bâtiments disponibles (emprise, hauteur, triangles, surfaces) pour les
# générateurs de quartiers et de lieux. Chaque modèle reçoit une famille, un usage (downtown, commerce, maison,
# industrie, ferme, service, repère) et le drapeau `allowed` : ruines, temples, tentes, igloos et maisons exotiques
# sont écartés d'une ville américaine ; le pack à licence non vérifiée n'est pas lu.
# Sortie : scenes/world/map/data/building_catalog.json
#
# Lancer : Godot --headless --path <projet> --script res://scenes/world/map/tools/BuildingCatalogBake.gd

const OUT_PATH := "res://scenes/world/map/data/building_catalog.json"
const SOURCES := [
	{"dir": "res://assets/building_pack_everythinglibrary", "pack": "everything_library"},
	{"dir": "res://assets/building_pack", "pack": "building_pack"},
	{"dir": "res://assets/building_pack_extra", "pack": "building_pack_extra"},
	{"dir": "res://assets/city_kit/models_active", "pack": "city_kit"},
]
const EXCLUDED_NAMES := ["Igloo", "GreenHut", "RecursiveHouse", "RidiculouslySmallHouse", "AdobeHouse", "GeodesicHome",
		"ThatchedCottage", "Industrial_OilRig", "Lighthouse", "Observatory"]   # plate-forme en mer ; le derrick terrestre reste
const KEPT_HISTORICAL := ["ChurchOld", "Bandstand"]


func _initialize() -> void:
	var entries: Array = []
	for source: Dictionary in SOURCES:
		for path in _models(source["dir"]):
			var entry := _measure(path, source["pack"])
			if not entry.is_empty():
				entries.append(entry)
	entries.sort_custom(func(a, b): return a["path"] < b["path"])
	var summary := {}
	var allowed := 0
	for e: Dictionary in entries:
		if e["allowed"]:
			allowed += 1
			summary[e["use"]] = int(summary.get(e["use"], 0)) + 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_PATH.get_base_dir()))
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"models": entries, "allowed_by_use": summary}, "\t"))
	f.close()
	print("CATALOG %d modèles mesurés, %d retenus : %s -> %s" % [entries.size(), allowed, summary, OUT_PATH])
	for use in ["tower", "office", "commerce", "house", "industry", "farm", "service"]:
		var heights: Array = []
		var tris: Array = []
		for e: Dictionary in entries:
			if e["allowed"] and e["use"] == use:
				heights.append(e["size"][1])
				tris.append(e["triangles"])
		if not heights.is_empty():
			heights.sort()
			tris.sort()
			print("CATALOG_USE %s : %d modèles, hauteur %.1f à %.1f m (médiane %.1f), triangles médiane %d, max %d"
					% [use, heights.size(), heights[0], heights[-1], heights[heights.size() / 2], tris[tris.size() / 2], tris[-1]])
	quit(0)


func _models(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	if not DirAccess.dir_exists_absolute(dir_path) or FileAccess.file_exists(dir_path.path_join(".gdignore")):
		return out
	for sub in DirAccess.get_directories_at(dir_path):
		out.append_array(_models(dir_path.path_join(sub)))
	for file in DirAccess.get_files_at(dir_path):
		if file.get_extension() in ["glb", "gltf", "fbx"]:
			if dir_path.ends_with("city_kit/models_active") and not file.begins_with("Building_"):
				continue
			out.append(dir_path.path_join(file))
	return out


func _measure(path: String, pack: String) -> Dictionary:
	var scene := load(path) as PackedScene
	if scene == null:
		print("CATALOG_SKIP %s (chargement impossible)" % path)
		return {}
	var root := scene.instantiate() as Node3D
	if root == null:
		return {}
	var box := AABB()
	var has := false
	var triangles := 0
	var surfaces := 0
	var materials := {}
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var b := _to_root(mi, root) * mi.mesh.get_aabb()
		box = box.merge(b) if has else b
		has = true
		var array_mesh := mi.mesh as ArrayMesh
		for s in mi.mesh.get_surface_count():
			surfaces += 1
			if array_mesh != null:
				var indices: int = array_mesh.surface_get_array_index_len(s)
				triangles += (indices if indices > 0 else array_mesh.surface_get_array_len(s)) / 3
			var mat := mi.get_active_material(s)
			if mat != null:
				materials[mat.get_rid()] = true
	root.free()
	if not has:
		return {}
	var name := path.get_file().get_basename()
	var family := name
	var use := "misc"
	var allowed := true
	match pack:
		"everything_library":
			family = name.get_slice("_", 0)
			use = _el_use(name)
			allowed = _el_allowed(name)
		"building_pack":
			use = "commerce"
		"building_pack_extra":
			use = "house" if name.begins_with("House") else "commerce"
		"city_kit":
			use = "downtown"
	return {
		"path": path, "name": name, "pack": pack, "family": family, "use": use, "allowed": allowed,
		"size": [snappedf(box.size.x, 0.01), snappedf(box.size.y, 0.01), snappedf(box.size.z, 0.01)],
		"center": [snappedf(box.get_center().x, 0.01), snappedf(box.position.y, 0.01), snappedf(box.get_center().z, 0.01)],
		"triangles": triangles, "surfaces": surfaces, "materials": materials.size(),
	}


func _to_root(node: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


func _el_use(name: String) -> String:
	if name.contains("Skyscraper"):
		return "tower"
	if name.contains("OfficeBuilding"):
		return "office"
	if name.begins_with("Residential_"):
		return "house"
	if name.begins_with("Industrial_"):
		return "industry"
	if name.begins_with("Farm_"):
		return "farm"
	if name.begins_with("Business_"):
		for s in ["Hospital", "FireStation", "Courthouse", "Library", "School", "Bank", "DoctorsOffice", "ParkingStructure"]:
			if name.contains(s):
				return "service"
		return "commerce"
	return "landmark"


func _el_allowed(name: String) -> bool:
	if name.begins_with("Ruins_") or name.begins_with("Tents_"):
		return false
	if name.begins_with("Historical_"):
		for kept in KEPT_HISTORICAL:
			if name.contains(kept):
				return true
		return false
	for excluded in EXCLUDED_NAMES:
		if name.contains(excluded):
			return false
	return true
