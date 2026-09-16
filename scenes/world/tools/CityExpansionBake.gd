extends SceneTree

# Outil lancé une fois en headless : agrandit World.tscn à 4 districts reliés entre eux.
#  - District (quai, eau, pontons) : référence ;
#  - District_W : copie à -432 m en X (6 blocs de 72 m) : son avenue G se superpose à l'avenue A du District ;
#  - District_N / District_NW : copies à +288 m en Z (4 blocs) : leur rangée 1 se superpose à la rangée 5.
# Les copies n'ont ni Quay (eau, quai, pontons) ni boutiques : les lots des boutiques reprennent leurs city_kit.
# Coutures (tout le contenu d'un district tient à 7.5 m de ses avenues extérieures) : chaque district garde ce qui
# est de son côté de l'avenue partagée, les pièces posées sur l'avenue elle-même ne sont gardées qu'une fois
# (priorité District > W > N > NW). Carrefours de couture : Road2_X là où les 4 branches existent désormais et,
# sur les branches qui n'avaient ni feu ni passage piéton (anciens angles de district), le mobilier du carrefour
# B3 (passage piéton, feu, lampadaire), sa ligne d'arrêt de passage piéton et la traversée du réseau piéton.
# CircuitPath et PedGraph fusionnés (noeuds confondus aux coutures), feux des copies recâblés, spawners sur tous
# les noeuds (population x3), SimulationCuller ajouté. Rien n'est enregistré si un garde-fou échoue.
#
# Lancer : Godot --headless --path <projet> --script res://scenes/world/tools/CityExpansionBake.gd

const WORLD_PATH := "res://scenes/world/World.tscn"
const Merge := preload("res://scenes/world/tools/CityGraphMerge.gd")
const CULLER := preload("res://scripts/world/SimulationCuller.gd")
const ROAD_X := "res://assets/modular_roads/Road2_X.glb"
const ROAD_T := "res://assets/modular_roads/Road2_T.glb"
const COPIES := [
	{"name": "District_W", "offset": Vector3(-432, 0, 0), "ground_drop": 0.02},
	{"name": "District_N", "offset": Vector3(0, 0, 288), "ground_drop": 0.03},
	{"name": "District_NW", "offset": Vector3(-432, 0, 288), "ground_drop": 0.04},
]
const SEAMS := [  # avenue partagée : axe, position, étendue le long de l'avenue, district côté négatif / positif
	{"axis": "x", "at": -460.0, "span": Vector2(-480, -152), "minus": "District_W", "plus": "District"},
	{"axis": "x", "at": -460.0, "span": Vector2(-192, 136), "minus": "District_NW", "plus": "District_N"},
	{"axis": "z", "at": -172.0, "span": Vector2(-480, -8), "minus": "District", "plus": "District_N"},
	{"axis": "z", "at": -172.0, "span": Vector2(-912, -440), "minus": "District_W", "plus": "District_NW"},
]
const PRIORITY := ["District", "District_W", "District_N", "District_NW"]
const CONTAINERS := ["Roads", "RoadsCollision", "SidewalksCollision", "Sidewalks", "Buildings"]
const BAND := 16.0      # m traités de part et d'autre de l'avenue partagée
const ON_LINE := 1.5    # m : pièce posée sur l'avenue partagée elle-même
const TILE := 12.0
const DIRS := {"+X": Vector3(1, 0, 0), "-X": Vector3(-1, 0, 0), "+Z": Vector3(0, 0, 1), "-Z": Vector3(0, 0, -1)}
const TEMPLATE_NODE := 7   # B3 : carrefour X complet, feu + passage piéton + lampadaire sur ses 4 approches
const TEMPLATE_TILES := {"-Z": "NS_B_2-3_5", "+Z": "NS_B_3-4_1", "-X": "EW_3_A-B_5", "+X": "EW_3_B-C_1"}
const PED_NEG := -8.0      # coins de trottoir du réseau piéton autour d'un carrefour (relevés dans PedGraph)
const PED_POS := 7.0
const FILLERS := [         # lots des boutiques dans les copies (transforms d'origine relevées dans la sauvegarde)
	{"name": "Building_Medium_2_001_102", "like": "Building_Medium_2_001_", "yaw": 90.0, "at": Vector3(-116.02784, 0, -437.21)},
	{"name": "Building_Small_1_152", "like": "Building_Small_1_", "yaw": 180.0, "at": Vector3(-118.697945, 0, -443.232)},
	{"name": "Building_Small_1_154", "like": "Building_Small_1_", "yaw": 180.0, "at": Vector3(-64.0, 0, -443.232)},
]
const TARGET_CARS := 252
const TARGET_NPCS := 315
const EXPECTED_SEAM_NODES := 21

