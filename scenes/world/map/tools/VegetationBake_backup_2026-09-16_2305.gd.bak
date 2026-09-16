extends SceneTree

# Étape 6 : végétation de la carte 3D. Forêts des zones boisées, collines en bordure de carte, bosquets de la campagne,
# haies de la campagne est le long des parcelles, arbres des jardins et des espaces libres des quartiers.
#  - placement sur une grille jittée de 11 m, densité selon le contexte (bruit de bosquets), jamais sur une chaussée,
#    la voie ferrée, l'eau, le centre-ville, un bâtiment ou un lieu (grille d'occupation de 4 m), ni près des points
#    de contrôle du garde-fou ;
#  - arbres détaillés (pins et feuillus du kit nature, maillages fusionnés à niveaux de détail) par cellules de 128 m,
#    visibles jusqu'à NEAR_RANGE m du centre de la cellule ; silhouettes légères (couleurs de sommet, shader
#    vegetation_far) par blocs de 512 m jusqu'à FAR_RANGE m, repliées par le shader à moins de FAR_HIDE m de la caméra
#    (portée des arbres détaillés moins la demi-diagonale d'une cellule : jamais de trou) ;
#  - collision des troncs (prismes, une forme par cellule, dans la zone explorable) ;
#  - generated/Vegetation.tscn instanciée dans Map.tscn, generated/vegetation/vegetation.json (comptes, pour les tests).
#
# Lancer après PlacesBake : Godot --headless --path <projet> --script res://scenes/world/map/tools/VegetationBake.gd

const Spec := preload("res://scenes/world/map/MapSpec.gd")
const Model := preload("res://scenes/world/map/tools/TerrainModel.gd")
const Network := preload("res://scenes/world/map/tools/RoadNetwork.gd")
const FIELD_SCRIPT := preload("res://scenes/world/map/BuildingField.gd")
const GEN := "res://scenes/world/map/generated"
const OUT := "res://scenes/world/map/generated/vegetation"
const SCENE := "res://scenes/world/map/generated/Vegetation.tscn"
const MAP_SCENE := "res://scenes/world/map/Map.tscn"
const LOTS := "res://scenes/world/map/generated/buildings/lots.json"
const PLACES := "res://scenes/world/map/generated/places/places.json"
const NEAR_CELL := 192.0
const FAR_BLOCK := 512.0
const NEAR_RANGE := 300.0
const FAR_RANGE := 2600.0
const FAR_HIDE := 290.0
const SPACING := 11.0
const GRID := 4.0
const NORTHERN_FORESTS := ["cedar_gulch", "foret_nord_ouest", "bois_nord_est"]
# espèces : modèle détaillé, silhouette lointaine, échelle
const SPECIES := {
	"pine": {"path": "res://assets/nature_kit/trees/Pine_5.gltf", "scale": Vector2(1.2, 2.0)},
	"oak": {"path": "res://assets/nature_kit/trees/CommonTree_5.gltf", "scale": Vector2(1.3, 2.2)},
	"elm": {"path": "res://assets/nature_kit/trees/CommonTree_3.gltf", "scale": Vector2(1.1, 1.8)},
}
const SPECIES_CODE := {"pine": 0.0, "oak": 0.5, "elm": 1.0}
const TRUNK_RADIUS := 0.3
const TRUNK_HEIGHT := 4.0

