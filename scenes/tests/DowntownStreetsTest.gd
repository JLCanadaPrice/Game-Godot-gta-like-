extends Node

# Test headless des rues du centre-ville reconstruit (chantier centre-ville, étape D2), monde complet (World.tscn,
# spawners coupés) :
#  - structure : Downtown/Streets instancié, quais et boutiques conservés dans Downtown, plus aucun ancien district ;
#  - graphes : Circuit (après fusion du graphe de la carte) fortement connexe, sens uniques compris ; réseau piéton
#    d'un seul tenant ; ni arête en double ni nœuds confondus ;
#  - chaque branche d'arrivée d'un carrefour à feux : feu visible câblé (nœud, arête, Circuit trouvé), phase simulée,
#    distance d'arrêt au passage piéton, traversée piétonne entre les deux coins ;
#  - sol et gabarit : le long de chaque arête du centre-ville, sur chacune de ses voies, chaussée à la hauteur prévue et
#    gabarit de voiture libre ; le long des trottoirs du réseau piéton, sol au niveau du trottoir (ou de la chaussée sur
#    une traversée) et passage libre ;
#  - boutiques : sol de plain-pied devant leur porte ; spawners, SimulationCuller, carte (routes dessinées), unique_id.
#
# Lancer : Godot --headless --fixed-fps 60 --quit-after 3000 res://scenes/tests/DowntownStreetsTest.tscn

const WORLD := preload("res://scenes/world/World.tscn")
const Traffic := preload("res://scenes/world/downtown/DowntownTraffic.gd")
const Spec := preload("res://scenes/world/downtown/DowntownSpec.gd")
const MapTexture := preload("res://scenes/ui/DistrictMapTexture.gd")
const ROAD_Y := Spec.ROAD_TOP
const WALK_Y := Spec.ROAD_TOP + Spec.SIDEWALK_RISE
const LANE_STEP := 4.0
const WALK_STEP := 2.0
const HEIGHT_TOLERANCE := 0.06

var _errors: Array[String] = []
var _space: PhysicsDirectSpaceState3D
var _exclude: Array[RID] = []


func _ready() -> void:
	print("DOWNTOWN_STREETS_BEGIN")
	var world := WORLD.instantiate()
	add_child(world)
	for spawner in ["CarSpawner", "NpcSpawner"]:
		world.get_node(spawner).set_process(false)
	for k in 4:
		await get_tree().physics_frame
	_space = get_viewport().world_3d.direct_space_state
	var player := get_tree().get_first_node_in_group("player")
	if player is CollisionObject3D:
		_exclude.append((player as CollisionObject3D).get_rid())
	var circuit := world.get_node("Circuit") as CircuitPath
	var ped := world.get_node("PedGraph") as PathGraph
	var traffic := Traffic.new()
	_check_structure(world)
	_check_graphs(circuit, ped, traffic)
	_check_intersections(world, circuit, ped, traffic)
	_check_lanes(circuit, traffic)
	_check_walks(ped, traffic)
	_check_misc(world)
	print("DOWNTOWN_STREETS_RESULT %s %s" % ["OK" if _errors.is_empty() else "FAIL", " | ".join(_errors)])
	get_tree().quit(0 if _errors.is_empty() else 1)


func _check_structure(world: Node) -> void:
	var missing := []
	for path in ["Downtown/Streets/Surfaces", "Downtown/Streets/Collision", "Downtown/Streets/TrafficLights", "Downtown/Quay/QuayPavement",
			"Downtown/Quay2", "Downtown/Shops/Dealership_Building", "Downtown/Shops/Agency_Building"]:
		if world.get_node_or_null(path) == null:
			missing.append(path)
	var old := []
	for n in world.get_children():
		if String(n.name).begins_with("District"):
			old.append(n.name)
	var surfaces := world.get_node_or_null("Downtown/Streets/Surfaces")
	print("DOWNTOWN_STREETS_STRUCTURE %d maillages de rue, %d corps de collision, %d feux | manquants %s | anciens districts %s"
			% [surfaces.get_child_count() if surfaces != null else 0, world.get_node("Downtown/Streets/Collision").get_child_count() if world.has_node("Downtown/Streets/Collision") else 0,
			_lights(world).size(), missing, old])
	if not missing.is_empty() or not old.is_empty():
		_errors.append("structure : manquants %s, anciens districts %s" % [missing, old])


