extends Node
## Vérification d'import des packs ajoutés (Everything Library + vehicle_models_extra), en headless :
## chaque .glb doit se charger et s'instancier, avoir des meshes et une AABB plausible, des couleurs de
## sommets lisibles et utilisées comme albedo (bâtiments) ou une texture albedo (véhicules). Pour les
## véhicules : roues visibles par Car.gd ("*heel*") ou nommées "Tire" (invisibles pour Car.gd), pivot des
## roues (Car.gd les fait tourner sur leur origine), origine du modèle, squelettes, et axe avant déduit du
## centre des roues avant/arrière nommées (Car.gd attend l'avant du modèle en +Z).
## Détail par fichier : user://extra_packs_import_report.csv

const ROOTS := ["res://assets/building_pack_everythinglibrary", "res://assets/vehicle_models_extra"]
const REFERENCE_CARS := ["res://assets/vehicle_models/NormalCar1.fbx", "res://assets/vehicle_models/Taxi.fbx"]
const REPORT_PATH := "user://extra_packs_import_report.csv"
const FRONT_TOKENS := ["front", "fl", "fr", "_f"]
const REAR_TOKENS := ["back", "rear", "rl", "rr", "bl", "br", "_r", "_b"]
const PIVOT_TOLERANCE := 0.05    # m : écart max entre l'origine d'une roue et le centre de ses meshes
const ORIGIN_TOLERANCE := 1.0    # m : écart max (plan XZ) entre l'origine du modèle et le centre de son AABB


func _ready() -> void:
	var files: Array[String] = []
	for root: String in ROOTS:
		_collect(root, files)
	files.append_array(REFERENCE_CARS)

	var csv := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	csv.store_line("path;ok;meshes;surfaces;verts;size_x;size_y;size_z;center_x;center_z;min_y;vcol_surfaces;vcol_albedo_surfaces;vcol_avg;textured_surfaces;wheels_heel;wheels_tire;wheel_pivot_off;skeletons;front_axis")
	var groups: Dictionary = {}
	var anomalies: Array[String] = []
	var flat: Array[String] = []
	for path in files:
		var r := _inspect(path)
		var avg: Color = r.vcol_avg
		csv.store_line(";".join(PackedStringArray([path, str(r.ok), str(r.meshes), str(r.surfaces), str(r.verts),
				"%.2f" % r.size.x, "%.2f" % r.size.y, "%.2f" % r.size.z, "%.2f" % r.center.x, "%.2f" % r.center.z,
				"%.2f" % r.min_y, str(r.vcol), str(r.vcol_albedo), "%.2f/%.2f/%.2f" % [avg.r, avg.g, avg.b],
				str(r.textured), str(r.heel), str(r.tire), "%.2f" % r.pivot_off, str(r.skeletons), r.front_axis])))
		var key := _group_of(path)
		if not groups.has(key):
			groups[key] = {"files": 0, "ok": 0, "verts": 0, "vcol_albedo": 0, "vcol_files": 0, "vcol_sum": Color(0, 0, 0, 0),
					"textured": 0, "heel4": 0, "tire_only": 0, "pivot_bad": 0, "origin_off": 0, "skel": 0, "plus_z": 0,
					"minus_z": 0, "unknown_axis": 0, "min_len": INF, "max_len": 0.0, "max_h": 0.0}
		var g: Dictionary = groups[key]
		g["files"] += 1
		if not r.ok:
			anomalies.append("ÉCHEC chargement : " + path)
			continue
		g["ok"] += 1
		g["verts"] += r.verts
		if r.surfaces > 0 and r.vcol_albedo == r.surfaces:
			g["vcol_albedo"] += 1
		if r.vcol > 0:
			g["vcol_files"] += 1
			g["vcol_sum"] += avg
		if r.textured > 0:
			g["textured"] += 1
		if r.heel >= 4:
			g["heel4"] += 1
		elif r.tire >= 4:
			g["tire_only"] += 1
		if r.pivot_off > PIVOT_TOLERANCE:
			g["pivot_bad"] += 1
		if Vector2(r.center.x, r.center.z).length() > ORIGIN_TOLERANCE:
			g["origin_off"] += 1
		if r.skeletons > 0:
			g["skel"] += 1
		match r.front_axis:
			"+Z":
				g["plus_z"] += 1
			"-Z":
				g["minus_z"] += 1
			_:
				g["unknown_axis"] += 1
		var length: float = max(r.size.x, r.size.z)
		g["min_len"] = min(g["min_len"], length)
		g["max_len"] = max(g["max_len"], length)
		g["max_h"] = max(g["max_h"], r.size.y)
		if r.meshes == 0:
			anomalies.append("aucun mesh : " + path)
		elif path.contains("everythinglibrary"):
			if r.vcol_albedo < r.surfaces:
				anomalies.append("couleurs de sommets non utilisées en albedo : " + path)
			if avg.get_luminance() > 0.97 or avg.get_luminance() < 0.02:
				anomalies.append("couleurs de sommets suspectes (moyenne %s) : %s" % [avg, path])
		elif path.contains("vehicle_models_extra") and r.textured == 0 and r.vcol == 0:
			flat.append(path.get_file())

	var keys := groups.keys()
	keys.sort()
	for key in keys:
		var g: Dictionary = groups[key]
		var mean_color: Color = g.vcol_sum / g.vcol_files if g.vcol_files > 0 else Color(0, 0, 0)
		print("[ExtraPacks] %s : %d/%d chargés | sommets %d | couleurs de sommets %d fichiers (moyenne %.2f/%.2f/%.2f), albedo=couleurs %d | texturés %d | roues '*heel*' x4+ %d | roues 'Tire' seules %d | pivots de roue décentrés %d | origine décalée %d | squelettes %d | avant +Z %d / -Z %d / ? %d | longueur %.1f-%.1f m | hauteur max %.1f m"
				% [key, g.ok, g.files, g.verts, g.vcol_files, mean_color.r, mean_color.g, mean_color.b, g.vcol_albedo, g.textured,
				g.heel4, g.tire_only, g.pivot_bad, g.origin_off, g.skel, g.plus_z, g.minus_z, g.unknown_axis, g.min_len,
				g.max_len, g.max_h])
	if not flat.is_empty():
		print("[ExtraPacks] véhicules à matériaux unis (ni texture ni couleurs de sommets) : %s" % ", ".join(flat))
	for a in anomalies.slice(0, 30):
		print("[ExtraPacks] ANOMALIE " + a)
	print("[ExtraPacks] RÉSULTAT : %s (%d fichiers, %d anomalies) -> %s"
			% ["OK" if anomalies.is_empty() else "À VÉRIFIER", files.size(), anomalies.size(), ProjectSettings.globalize_path(REPORT_PATH)])
	csv.close()
	get_tree().quit(0 if anomalies.is_empty() else 1)


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("dossier introuvable : " + dir_path)
		return
	for sub in dir.get_directories():
		if not sub.begins_with("_") and not sub.begins_with("."):
			_collect(dir_path.path_join(sub), out)
	for f in dir.get_files():
		if f.get_extension().to_lower() == "glb":
			out.append(dir_path.path_join(f))