var model: Model
var net: Network
var heights := PackedFloat32Array()
var mask := PackedByteArray()
var mask_w := 0
var mask_h := 0
var noise := FastNoiseLite.new()
var trees: Array[Dictionary] = []          # {"species", "pos": Vector3, "yaw", "scale", "tint"}
var near_meshes := {}
var far_meshes := {}
var stats := {"arbres": 0, "par_contexte": {}, "par_espèce": {}, "cellules": 0, "blocs": 0, "troncs": 0}


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	model = Model.new()
	net = Network.new(model)
	net.build()
	if not net.errors.is_empty():
		print("VEGETATION_ERROR réseau routier en erreur")
		quit(1)
		return
	heights = (load(GEN + "/terrain/heights.res") as Image).get_data().to_float32_array()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for file in DirAccess.get_files_at(OUT):
		if file.begins_with("trunks_") or file.ends_with("_far.res"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(OUT.path_join(file)))
	noise.seed = 9091
	noise.frequency = 0.004
	noise.fractal_octaves = 3
	_build_mask()
	print("VEGETATION masque %dx%d en %.1f s" % [mask_w, mask_h, (Time.get_ticks_msec() - t0) / 1000.0])
	_scatter()
	for species: String in SPECIES:
		near_meshes[species] = _near_mesh(species)
	far_meshes = _far_meshes()
	_write_scene()
	var f := FileAccess.open(OUT.path_join("vegetation.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(stats, "\t"))
	f.close()
	_ensure_in_map()
	print("VEGETATION_BAKE %s en %.1f s" % [stats, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0)


# --- occupation -------------------------------------------------------------------------------------------------
func _build_mask() -> void:
	var r := Spec.TERRAIN
	mask_w = ceili(r.size.x / GRID)
	mask_h = ceili(r.size.y / GRID)
	mask.resize(mask_w * mask_h)
	var downtown := Spec.DOWNTOWN.grow(15.0)
	for j in mask_h:
		for i in mask_w:
			var p := r.position + Vector2(i + 0.5, j + 0.5) * GRID
			if downtown.has_point(p) or model.is_excluded(p) or model.river_info(p).x < 5.0:
				mask[j * mask_w + i] = 1
				continue
			for lake: Dictionary in Spec.LAKES:
				if ((p - lake["center"]) / (lake["radii"] * 1.15 + Vector2(4.0, 4.0))).length() < 1.0:
					mask[j * mask_w + i] = 1
					break
	for rb in net.ribbons:
		for p: Vector3 in rb.points:
			_stamp_disc(Vector2(p.x, p.z), float(rb.width) * 0.5 + 5.0)
	for pad: Dictionary in net.pads:
		var c: Vector3 = pad["center"]
		var radius := 0.0
		for p: Vector3 in pad["rim"]:
			radius = maxf(radius, Vector2(p.x - c.x, p.z - c.z).length())
		_stamp_disc(Vector2(c.x, c.z), radius + 5.0)
	for k in net.rail_line.size():
		_stamp_disc(net.rail_line[k], 7.0)
	# tunnels et sorties de carte des autoroutes : leur couloir au-delà de la limite
	for t: Dictionary in net.tunnels:
		var a: Vector3 = t["pos"]
		var dir: Vector2 = t["dir"]
		for s in range(-60, 80, 4):
			_stamp_disc(Vector2(a.x, a.z) + dir * s, float(t["width"]) * 0.5 + 6.0)
	if FileAccess.file_exists(LOTS):
		for lot: Dictionary in JSON.parse_string(FileAccess.get_file_as_string(LOTS)):
			var yaw := float(lot["yaw"])
			var front := Vector2(sin(yaw), cos(yaw))
			_stamp_rect(Vector2(float(lot["x"]), float(lot["z"])), Vector2(-front.y, front.x), front, Vector2(float(lot["size"][0]), float(lot["size"][2])) * 0.5 + Vector2(5.0, 5.0))
	if FileAccess.file_exists(PLACES):
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PLACES))
		for fp: Dictionary in data["footprints"]:
			var lo := Vector2(INF, INF)
			var hi := -lo
			for q: Array in fp["poly"]:
				lo = lo.min(Vector2(float(q[0]), float(q[1])))
				hi = hi.max(Vector2(float(q[0]), float(q[1])))
			_stamp_rect((lo + hi) * 0.5, Vector2(1, 0), Vector2(0, 1), (hi - lo) * 0.5 + Vector2(8.0, 8.0))
	for poi: Dictionary in Spec.POIS:
		# aéroport, parcs et cours des lieux : dégagés en entier ; ranch : pâture laissée libre autour de la cour
		var grow := 10.0 if poi["kind"] != "ranch" else -60.0
		_stamp_rect(poi["pos"], Vector2(1, 0), Vector2(0, 1), Vector2(poi["size"]) * 0.5 + Vector2(grow, grow))
	for spot: Dictionary in Spec.GATE_SPOTS:
		_stamp_disc(spot["pos"], 18.0)


func _stamp_disc(p: Vector2, radius: float) -> void:
	var c := (p - Spec.TERRAIN.position) / GRID
	var r := radius / GRID
	for j in range(maxi(0, floori(c.y - r)), mini(mask_h - 1, ceili(c.y + r)) + 1):
		for i in range(maxi(0, floori(c.x - r)), mini(mask_w - 1, ceili(c.x + r)) + 1):
			if Vector2(i + 0.5, j + 0.5).distance_squared_to(c) <= r * r:
				mask[j * mask_w + i] = 1


func _stamp_rect(center: Vector2, right: Vector2, front: Vector2, half: Vector2) -> void:
	if half.x <= 0.0 or half.y <= 0.0:
		return
	var c := (center - Spec.TERRAIN.position) / GRID
	var r := half.length() / GRID + 1.0
	for j in range(maxi(0, floori(c.y - r)), mini(mask_h - 1, ceili(c.y + r)) + 1):
		for i in range(maxi(0, floori(c.x - r)), mini(mask_w - 1, ceili(c.x + r)) + 1):
			var d := Spec.TERRAIN.position + Vector2(i + 0.5, j + 0.5) * GRID - center
			if absf(d.dot(right)) <= half.x and absf(d.dot(front)) <= half.y:
				mask[j * mask_w + i] = 1


func _free(p: Vector2) -> bool:
	var i := floori((p.x - Spec.TERRAIN.position.x) / GRID)
	var j := floori((p.y - Spec.TERRAIN.position.y) / GRID)
	return i >= 0 and j >= 0 and i < mask_w and j < mask_h and mask[j * mask_w + i] == 0


# --- répartition ------------------------------------------------------------------------------------------------
func _scatter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var zone_polys: Array = []
	for zone: Dictionary in Spec.ZONES:
		var poly := Spec.zone_polygon(zone)
		var bounds := Rect2(poly[0], Vector2.ZERO)
		for q in poly:
			bounds = bounds.expand(q)
		zone_polys.append([zone, poly, bounds])
	var r := Spec.TERRAIN
	var nx := int(r.size.x / SPACING)
	var nz := int(r.size.y / SPACING)
	for j in nz:
		for i in nx:
			var p := r.position + Vector2(i + 0.5, j + 0.5) * SPACING + Vector2(rng.randf_range(-4.5, 4.5), rng.randf_range(-4.5, 4.5))
			var roll := rng.randf()
			if not _free(p):
				continue
			var zone: Dictionary = {}
			for entry: Array in zone_polys:
				if (entry[2] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, entry[1]):
					zone = entry[0]
					break
			var grove := clampf(noise.get_noise_2d(p.x, p.y) * 0.5 + 0.5, 0.0, 1.0)
			var context := "campagne"
			var chance := 0.0
			if not Spec.PLAYABLE.has_point(p):
				context = "bordure"
				chance = 0.08 + 0.3 * smoothstep(0.35, 0.7, grove)
			elif zone.is_empty():
				chance = 0.02 + 0.45 * smoothstep(0.58, 0.75, grove)
			else:
				context = String(zone["type"])
				match context:
					"forest":
						chance = 0.5 + 0.3 * grove
					"farmland":
						var hedge := fposmod(p.x, 150.0) < 6.0 or fposmod(p.y, 110.0) < 6.0
						var cell := Vector2i(floori(p.x / 150.0), floori(p.y / 110.0))
						chance = 0.5 if hedge and absi((cell.x * 92821) ^ (cell.y * 68917)) % 3 != 0 else 0.012
					"suburb", "residential":
						chance = 0.09 + 0.1 * smoothstep(0.5, 0.8, grove)
					"mixed":
						chance = 0.04
					"industrial":
						chance = 0.015
					_:
						chance = 0.0
			if roll >= chance:
				continue
			var northern: bool = context == "bordure" or (not zone.is_empty() and String(zone["id"]) in NORTHERN_FORESTS)
			var species := "pine" if rng.randf() < (0.62 if northern else 0.22) else ("oak" if rng.randf() < 0.6 else "elm")
			var range: Vector2 = SPECIES[species]["scale"]
			var scale := rng.randf_range(range.x, range.y)
			var ground := _height(p)
			var shade := rng.randf_range(0.85, 1.12)
			trees.append({"species": species, "pos": Vector3(p.x, ground - 0.15, p.y), "yaw": rng.randf() * TAU, "scale": scale,
					"tint": Color(shade * rng.randf_range(0.95, 1.05), shade, shade * rng.randf_range(0.9, 1.0))})
			var per_context: Dictionary = stats["par_contexte"]
			per_context[context] = int(per_context.get(context, 0)) + 1
			var per_species: Dictionary = stats["par_espèce"]
			per_species[species] = int(per_species.get(species, 0)) + 1
	stats["arbres"] = trees.size()


func _height(p: Vector2) -> float:
	var fx := (p.x - Spec.TERRAIN.position.x) / Model.CELL
	var fz := (p.y - Spec.TERRAIN.position.y) / Model.CELL
	var i := clampi(floori(fx), 0, model.width - 2)
	var j := clampi(floori(fz), 0, model.depth - 2)
	var tx := clampf(fx - i, 0.0, 1.0)
	var tz := clampf(fz - j, 0.0, 1.0)
	var w := model.width
	return lerpf(lerpf(heights[j * w + i], heights[j * w + i + 1], tx), lerpf(heights[(j + 1) * w + i], heights[(j + 1) * w + i + 1], tx), tz)


# --- maillages --------------------------------------------------------------------------------------------------
# Arbre détaillé : sous-maillages fusionnés avec leurs transformations, matériaux d'origine, niveaux de détail.
func _near_mesh(species: String) -> Mesh:
	var inst: Node = (load(SPECIES[species]["path"]) as PackedScene).instantiate()
	var importer := ImporterMesh.new()
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var xform := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != inst and cur != null:
			if cur is Node3D:
				xform = (cur as Node3D).transform * xform
			cur = cur.get_parent()
		for s in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for k in verts.size():
				verts[k] = xform * verts[k]
				normals[k] = (xform.basis * normals[k]).normalized()
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_TANGENT] = null
			importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mi.get_active_material(s))
	inst.free()
	importer.generate_lods(25.0, 60.0, [])
	var path := OUT.path_join("%s.res" % species)
	ResourceSaver.save(importer.get_mesh(), path)
	return load(path)


