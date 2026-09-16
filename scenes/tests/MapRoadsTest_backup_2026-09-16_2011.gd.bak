extends Node

# Test headless des routes de la carte 3D (étape 2a et suivantes), sur la carte seule (Map.tscn) :
#  - modèle : RoadNetwork sans erreur, graphe de circulation fortement connexe ;
#  - surface : le long de chaque arête du graphe, tous les 6 m, un rayon descendant rencontre la chaussée à la hauteur
#    du trajet (écart < 0,35 m) et rien n'encombre le gabarit au-dessus (4,5 m) ;
#  - circulation : voitures IA (Car.tscn) sur un CircuitPath construit depuis le graphe, 70 s simulées : chacune
#    parcourt au moins MIN_DRIVE m et reste posée sur la chaussée (rayon sous la caisse).
#
# Lancer : Godot --headless --fixed-fps 60 --quit-after 30000 res://scenes/tests/MapRoadsTest.tscn

const MAP := preload("res://scenes/world/map/Map.tscn")
const CAR := preload("res://scenes/vehicles/Car.tscn")
const Network := preload("res://scenes/world/map/tools/RoadNetwork.gd")
const SAMPLE := 6.0
const GAUGE := 4.5
const CARS := 18
const START_SPACING := 60.0
const DRIVE_SECONDS := 70.0
const MIN_DRIVE := 350.0
const MAX_OFF_ROAD := 0.03

var _errors: Array[String] = []


func _ready() -> void:
	print("MAP_ROADS_BEGIN")
	add_child(MAP.instantiate())
	for k in 3:
		await get_tree().physics_frame
	var net := Network.new()
	net.build()
	if not net.errors.is_empty():
		_errors.append("modèle : " + " ; ".join(net.errors))
	print("MAP_ROADS_GRAPH %d noeuds, %d arêtes, fortement connexe %s" % [net.g_nodes.size(), net.g_edges.size(), net.strongly_connected()])
	if not net.strongly_connected():
		_errors.append("graphe non fortement connexe")
	_check_surface(net)
	await _check_traffic(net)
	print("MAP_ROADS_RESULT %s %s" % ["OK" if _errors.is_empty() else "FAIL", " | ".join(_errors)])
	get_tree().quit(0 if _errors.is_empty() else 1)


func _check_surface(net: Network) -> void:
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
				var surface := p.y + Network.ROAD_TOP
				samples += 1
				var hit := _ray(space, p + Vector3.UP * 2.0, p + Vector3.DOWN * 3.0, [])
				if hit.is_empty() or absf((hit["position"] as Vector3).y - surface) > 0.35:
					misses += 1
					if first_miss == "":
						first_miss = "(%.0f, %.1f, %.0f) sol %s" % [p.x, surface, p.z, "absent" if hit.is_empty() else "%.2f" % (hit["position"] as Vector3).y]
				elif not _ray(space, Vector3(p.x, surface + 0.3, p.z), Vector3(p.x, surface + GAUGE, p.z), []).is_empty():
					blocked += 1
					if first_block == "":
						first_block = "(%.0f, %.1f, %.0f)" % [p.x, surface, p.z]
				next += SAMPLE
			along += seg
	print("MAP_ROADS_SURFACE %d points : %d sans chaussée à la bonne hauteur %s, %d gabarits encombrés %s" % [samples, misses, first_miss, blocked, first_block])
	if misses > 0:
		_errors.append("%d points sans chaussée, premier %s" % [misses, first_miss])
	if blocked > 0:
		_errors.append("%d gabarits encombrés, premier %s" % [blocked, first_block])


func _check_traffic(net: Network) -> void:
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
		if circuit.pick_next_edge(i, -1) < 0 or circuit.is_roundabout_node(i):
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
	var off_ratio := float(total_off) / maxf(total_checks, 1)
	print("MAP_ROADS_TRAFFIC %d voitures, %.0f s : distance mini %.0f m, %d sous %.0f m, hors chaussée %.1f %% des relevés"
			% [cars.size(), DRIVE_SECONDS, shortest, slow, MIN_DRIVE, off_ratio * 100.0])
	if cars.size() < CARS:
		_errors.append("seulement %d départs possibles" % cars.size())
	if slow > 0:
		_errors.append("%d voitures bloquées ou trop lentes" % slow)
	if off_ratio > MAX_OFF_ROAD:
		_errors.append("voitures hors chaussée (%.1f %% des relevés)" % (off_ratio * 100.0))


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID]) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = exclude
	return space.intersect_ray(query)
