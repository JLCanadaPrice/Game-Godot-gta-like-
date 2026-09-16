extends Node3D
class_name CircuitPath

# Graphe de circulation routière : noeuds = intersections réelles du District
# (34 carrefours + le rond-point), arêtes = tronçons de route entre deux
# noeuds voisins. La plupart des arêtes sont des lignes droites (2 points) ;
# quelques-unes (approches du rond-point, chicane) ont des points
# intermédiaires pour suivre la géométrie réelle courbe plutôt que couper
# tout droit à travers l'herbe.
#
# Une voiture suit une arête courante (noeud de départ -> noeud d'arrivée +
# progression locale sur CETTE arête, pas une abscisse globale). En
# atteignant le noeud d'arrivée, elle tire une nouvelle arête au hasard
# (jamais de demi-tour sauf cul-de-sac) via pick_next_edge().

@export var nodes: Array[Vector3] = []
@export var edges: Array[Dictionary] = []   # {a:int, b:int, points:PackedVector3Array, seg_len:PackedFloat32Array, cum:PackedFloat32Array, length:float, one_way:bool}

# Noeuds T_North/South/East/West du rond-point : pas de feu tricolore dessus
# (cédez-le-passage géré par les voitures elles-mêmes, cf. Car.gd), et les
# arêtes de l'anneau entre ces noeuds sont marquées one_way (cf. add_edge).
@export var roundabout_nodes: Array[int] = []

var _adj: Array = []   # _adj[i] = Array[int] des indices d'arêtes touchant le noeud i

# Distance réelle (mesurée sur le décalque de passage piéton de chaque
# approche, pas une constante théorique) entre le centre du carrefour et le
# bord du décalque le plus proche de la voiture qui approche. Clé "%d_%d" %
# [edge_idx, node_idx], absente si cette approche n'a pas de passage piéton
# (rond-point, carrefour non éclairé). Remplie une seule fois au moment du
# placement des décalques (cf. script de construction), pas recalculée au
# runtime : la géométrie ne change jamais en jeu.
@export var crosswalk_stop_dist: Dictionary = {}

# Graphe de la carte 3D (autoroutes, bretelles) : noeuds sans feu tricolore (divergents, convergents, anneaux) et
# approches qui cèdent le passage, clé "%d_%d" % [edge_idx, node_idx] (bretelle d'insertion -> noeud de convergence).
# Une arête peut aussi porter "lanes" : décalages latéraux de ses voies (sens unique à plusieurs voies, bretelle).
@export var unlit_nodes: Array[int] = []
@export var yield_approaches: Dictionary = {}

func crosswalk_clear_distance(edge_idx: int, node_idx: int) -> float:
	var key := "%d_%d" % [edge_idx, node_idx]
	if crosswalk_stop_dist.has(key):
		return float(crosswalk_stop_dist[key])
	return -1.0   # pas de passage piéton connu sur cette approche

# --- feux tricolores (carrefours classiques uniquement, jamais le rond-point) ---
const LIGHT_GREEN_TIME := 8.0
const LIGHT_YELLOW_TIME := 2.0
var _light_edge_phase: Dictionary = {}   # edge_idx -> 0/1 (axe EW ou NS), uniquement pour les noeuds à feu
var _light_state: Dictionary = {}        # node_idx -> {"phase":int, "timer":float, "green":bool}

func _ready() -> void:
	# `_adj` n'est pas exporté (donc pas sauvegardé) : après un rechargement
	# de scène il faut le reconstruire depuis `edges`, qui lui est persisté.
	rebuild_adjacency()
	_setup_lights()

func _process(delta: float) -> void:
	for node_idx in _light_state.keys():
		var st: Dictionary = _light_state[node_idx]
		st["timer"] -= delta
		if st["timer"] <= 0.0:
			if st["green"]:
				st["green"] = false
				st["timer"] = LIGHT_YELLOW_TIME
			else:
				st["phase"] = 1 - int(st["phase"])
				st["green"] = true
				st["timer"] = LIGHT_GREEN_TIME
		_light_state[node_idx] = st

# Construit la simulation de feux à partir du graphe déjà chargé (nodes/edges/
# roundabout_nodes, tous persistés) : un carrefour "classique" (≥3 arêtes,
# pas un noeud du rond-point) reçoit un cycle 2 phases (axe EW vs axe NS,
# déterminé par la direction dominante vers le noeud voisin). Volontairement
# PAS persisté : refait à chaque démarrage, déphasé aléatoirement par noeud.
func _setup_lights() -> void:
	_light_edge_phase.clear()
	_light_state.clear()
	for node_idx in nodes.size():
		if node_idx in roundabout_nodes or node_idx in unlit_nodes:
			continue
		var conn: Array = node_edges(node_idx)
		if conn.size() < 3:
			continue   # impasse ou simple passage (pas de vraie traversée ici)
		for e in conn:
			var other := edge_other_node(e, node_idx)
			var d: Vector3 = nodes[other] - nodes[node_idx]
			_light_edge_phase[e] = 0 if absf(d.x) > absf(d.z) else 1
		_light_state[node_idx] = {
			"phase": randi() % 2,
			"timer": randf_range(0.0, LIGHT_GREEN_TIME),
			"green": true,
		}