var _report := {}


func _initialize() -> void:
	var root := (load(WORLD_PATH) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
	if root.has_node("District_W"):
		push_error("World.tscn a déjà 4 districts : rien à faire")
		root.free()
		quit(1)
		return
	var main := root.get_node("District") as Node3D
	var circuit := root.get_node("Circuit") as CircuitPath
	var ped := root.get_node("PedGraph") as PathGraph
	_report["circuit_avant"] = [circuit.nodes.size(), circuit.edges.size(), circuit.crosswalk_stop_dist.size()]
	_report["ped_avant"] = [ped.nodes.size(), ped.edges.size(), _components(ped.nodes.size(), ped.edges)]
	var base_c := CircuitPath.new()
	base_c.nodes = circuit.nodes.duplicate()
	base_c.edges = circuit.edges.duplicate(true)
	base_c.roundabout_nodes = circuit.roundabout_nodes.duplicate()
	base_c.crosswalk_stop_dist = circuit.crosswalk_stop_dist.duplicate()
	var base_p := PathGraph.new()
	base_p.nodes = ped.nodes.duplicate()
	base_p.edges = ped.edges.duplicate()

	var districts := {"District": main}
	for spec: Dictionary in COPIES:
		var copy := main.duplicate() as Node3D
		copy.name = spec.name
		root.add_child(copy)
		copy.owner = root
		_own(main, copy, root)
		copy.position = spec.offset
		_drop(copy.get_node_or_null("Quay"))
		for shop in ["Dealership_Building", "Agency_Building"]:
			_drop(copy.get_node_or_null("Buildings/" + shop))
		var fillers := 0
		for filler: Dictionary in FILLERS:
			fillers += _add_filler(copy, filler, root)
		(copy.get_node("DistrictGround") as Node3D).position.y -= float(spec.ground_drop)
		var maps := Merge.merge_circuit(circuit, base_c, spec.offset)
		Merge.merge_ped(ped, base_p, spec.offset)
		var node_map: PackedInt32Array = maps.nodes
		var edge_map: PackedInt32Array = maps.edges
		var lights := _traffic_lights(copy)
		for tl in lights:
			if tl.circuit_node >= 0 and tl.circuit_edge >= 0:
				tl.circuit_node = node_map[tl.circuit_node]
				tl.circuit_edge = edge_map[tl.circuit_edge]
		_report[spec.name] = {"feux_recables": lights.size(), "lots_remplis": fillers, "quai": copy.has_node("Quay")}
		districts[spec.name] = copy
	base_c.free()
	base_p.free()

	for seam: Dictionary in SEAMS:
		_report["couture %s/%s" % [seam.minus, seam.plus]] = _clean_seam(districts, seam)
	var seams_root := _add_node3d(root, "DistrictSeams", root)
	var seam_roads := _add_node3d(seams_root, "Roads", root)
	var seam_stats := _seam_intersections(districts, seam_roads, circuit, ped, root)
	_report["carrefours_couture"] = seam_stats

	var circuit_pairs: Array[Vector2i] = []
	for e: Dictionary in circuit.edges:
		circuit_pairs.append(Vector2i(int(e.a), int(e.b)))
	var circuit_parts := _components(circuit.nodes.size(), circuit_pairs)
	_report["circuit_apres"] = [circuit.nodes.size(), circuit.edges.size(), circuit.roundabout_nodes.size(), circuit.crosswalk_stop_dist.size(), circuit_parts]
	_report["ped_apres"] = [ped.nodes.size(), ped.edges.size(), _components(ped.nodes.size(), ped.edges)]

	_set_spawner(root.get_node("CarSpawner"), circuit.nodes.size(), TARGET_CARS)
	_set_spawner(root.get_node("NpcSpawner"), ped.nodes.size(), TARGET_NPCS)
	var culler := CULLER.new() as Node
	culler.name = "SimulationCuller"
	root.add_child(culler)
	culler.owner = root

	var problems: Array[String] = []
	if circuit_parts != 1:
		problems.append("circuit en %d morceaux" % circuit_parts)
	if int(seam_stats.noeuds) != EXPECTED_SEAM_NODES:
		problems.append("%d carrefours de couture au lieu de %d" % [seam_stats.noeuds, EXPECTED_SEAM_NODES])
	if int(seam_stats.tuiles_manquantes) > 0:
		problems.append("%d tuiles d'approche introuvables" % seam_stats.tuiles_manquantes)
	var err := OK
	if problems.is_empty():
		var packed := PackedScene.new()
		err = packed.pack(root)
		if err == OK:
			err = ResourceSaver.save(packed, WORLD_PATH)
		if err == OK:
			_report["unique_id_renumerotes"] = _renumber_duplicate_ids(WORLD_PATH)
		_report["sauvegarde"] = error_string(err)
	else:
		_report["sauvegarde"] = "ANNULEE : " + " | ".join(problems)
	print("CITY_BAKE " + JSON.stringify(_report, "  "))
	root.free()
	quit(0 if problems.is_empty() and err == OK else 1)


# Propriétaire = racine pour les nœuds de la copie qui l'étaient dans l'original (enfants internes des .glb exclus).
func _own(orig: Node, dup: Node, root: Node) -> void:
	for oc in orig.get_children():
		var dc := dup.get_node_or_null(NodePath(String(oc.name)))
		if dc == null:
			continue
		if oc.owner == root:
			dc.owner = root
			if root.is_editable_instance(oc):
				root.set_editable_instance(dc, true)
		_own(oc, dc, root)


func _add_filler(district: Node, filler: Dictionary, root: Node) -> int:
	var buildings := district.get_node("Buildings")
	for b in buildings.get_children():
		if String(b.name).begins_with(filler.like):
			var dup := b.duplicate() as Node3D
			dup.name = filler.name
			buildings.add_child(dup)
			dup.owner = root
			_own(b, dup, root)
			dup.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(filler.yaw)), filler.at)
			return 1
	return 0