func _check_graphs(circuit: CircuitPath, ped: PathGraph, traffic: Traffic) -> void:
	var fwd := _reach(circuit, false)
	var back := _reach(circuit, true)
	var seen := {}
	var dup_edges := 0
	for e: Dictionary in circuit.edges:
		var key := "%d_%d" % [mini(int(e["a"]), int(e["b"])), maxi(int(e["a"]), int(e["b"]))]
		dup_edges += 1 if seen.has(key) else 0
		seen[key] = true
	var close := _close_pairs(circuit.nodes, 1.0) + _close_pairs(ped.nodes, 0.6)
	var ped_parts := _components(ped.nodes.size(), ped.edges)
	var downtown_ok := circuit.nodes.size() >= traffic.nodes.size()
	for i in traffic.nodes.size():
		downtown_ok = downtown_ok and circuit.nodes[i].is_equal_approx(traffic.nodes[i])
	print("DOWNTOWN_STREETS_GRAPHS circuit %d nœuds (dont %d du centre-ville, identiques au plan : %s), %d arêtes, atteints depuis le 0 : %d / en sens inverse : %d | réseau piéton %d nœuds, %d arêtes, %d composante(s) | %d arêtes doublées, %d paires de nœuds confondus"
			% [circuit.nodes.size(), traffic.nodes.size(), downtown_ok, circuit.edges.size(), fwd, back, ped.nodes.size(), ped.edges.size(), ped_parts, dup_edges, close])
	if fwd != circuit.nodes.size() or back != circuit.nodes.size():
		_errors.append("Circuit non fortement connexe (%d / %d sur %d)" % [fwd, back, circuit.nodes.size()])
	if ped_parts != 1:
		_errors.append("réseau piéton en %d morceaux" % ped_parts)
	if dup_edges > 0 or close > 0 or not downtown_ok:
		_errors.append("graphes : %d arêtes doublées, %d nœuds confondus, centre-ville conforme %s" % [dup_edges, close, downtown_ok])


func _check_intersections(world: Node, circuit: CircuitPath, ped: PathGraph, traffic: Traffic) -> void:
	var lights := {}
	var unwired := 0
	for light in _lights(world):
		lights["%d_%d" % [light.circuit_node, light.circuit_edge]] = light
		if light._circuit != circuit:
			unwired += 1
	var ped_pairs := {}
	for e in ped.edges:
		ped_pairs["%d_%d" % [mini(e.x, e.y), maxi(e.x, e.y)]] = true
	var approaches := 0
	var problems := {}
	var first := ""
	var layout := traffic.layout
	for n in layout.nodes.size():
		var node: Dictionary = layout.nodes[n]
		if not node["lit"]:
			continue
		for arm: String in node["arms"]:
			var e := int(node["arms"][arm])
			if bool(circuit.edges[e].get("one_way", false)) and int(circuit.edges[e]["b"]) != n:
				continue
			approaches += 1
			var what := []
			if not lights.has("%d_%d" % [n, e]):
				what.append("feu absent")
			if not circuit._light_state.has(n) or not circuit._light_edge_phase.has(e):
				what.append("feu non simulé")
			if circuit.crosswalk_clear_distance(e, n) <= 0.0:
				what.append("ligne d'arrêt absente")
			var pair := traffic._arm_corners(n, arm)
			if pair.x < 0 or pair.y < 0 or not ped_pairs.has("%d_%d" % [mini(pair.x, pair.y), maxi(pair.x, pair.y)]):
				what.append("traversée piétonne absente")
			for w in what:
				problems[w] = int(problems.get(w, 0)) + 1
			if not what.is_empty() and first == "":
				first = "carrefour %s branche %s : %s" % [node["pos"], arm, ", ".join(what)]
	print("DOWNTOWN_STREETS_LIGHTS %d approches de carrefours à feux vérifiées, %d feux, %d feux sans Circuit | défauts %s %s"
			% [approaches, lights.size(), unwired, problems, first])
	if not problems.is_empty() or unwired > 0:
		_errors.append("carrefours : %s, %d feux sans Circuit, premier %s" % [problems, unwired, first])