# true si la voie est libre (vert, ou pas de feu à ce noeud) pour continuer
# sur `edge_idx` en arrivant à `node_idx` ; false = rouge/orange -> s'arrêter.
func light_allows(edge_idx: int, node_idx: int) -> bool:
	if not _light_state.has(node_idx) or not _light_edge_phase.has(edge_idx):
		return true
	var st: Dictionary = _light_state[node_idx]
	return bool(st["green"]) and int(_light_edge_phase[edge_idx]) == int(st["phase"])

# Couleur visuelle (0=rouge, 1=orange, 2=vert, cf. TrafficLight.State) de
# l'approche `edge_idx` au carrefour `node_idx`, pour les feux visuels
# (TrafficLight.gd) -- pure lecture de l'état RÉEL déjà utilisé par Car.gd
# pour la conduite, aucune logique de cycle indépendante ici.
func light_color(edge_idx: int, node_idx: int) -> int:
	if not _light_state.has(node_idx) or not _light_edge_phase.has(edge_idx):
		return 2   # pas de feu à ce noeud (ne devrait pas être appelé) -> vert par défaut
	var st: Dictionary = _light_state[node_idx]
	if int(_light_edge_phase[edge_idx]) != int(st["phase"]):
		return 0   # rouge : ce n'est pas la phase active
	return 2 if bool(st["green"]) else 1   # vert si la phase active est verte, sinon orange

func is_edge_one_way(edge_idx: int) -> bool:
	return bool(edges[edge_idx].get("one_way", false))

func is_roundabout_node(node_idx: int) -> bool:
	return node_idx in roundabout_nodes

# Arête de l'anneau d'un rond-point (ou d'un échangeur) : sens unique entre deux noeuds de l'anneau. Les chaussées et
# bretelles d'autoroute sont aussi à sens unique mais ne sont pas prioritaires comme un anneau.
func is_ring_edge(edge_idx: int) -> bool:
	var e: Dictionary = edges[edge_idx]
	return bool(e.get("one_way", false)) and int(e["a"]) in roundabout_nodes and int(e["b"]) in roundabout_nodes

# Décalage latéral effectif sur une arête : la voie de l'arête la plus proche du décalage voulu, ou ce décalage tel
# quel si l'arête ne décrit pas ses voies (rues du centre-ville à double sens).
func lane_offset(edge_idx: int, preferred: float) -> float:
	var lanes: Variant = edges[edge_idx].get("lanes")
	if lanes == null or (lanes as PackedFloat32Array).is_empty():
		return preferred
	var best: float = lanes[0]
	for lane: float in lanes:
		if absf(lane - preferred) < absf(best - preferred):
			best = lane
	return best

func must_yield(edge_idx: int, node_idx: int) -> bool:
	return yield_approaches.has("%d_%d" % [edge_idx, node_idx])

func rebuild_adjacency() -> void:
	_adj.clear()
	for i in nodes.size():
		_adj.append([])
	for i in edges.size():
		var e: Dictionary = edges[i]
		var a: int = int(e["a"])
		var b: int = int(e["b"])
		_adj[a].append(i)
		_adj[b].append(i)

func clear() -> void:
	nodes.clear()
	edges.clear()
	_adj.clear()

func add_node(pos: Vector3) -> int:
	nodes.append(pos)
	_adj.append([])
	return nodes.size() - 1

# via : points intermédiaires (monde) entre nodes[a] et nodes[b], dans l'ordre
# a -> b. Laisser vide pour une arête en ligne droite. one_way=true (rond-point
# uniquement) : ne peut être empruntée QUE dans le sens a -> b, jamais b -> a
# (cf. pick_next_edge). Ne jamais mettre one_way=true sur une arête d'approche
# (elle doit rester utilisable dans les deux sens pour entrer ET sortir).
func add_edge(a: int, b: int, via: Array = [], one_way: bool = false) -> int:
	var pts := PackedVector3Array()
	pts.append(nodes[a])
	for v in via:
		pts.append(v)
	pts.append(nodes[b])

	var seg_len := PackedFloat32Array()
	var cum := PackedFloat32Array()
	var total := 0.0
	for i in pts.size() - 1:
		cum.append(total)
		var d: float = pts[i].distance_to(pts[i + 1])
		seg_len.append(d)
		total += d

	var idx := edges.size()
	edges.append({"a": a, "b": b, "points": pts, "seg_len": seg_len, "cum": cum, "length": total, "one_way": one_way})
	_adj[a].append(idx)
	_adj[b].append(idx)
	return idx

func node_count() -> int:
	return nodes.size()

func node_pos(i: int) -> Vector3:
	return nodes[i] if i >= 0 and i < nodes.size() else global_position

