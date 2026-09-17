extends Node

# Test headless d'exploration de la carte 3D (étape 7), monde complet (World.tscn, spawners coupés) :
#  - itinéraires : depuis le point de départ du joueur, plus court chemin sur le Circuit (centre-ville et graphe de la
#    carte fusionnés, sens uniques respectés) jusqu'au noeud le plus proche de l'entrée de chaque lieu ;
#  - parcours en voiture simulé le long de chaque itinéraire, tous les 3 m, sur chacune des voies décrites par l'arête
#    (boulevards à terre-plein : jamais sur l'axe, planté), sinon sur l'axe et sur la voie de droite : sol roulable à la
#    hauteur du trajet et gabarit libre (boîte de 1,4 m de large de 0,7 à 2,5 m au-dessus du trajet) ;
#  - bilan des collisions de la carte par famille (routes, bâtiments, lieux, troncs, terrain).
#
# Lancer : Godot --headless --fixed-fps 60 --quit-after 3000 res://scenes/tests/MapExplorationTest.tscn

const WORLD := preload("res://scenes/world/World.tscn")
const PLACES_JSON := "res://scenes/world/map/generated/places/places.json"
const SAMPLE := 3.0
const ENTRANCE_REACH := 80.0
const HEIGHT_TOLERANCE := 0.9

var _errors: Array[String] = []


func _ready() -> void:
	print("MAP_EXPLORATION_BEGIN")
	var world := WORLD.instantiate()
	add_child(world)
	for spawner_name in ["CarSpawner", "NpcSpawner"]:
		var spawner := world.get_node_or_null(spawner_name)
		if spawner != null:
			spawner.set_process(false)
	for k in 5:
		await get_tree().physics_frame
	var circuit := world.get_node("Circuit") as CircuitPath
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PLACES_JSON))
	var start := _nearest_node(circuit, player.global_position)
	var dist := _dijkstra(circuit, start)
	var space := get_viewport().world_3d.direct_space_state
	var exclude: Array[RID] = []
	if player is CollisionObject3D:
		exclude.append((player as CollisionObject3D).get_rid())
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 1.8, 1.4)
	var total_km := 0.0
	for place: Dictionary in data["places"]:
		var entrance := Vector3(float(place["entrance"][0]), float(place["entrance"][1]), float(place["entrance"][2]))
		var target := _nearest_node(circuit, entrance)
		var gap := circuit.node_pos(target).distance_to(entrance)
		if gap > ENTRANCE_REACH or not dist[0].has(target):
			print("MAP_EXPLORATION_ROUTE %s : aucun noeud atteignable près de l'entrée (%.0f m)" % [place["id"], gap])
			_errors.append("%s inaccessible" % place["id"])
			continue
		var route := _route(circuit, dist, start, target)
		var length := 0.0
		var samples := 0
		var misses := 0
		var blocked := 0
		var first := ""
		for step: Array in route:
			var edge: int = step[0]
			var from_node: int = step[1]
			var edge_len := circuit.edge_length(edge)
			var s := 0.0
			var laterals: Array = [0.0, circuit.lane_offset(edge, 1.75)]
			var lanes: Variant = circuit.edges[edge].get("lanes")
			if lanes != null and not (lanes as PackedFloat32Array).is_empty():
				laterals = Array(lanes as PackedFloat32Array)
			while s < edge_len:
				for lateral: float in laterals:
					var p := circuit.sample_offset(edge, from_node, s, lateral)
					samples += 1
					var hit := space.intersect_ray(_ray(p + Vector3.UP * 3.0, p + Vector3.DOWN * 2.0, exclude))
					if hit.is_empty() or absf((hit["position"] as Vector3).y - p.y) > HEIGHT_TOLERANCE:
						misses += 1
						if first == "":
							first = "(%.0f, %.1f, %.0f) sol %s" % [p.x, p.y, p.z, "absent" if hit.is_empty() else "%.2f sur %s" % [(hit["position"] as Vector3).y, (hit["collider"] as Node).name]]
						continue
					var query := PhysicsShapeQueryParameters3D.new()
					query.shape = box
					query.transform = Transform3D(Basis.IDENTITY, (hit["position"] as Vector3) + Vector3(0, 0.7 + 0.9, 0))
					query.exclude = exclude
					var overlaps := space.intersect_shape(query, 4)
					if not overlaps.is_empty():
						blocked += 1
						if first == "":
							first = "(%.0f, %.1f, %.0f) gabarit : %s" % [p.x, p.y, p.z, (overlaps[0]["collider"] as Node).get_path()]
				s += SAMPLE
			length += edge_len
		total_km += length / 1000.0
		print("MAP_EXPLORATION_ROUTE %s : %.2f km, %d arêtes, %d relevés, %d sans sol, %d gabarits encombrés %s"
				% [place["id"], length / 1000.0, route.size(), samples, misses, blocked, first])
		if misses > 0 or blocked > 0:
			_errors.append("%s : %d sans sol, %d encombrés, premier %s" % [place["id"], misses, blocked, first])
	print("MAP_EXPLORATION_TOTAL %.1f km d'itinéraires vérifiés vers %d lieux" % [total_km, data["places"].size()])
	_collision_audit(world)
	print("MAP_EXPLORATION_RESULT %s %s" % ["OK" if _errors.is_empty() else "FAIL", " | ".join(_errors)])
	get_tree().quit(0 if _errors.is_empty() else 1)


