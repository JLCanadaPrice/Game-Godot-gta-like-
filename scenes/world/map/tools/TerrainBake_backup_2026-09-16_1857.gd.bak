extends SceneTree

# Étape 1 : cuisson du terrain et de l'eau de la carte 3D à partir de MapSpec et TerrainModel.
#  - grille de hauteurs de 4 m (generated/terrain/heights.res), reprise par les étapes suivantes ;
#  - tuiles de 256 m : maillage à LOD automatiques, jupes contre les fissures entre niveaux de détail, poids de matière
#    par sommet (herbe, terre, roche, sable selon la pente, l'eau proche et les zones), collision HeightMapShape3D,
#    trous sous le centre-ville et le bassin existants, pas d'ombre portée ;
#  - murs du bassin et limites de la zone explorable ;
#  - rivière et plans d'eau : surface avec le matériau d'eau existant (vagues calmées), dalle et zone de nage
#    (WaterZone) disposées comme celles du bassin ;
#  - scènes generated/Terrain.tscn, Water.tscn, Boundary.tscn et Map.tscn qui les instancie.
#
# Lancer : Godot --headless --path <projet> --script res://scenes/world/map/tools/TerrainBake.gd

const Spec := preload("res://scenes/world/map/MapSpec.gd")
const Model := preload("res://scenes/world/map/tools/TerrainModel.gd")
const WATER_ZONE_SCRIPT := preload("res://scenes/world/WaterZone.gd")
const BASE_WATER := preload("res://assets/water_shader/materials/WaterShader.tres")
const GEN := "res://scenes/world/map/generated"
const MAP_SCENE := "res://scenes/world/map/Map.tscn"
const TEXTURES := "res://scenes/world/map/terrain/textures"
const CELLS := 64
const CHUNK := 256.0
const SKIRT := 3.0
const ZONE_CELL := 8.0
const ZONE_CODES := {"downtown": 1, "suburb": 2, "residential": 3, "mixed": 4, "industrial": 5, "airport": 6, "farmland": 7, "forest": 8}
const WATER_ZONE_OFFSET := -1.934   # origine de la zone de nage sous la surface visible, comme le bassin
const SLAB_OFFSET := -0.35          # dalle d'eau (0,4 m) juste sous la surface, comme le bassin
const RIVER_OVERLAP := 24.0         # la surface de la rivière passe sous les berges