# Chaque arête du centre-ville, sur chacune de ses voies et dans son sens de marche : chaussée à ROAD_Y sous la voie,
# gabarit de 1,4 m de large de 0,7 à 2,5 m au-dessus libre.
func _check_lanes(circuit: CircuitPath, traffic: Traffic) -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 1.8, 1.4)
	var samples := 0
	var misses := 0
	var blocked := 0
	var first := ""
	for e in traffic.edges.size():
		var edge: Dictionary = circuit.edges[e]
		var from := int(edge["a"])
		var length := circuit.edge_length(e)
		var lanes: PackedFloat32Array = edge.get("lanes", PackedFloat32Array([2.0]))
		var s := 14.0
		while s < length - 14.0:
			for lane in lanes:
				var p := circuit.sample_offset(e, from, s, lane)
				samples += 1
				var hit := _ray(p + Vector3.UP * 3.0, p + Vector3.DOWN * 2.0)
				if hit.is_empty() or absf((hit["position"] as Vector3).y - ROAD_Y) > HEIGHT_TOLERANCE:
					misses += 1
					if first == "":
						first = "(%.1f, %.1f) sol %s" % [p.x, p.z, "absent" if hit.is_empty() else "%.2f" % (hit["position"] as Vector3).y]
					continue
				if not _clear(box, (hit["position"] as Vector3) + Vector3.UP * 1.6):
					blocked += 1
					if first == "":
						first = "(%.1f, %.1f) gabarit encombré" % [p.x, p.z]
			s += LANE_STEP
	print("DOWNTOWN_STREETS_LANES %d relevés sur les voies : %d hors chaussée, %d gabarits encombrés %s" % [samples, misses, blocked, first])
	if misses > 0 or blocked > 0:
		_errors.append("voies : %d hors chaussée, %d encombrées, premier %s" % [misses, blocked, first])


# Arêtes du réseau piéton du centre-ville : sol au niveau du trottoir, ou de la chaussée sur une traversée ; passage
# de 0,6 m de large de 0,5 à 1,9 m au-dessus libre (mâts des feux, lampadaires).
func _check_walks(ped: PathGraph, traffic: Traffic) -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 1.4, 0.6)
	var samples := 0
	var bad_ground := 0
	var blocked := 0
	var first := ""
	for e in traffic.ped_edges:
		var a := ped.nodes[e.x]
		var b := ped.nodes[e.y]
		var length := Vector2(a.x - b.x, a.z - b.z).length()
		var steps := maxi(1, ceili(length / WALK_STEP))
		for k in range(1, steps):
			var p := a.lerp(b, float(k) / steps)
			samples += 1
			var hit := _ray(Vector3(p.x, 3.0, p.z), Vector3(p.x, -2.0, p.z))
			var y := INF if hit.is_empty() else (hit["position"] as Vector3).y
			if absf(y - WALK_Y) > HEIGHT_TOLERANCE and absf(y - ROAD_Y) > HEIGHT_TOLERANCE:
				bad_ground += 1
				if first == "":
					first = "(%.1f, %.1f) sol %s" % [p.x, p.z, "absent" if hit.is_empty() else "%.2f" % y]
				continue
			if not _clear(box, Vector3(p.x, y + 1.2, p.z)):
				blocked += 1
				if first == "":
					first = "(%.1f, %.1f) passage encombré" % [p.x, p.z]
	print("DOWNTOWN_STREETS_WALKS %d relevés sur le réseau piéton : %d sols inattendus, %d passages encombrés %s" % [samples, bad_ground, blocked, first])
	if bad_ground > 0 or blocked > 0:
		_errors.append("trottoirs : %d sols inattendus, %d encombrés, premier %s" % [bad_ground, blocked, first])