func _clean_seam(districts: Dictionary, seam: Dictionary) -> Dictionary:
	var minus: Node = districts[seam.minus]
	var plus: Node = districts[seam.plus]
	var keep := minus if PRIORITY.find(seam.minus) < PRIORITY.find(seam.plus) else plus
	var other := plus if keep == minus else minus
	var kept := {}
	var stats := {"hors_cote": 0, "doublons": 0}
	for d: Node in [keep, other]:
		var own_sign := -1.0 if d == minus else 1.0
		for piece in _pieces(d):
			var c := _center(piece)
			var along := c.z if seam.axis == "x" else c.x
			var off := (c.x if seam.axis == "x" else c.z) - float(seam.at)
			if along < seam.span.x or along > seam.span.y or absf(off) > BAND:
				continue
			if off * own_sign < -ON_LINE:
				_drop(piece)
				stats.hors_cote += 1
			elif absf(off) <= ON_LINE:
				var sig := _signature(piece, c)
				if d == keep:
					kept[sig] = true
				elif kept.has(sig):
					_drop(piece)
					stats.doublons += 1
	return stats


func _seam_intersections(districts: Dictionary, seam_roads: Node3D, circuit: CircuitPath, ped: PathGraph, root: Node) -> Dictionary:
	var stats := {"noeuds": 0, "X": 0, "T": 0, "X_poses": 0, "T_poses": 0, "pieces_retirees": 0, "feux_ajoutes": 0,
			"passages_ajoutes": 0, "traversees_pietons": 0, "tuiles_manquantes": 0, "gabarit_traversees": 0}
	var templates := _templates(districts["District"], circuit, ped, stats)
	var wired := {}
	var road_pieces := []
	for d: Node in districts.values():
		road_pieces.append_array(_road_pieces(d))
		for tl in _traffic_lights(d):
			wired["%d_%d" % [tl.circuit_node, tl.circuit_edge]] = true
	for i in circuit.nodes.size():
		var p: Vector3 = circuit.nodes[i]
		if not _on_seam(p):
			continue
		var arms := Merge.arm_edges(circuit, i)
		if arms.size() < 3:
			continue
		stats.noeuds += 1
		stats["X" if arms.size() >= 4 else "T"] += 1
		_fix_intersection_piece(road_pieces, seam_roads, p, i, arms, root, stats)
		for key: String in arms:
			var e: int = arms[key]
			if wired.has("%d_%d" % [i, e]):
				continue
			var dir: Vector3 = DIRS[key]
			var tile := _tile_at(road_pieces, p + dir * TILE)
			if tile == null:
				stats.tuiles_manquantes += 1
				continue
			var tpl: Dictionary = templates[key]
			_furnish(tile, tpl, p, i, e, root)
			wired["%d_%d" % [i, e]] = true
			stats.feux_ajoutes += 1
			var stop_key := "%d_%d" % [e, i]
			if float(tpl.stop) > 0.0 and not circuit.crosswalk_stop_dist.has(stop_key):
				circuit.crosswalk_stop_dist[stop_key] = tpl.stop
				stats.passages_ajoutes += 1
			if int(stats.gabarit_traversees) == 4:
				stats.traversees_pietons += _add_ped_crossing(ped, p, dir)
	return stats