var model: Model
var heights := PackedFloat32Array()
var excluded := PackedByteArray()
var zones := PackedByteArray()
var zones_w := 0
var zones_h := 0
var _detail := FastNoiseLite.new()
var _stats := {"tuiles": 0, "triangles": 0, "cellules_trouees": 0, "troncons_riviere": 0}


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	model = Model.new()
	heights = model.build_heights()
	print("TERRAIN_HEIGHTS %dx%d en %.1f s, lacs %s" % [model.width, model.depth, (Time.get_ticks_msec() - t0) / 1000.0, model.lake_levels])
	_detail.seed = 911
	_detail.frequency = 1.0 / 90.0
	_build_excluded()
	_build_zone_raster()
	for sub in ["terrain", "water"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GEN.path_join(sub)))
	ResourceSaver.save(Image.create_from_data(model.width, model.depth, false, Image.FORMAT_RF, heights.to_byte_array()), GEN + "/terrain/heights.res")
	_build_terrain(_terrain_material())
	_build_water()
	_build_boundary()
	_ensure_map_scene()
	print("TERRAIN_BAKE %s en %.1f s" % [_stats, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0)


# --- rasters ----------------------------------------------------------------------------------------------------
func _build_excluded() -> void:
	excluded.resize(model.width * model.depth)
	for j in model.depth:
		for i in model.width:
			excluded[j * model.width + i] = 1 if model.is_excluded(model.grid_to_world(i, j)) else 0


func _build_zone_raster() -> void:
	zones_w = int(Spec.TERRAIN.size.x / ZONE_CELL) + 1
	zones_h = int(Spec.TERRAIN.size.y / ZONE_CELL) + 1
	zones.resize(zones_w * zones_h)
	var ordered: Array = []
	for pass_type in ["forest", "farmland", "other"]:
		for zone: Dictionary in Spec.ZONES:
			var t: String = zone["type"]
			if (pass_type == "other" and t != "forest" and t != "farmland") or t == pass_type:
				ordered.append(zone)
	for zone: Dictionary in ordered:
		var poly := Spec.zone_polygon(zone)
		var box := Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			box = box.expand(p)
		var i0 := maxi(0, int((box.position.x - Spec.TERRAIN.position.x) / ZONE_CELL))
		var i1 := mini(zones_w - 1, int((box.end.x - Spec.TERRAIN.position.x) / ZONE_CELL) + 1)
		var j0 := maxi(0, int((box.position.y - Spec.TERRAIN.position.y) / ZONE_CELL))
		var j1 := mini(zones_h - 1, int((box.end.y - Spec.TERRAIN.position.y) / ZONE_CELL) + 1)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var p := Spec.TERRAIN.position + Vector2(i, j) * ZONE_CELL
				if Geometry2D.is_point_in_polygon(p, poly):
					zones[j * zones_w + i] = ZONE_CODES[zone["type"]]


func _zone_at(p: Vector2) -> int:
	var i := clampi(int(roundf((p.x - Spec.TERRAIN.position.x) / ZONE_CELL)), 0, zones_w - 1)
	var j := clampi(int(roundf((p.y - Spec.TERRAIN.position.y) / ZONE_CELL)), 0, zones_h - 1)
	return zones[j * zones_w + i]


# --- terrain ----------------------------------------------------------------------------------------------------
func _terrain_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scenes/world/map/shaders/terrain.gdshader")
	for tex_name in ["grass", "dirt", "rock", "sand"]:
		mat.set_shader_parameter("tex_" + tex_name, load(TEXTURES.path_join(tex_name + ".png")))
	var path := GEN + "/terrain/terrain_material.tres"
	ResourceSaver.save(mat, path)
	return load(path)


func _build_terrain(material: Material) -> void:
	var root := Node3D.new()
	root.name = "Terrain"
	for cz in int(Spec.TERRAIN.size.y / CHUNK):
		for cx in int(Spec.TERRAIN.size.x / CHUNK):
			var body := _chunk(cx, cz, material)
			if body != null:
				root.add_child(body)
	_harbor_walls(root)
	_pack(root, GEN + "/Terrain.tscn")


func _chunk(cx: int, cz: int, material: Material) -> StaticBody3D:
	var i0 := cx * CELLS
	var j0 := cz * CELLS
	var n := CELLS + 1
	var origin := Spec.TERRAIN.position + Vector2(i0, j0) * Model.CELL
	var center := origin + Vector2(CHUNK, CHUNK) * 0.5
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for j in n:
		for i in n:
			var gi := i0 + i
			var gj := j0 + j
			var h := heights[gj * model.width + gi]
			var p := origin + Vector2(i, j) * Model.CELL
			var nrm := _normal(gi, gj)
			verts.append(Vector3(p.x - center.x, h, p.y - center.y))
			normals.append(nrm)
			colors.append(_splat(p, h, nrm))
	var solid := 0
	for j in CELLS:
		for i in CELLS:
			if _cell_hole(i0 + i, j0 + j):
				_stats["cellules_trouees"] += 1
				continue
			solid += 1
			var a := j * n + i
			indices.append_array(PackedInt32Array([a, a + 1, a + n, a + 1, a + n + 1, a + n]))
	if solid == 0:
		return null
	_add_skirts(verts, normals, colors, indices, i0, j0, n)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, material, "terrain")
	importer.generate_lods(25.0, 60.0, [])
	var mesh_path := GEN + "/terrain/chunk_%02d_%02d.res" % [cx, cz]
	ResourceSaver.save(importer.get_mesh(), mesh_path)
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	var data := PackedFloat32Array()
	data.resize(n * n)
	for j in n:
		for i in n:
			data[j * n + i] = heights[(j0 + j) * model.width + i0 + i]
	shape.map_data = data
	var shape_path := GEN + "/terrain/chunk_%02d_%02d_shape.res" % [cx, cz]
	ResourceSaver.save(shape, shape_path)
	var body := StaticBody3D.new()
	body.name = "Chunk_%02d_%02d" % [cx, cz]
	body.position = Vector3(center.x, 0.0, center.y)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = load(mesh_path)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	collision.name = "Shape"
	collision.shape = load(shape_path)
	collision.scale = Vector3(Model.CELL, 1.0, Model.CELL)
	body.add_child(collision)
	_stats["tuiles"] += 1
	_stats["triangles"] += indices.size() / 3
	return body