func _check_misc(world: Node) -> void:
	# boutiques : sol devant la porte au niveau du trottoir, sol intérieur de plain-pied
	for shop_name in ["Dealership_Building", "Agency_Building"]:
		var shop := world.get_node_or_null("Downtown/Shops/" + shop_name) as Node3D
		if shop == null:
			continue
		var door := (shop.find_child("Socket_DoorOutside", true, false) as Node3D).global_position
		var inside := (shop.find_child("Socket_DoorInside", true, false) as Node3D).global_position
		var out_hit := _ray(door + Vector3.UP * 2.0, door + Vector3.DOWN * 2.0)
		var in_hit := _ray(inside + Vector3.UP * 2.0, inside + Vector3.DOWN * 2.0)
		var out_y := INF if out_hit.is_empty() else (out_hit["position"] as Vector3).y
		var in_y := INF if in_hit.is_empty() else (in_hit["position"] as Vector3).y
		print("DOWNTOWN_STREETS_SHOP %s : sol dehors %.2f, dedans %.2f (trottoir %.2f)" % [shop_name, out_y, in_y, WALK_Y])
		if absf(out_y - WALK_Y) > HEIGHT_TOLERANCE or absf(in_y - WALK_Y) > HEIGHT_TOLERANCE:
			_errors.append("%s : sol dehors %.2f / dedans %.2f au lieu de %.2f" % [shop_name, out_y, in_y, WALK_Y])
	var cars := world.get_node("CarSpawner")
	var npcs := world.get_node("NpcSpawner")
	if cars.max_active != 252 or npcs.max_active != 315 or not cars.proximity or not npcs.proximity or world.get_node_or_null("SimulationCuller") == null:
		_errors.append("spawners / SimulationCuller mal réglés")
	var img := MapTexture.build(world, 0.5).get_image()
	if img != null:
		var at := MapTexture.world_to_pixel(Vector3(-532, 0, -172), 0.5)
		if img.get_pixelv(Vector2i(at)).a < 0.5:
			_errors.append("carte : carrefour Main Street × Central Boulevard non dessiné")
	var text := FileAccess.get_file_as_string("res://scenes/world/World.tscn")
	var ids := {}
	var dups := 0
	for m in RegEx.create_from_string("\\[node [^\\]]*unique_id=(\\d+)[^\\]]*\\]").search_all(text):
		if m.get_string(0).contains(" index=\""):
			continue
		dups += 1 if ids.has(m.get_string(1)) else 0
		ids[m.get_string(1)] = true
	print("DOWNTOWN_STREETS_SCENE World.tscn : %d lignes, %d nœuds identifiés, %d unique_id en double" % [text.count("\n"), ids.size(), dups])
	if dups > 0:
		_errors.append("%d unique_id en double dans World.tscn" % dups)


func _lights(world: Node) -> Array[TrafficLight]:
	var out: Array[TrafficLight] = []
	var holder := world.get_node_or_null("Downtown/Streets/TrafficLights")
	if holder != null:
		for c in holder.get_children():
			if c is TrafficLight:
				out.append(c as TrafficLight)
	return out


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.exclude = _exclude
	return _space.intersect_ray(q)


func _clear(shape: Shape3D, center: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, center)
	query.exclude = _exclude
	return _space.intersect_shape(query, 1).is_empty()


# Nœuds atteints depuis le nœud 0 en suivant les sens uniques (ou à rebours).
func _reach(circuit: CircuitPath, reverse: bool) -> int:
	var seen := {0: true}
	var stack := [0]
	while not stack.is_empty():
		var u: int = stack.pop_back()
		for e in circuit.node_edges(u):
			var edge: Dictionary = circuit.edges[e]
			if bool(edge.get("one_way", false)) and int(edge["b" if reverse else "a"]) != u:
				continue
			var v := circuit.edge_other_node(e, u)
			if not seen.has(v):
				seen[v] = true
				stack.append(v)
	return seen.size()


func _close_pairs(nodes: Array[Vector3], dist: float) -> int:
	var buckets := {}
	var n := 0
	for i in nodes.size():
		var key := Vector2i(floori(nodes[i].x / 4.0), floori(nodes[i].z / 4.0))
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				for j: int in buckets.get(key + Vector2i(dx, dz), []):
					if nodes[i].distance_to(nodes[j]) < dist:
						n += 1
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(i)
	return n


func _components(count: int, pairs: Array[Vector2i]) -> int:
	var parent := PackedInt32Array()
	parent.resize(count)
	for i in count:
		parent[i] = i
	for pr in pairs:
		var a := _root(parent, pr.x)
		var b := _root(parent, pr.y)
		if a != b:
			parent[a] = b
	var roots := {}
	for i in count:
		roots[_root(parent, i)] = true
	return roots.size()


func _root(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		i = parent[i]
	return i