# Silhouettes lointaines (échelle 1 = modèle détaillé) : pin en deux cônes étagés, feuillus en couronne à 12 faces,
# réunies dans un seul maillage (UV.x = code d'espèce) : le shader ne garde que la silhouette de l'espèce de
# l'instance (INSTANCE_CUSTOM.r), un seul appel de dessin par bloc.
func _far_meshes() -> Dictionary:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scenes/world/map/shaders/vegetation_far.gdshader")
	mat.set_shader_parameter("near_hide", FAR_HIDE)
	var mat_path := OUT.path_join("far_material.tres")
	ResourceSaver.save(mat, mat_path)
	mat = load(mat_path)
	var out := {}
	var all_verts := PackedVector3Array()
	var all_normals := PackedVector3Array()
	var all_colors := PackedColorArray()
	var all_uvs := PackedVector2Array()
	var shapes := {
		"pine": [[3.0, 1.2, 5.6, Color(0.13, 0.24, 0.12)], [2.3, 4.2, 8.7, Color(0.15, 0.27, 0.13)]],
		"oak": [[2.0, 2.9, 7.0, Color(0.2, 0.33, 0.14)]],
		"elm": [[2.1, 3.4, 9.4, Color(0.22, 0.35, 0.15)]],
	}
	for species: String in shapes:
		var verts := PackedVector3Array()
		var normals := PackedVector3Array()
		var colors := PackedColorArray()
		for part: Array in shapes[species]:
			var radius: float = part[0]
			var y0: float = part[1]
			var y1: float = part[2]
			var color: Color = part[3]
			if species == "pine":
				for k in 6:
					var a0 := TAU * k / 6.0
					var a1 := TAU * (k + 1) / 6.0
					var p0 := Vector3(cos(a0) * radius, y0, sin(a0) * radius)
					var p1 := Vector3(cos(a1) * radius, y0, sin(a1) * radius)
					var apex := Vector3(0, y1, 0)
					_tri(verts, normals, colors, p0, apex, p1, color.darkened(0.15), color)
			else:
				var mid := (y0 + y1) * 0.55
				var top := Vector3(0, y1, 0)
				var bottom := Vector3(0, y0, 0)
				for k in 6:
					var a0 := TAU * k / 6.0
					var a1 := TAU * (k + 1) / 6.0
					var p0 := Vector3(cos(a0) * radius, mid, sin(a0) * radius)
					var p1 := Vector3(cos(a1) * radius, mid, sin(a1) * radius)
					_tri(verts, normals, colors, p0, top, p1, color, color.lightened(0.08))
					_tri(verts, normals, colors, p1, bottom, p0, color.darkened(0.2), color.darkened(0.1))
		for k in verts.size():
			all_uvs.append(Vector2(SPECIES_CODE[species], 0.0))
		all_verts.append_array(verts)
		all_normals.append_array(normals)
		all_colors.append_array(colors)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = all_verts
	arrays[Mesh.ARRAY_NORMAL] = all_normals
	arrays[Mesh.ARRAY_COLOR] = all_colors
	arrays[Mesh.ARRAY_TEX_UV] = all_uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	var path := OUT.path_join("far_trees.res")
	ResourceSaver.save(mesh, path)
	out["all"] = load(path)
	return out


