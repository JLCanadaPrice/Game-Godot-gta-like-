extends Node

# Test headless des routes de la carte 3D (étapes 2a, 2b et suivantes).
# Carte seule (Map.tscn) :
#  - modèle : RoadNetwork sans erreur, graphe de circulation fortement connexe (grille du centre-ville comprise) ;
#  - surface : le long de chaque arête du graphe (hors raccords posés sur la grille du centre-ville), tous les 6 m, un
#    rayon descendant rencontre la chaussée à la hauteur du trajet (écart < 0,35 m) et rien n'encombre le gabarit ;
#  - circulation : voitures IA (Car.tscn) sur un CircuitPath construit depuis le graphe, 70 s simulées : chacune
#    parcourt au moins MIN_DRIVE m et reste posée sur la chaussée (rayon sous la caisse).
# Monde complet (World.tscn) :
#  - le Circuit du centre-ville a reçu le graphe de la carte (MapTraffic) et reste fortement connexe ;
#  - des voitures parties des raccords du centre-ville sortent sur les artères et roulent.
#
# Lancer : Godot --headless --fixed-fps 60 --quit-after 40000 res://scenes/tests/MapRoadsTest.tscn

const MAP := preload("res://scenes/world/map/Map.tscn")
const WORLD_PATH := "res://scenes/world/World.tscn"
const CAR := preload("res://scenes/vehicles/Car.tscn")
const Network := preload("res://scenes/world/map/tools/RoadNetwork.gd")
const SAMPLE := 6.0
const GAUGE := 4.5
const CARS := 18
const START_SPACING := 60.0
const DRIVE_SECONDS := 70.0
const MIN_DRIVE := 350.0
const MAX_OFF_ROAD := 0.03
const GRID_ZONE := 16.0            # autour d'un raccord : la chaussée est celle du centre-ville (absente de la carte seule)
const WORLD_CARS := 8
const WORLD_SECONDS := 40.0
const WORLD_MIN_DRIVE := 150.0

var _errors: Array[String] = []


func _ready() -> void:
	print("MAP_ROADS_BEGIN")
	var map := MAP.instantiate()
	add_child(map)
	for k in 3:
		await get_tree().physics_frame
	var net := Network.new()
	net.build()
	if not net.errors.is_empty():
		_errors.append("modèle : " + " ; ".join(net.errors))
	print("MAP_ROADS_GRAPH %d noeuds, %d arêtes, %d feux, %d raccords au centre-ville, fortement connexe %s"
			% [net.g_nodes.size(), net.g_edges.size(), net.g_lit.size(), net.g_grid.size(), net.strongly_connected()])
	if not net.strongly_connected():
		_errors.append("graphe non fortement connexe")
	var grid_points: Array[Vector3] = []
	for i in net.g_grid:
		grid_points.append(net.g_nodes[i])
	_check_surface(net, grid_points)
	await _check_traffic(net, grid_points)
	map.queue_free()
	for k in 3:
		await get_tree().physics_frame
	await _check_world()
	print("MAP_ROADS_RESULT %s %s" % ["OK" if _errors.is_empty() else "FAIL", " | ".join(_errors)])
	get_tree().quit(0 if _errors.is_empty() else 1)


func _near_grid(p: Vector3, grid_points: Array[Vector3]) -> bool:
	for g in grid_points:
		if Vector2(p.x - g.x, p.z - g.z).length() < GRID_ZONE:
			return true
	return false


func _check_surface(net: Network, grid_points: Array[Vector3]) -> void:
	var space := get_viewport().find_world_3d().direct_space_state
	var samples := 0
	var misses := 0
	var blocked := 0
	var first_miss := ""
	var first_block := ""
	for e: Dictionary in net.g_edges:
		var pts: PackedVector3Array = e["points"]
		var along := 0.0
		var next := SAMPLE * 0.5
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			var seg := a.distance_to(b)
			while next <= along + seg:
				var p := a.lerp(b, (next - along) / maxf(seg, 0.001))
				next += SAMPLE
				if _near_grid(p, grid_points):
					continue
				var surface := p.y + Network.ROAD_TOP
				samples += 1
				var hit := _ray(space, p + Vector3.UP * 2.0, p + Vector3.DOWN * 3.0, [])
				if hit.is_empty() or absf((hit["position"] as Vector3).y - surface) > 0.35:
					misses += 1
					if misses <= 6:
						print("MAP_ROADS_MISS (%.1f, %.2f, %.1f) sol %s" % [p.x, surface, p.z, "absent" if hit.is_empty() else "%.2f sur %s" % [(hit["position"] as Vector3).y, (hit["collider"] as Node).name]])
					if first_miss == "":
						first_miss = "(%.0f, %.1f, %.0f) sol %s" % [p.x, surface, p.z, "absent" if hit.is_empty() else "%.2f" % (hit["position"] as Vector3).y]
				elif not _ray(space, Vector3(p.x, surface + 0.3, p.z), Vector3(p.x, surface + GAUGE, p.z), []).is_empty():
					blocked += 1
					if first_block == "":
						first_block = "(%.0f, %.1f, %.0f)" % [p.x, surface, p.z]
			along += seg
	print("MAP_ROADS_SURFACE %d points : %d sans chaussée à la bonne hauteur %s, %d gabarits encombrés %s" % [samples, misses, first_miss, blocked, first_block])
	if misses > 0:
		_errors.append("%d points sans chaussée, premier %s" % [misses, first_miss])
	if blocked > 0:
		_errors.append("%d gabarits encombrés, premier %s" % [blocked, first_block])


