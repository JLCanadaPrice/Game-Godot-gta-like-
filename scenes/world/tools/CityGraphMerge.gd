extends RefCounted

# Fusion des graphes d'un district copié dans ceux de la carte (outil de CityExpansionBake) : les noeuds qui
# tombent au même endroit sont fusionnés (coutures entre districts), les arêtes en double ignorées. Les cartes
# d'indices renvoyées servent à recâbler les feux tricolores et les passages piétons de la copie.

const CIRCUIT_MERGE_DIST := 1.0
const PED_MERGE_DIST := 0.6


# Ajoute à dst les noeuds et arêtes de src décalés de offset ; renvoie {"nodes": src->dst, "edges": src->dst}.
static func merge_circuit(dst: CircuitPath, src: CircuitPath, offset: Vector3) -> Dictionary:
	var node_map := PackedInt32Array()
	for p: Vector3 in src.nodes:
		node_map.append(_find_or_add(dst.nodes, p + offset, CIRCUIT_MERGE_DIST))
	var edge_map := PackedInt32Array()
	for e: Dictionary in src.edges:
		var a := node_map[int(e["a"])]
		var b := node_map[int(e["b"])]
		var existing := _find_edge(dst.edges, a, b, e)
		if existing >= 0:
			edge_map.append(existing)
			continue
		var copy := e.duplicate(true)
		var pts := PackedVector3Array()
		for q: Vector3 in e["points"]:
			pts.append(q + offset)
		copy["a"] = a
		copy["b"] = b
		copy["points"] = pts
		dst.edges.append(copy)
		edge_map.append(dst.edges.size() - 1)
	for r in src.roundabout_nodes:
		if not dst.roundabout_nodes.has(node_map[r]):
			dst.roundabout_nodes.append(node_map[r])
	for key in src.crosswalk_stop_dist:
		var parts := String(key).split("_")
		var new_key := "%d_%d" % [edge_map[int(parts[0])], node_map[int(parts[1])]]
		if not dst.crosswalk_stop_dist.has(new_key):
			dst.crosswalk_stop_dist[new_key] = src.crosswalk_stop_dist[key]
	return {"nodes": node_map, "edges": edge_map}


# Idem pour le réseau piéton ; renvoie la carte des noeuds src->dst.
static func merge_ped(dst: PathGraph, src: PathGraph, offset: Vector3) -> PackedInt32Array:
	var node_map := PackedInt32Array()
	for p: Vector3 in src.nodes:
		node_map.append(_find_or_add(dst.nodes, p + offset, PED_MERGE_DIST))
	var seen := {}
	for e: Vector2i in dst.edges:
		seen[_key(e.x, e.y)] = true
	for e: Vector2i in src.edges:
		var a := node_map[e.x]
		var b := node_map[e.y]
		if a != b and not seen.has(_key(a, b)):
			seen[_key(a, b)] = true
			dst.edges.append(Vector2i(a, b))
	return node_map


# Branches d'un carrefour : direction cardinale ("+X", "-X", "+Z", "-Z", lue sur le premier segment de chaque
# arête) -> index de l'arête.
static func arm_edges(c: CircuitPath, node: int) -> Dictionary:
	var out := {}
	for idx in c.edges.size():
		var e: Dictionary = c.edges[idx]
		var pts: PackedVector3Array = e["points"]
		var d := Vector3.ZERO
		if int(e["a"]) == node:
			d = pts[1] - pts[0]
		elif int(e["b"]) == node:
			d = pts[pts.size() - 2] - pts[pts.size() - 1]
		else:
			continue
		out[("+X" if d.x > 0.0 else "-X") if absf(d.x) > absf(d.z) else ("+Z" if d.z > 0.0 else "-Z")] = idx
	return out


static func _find_or_add(nodes: Array[Vector3], p: Vector3, dist: float) -> int:
	for i in nodes.size():
		if nodes[i].distance_to(p) <= dist:
			return i
	nodes.append(p)
	return nodes.size() - 1


static func _find_edge(edges: Array[Dictionary], a: int, b: int, e: Dictionary) -> int:
	var one_way := bool(e.get("one_way", false))
	for i in edges.size():
		var d: Dictionary = edges[i]
		var same := int(d["a"]) == a and int(d["b"]) == b
		var reverse := int(d["a"]) == b and int(d["b"]) == a and not one_way
		if (same or reverse) and absf(float(d["length"]) - float(e["length"])) < 1.0:
			return i
	return -1


static func _key(a: int, b: int) -> String:
	return "%d_%d" % [mini(a, b), maxi(a, b)]
