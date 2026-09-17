extends RefCounted

# Données de circulation du centre-ville reconstruit, tirées du plan (DowntownLayout) : graphe routier du Circuit,
# distances d'arrêt aux passages piétons, réseau piéton (PedGraph) et poses des feux. Déterministe : l'installation
# dans World.tscn (DowntownInstall) et la génération des rues (DowntownStreetsBake, feux câblés par indices) en tirent
# les mêmes indices.
#
# Circuit : un nœud par carrefour (y = 0, les voitures roulent à Car.ROAD_TOP_Y) ; une arête par tronçon, dans l'ordre
# des tronçons (indice d'arête = indice de tronçon), sens unique dans le sens de marche, voies décrites ("lanes") ;
# feux simulés par CircuitPath lui-même à tout carrefour de 3 branches ou plus (angles du pourtour : sans feu).
# Réseau piéton : quatre coins de trottoir par carrefour (chemin au milieu du trottoir), trottoirs le long des tronçons,
# traversée de chaque branche d'un carrefour à feux sur son passage piéton, trottoir continu devant une branche absente
# (carrefour en T, angle du pourtour).

const Layout := preload("res://scenes/world/downtown/DowntownLayout.gd")
const Spec := preload("res://scenes/world/downtown/DowntownSpec.gd")

const LIGHT_HEIGHT := 3.785        # tête du feu au-dessus du pied de son mât (MapTraffic.POST_BELOW_LIGHT)
const LIGHT_BACK := 0.4            # m au-delà du bord du carrefour, le long de la branche (anciens feux : 6,4 m pour 6)
const LIGHT_SIDE := 0.3            # m au-delà du bord de la chaussée de la branche, sur le trottoir
const QUADRANTS := [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]   # NW, NE, SW, SE

var layout: Layout
var nodes: Array[Vector3] = []
var edges: Array[Dictionary] = []
var crosswalk_stop_dist := {}
var ped_nodes: Array[Vector3] = []
var ped_edges: Array[Vector2i] = []
var lights: Array[Dictionary] = []   # {"node", "edge", "transform"}
var _corner := {}                    # Vector3i(nœud, sx, sz) -> indice du nœud piéton


func _init(p_layout: Layout = null) -> void:
	layout = p_layout if p_layout != null else Layout.new()
	_build_circuit()
	_build_ped()
	_build_lights()


func _build_circuit() -> void:
	var circuit := CircuitPath.new()
	for n in layout.nodes.size():
		circuit.add_node(layout.node_pos3(n))
	for i in layout.segments.size():
		var s: Dictionary = layout.segments[i]
		var a := int(s["a"])
		var b := int(s["b"])
		if int(s["dir"]) < 0:
			var t := a
			a = b
			b = t
		var e := circuit.add_edge(a, b, [], bool(s["one_way"]))
		circuit.edges[e]["lanes"] = (s["lanes"] as PackedFloat32Array).duplicate()
	nodes = circuit.nodes.duplicate()
	edges = circuit.edges.duplicate(true)
	circuit.free()
	for n in layout.nodes.size():
		var node: Dictionary = layout.nodes[n]
		if not node["lit"]:
			continue
		for arm: String in node["arms"]:
			crosswalk_stop_dist["%d_%d" % [int(node["arms"][arm]), n]] = snappedf(float(layout.crosswalk(n, arm)["stop"]), 0.01)