# Mobilier des 4 approches du carrefour de référence, en transforms relatives au centre du carrefour.
func _templates(main: Node, circuit: CircuitPath, ped: PathGraph, stats: Dictionary) -> Dictionary:
	var out := {}
	var center: Vector3 = circuit.nodes[TEMPLATE_NODE]
	var arms := Merge.arm_edges(circuit, TEMPLATE_NODE)
	for key: String in TEMPLATE_TILES:
		var tile := main.get_node("Roads/" + String(TEMPLATE_TILES[key]))
		var kids := []
		for k in tile.get_children():
			if k.owner == main.owner:
				kids.append({"node": k, "rel": Transform3D(Basis.IDENTITY, -center) * _global(k)})
		out[key] = {"kids": kids, "stop": circuit.crosswalk_stop_dist.get("%d_%d" % [arms.get(key, -1), TEMPLATE_NODE], -1.0)}
		var pair := _ped_crossing(ped, center, DIRS[key])
		if pair.x >= 0 and pair.y >= 0 and _has_ped_edge(ped, pair.x, pair.y):
			stats.gabarit_traversees += 1
	return out


func _fix_intersection_piece(road_pieces: Array, seam_roads: Node3D, p: Vector3, node: int, arms: Dictionary, root: Node, stats: Dictionary) -> void:
	var here := []
	for piece in road_pieces:
		if is_instance_valid(piece):
			var o := _global(piece).origin
			if Vector2(o.x - p.x, o.z - p.z).length() < 2.0:
				here.append(piece)
	var want := ROAD_X if arms.size() >= 4 else ROAD_T
	var yaw := 0.0 if want == ROAD_X else _t_yaw(arms)
	if here.size() == 1:
		var cur := here[0] as Node3D
		# Road2_X gardé aussi pour un T : c'est déjà la pièce des carrefours de bord du District d'origine
		if cur.scene_file_path == ROAD_X or (cur.scene_file_path == want and absf(wrapf(cur.rotation.y - yaw, -PI, PI)) < 0.05):
			return
	for piece in here:
		_drop(piece)
		stats.pieces_retirees += 1
	var fresh := (load(want) as PackedScene).instantiate() as Node3D
	fresh.name = "Seam_%s_%d" % ["X" if want == ROAD_X else "T", node]
	seam_roads.add_child(fresh)
	fresh.owner = root
	fresh.position = Vector3(p.x, 0.0, p.z)
	fresh.rotation.y = yaw
	stats["X_poses" if want == ROAD_X else "T_poses"] += 1


