extends Node

# Ajoute au démarrage le graphe de circulation de la carte 3D (MapTrafficGraph) au Circuit du monde : les noeuds de la
# grille sont confondus avec ceux du centre-ville, les autres ajoutés ; arêtes avec leurs voies et leur sens unique,
# noeuds d'anneau, noeuds sans feu et approches qui cèdent le passage renumérotés ; feux recalculés. Un raccord sur un
# carrefour du centre-ville déjà à feux reçoit un feu visible pour sa branche (copie de la pose d'un feu existant du
# carrefour, tournée vers la nouvelle branche) ; un raccord sur un coin sans feu reste sans feu. Sans Circuit (carte
# chargée seule), ne fait rien.

const TRAFFIC_LIGHT := preload("res://scenes/world/TrafficLight.tscn")

@export var graph: MapTrafficGraph

var merged_nodes := 0
var merged_edges := 0
var first_edge := -1                  # indice de la première arête ajoutée au Circuit
var added_lights := 0


func _ready() -> void:
	if graph == null:
		return
	var circuit := _find_circuit()
	if circuit != null:
		merge_into(circuit)


func _find_circuit() -> CircuitPath:
	var node := get_parent()
	while node != null:
		var found := node.get_node_or_null("Circuit") as CircuitPath
		if found != null:
			return found
		node = node.get_parent()
	return null


func merge_into(circuit: CircuitPath) -> void:
	var remap := PackedInt32Array()
	remap.resize(graph.nodes.size())
	var grid := {}
	var city_degree := {}                 # noeud du Circuit -> nombre d'arêtes du centre-ville avant la fusion
	for i in graph.grid:
		grid[i] = true
	for i in graph.nodes.size():
		var p := graph.nodes[i]
		var existing := -1
		if grid.has(i):
			var best := 1.5
			for j in circuit.node_count():
				var d := circuit.node_pos(j).distance_to(p)
				if d < best:
					best = d
					existing = j
			if existing >= 0:
				city_degree[existing] = circuit.node_edges(existing).size()
		remap[i] = existing if existing >= 0 else circuit.add_node(p)
		if existing < 0:
			merged_nodes += 1
	first_edge = circuit.edges.size()
	var edge_remap := PackedInt32Array()
	for e: Dictionary in graph.edges:
		var pts: PackedVector3Array = e["points"]
		var via: Array = []
		for k in range(1, pts.size() - 1):
			via.append(pts[k])
		var idx := circuit.add_edge(remap[int(e["a"])], remap[int(e["b"])], via, bool(e["one_way"]))
		var lanes: PackedFloat32Array = e.get("lanes", PackedFloat32Array())
		if not lanes.is_empty():
			circuit.edges[idx]["lanes"] = lanes
		edge_remap.append(idx)
		merged_edges += 1
	for i in graph.roundabout:
		circuit.roundabout_nodes.append(remap[i])
	for i in graph.unlit:
		if not grid.has(i):
			circuit.unlit_nodes.append(remap[i])
	for key: String in graph.yields:
		var parts := key.split("_")
		circuit.yield_approaches["%d_%d" % [edge_remap[int(parts[0])], remap[int(parts[1])]]] = true
	for node: int in city_degree:
		if int(city_degree[node]) < 3:
			circuit.unlit_nodes.append(node)   # coin du centre-ville devenu carrefour : pas de feu invisible
	circuit._setup_lights()
	for node: int in city_degree:
		if int(city_degree[node]) >= 3:
			for e in circuit.node_edges(node):
				if e >= first_edge:
					_add_light(circuit, node, e)


# Feu visible pour l'arête `edge` du carrefour `node` : même pose, relative à sa branche, qu'un feu existant du
# carrefour (enfant d'une tuile de route du centre-ville), tournée vers la nouvelle branche.
func _add_light(circuit: CircuitPath, node: int, edge: int) -> void:
	var model: TrafficLight = null
	for light in _world_lights(circuit):
		if light.circuit_node == node:
			model = light
			break
	if model == null:
		return
	var center := circuit.node_pos(node)
	var model_dir := _arm_direction(circuit, node, model.circuit_edge)
	var new_dir := _arm_direction(circuit, node, edge)
	var turn := Basis(Vector3.UP, atan2(new_dir.x, new_dir.z) - atan2(model_dir.x, model_dir.z))
	var relative: Transform3D = model.global_transform
	relative.origin -= center
	var light := TRAFFIC_LIGHT.instantiate() as TrafficLight
	light.name = "MapTrafficLight_%d" % edge
	light.circuit_node = node
	light.circuit_edge = edge
	add_child(light)
	light.global_transform = Transform3D(turn * relative.basis, center + turn * relative.origin)
	light.circuit_path = light.get_path_to(circuit)
	light._circuit = circuit
	added_lights += 1


func _world_lights(circuit: CircuitPath) -> Array[TrafficLight]:
	var out: Array[TrafficLight] = []
	var world := circuit.get_parent()
	for n in world.find_children("*", "TrafficLight", true, false):
		if n.get_parent() != self:
			out.append(n as TrafficLight)
	return out


# Direction horizontale de la branche d'une arête, depuis le carrefour vers l'extérieur.
static func _arm_direction(circuit: CircuitPath, node: int, edge: int) -> Vector3:
	var pts: PackedVector3Array = circuit.edges[edge]["points"]
	var d := pts[1] - pts[0] if int(circuit.edges[edge]["a"]) == node else pts[pts.size() - 2] - pts[pts.size() - 1]
	d.y = 0.0
	return d.normalized()