func _normal(gi: int, gj: int) -> Vector3:
	var w: int = model.width
	var hl := heights[gj * w + maxi(gi - 1, 0)]
	var hr := heights[gj * w + mini(gi + 1, w - 1)]
	var hu := heights[maxi(gj - 1, 0) * w + gi]
	var hd := heights[mini(gj + 1, model.depth - 1) * w + gi]
	return Vector3(hl - hr, 2.0 * Model.CELL, hu - hd).normalized()


func _cell_hole(gi: int, gj: int) -> bool:
	var w: int = model.width
	return excluded[gj * w + gi] == 1 and excluded[gj * w + gi + 1] == 1 \
			and excluded[(gj + 1) * w + gi] == 1 and excluded[(gj + 1) * w + gi + 1] == 1


# Poids de matière (herbe, terre, roche, sable) d'un sommet.
func _splat(p: Vector2, h: float, nrm: Vector3) -> Color:
	var rock := smoothstep(0.16, 0.34, 1.0 - nrm.y)
	var sand := 0.0
	var river: Vector2 = model.river_info(p)
	if river.x < 16.0:
		sand = 1.0 - smoothstep(0.0, 16.0, river.x)
	for lake: Dictionary in Spec.LAKES:
		var r: float = ((p - lake["center"]) / lake["radii"]).length()
		if r < 1.5:
			sand = maxf(sand, 1.0 - smoothstep(0.95, 1.5, r))
	if h < -0.6:
		sand = maxf(sand, 0.85)
	var dirt := 0.14
	match _zone_at(p):
		1:
			dirt = 0.22
		2, 3, 4:
			dirt = 0.12
		5:
			dirt = 0.55
		6:
			dirt = 0.06
		7:
			dirt = _field(p)
		8:
			dirt = 0.34
	dirt = clampf(dirt + _detail.get_noise_2d(p.x, p.y) * 0.18, 0.0, 1.0)
	var w_rock := rock
	var w_sand := sand * (1.0 - w_rock)
	var w_dirt := dirt * maxf(0.0, 1.0 - w_rock - w_sand)
	return Color(maxf(0.0, 1.0 - w_rock - w_sand - w_dirt), w_dirt, w_rock, w_sand)


# Champs en damier irrégulier : chaque parcelle a sa proportion de terre (labour, chaume, prairie).
func _field(p: Vector2) -> float:
	var cell := Vector2i(floori(p.x / 150.0), floori(p.y / 110.0))
	var hash := absi((cell.x * 73856093) ^ (cell.y * 19349663)) % 4
	return [0.12, 0.42, 0.78, 0.26][hash]


func _add_skirts(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, i0: int, j0: int, n: int) -> void:
	var edges := [
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 0)],
		[Vector2i(0, CELLS), Vector2i(1, 0), Vector2i(0, CELLS - 1)],
		[Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 0)],
		[Vector2i(CELLS, 0), Vector2i(0, 1), Vector2i(CELLS - 1, 0)],
	]
	for edge: Array in edges:
		var start: Vector2i = edge[0]
		var step: Vector2i = edge[1]
		var cell_base: Vector2i = edge[2]
		for k in CELLS:
			var cell := cell_base + step * k
			if _cell_hole(i0 + cell.x, j0 + cell.y):
				continue
			var p0 := start + step * k
			var p1 := p0 + step
			var a := p0.y * n + p0.x
			var b := p1.y * n + p1.x
			var base := verts.size()
			for src in [a, b]:
				verts.append(verts[src] - Vector3(0.0, SKIRT, 0.0))
				normals.append(normals[src])
				colors.append(colors[src])
			indices.append_array(PackedInt32Array([a, b, base, b, base + 1, base, a, base, b, b, base, base + 1]))