func _build_ped() -> void:
	for n in layout.nodes.size():
		var arms: Dictionary = layout.nodes[n]["arms"]
		for q: Vector2i in QUADRANTS:
			# coin sur un trottoir : branche du côté x ou du côté z du coin, ou angle du pourtour (les deux trottoirs
			# extérieurs s'y rejoignent)
			var on_walk := arms.has("E" if q.x > 0 else "W") or arms.has("S" if q.y > 0 else "N") or arms.size() == 2
			if not on_walk:
				continue
			var c := layout.ped_corner(n, q.x, q.y)
			_corner[Vector3i(n, q.x, q.y)] = ped_nodes.size()
			ped_nodes.append(Vector3(c.x, 0.0, c.y))
	for n in layout.nodes.size():
		var node: Dictionary = layout.nodes[n]
		var arms: Dictionary = node["arms"]
		# branche présente et carrefour à feux : traversée sur le passage piéton ; branche absente : trottoir continu
		for arm: String in ["N", "S", "W", "E"]:
			var pair := _arm_corners(n, arm)
			if pair.x < 0 or pair.y < 0:
				continue
			if arms.has(arm) and not node["lit"]:
				continue
			_ped_edge(pair.x, pair.y)
	for i in layout.segments.size():
		var s: Dictionary = layout.segments[i]
		var a := int(s["a"])
		var b := int(s["b"])
		if s["axis"] == "x":
			_ped_edge(int(_corner.get(Vector3i(a, -1, 1), -1)), int(_corner.get(Vector3i(b, -1, -1), -1)))
			_ped_edge(int(_corner.get(Vector3i(a, 1, 1), -1)), int(_corner.get(Vector3i(b, 1, -1), -1)))
		else:
			_ped_edge(int(_corner.get(Vector3i(a, 1, -1), -1)), int(_corner.get(Vector3i(b, -1, -1), -1)))
			_ped_edge(int(_corner.get(Vector3i(a, 1, 1), -1)), int(_corner.get(Vector3i(b, -1, 1), -1)))


# Coins de trottoir qui encadrent la branche `arm` (N : NW-NE, S : SW-SE, W : NW-SW, E : NE-SE).
func _arm_corners(n: int, arm: String) -> Vector2i:
	var qa: Vector2i
	var qb: Vector2i
	match arm:
		"N":
			qa = Vector2i(-1, -1)
			qb = Vector2i(1, -1)
		"S":
			qa = Vector2i(-1, 1)
			qb = Vector2i(1, 1)
		"W":
			qa = Vector2i(-1, -1)
			qb = Vector2i(-1, 1)
		_:
			qa = Vector2i(1, -1)
			qb = Vector2i(1, 1)
	return Vector2i(int(_corner.get(Vector3i(n, qa.x, qa.y), -1)), int(_corner.get(Vector3i(n, qb.x, qb.y), -1)))


func _ped_edge(a: int, b: int) -> void:
	if a < 0 or b < 0 or a == b:
		return
	var e := Vector2i(mini(a, b), maxi(a, b))
	if not ped_edges.has(e):
		ped_edges.append(e)


# Un feu par approche (branche d'où l'on peut arriver) de chaque carrefour à feux : sur le trottoir à droite de la
# voiture qui arrive, juste avant le carrefour, tourné vers elle ; même pose que les feux de l'ancien centre-ville.
func _build_lights() -> void:
	for n in layout.nodes.size():
		var node: Dictionary = layout.nodes[n]
		if not node["lit"]:
			continue
		var center := layout.node_pos3(n)
		for arm: String in node["arms"]:
			var e := int(node["arms"][arm])
			if bool(edges[e]["one_way"]) and int(edges[e]["b"]) != n:
				continue   # sens unique qui part du carrefour : personne n'arrive par là
			var d2 := Layout.arm_dir(arm)
			var out := Vector3(d2.x, 0.0, d2.y)
			var travel := -out
			var right := travel.cross(Vector3.UP).normalized()
			var box := float(node["hz"]) if arm == "N" or arm == "S" else float(node["hx"])
			var half := float(layout.segments[e]["half"])
			var pos := center + out * (box + LIGHT_BACK) + right * (half + LIGHT_SIDE) \
					+ Vector3.UP * (Spec.ROAD_TOP + Spec.SIDEWALK_RISE + LIGHT_HEIGHT)
			lights.append({"node": n, "edge": e, "transform": Transform3D(Basis.looking_at(out, Vector3.UP), pos)})


func stats() -> Dictionary:
	return {"noeuds": nodes.size(), "aretes": edges.size(), "sens_unique": edges.filter(func(e: Dictionary) -> bool: return e["one_way"]).size(),
			"arrets_passages": crosswalk_stop_dist.size(), "pietons": [ped_nodes.size(), ped_edges.size()], "feux": lights.size()}