# Road2_T à yaw 0 a son pied vers -Z : yaw = atan2(-pied.x, -pied.z), pied = opposé de la branche manquante.
func _t_yaw(arms: Dictionary) -> float:
	for key: String in DIRS:
		if not arms.has(key):
			var missing: Vector3 = DIRS[key]
			return atan2(missing.x, missing.z)
	return 0.0


func _furnish(tile: Node3D, tpl: Dictionary, p: Vector3, node: int, edge: int, root: Node) -> void:
	var to_local := _global(tile).affine_inverse()
	for item: Dictionary in tpl.kids:
		var src: Node3D = item.node
		if _has_kind(tile, src, root):
			continue
		var dup := src.duplicate() as Node3D
		tile.add_child(dup, true)
		dup.owner = root
		dup.transform = to_local * Transform3D(Basis.IDENTITY, p) * (item.rel as Transform3D)
		if "circuit_node" in dup:
			dup.set("circuit_node", node)
			dup.set("circuit_edge", edge)


func _has_kind(tile: Node, src: Node, root: Node) -> bool:
	for k in tile.get_children():
		if k.owner == root and k.get_class() == src.get_class() and k.scene_file_path == src.scene_file_path:
			return true
	return false


func _tile_at(road_pieces: Array, pos: Vector3) -> Node3D:
	for piece in road_pieces:
		if not is_instance_valid(piece) or piece.scene_file_path == ROAD_X or piece.scene_file_path == ROAD_T:
			continue
		var o := _global(piece).origin
		if Vector2(o.x - pos.x, o.z - pos.z).length() < 1.0:
			return piece
	return null


func _ped_crossing(ped: PathGraph, p: Vector3, dir: Vector3) -> Vector2i:
	var side := PED_POS if dir.x + dir.z > 0.0 else PED_NEG
	var a := Vector3(side, 0, PED_NEG) if absf(dir.x) > 0.5 else Vector3(PED_NEG, 0, side)
	var b := Vector3(side, 0, PED_POS) if absf(dir.x) > 0.5 else Vector3(PED_POS, 0, side)
	return Vector2i(_ped_near(ped, p + a), _ped_near(ped, p + b))


func _ped_near(ped: PathGraph, q: Vector3) -> int:
	for i in ped.nodes.size():
		var n: Vector3 = ped.nodes[i]
		if Vector2(n.x - q.x, n.z - q.z).length() < 1.0:
			return i
	return -1


func _has_ped_edge(ped: PathGraph, a: int, b: int) -> bool:
	for e in ped.edges:
		if (e.x == a and e.y == b) or (e.x == b and e.y == a):
			return true
	return false


func _add_ped_crossing(ped: PathGraph, p: Vector3, dir: Vector3) -> int:
	var pair := _ped_crossing(ped, p, dir)
	if pair.x < 0 or pair.y < 0 or _has_ped_edge(ped, pair.x, pair.y):
		return 0
	ped.edges.append(pair)
	return 1


func _on_seam(p: Vector3) -> bool:
	for seam: Dictionary in SEAMS:
		var along := p.z if seam.axis == "x" else p.x
		var across := p.x if seam.axis == "x" else p.z
		if absf(across - float(seam.at)) < 1.0 and along >= seam.span.x and along <= seam.span.y:
			return true
	return false


func _pieces(d: Node) -> Array:
	var out := []
	for c in d.get_children():
		if String(c.name) in CONTAINERS:
			out.append_array(c.get_children())
		elif c.name != &"DistrictGround" and c.name != &"Quay":
			out.append(c)
	return out