func _harbor_walls(root: Node3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.56, 0.55, 0.51)
	mat.roughness = 0.9
	var mat_path := GEN + "/terrain/harbor_wall_material.tres"
	ResourceSaver.save(mat, mat_path)
	var walls := Node3D.new()
	walls.name = "HarborWalls"
	root.add_child(walls)
	var top := 0.3
	var bottom := Model.HARBOR_UNDER
	var specs := [
		["Ouest", Vector3(-500.6, 0, -572.0), Vector3(1.2, 0, 157.0)],
		["Est", Vector3(0.6, 0, -572.0), Vector3(1.2, 0, 157.0)],
		["Nord", Vector3(-250.0, 0, -650.6), Vector3(502.4, 0, 1.2)],
	]
	for spec: Array in specs:
		var size := Vector3(spec[2].x, top - bottom, spec[2].z)
		var body := StaticBody3D.new()
		body.name = "Mur" + String(spec[0])
		body.position = Vector3(spec[1].x, (top + bottom) * 0.5, spec[1].z)
		var mesh := BoxMesh.new()
		mesh.size = size
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = mesh
		mi.material_override = load(mat_path)
		body.add_child(mi)
		var box := BoxShape3D.new()
		box.size = size
		var cs := CollisionShape3D.new()
		cs.name = "Shape"
		cs.shape = box
		body.add_child(cs)
		walls.add_child(body)


# --- eau --------------------------------------------------------------------------------------------------------
func _river_material() -> Material:
	var mat := BASE_WATER.duplicate() as ShaderMaterial
	mat.set_shader_parameter("vertex_wave_height", 0.06)
	mat.set_shader_parameter("wave_speed", 0.55)
	mat.set_shader_parameter("wave_choppiness", 1.2)
	mat.set_shader_parameter("normal_strength", 0.9)
	mat.set_shader_parameter("shoreline_foam_distance", 1.0)
	var path := GEN + "/water/river_water.tres"
	ResourceSaver.save(mat, path)
	return load(path)


func _build_water() -> void:
	var root := Node3D.new()
	root.name = "Water"
	var mat := _river_material()
	var curve: Array = model.river_curve(12.0)
	var piece := 0
	var k := 0
	while k < curve.size() - 1:
		var last := mini(k + 24, curve.size() - 1)
		_river_piece(root, curve, k, last, mat, piece)
		piece += 1
		k = last
	for lake: Dictionary in Spec.LAKES:
		_lake(root, lake, mat)
	_stats["troncons_riviere"] = piece
	_pack(root, GEN + "/Water.tscn")


func _river_piece(root: Node3D, curve: Array, first: int, last: int, mat: Material, index: int) -> void:
	var holder := Node3D.new()
	holder.name = "River_%02d" % index
	root.add_child(holder)
	var anchor: Vector2 = curve[first][0]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var columns := 8
	for s in range(first, last + 1):
		var p: Vector2 = curve[s][0]
		var dir := ((curve[mini(s + 1, curve.size() - 1)][0] as Vector2) - (curve[maxi(s - 1, 0)][0] as Vector2)).normalized()
		var side := Vector2(-dir.y, dir.x)
		var half: float = curve[s][1] * 0.5 + RIVER_OVERLAP
		for c in columns + 1:
			var q := p + side * lerpf(-half, half, float(c) / columns)
			verts.append(Vector3(q.x - anchor.x, Spec.WATER_LEVEL, q.y - anchor.y))
			normals.append(Vector3.UP)
	var rows := last - first
	for r in rows:
		for c in columns:
			var a := r * (columns + 1) + c
			var b := a + 1
			var d := a + columns + 1
			var e := d + 1
			var tri := [a, b, d, b, e, d]
			if (verts[b] - verts[a]).cross(verts[d] - verts[a]).y > 0.0:
				tri = [a, d, b, b, d, e]
			indices.append_array(PackedInt32Array(tri))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	var mesh_path := GEN + "/water/river_%02d.res" % index
	ResourceSaver.save(mesh, mesh_path)
	var mi := MeshInstance3D.new()
	mi.name = "Surface"
	mi.mesh = load(mesh_path)
	mi.position = Vector3(anchor.x, 0.0, anchor.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)
	var slab := StaticBody3D.new()
	slab.name = "Slab"
	slab.position.y = Spec.WATER_LEVEL + SLAB_OFFSET
	holder.add_child(slab)
	var zone := Area3D.new()
	zone.name = "WaterZone"
	zone.set_script(WATER_ZONE_SCRIPT)
	zone.position.y = Spec.WATER_LEVEL + WATER_ZONE_OFFSET
	holder.add_child(zone)
	var s := first
	while s < last:
		var t := mini(s + 4, last)
		var a: Vector2 = curve[s][0]
		var b: Vector2 = curve[t][0]
		var mid := (a + b) * 0.5
		var length := a.distance_to(b) + 8.0
		var across: float = maxf(curve[s][1], curve[t][1]) + 8.0
		var yaw := atan2(b.x - a.x, b.y - a.y)
		for pair in [[slab, 0.4], [zone, 6.0]]:
			var box := BoxShape3D.new()
			box.size = Vector3(across, pair[1], length)
			var cs := CollisionShape3D.new()
			cs.name = "Box_%d" % s
			cs.shape = box
			cs.position = Vector3(mid.x, 0.0, mid.y)
			cs.rotation.y = yaw
			(pair[0] as Node3D).add_child(cs)
		s = t