func _check_traffic(net: Network, grid_points: Array[Vector3]) -> void:
	var circuit := CircuitPath.new()
	circuit.name = "HighwayCircuit"
	add_child(circuit)
	for p in net.g_nodes:
		circuit.add_node(p)
	for e: Dictionary in net.g_edges:
		var pts: PackedVector3Array = e["points"]
		var via: Array = []
		for k in range(1, pts.size() - 1):
			via.append(pts[k])
		var idx := circuit.add_edge(int(e["a"]), int(e["b"]), via, bool(e["one_way"]))
		circuit.edges[idx]["lanes"] = e["lanes"]
	circuit.roundabout_nodes.assign(net.g_roundabout)
	circuit.unlit_nodes.assign(net.g_unlit)
	circuit.yield_approaches = net.g_yield.duplicate()
	circuit._setup_lights()
	# départs espacés, sur des noeuds qui ont une arête sortante
	var starts: Array[int] = []
	for i in circuit.node_count():
		if circuit.pick_next_edge(i, -1) < 0 or circuit.is_roundabout_node(i) or _near_grid(circuit.node_pos(i), grid_points):
			continue
		var free := true
		for s in starts:
			free = free and circuit.node_pos(s).distance_to(circuit.node_pos(i)) >= START_SPACING
		if free:
			starts.append(i)
	var cars: Array[Dictionary] = []
	for c in mini(CARS, starts.size()):
		var car := CAR.instantiate()
		add_child(car)
		car.setup(circuit, starts[(c * starts.size()) / mini(CARS, starts.size())], 13.0, 1.8, 100000)
		cars.append({"car": car, "last": car.global_position, "dist": 0.0, "off": 0, "checks": 0, "first_off": ""})
	var space := get_viewport().find_world_3d().direct_space_state
	var frames := int(DRIVE_SECONDS * Engine.physics_ticks_per_second)
	for f in frames:
		await get_tree().physics_frame
		if f % 30 != 29:
			continue
		for entry in cars:
			var car := entry["car"] as CharacterBody3D
			if not is_instance_valid(car):
				continue
			var pos := car.global_position
			entry["dist"] = float(entry["dist"]) + Vector2(pos.x - entry["last"].x, pos.z - entry["last"].z).length()
			entry["last"] = pos
			if _near_grid(pos, grid_points):
				continue
			entry["checks"] = int(entry["checks"]) + 1
			var bottom := pos.y - float(car.get("_ride_height"))
			var hit := _ray(space, pos + Vector3.UP * 1.5, pos + Vector3.DOWN * 4.0, [car.get_rid()])
			var on_road := not hit.is_empty() and String((hit["collider"] as Node).name).begins_with("RoadCell_") \
					and absf((hit["position"] as Vector3).y + Network.ROAD_TOP - 0.05 - bottom) < 0.6
			if not on_road:
				entry["off"] = int(entry["off"]) + 1
				if entry["first_off"] == "":
					entry["first_off"] = "(%.0f, %.1f, %.0f) sous la caisse : %s" % [pos.x, pos.y, pos.z,
							"rien" if hit.is_empty() else "%s à %.2f (bas de caisse %.2f)" % [(hit["collider"] as Node).name, (hit["position"] as Vector3).y, bottom]]
	var total_checks := 0
	var total_off := 0
	var slow := 0
	var shortest := INF
	for entry in cars:
		total_checks += int(entry["checks"])
		total_off += int(entry["off"])
		shortest = minf(shortest, float(entry["dist"]))
		if float(entry["dist"]) < MIN_DRIVE or not is_instance_valid(entry["car"]):
			slow += 1
			print("MAP_ROADS_CAR lente ou disparue : %.0f m, dernière position %s" % [entry["dist"], entry["last"]])
		if int(entry["off"]) > 0:
			print("MAP_ROADS_CAR hors chaussée %d/%d relevés, premier en %s" % [entry["off"], entry["checks"], entry["first_off"]])
		if is_instance_valid(entry["car"]):
			(entry["car"] as Node).queue_free()
	circuit.queue_free()
	var off_ratio := float(total_off) / maxf(total_checks, 1)
	print("MAP_ROADS_TRAFFIC %d voitures, %.0f s : distance mini %.0f m, %d sous %.0f m, hors chaussée %.1f %% des relevés"
			% [cars.size(), DRIVE_SECONDS, shortest, slow, MIN_DRIVE, off_ratio * 100.0])
	if cars.size() < CARS:
		_errors.append("seulement %d départs possibles" % cars.size())
	if slow > 0:
		_errors.append("%d voitures bloquées ou trop lentes" % slow)
	if off_ratio > MAX_OFF_ROAD:
		_errors.append("voitures hors chaussée (%.1f %% des relevés)" % (off_ratio * 100.0))