func _ray(from: Vector3, to: Vector3, exclude: Array[RID]) -> PhysicsRayQueryParameters3D:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.exclude = exclude
	return q


func _nearest_node(circuit: CircuitPath, p: Vector3) -> int:
	var best := -1
	var best_d := INF
	for i in circuit.node_count():
		var d := Vector2(circuit.node_pos(i).x - p.x, circuit.node_pos(i).z - p.z).length()
		if d < best_d:
			best_d = d
			best = i
	return best


# [distances, prédécesseurs (noeud -> [arête, noeud précédent])] depuis `start`, sens uniques respectés.
func _dijkstra(circuit: CircuitPath, start: int) -> Array:
	var dist := {start: 0.0}
	var prev := {}
	var open := {start: true}
	while not open.is_empty():
		var u := -1
		var best := INF
		for n: int in open:
			if float(dist[n]) < best:
				best = dist[n]
				u = n
		open.erase(u)
		for e: int in circuit.node_edges(u):
			var edge: Dictionary = circuit.edges[e]
			if bool(edge.get("one_way", false)) and int(edge["a"]) != u:
				continue
			var v := circuit.edge_other_node(e, u)
			var nd := float(dist[u]) + circuit.edge_length(e)
			if nd < float(dist.get(v, INF)) - 0.001:
				dist[v] = nd
				prev[v] = [e, u]
				open[v] = true
	return [dist, prev]


# Liste [arête, noeud de départ] du départ vers la cible.
func _route(circuit: CircuitPath, dist: Array, start: int, target: int) -> Array:
	var prev: Dictionary = dist[1]
	var steps: Array = []
	var node := target
	while node != start:
		var p: Array = prev[node]
		steps.push_front([p[0], p[1]])
		node = p[1]
	return steps


func _collision_audit(world: Node) -> void:
	var families := {"routes et ouvrages": 0, "bâtiments des quartiers": 0, "lieux": 0, "troncs": 0, "terrain": 0, "limites": 0}
	var map := world.get_node_or_null("Map")
	if map == null:
		return
	for body in map.find_children("*", "CollisionObject3D", true, false):
		var path := String(body.get_path())
		var shapes := 0
		for child in body.get_children():
			if child is CollisionShape3D:
				shapes += 1
		if path.contains("/Roads/"):
			families["routes et ouvrages"] += shapes
		elif path.contains("/Buildings/"):
			families["bâtiments des quartiers"] += shapes
		elif path.contains("/Places/"):
			families["lieux"] += shapes
		elif path.contains("/Vegetation/"):
			families["troncs"] += shapes
		elif path.contains("/Terrain/"):
			families["terrain"] += shapes
		elif path.contains("/Boundary"):
			families["limites"] += shapes
	print("MAP_EXPLORATION_COLLISIONS formes de collision par famille : %s" % families)