func _lake(root: Node3D, lake: Dictionary, mat: Material) -> void:
	var level: float = model.lake_levels[lake["id"]]
	var center: Vector2 = lake["center"]
	var radii: Vector2 = lake["radii"] * 1.15
	var holder := Node3D.new()
	holder.name = "Lake_" + String(lake["id"])
	holder.position = Vector3(center.x, 0.0, center.y)
	root.add_child(holder)
	var verts := PackedVector3Array([Vector3(0, level, 0)])
	var normals := PackedVector3Array([Vector3.UP])
	var indices := PackedInt32Array()
	var segments := 32
	for k in segments:
		var a := TAU * k / segments
		verts.append(Vector3(cos(a) * radii.x, level, sin(a) * radii.y))
		normals.append(Vector3.UP)
	for k in segments:
		var i1 := 1 + k
		var i2 := 1 + (k + 1) % segments
		var tri := [0, i1, i2]
		if (verts[i1] - verts[0]).cross(verts[i2] - verts[0]).y > 0.0:
			tri = [0, i2, i1]
		indices.append_array(PackedInt32Array(tri))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	var mesh_path := GEN + "/water/lake_%s.res" % lake["id"]
	ResourceSaver.save(mesh, mesh_path)
	var mi := MeshInstance3D.new()
	mi.name = "Surface"
	mi.mesh = load(mesh_path)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)
	var slab := StaticBody3D.new()
	slab.name = "Slab"
	slab.position.y = level + SLAB_OFFSET
	var zone := Area3D.new()
	zone.name = "WaterZone"
	zone.set_script(WATER_ZONE_SCRIPT)
	zone.position.y = level + WATER_ZONE_OFFSET
	for pair in [[slab, 0.4], [zone, 6.0]]:
		var box := BoxShape3D.new()
		box.size = Vector3(lake["radii"].x * 1.8, pair[1], lake["radii"].y * 1.8)
		var cs := CollisionShape3D.new()
		cs.name = "Box"
		cs.shape = box
		(pair[0] as Node3D).add_child(cs)
		holder.add_child(pair[0])


# --- limites ----------------------------------------------------------------------------------------------------
func _build_boundary() -> void:
	var body := StaticBody3D.new()
	body.name = "Boundary"
	var r := Spec.PLAYABLE
	var height := 220.0
	var sides := [
		["Nord", Vector3(r.get_center().x, 60.0, r.position.y - 1.0), Vector3(r.size.x + 8.0, height, 2.0)],
		["Sud", Vector3(r.get_center().x, 60.0, r.end.y + 1.0), Vector3(r.size.x + 8.0, height, 2.0)],
		["Ouest", Vector3(r.position.x - 1.0, 60.0, r.get_center().y), Vector3(2.0, height, r.size.y + 8.0)],
		["Est", Vector3(r.end.x + 1.0, 60.0, r.get_center().y), Vector3(2.0, height, r.size.y + 8.0)],
	]
	for side: Array in sides:
		var box := BoxShape3D.new()
		box.size = side[2]
		var cs := CollisionShape3D.new()
		cs.name = "Limite" + String(side[0])
		cs.shape = box
		cs.position = side[1]
		body.add_child(cs)
	_pack(body, GEN + "/Boundary.tscn")


# --- scènes -----------------------------------------------------------------------------------------------------
func _ensure_map_scene() -> void:
	if FileAccess.file_exists(MAP_SCENE):
		return
	var root := Node3D.new()
	root.name = "Map"
	for part in ["Terrain", "Water", "Boundary"]:
		var inst := (load(GEN.path_join(part + ".tscn")) as PackedScene).instantiate()
		inst.name = part
		root.add_child(inst)
	_pack(root, MAP_SCENE)


func _pack(root: Node, path: String) -> void:
	_own(root, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	print("TERRAIN_SCENE %s : %s" % [path, error_string(err)])
	root.free()


func _own(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		if child.scene_file_path == "":
			_own(child, root)