func _check_world() -> void:
	var world: Node = (load(WORLD_PATH) as PackedScene).instantiate()
	add_child(world)
	for spawner_name in ["CarSpawner", "NpcSpawner"]:
		var spawner := world.get_node_or_null(spawner_name)
		if spawner != null:
			spawner.set_process(false)
	var culler := world.get_node_or_null("SimulationCuller")
	if culler != null:
		culler.set("enabled", false)   # voitures loin du joueur : restent actives pour le test
	for k in 10:
		await get_tree().physics_frame
	var circuit := world.get_node_or_null("Circuit") as CircuitPath
	var traffic := world.get_node_or_null("Map/Roads/Traffic")
	if circuit == null or traffic == null:
		_errors.append("Circuit ou Map/Roads/Traffic absent du monde")
		return
	var reach_fwd := _circuit_reach(circuit, false)
	var reach_back := _circuit_reach(circuit, true)
	print("MAP_ROADS_WORLD Circuit : %d noeuds (%d ajoutés par la carte), %d arêtes (%d ajoutées), depuis le noeud 0 : %d atteints, %d qui l'atteignent"
			% [circuit.node_count(), traffic.merged_nodes, circuit.edges.size(), traffic.merged_edges, reach_fwd, reach_back])
	if traffic.merged_edges == 0:
		_errors.append("graphe de la carte non fusionné au Circuit")
	if reach_fwd != circuit.node_count() or reach_back != circuit.node_count():
		_errors.append("Circuit du monde non fortement connexe après fusion")
	# voitures au départ des raccords du centre-ville, vers l'extérieur
	var graph: MapTrafficGraph = traffic.graph
	var cars: Array[Dictionary] = []
	var space := get_viewport().find_world_3d().direct_space_state
	for i in graph.grid:
		if cars.size() >= WORLD_CARS:
			break
		var p := graph.nodes[i]
		var node := -1
		for j in circuit.node_count():
			if circuit.node_pos(j).distance_to(p) < 1.5:
				node = j
		if node < 0:
			continue
		# arête qui part vers la carte : celle dont l'autre bout n'est pas dans le centre-ville (plus loin du centre)
		var car := CAR.instantiate()
		world.add_child(car)
		car.setup(circuit, node, 12.0, 2.0, 100000)
		var outward := -1
		for e in circuit.node_edges(node):
			var other := circuit.edge_other_node(e, node)
			if circuit.node_pos(other).distance_to(Vector3(-460, 0, -172)) > p.distance_to(Vector3(-460, 0, -172)):
				outward = e
		if outward >= 0:
			car.set("_cur_edge", outward)
			car.call("_snap_to_path")
		cars.append({"car": car, "last": car.global_position, "dist": 0.0})
	for f in int(WORLD_SECONDS * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
		if f % 30 != 29:
			continue
		for entry in cars:
			var car := entry["car"] as Node3D
			if not is_instance_valid(car):
				continue
			var pos := car.global_position
			entry["dist"] = float(entry["dist"]) + Vector2(pos.x - entry["last"].x, pos.z - entry["last"].z).length()
			entry["last"] = pos
	var slow := 0
	var shortest := INF
	for entry in cars:
		shortest = minf(shortest, float(entry["dist"]))
		if float(entry["dist"]) < WORLD_MIN_DRIVE:
			slow += 1
			print("MAP_ROADS_WORLD voiture lente : %.0f m, dernière position %s" % [entry["dist"], entry["last"]])
	print("MAP_ROADS_WORLD %d voitures parties des raccords, %.0f s : distance mini %.0f m" % [cars.size(), WORLD_SECONDS, shortest])
	if cars.size() < WORLD_CARS:
		_errors.append("seulement %d raccords au centre-ville trouvés dans le Circuit" % cars.size())
	if slow > 0:
		_errors.append("%d voitures du centre-ville bloquées" % slow)


func _circuit_reach(circuit: CircuitPath, reverse: bool) -> int:
	var adj := {}
	for i in circuit.edges.size():
		var e: Dictionary = circuit.edges[i]
		var a: int = e["b"] if reverse else e["a"]
		var b: int = e["a"] if reverse else e["b"]
		if not adj.has(a):
			adj[a] = []
		adj[a].append(b)
		if not bool(e.get("one_way", false)):
			if not adj.has(b):
				adj[b] = []
			adj[b].append(a)
	var seen := {0: true}
	var stack: Array = [0]
	while not stack.is_empty():
		for m in adj.get(stack.pop_back(), []):
			if not seen.has(m):
				seen[m] = true
				stack.append(m)
	return seen.size()


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID]) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = exclude
	return space.intersect_ray(query)