func _group_of(path: String) -> String:
	var parts := path.trim_prefix("res://assets/").split("/")
	if parts.size() <= 2:
		return parts[0]
	return parts[0] + "/" + parts[1]


func _inspect(path: String) -> Dictionary:
	var r := {"ok": false, "meshes": 0, "surfaces": 0, "verts": 0, "size": Vector3.ZERO, "center": Vector3.ZERO,
			"min_y": 0.0, "vcol": 0, "vcol_albedo": 0, "vcol_avg": Color(0, 0, 0), "textured": 0, "heel": 0,
			"tire": 0, "pivot_off": 0.0, "skeletons": 0, "front_axis": "?"}
	var scene := load(path) as PackedScene
	if scene == null:
		return r
	var inst := scene.instantiate() as Node3D
	if inst == null:
		return r
	r["ok"] = true
	var aabb := AABB()
	var has_aabb := false
	var front_z: Array[float] = []
	var rear_z: Array[float] = []
	var color_sum := Color(0, 0, 0, 0)
	var color_count := 0
	var nodes := inst.find_children("*", "Node3D", true, false)
	nodes.append(inst)
	for n in nodes:
		var n3 := n as Node3D
		var lname := String(n3.name).to_lower()
		if n3 is Skeleton3D:
			r["skeletons"] += 1
		if lname.contains("heel") or lname.contains("tire") or lname.contains("tyre"):
			r["heel" if lname.contains("heel") else "tire"] += 1
			_measure_wheel(n3, inst, lname, r, front_z, rear_z)
		var mi := n3 as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		r["meshes"] += 1
		var box := _to_ancestor(mi, inst) * mi.mesh.get_aabb()
		aabb = aabb.merge(box) if has_aabb else box
		has_aabb = true
		for s in mi.mesh.get_surface_count():
			r["surfaces"] += 1
			var am := mi.mesh as ArrayMesh
			var has_vcol := am != null and (am.surface_get_format(s) & Mesh.ARRAY_FORMAT_COLOR) != 0
			if am != null:
				r["verts"] += am.surface_get_array_len(s)
			if has_vcol:
				r["vcol"] += 1
				var colors: PackedColorArray = am.surface_get_arrays(s)[Mesh.ARRAY_COLOR]
				for c in colors:
					color_sum += c
				color_count += colors.size()
			var mat := mi.get_active_material(s) as BaseMaterial3D
			if mat != null:
				if has_vcol and mat.vertex_color_use_as_albedo:
					r["vcol_albedo"] += 1
				if mat.albedo_texture != null:
					r["textured"] += 1
	if has_aabb:
		r["size"] = aabb.size
		r["center"] = aabb.get_center()
		r["min_y"] = aabb.position.y
	if color_count > 0:
		r["vcol_avg"] = color_sum / color_count
	if not front_z.is_empty() and not rear_z.is_empty():
		r["front_axis"] = "+Z" if _mean(front_z) > _mean(rear_z) else "-Z"
	inst.free()
	return r


# Roue : écart entre son origine (pivot de rotation utilisé par Car.gd) et le centre de ses meshes, puis
# position avant/arrière de ce centre (repère du modèle) si le nom de la roue l'indique.
func _measure_wheel(wheel: Node3D, root: Node3D, lname: String, r: Dictionary, front_z: Array[float], rear_z: Array[float]) -> void:
	var local := AABB()
	var has := false
	var parts := wheel.find_children("*", "MeshInstance3D", true, false)
	parts.append(wheel)
	for p in parts:
		var mi := p as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var box := _to_ancestor(mi, wheel) * mi.mesh.get_aabb()
		local = local.merge(box) if has else box
		has = true
	if not has:
		return
	var to_root := _to_ancestor(wheel, root)
	var center := to_root * local.get_center()
	r["pivot_off"] = maxf(r["pivot_off"], center.distance_to(to_root.origin))
	if FRONT_TOKENS.any(func(t: String) -> bool: return lname.contains(t)):
		front_z.append(center.z)
	elif REAR_TOKENS.any(func(t: String) -> bool: return lname.contains(t)):
		rear_z.append(center.z)


func _to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != ancestor:
		var n3 := n as Node3D
		if n3 != null:
			t = n3.transform * t
		n = n.get_parent()
	return t


func _mean(values: Array[float]) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total / values.size()