func node_edges(node_idx: int) -> Array:
	if node_idx < 0 or node_idx >= _adj.size():
		return []
	return _adj[node_idx]

func edge_length(edge_idx: int) -> float:
	return edges[edge_idx]["length"]

func edge_other_node(edge_idx: int, from_node: int) -> int:
	var e: Dictionary = edges[edge_idx]
	return int(e["b"]) if int(e["a"]) == from_node else int(e["a"])

# Prochaine arête au hasard depuis `node`, en évitant `avoid_edge` (celle
# d'où l'on vient) tant qu'il reste au moins une autre possibilité. Les
# arêtes one_way (anneau du rond-point) sont exclues si `node` n'est PAS leur
# extrémité `a` -> impossible de les emprunter à l'envers, y compris dans le
# repli ci-dessous (jamais de demi-tour interdit, même en dernier recours).
func pick_next_edge(node_idx: int, avoid_edge: int) -> int:
	var all_edges: Array = node_edges(node_idx)
	if all_edges.is_empty():
		return -1
	var allowed: Array = []
	for e in all_edges:
		if is_edge_one_way(e) and int(edges[e]["a"]) != node_idx:
			continue
		allowed.append(e)
	if allowed.is_empty():
		return -1
	var options: Array = []
	for e in allowed:
		if e != avoid_edge:
			options.append(e)
	if options.is_empty():
		return allowed[randi() % allowed.size()]
	return options[randi() % options.size()]

func _seg_index(seg_len: PackedFloat32Array, cum: PackedFloat32Array, s: float) -> int:
	for i in range(seg_len.size() - 1, -1, -1):
		if s >= cum[i]:
			return i
	return 0

# Position sur l'arête `edge_idx`, en parcourant depuis `from_node`, à la
# distance `s` (0 = from_node, edge_length = other node).
func sample(edge_idx: int, from_node: int, s: float) -> Vector3:
	var e: Dictionary = edges[edge_idx]
	var pts: PackedVector3Array = e["points"]
	var seg_len: PackedFloat32Array = e["seg_len"]
	var cum: PackedFloat32Array = e["cum"]
	var total: float = e["length"]
	if total <= 0.0:
		return pts[0]
	s = clampf(s, 0.0, total)
	var reversed: bool = int(e["a"]) != from_node
	var query_s: float = (total - s) if reversed else s
	var i := _seg_index(seg_len, cum, query_s)
	var t: float = ((query_s - cum[i]) / seg_len[i]) if seg_len[i] > 0.0 else 0.0
	return pts[i].lerp(pts[i + 1], t)

# Direction unitaire (horizontale) du déplacement le long de l'arête, en
# parcourant depuis `from_node`.
func direction_at(edge_idx: int, from_node: int, s: float) -> Vector3:
	var e: Dictionary = edges[edge_idx]
	var pts: PackedVector3Array = e["points"]
	var seg_len: PackedFloat32Array = e["seg_len"]
	var cum: PackedFloat32Array = e["cum"]
	var total: float = e["length"]
	if total <= 0.0:
		return Vector3.FORWARD
	var reversed: bool = int(e["a"]) != from_node
	var query_s: float = clampf((total - s) if reversed else s, 0.0, total)
	var i := _seg_index(seg_len, cum, query_s)
	var d: Vector3 = (pts[i + 1] - pts[i]).normalized()
	return -d if reversed else d

# Position décalée latéralement (+lateral = à droite du sens de marche).
#
# Résout l'arête et le segment UNE seule fois, puis en tire à la fois la
# position et la direction. La version précédente enchaînait direction_at()
# puis sample(), qui refaisaient chacun les quatre lectures du dictionnaire
# d'arête, le calcul de `reversed`, le clamp et la recherche de segment : soit
# deux fois le même travail par appel, pour chaque voiture et chaque frame.
# Résultat identique (mêmes formules, mêmes bornes), simplement calculé une fois.
func sample_offset(edge_idx: int, from_node: int, s: float, lateral: float) -> Vector3:
	var e: Dictionary = edges[edge_idx]
	var pts: PackedVector3Array = e["points"]
	var total: float = e["length"]
	if total <= 0.0:
		# même repli que direction_at (Vector3.FORWARD -> right = Vector3.RIGHT) suivi de sample (pts[0])
		return pts[0] + Vector3.RIGHT * lateral
	var seg_len: PackedFloat32Array = e["seg_len"]
	var cum: PackedFloat32Array = e["cum"]
	var reversed: bool = int(e["a"]) != from_node
	var query_s: float = clampf((total - s) if reversed else s, 0.0, total)
	var i := _seg_index(seg_len, cum, query_s)
	var d: Vector3 = (pts[i + 1] - pts[i]).normalized()
	var dir := -d if reversed else d
	var t: float = ((query_s - cum[i]) / seg_len[i]) if seg_len[i] > 0.0 else 0.0
	var pos := pts[i].lerp(pts[i + 1], t)
	return pos + dir.cross(Vector3.UP).normalized() * lateral