func _road_pieces(d: Node) -> Array:
	var out := []
	var roads := d.get_node_or_null("Roads")
	if roads != null:
		out.append_array(roads.get_children())
	for c in d.get_children():
		if c.scene_file_path.begins_with("res://assets/modular_roads/"):
			out.append(c)
	return out


func _traffic_lights(d: Node) -> Array:
	var out := []
	var roads := d.get_node_or_null("Roads")
	if roads != null:
		for tile in roads.get_children():
			for k in tile.get_children():
				if "circuit_node" in k:
					out.append(k)
	return out


# Centre monde d'une pièce : origine d'une instance ou d'un bâtiment, sinon centre de ses collisions, sinon de ses meshes.
func _center(piece: Node) -> Vector3:
	if piece.scene_file_path != "" or piece is Area3D:
		return _global(piece).origin
	var shapes := piece.find_children("*", "CollisionShape3D", true, false)
	if not shapes.is_empty():
		var sum := Vector3.ZERO
		for s in shapes:
			sum += _global(s).origin
		return sum / shapes.size()
	var meshes := piece.find_children("*", "MeshInstance3D", true, false)
	if piece is MeshInstance3D:
		meshes.append(piece)
	var box := AABB()
	var has := false
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh != null:
			var b := _global(mi) * mi.mesh.get_aabb()
			box = box.merge(b) if has else b
			has = true
	return box.get_center() if has else _global(piece).origin


func _signature(piece: Node, c: Vector3) -> String:
	var kind := piece.scene_file_path if piece.scene_file_path != "" else piece.get_class()
	for s in piece.find_children("*", "CollisionShape3D", true, false):
		var box := (s as CollisionShape3D).shape as BoxShape3D
		if box != null:
			kind += str(box.size.snapped(Vector3.ONE * 0.1))
	return "%s|%d|%d|%d" % [kind, roundi(c.x * 2.0), roundi(c.y * 2.0), roundi(c.z * 2.0)]


func _global(node: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur := node
	while cur != null:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


func _add_node3d(parent: Node, node_name: String, root: Node) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	parent.add_child(n)
	n.owner = root
	return n


func _drop(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.get_parent().remove_child(node)
		node.free()


func _set_spawner(spawner: Node, points: int, target: int) -> void:
	var nodes: Array[int] = []
	for i in points:
		nodes.append(i)
	spawner.set("spawn_nodes", nodes)
	spawner.set("max_active", target)
	_report[String(spawner.name)] = {"points": points, "max_active": target}


# PackedScene.pack garde le unique_id des enfants d'instance éditable dupliqués (Road11_Y_Splitter_452 des copies) :
# chaque doublon reçoit un identifiant libre dans le fichier enregistré.
func _renumber_duplicate_ids(path: String) -> int:
	var text := FileAccess.get_file_as_string(path)
	var re := RegEx.create_from_string("unique_id=(\\d+)")
	var matches := re.search_all(text)
	var used := {}
	for m in matches:
		used[m.get_string(1)] = true
	var seen := {}
	var parts := PackedStringArray()
	var last := 0
	for m in matches:
		var id := m.get_string(1)
		if seen.has(id):
			var fresh := str(randi_range(1, 2147483646))
			while used.has(fresh):
				fresh = str(randi_range(1, 2147483646))
			used[fresh] = true
			parts.append(text.substr(last, m.get_start(1) - last))
			parts.append(fresh)
			last = m.get_end(1)
		seen[id] = true
	if parts.is_empty():
		return 0
	parts.append(text.substr(last))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("".join(parts))
	f.close()
	return parts.size() / 2


func _components(count: int, pairs: Array[Vector2i]) -> int:
	var parent := PackedInt32Array()
	parent.resize(count)
	for i in count:
		parent[i] = i
	for pr in pairs:
		var a := _root_of(parent, pr.x)
		var b := _root_of(parent, pr.y)
		if a != b:
			parent[a] = b
	var roots := {}
	for i in count:
		roots[_root_of(parent, i)] = true
	return roots.size()


func _root_of(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		i = parent[i]
	return i