# Triangle a-b-c vu de l'extérieur (sens horaire côté normale, convention de Godot) ; `tip` : couleur du sommet b.
func _tri(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3, base_color: Color, tip: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	var outward := ((a + b + c) / 3.0 - Vector3(0, (a.y + b.y + c.y) / 3.0, 0)).normalized()
	if n.dot(outward) > 0.0:
		var t := b
		b = c
		c = t
		n = -n
	verts.append_array(PackedVector3Array([a, b, c]))
	var face := -n
	normals.append_array(PackedVector3Array([face, face, face]))
	colors.append_array(PackedColorArray([base_color, tip if b.y >= c.y else base_color, base_color if b.y >= c.y else tip]))


# --- scène --------------------------------------------------------------------------------------------------------
func _write_scene() -> void:
	var root := Node3D.new()
	root.name = "Vegetation"
	var near_cells := {}
	var far_blocks := {}
	for tree in trees:
		var p: Vector3 = tree["pos"]
		var key := Vector2i(floori(p.x / NEAR_CELL), floori(p.z / NEAR_CELL))
		if not near_cells.has(key):
			near_cells[key] = []
		near_cells[key].append(tree)
		var block := Vector2i(floori(p.x / FAR_BLOCK), floori(p.z / FAR_BLOCK))
		if not far_blocks.has(block):
			far_blocks[block] = []
		far_blocks[block].append(tree)
	var trunk_shape_faces := _trunk_prism()
	var keys := near_cells.keys()
	keys.sort()
	for key: Vector2i in keys:
		var cell := Node3D.new()
		cell.name = "TreeCell_%03d_%03d" % [key.x + 40, key.y + 40]
		root.add_child(cell)
		cell.add_child(_field(near_cells[key], near_meshes, NEAR_RANGE + NEAR_CELL * 0.71, true))
		var faces := PackedVector3Array()
		for tree: Dictionary in near_cells[key]:
			var p: Vector3 = tree["pos"]
			if not Spec.PLAYABLE.grow(20.0).has_point(Vector2(p.x, p.z)):
				continue
			var s: float = tree["scale"]
			for v in trunk_shape_faces:
				faces.append(Vector3(v.x * s, v.y, v.z * s) + p)
			stats["troncs"] += 1
		if not faces.is_empty():
			var body := StaticBody3D.new()
			body.name = "Trunks"
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(faces)
			shape.backface_collision = true
			var shape_path := OUT.path_join("trunks_%03d_%03d.res" % [key.x + 40, key.y + 40])
			ResourceSaver.save(shape, shape_path)
			var cs := CollisionShape3D.new()
			cs.name = "Shape"
			cs.shape = load(shape_path)
			body.add_child(cs)
			cell.add_child(body)
	var block_keys := far_blocks.keys()
	block_keys.sort()
	for block: Vector2i in block_keys:
		var node := _far_field(far_blocks[block])
		node.name = "FarBlock_%02d_%02d" % [block.x + 10, block.y + 10]
		root.add_child(node)
	stats["cellules"] = keys.size()
	stats["blocs"] = block_keys.size()
	_pack(root, SCENE)


func _field(list: Array, mesh_by_species: Dictionary, range_end: float, shadows: bool) -> Node3D:
	var field := Node3D.new()
	field.name = "Field"
	field.set_script(FIELD_SCRIPT)
	var meshes: Array[Mesh] = []
	var data: Array[PackedFloat32Array] = []
	var ranges := PackedFloat32Array()
	for species: String in SPECIES:
		var buffer := PackedFloat32Array()
		for tree: Dictionary in list:
			if tree["species"] != species:
				continue
			var basis := Basis(Vector3.UP, float(tree["yaw"])).scaled(Vector3.ONE * float(tree["scale"]))
			var p: Vector3 = tree["pos"]
			var tint: Color = tree["tint"]
			buffer.append_array(PackedFloat32Array([basis.x.x, basis.x.y, basis.x.z, basis.y.x, basis.y.y, basis.y.z,
					basis.z.x, basis.z.y, basis.z.z, p.x, p.y, p.z, tint.r, tint.g, tint.b, 1.0]))
		if buffer.is_empty():
			continue
		meshes.append(mesh_by_species[species])
		data.append(buffer)
		ranges.append(range_end)
	field.set("meshes", meshes)
	field.set("instance_data", data)
	field.set("ranges", ranges)
	field.set("shadows", shadows)
	return field


# Bloc de silhouettes lointaines : un seul maillage, espèce de chaque instance dans INSTANCE_CUSTOM.r.
func _far_field(list: Array) -> Node3D:
	var field := Node3D.new()
	field.set_script(FIELD_SCRIPT)
	var buffer := PackedFloat32Array()
	var custom := PackedFloat32Array()
	for tree: Dictionary in list:
		var basis := Basis(Vector3.UP, float(tree["yaw"])).scaled(Vector3.ONE * float(tree["scale"]))
		var p: Vector3 = tree["pos"]
		var tint: Color = tree["tint"]
		buffer.append_array(PackedFloat32Array([basis.x.x, basis.x.y, basis.x.z, basis.y.x, basis.y.y, basis.y.z,
				basis.z.x, basis.z.y, basis.z.z, p.x, p.y, p.z, tint.r, tint.g, tint.b, 1.0]))
		custom.append_array(PackedFloat32Array([SPECIES_CODE[tree["species"]], 0.0, 0.0, 0.0]))
	var meshes: Array[Mesh] = [far_meshes["all"]]
	var data: Array[PackedFloat32Array] = [buffer]
	var customs: Array[PackedFloat32Array] = [custom]
	field.set("meshes", meshes)
	field.set("instance_data", data)
	field.set("instance_custom", customs)
	field.set("ranges", PackedFloat32Array([FAR_RANGE]))
	field.set("shadows", false)
	return field


# Prisme hexagonal de tronc (rayon TRUNK_RADIUS, hauteur TRUNK_HEIGHT) en triangles de collision.
func _trunk_prism() -> PackedVector3Array:
	var out := PackedVector3Array()
	for k in 6:
		var a0 := TAU * k / 6.0
		var a1 := TAU * (k + 1) / 6.0
		var b0 := Vector3(cos(a0) * TRUNK_RADIUS, 0.0, sin(a0) * TRUNK_RADIUS)
		var b1 := Vector3(cos(a1) * TRUNK_RADIUS, 0.0, sin(a1) * TRUNK_RADIUS)
		var t0 := b0 + Vector3(0, TRUNK_HEIGHT, 0)
		var t1 := b1 + Vector3(0, TRUNK_HEIGHT, 0)
		out.append_array(PackedVector3Array([b0, t0, b1, b1, t0, t1]))
	return out


func _ensure_in_map() -> void:
	var text := FileAccess.get_file_as_string(MAP_SCENE)
	if text.contains(SCENE):
		return
	var last_ext := text.rfind("[ext_resource")
	var insert_at := text.find("\n", last_ext) + 1
	text = text.substr(0, insert_at) + '[ext_resource type="PackedScene" path="%s" id="7_vegetation"]\n' % SCENE + text.substr(insert_at)
	text = text.strip_edges() + '\n\n[node name="Vegetation" type="Node3D" parent="." unique_id=1377240991 instance=ExtResource("7_vegetation")]\n'
	var f := FileAccess.open(MAP_SCENE, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("VEGETATION_BAKE Map.tscn : Vegetation ajoutée")


func _pack(root: Node, path: String) -> void:
	_own(root, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	print("VEGETATION_SCENE %s : %s" % [path, error_string(err)])
	root.free()


func _own(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_own(child, root)
