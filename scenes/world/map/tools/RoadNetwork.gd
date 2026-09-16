extends RefCounted

# Réseau routier de la carte 3D calculé depuis MapSpec (étape 2a : autoroutes et voies express).
#  - axes : tronçons d'un même axe enchaînés puis lissés (Catmull-Rom centripète), échantillonnés tous les 4 m ;
#  - profils en long : relief naturel lissé (sans la remontée des bords de carte), pente limitée, tablier au-dessus de
#    l'eau ; niveau des axes aux échangeurs (tranchée / viaduc), aux losanges et aux passages de la voie ferrée choisi
#    par recherche locale : d'abord aucune pente dépassée ni contrainte violée, ensuite le moins de terrassement ;
#  - autoroutes : deux chaussées de 2 voies séparées par un terre-plein ;
#  - échangeurs en anneau à trois niveaux : un axe en tranchée, l'anneau au niveau du sol, l'autre axe sur viaduc ;
#    bretelles qui longent leur chaussée puis s'évasent vers l'anneau ; un axe qui s'arrête à l'échangeur se raccorde
#    directement à l'anneau ; jonction continue là où deux axes se prolongent ;
#  - sorties de carte en tranchée puis en tunnel, demi-tour caché au fond ;
#  - graphe de circulation : arêtes avec voies et sens unique, anneaux gérés comme le rond-point existant, noeuds sans
#    feu, bretelles d'insertion qui cèdent le passage.
# Géométrie en rubans (axe 3D + largeur), utilisée par RoadBake et par les tests de routes ; `errors` liste ce qui
# rendrait la géométrie inutilisable (pentes, eau, conflits entre rubans, tunnels).

const Spec := preload("res://scenes/world/map/MapSpec.gd")
const TerrainModel := preload("res://scenes/world/map/tools/TerrainModel.gd")

const STEP := 4.0
const ROAD_TOP := 0.05              # surface des routes du centre-ville (Car.ROAD_TOP_Y) : y = 0 dans le graphe
const DECK := 1.2                   # épaisseur de tablier
const CLEARANCE := 7.0              # hauteur libre sous un viaduc d'autoroute
const LOW_CLEARANCE := 5.8          # hauteur libre au-dessus d'un axe en tranchée (sous l'anneau, un pont, la voie ferrée)
const RAIL_DECK := 1.2
const WATER_DECK := 8.55            # surface de chaussée au-dessus de l'eau (niveau -0,95 + 9,5)
const CW_OFFSET := 6.85             # axe d'une chaussée d'autoroute depuis l'axe du terre-plein
const CW_WIDTH := 10.7
const MEDIAN_WIDTH := 3.0
const RAMP_WIDTH := 7.0
const RAMP_OFFSET := 15.7           # axe d'une bretelle qui longe sa chaussée (CW_OFFSET + demi-largeurs)
const RING_WIDTH := 10.0
const RING_RADIUS := 72.0
const RING_ANGLE := 0.383972        # 22° : entrée et sortie d'anneau de part et d'autre de chaque branche
const RING_FLARE := 45.0            # au-delà du rayon : la bretelle quitte l'axe et s'évase vers l'anneau
const RAMP_DISTANCE := 260.0        # du centre, le long de l'axe : départ / arrivée des bretelles (au plus)
const RAMP_MIN_DISTANCE := 160.0
const EDGE_LEG_MIN := 300.0         # branche traversante vers une sortie de carte : bretelles seulement au-delà
const DIAMOND_CLEAR := 190.0        # longueur d'axe réservée aux bretelles d'un losange (étape 2b)
const DIAMOND_REACH := 40.0         # demi-longueur de l'ouvrage d'un losange au niveau haut / bas
const TERMINAL_DISTANCE := 190.0    # du centre : fin des chaussées d'un axe qui s'arrête à l'anneau
const LEVEL_LOW := -7.0             # axe en tranchée
const LEVEL_HIGH := 8.2             # axe sur viaduc (CLEARANCE + DECK)
const JOIN_TRIM := 120.0
const TUNNEL_DEPTH := 36.0
const PORTAL_COVER := 8.0           # terrain au-dessus de la chaussée à l'entrée d'un tunnel
const BLEND := 40.0                 # m pour passer de l'axe d'une chaussée à celui d'une bretelle
const LEVEL_WITH_CARRIAGEWAY := 26.0  # m de bretelle accolée à niveau de sa chaussée (le trajet franchit le joint vers 23 m)
const GRADE := {"highway": 0.045, "ramp": 0.08}
const GRADE_LIMIT := {"carriageway": 0.052, "median": 0.052, "ramp": 0.092, "ring": 0.01}
const SMOOTH := {"highway": 220.0, "ramp": 12.0}
const AXIS_PRIORITY := ["an", "vxo", "as", "vxe"]
const WIDTHS := {"carriageway": CW_WIDTH, "median": MEDIAN_WIDTH, "ramp": RAMP_WIDTH, "ring": RING_WIDTH}


class Ribbon:
	var id := ""
	var kind := ""                          # carriageway, median, ramp, ring
	var width := 0.0
	var chain := ""                         # chaîne d'autoroute d'origine
	var points := PackedVector3Array()      # axe géométrique (x, surface de chaussée, z)
	var path := PackedVector3Array()        # trajet de circulation (même nombre d'échantillons, y = surface - ROAD_TOP)
	var one_way := true
	var lanes := PackedFloat32Array()
	var graph := true
	var closed := false
	var splits := {}                        # index d'échantillon -> noeud de graphe obligatoire
	var yield_end := false                  # la dernière arête cède le passage (insertion)


var terrain: TerrainModel
var chains: Array[Dictionary] = []
var ribbons: Array = []
var tunnels: Array[Dictionary] = []
var boundary_gaps: Array[Dictionary] = []
var rail_crossings: Array[Dictionary] = []
var road_crossings: Array[Dictionary] = []  # artères qui croisent une autoroute hors losange (ouvrage, étape 2b)
var attachments: Array[Dictionary] = []     # bords de rubans accolés à un raccord (ni garde-corps ni mur) : ruban, indices, côté
var levels := {}                            # anneau -> axe en tranchée ("low"/"high" s'il n'a qu'un axe traversant) ; losange -> "low"/"high"
var rail_modes := {}                        # passage (voie ferrée ou artère) -> "over" (autoroute au-dessus) / "under"
var report: PackedStringArray = []
var errors: PackedStringArray = []
var conflicts: Array[Vector3] = []
var g_nodes := PackedVector3Array()
var g_edges: Array[Dictionary] = []
var g_roundabout: Array[int] = []
var g_unlit: Array[int] = []
var g_yield := {}
var _node_base_cache := {}
var _chain_ribbons := {}                    # id de chaîne -> {"d": Ribbon, "i": Ribbon, "m": Ribbon}
var _node_hash := {}


func _init(model: TerrainModel = null) -> void:
	terrain = model if model != null else TerrainModel.new()


func build() -> void:
	_build_chains()
	_profile_chains()
	for chain in chains:
		_make_chain_ribbons(chain)
	for node_id: String in Spec.NODES:
		if shape(node_id) == "ring":
			_build_ring(node_id)
		elif shape(node_id) == "join":
			_build_join(node_id)
	_build_tunnels()
	_finalize_paths()
	_build_graph()
	_check()


static func shape(node_id: String) -> String:
	var node: Dictionary = Spec.NODES[node_id]
	return String(node.get("shape", "")) if node["kind"] == "interchange" else ""


# --- axes -------------------------------------------------------------------------------------------------------
func _build_chains() -> void:
	var by_axis := {}
	for road: Dictionary in Spec.ROADS:
		if road["class"] == "highway":
			if not by_axis.has(road["axis"]):
				by_axis[road["axis"]] = []
			by_axis[road["axis"]].append(road)
	for axis: String in by_axis:
		var pending: Array = by_axis[axis].duplicate()
		while not pending.is_empty():
			var head: Dictionary = pending[0]
			for r: Dictionary in pending:
				var is_head := true
				for other: Dictionary in pending:
					if other["to"] == r["from"]:
						is_head = false
				if is_head:
					head = r
					break
			var roads: Array[Dictionary] = [head]
			pending.erase(head)
			var searching := true
			while searching:
				searching = false
				for r: Dictionary in pending:
					if r["from"] == roads[-1]["to"]:
						roads.append(r)
						pending.erase(r)
						searching = true
						break
			chains.append(_make_chain(axis, roads))


func _make_chain(axis: String, roads: Array[Dictionary]) -> Dictionary:
	var control := PackedVector2Array()
	var nodes: Array[String] = []
	for road in roads:
		if control.is_empty():
			control.append(Spec.node_pos(road["from"]))
			nodes.append(road["from"])
		for v: Vector2 in road["via"]:
			control.append(v)
		control.append(Spec.node_pos(road["to"]))
		nodes.append(road["to"])
	var points := smooth(control, STEP)
	var node_index := {}
	for node_id in nodes:
		node_index[node_id] = nearest_index(points, Spec.node_pos(node_id))
	return {"id": axis + "_" + String(roads[0]["id"]), "axis": axis, "nodes": nodes, "points": points,
			"node_index": node_index, "heights": PackedFloat32Array(), "first": 0, "last": points.size() - 1}


# --- profils en long ----------------------------------------------------------------------------------------------
func _profile_chains() -> void:
	var variables: Array[Dictionary] = []
	for chain in chains:
		var pts: PackedVector2Array = chain["points"]
		chain["natural"] = _natural_profile(pts)
		chain["water"] = water_spans(pts, 10.0)
		var rails: Array = []
		var lines: Array = [["voie ferrée", PackedVector2Array(Spec.RAIL)]]
		for road: Dictionary in Spec.ROADS:
			if road["class"] != "highway":
				lines.append([road["id"], Spec.road_polyline(road)])
		for line: Array in lines:
			for hit in polyline_intersections(pts, line[1]):
				var near_node := false
				for node_id: String in chain["nodes"]:
					near_node = near_node or hit.distance_to(Spec.node_pos(node_id)) < 60.0
				if near_node:
					continue
				var key := "%s@%d" % [chain["id"], rails.size()]
				var rail_h := maxf(terrain.height_at(hit), TerrainModel.RIVER_BANK_TOP) + 0.3
				rails.append({"key": key, "i": nearest_index(pts, hit), "pos": hit, "rail_h": rail_h, "with": line[0]})
				rail_modes[key] = "over"
				variables.append({"key": key, "rail": true, "options": ["over", "under"], "chains": [chain]})
		chain["rails"] = rails
	for node_id: String in Spec.NODES:
		var touching: Array = chains.filter(func(c: Dictionary) -> bool: return (c["nodes"] as Array).has(node_id))
		if touching.is_empty():
			continue
		if shape(node_id) == "ring":
			var through := through_axes(node_id)
			var ordered: Array = AXIS_PRIORITY.filter(func(a: String) -> bool: return through.has(a))
			if ordered.size() == 2:
				levels[node_id] = ordered[0]
				variables.append({"key": node_id, "rail": false, "options": ordered, "chains": touching})
			elif ordered.size() == 1:
				levels[node_id] = "low"
				variables.append({"key": node_id, "rail": false, "options": ["low", "high"], "chains": touching})
		elif Spec.NODES[node_id]["kind"] == "diamond":
			levels[node_id] = "high"
			variables.append({"key": node_id, "rail": false, "options": ["high", "low"], "chains": touching})
	var results := {}
	for chain in chains:
		results[chain["id"]] = _evaluate(chain)
	for pass_index in 6:
		var improved := false
		for v in variables:
			var store: Dictionary = rail_modes if v["rail"] else levels
			var current: String = store[v["key"]]
			for option: String in v["options"]:
				if option == current:
					continue
				var saved_modes := rail_modes.duplicate()
				store[v["key"]] = option
				var trial := {}
				for chain: Dictionary in v["chains"]:
					trial[chain["id"]] = _evaluate(chain)
				if not v["rail"]:
					_refine_crossings(v["chains"], trial)
				var delta := 0.0
				for chain: Dictionary in v["chains"]:
					delta += float(trial[chain["id"]]["cost"]) - float(results[chain["id"]]["cost"])
				if delta < -0.001:
					current = option
					for id: String in trial:
						results[id] = trial[id]
					improved = true
				else:
					store[v["key"]] = current
					for key: String in saved_modes:
						rail_modes[key] = saved_modes[key]
		if not improved:
			break
	var parts: PackedStringArray = []
	for node_id: String in levels:
		parts.append("%s=%s" % [node_id, levels[node_id]])
	report.append("niveaux : " + ", ".join(parts))
	for chain in chains:
		var r: Dictionary = results[chain["id"]]
		chain["heights"] = r["heights"]
		report.append("profil %s : terrassement %.0f m², contraintes non tenues %.2f" % [chain["id"], r["earth"], r["violation"]])
		if float(r["violation"]) > 0.05:
			errors.append("profil %s : pentes ou contraintes non tenues (%.2f, pire écart %s)" % [chain["id"], r["violation"], r["worst"]])
		for rc: Dictionary in chain["rails"]:
			var h: float = (chain["heights"] as PackedFloat32Array)[rc["i"]]
			var mode: String = rail_modes[rc["key"]]
			var gap := (h - DECK - float(rc["rail_h"])) if mode == "over" else (float(rc["rail_h"]) - RAIL_DECK - h)
			var entry := {"pos": rc["pos"], "rail_height": rc["rail_h"], "road_height": h, "chain": chain["id"], "mode": mode, "with": rc["with"], "index": rc["i"]}
			if rc["with"] == "voie ferrée":
				rail_crossings.append(entry)
			else:
				road_crossings.append(entry)
			report.append("%s %s %s : dégagement %.1f m" % [rc["with"], "sous" if mode == "over" else "au-dessus de", chain["id"], gap])
			if gap < LOW_CLEARANCE - 0.3:
				errors.append("%s / %s : dégagement %.1f m" % [rc["with"], chain["id"], gap])


# Après le changement de niveau d'un noeud : chaque passage des chaînes concernées essaie l'autre sens.
func _refine_crossings(touching: Array, trial: Dictionary) -> void:
	for chain: Dictionary in touching:
		for rc: Dictionary in chain["rails"]:
			var key: String = rc["key"]
			var before: String = rail_modes[key]
			rail_modes[key] = "under" if before == "over" else "over"
			var r := _evaluate(chain)
			if float(r["cost"]) < float(trial[chain["id"]]["cost"]) - 0.001:
				trial[chain["id"]] = r
			else:
				rail_modes[key] = before


func _natural_profile(pts: PackedVector2Array) -> PackedFloat32Array:
	var r := Spec.PLAYABLE
	var out := PackedFloat32Array()
	for p in pts:
		var q := Vector2(clampf(p.x, r.position.x + 2.0, r.end.x - 2.0), clampf(p.y, r.position.y + 2.0, r.end.y - 2.0))
		out.append(maxf(terrain.height_at(q), TerrainModel.RIVER_BANK_TOP) + 0.3)
	return out


func _evaluate(chain: Dictionary) -> Dictionary:
	var pts: PackedVector2Array = chain["points"]
	var natural: PackedFloat32Array = chain["natural"]
	var n := pts.size()
	var fixed := {}
	var constraints: Array = []
	for node_id: String in chain["nodes"]:
		if Spec.NODES[node_id]["kind"] == "edge" or shape(node_id) == "join":
			continue
		var idx: int = chain["node_index"][node_id]
		var h := node_axis_height(node_id, chain["axis"])
		var base := node_base(node_id)
		fixed[idx] = h
		if absf(h - base) > 0.5:
			var reach := (RING_RADIUS + RING_WIDTH + 40.0) if shape(node_id) == "ring" else DIAMOND_REACH
			var half := int(reach / STEP)
			constraints.append({"i0": idx - half, "i1": idx + half, "h": h, "type": "max" if h < base else "min"})
	for span: Vector2i in chain["water"]:
		constraints.append({"i0": span.x - 3, "i1": span.y + 3, "h": WATER_DECK, "type": "min"})
	for rc: Dictionary in chain["rails"]:
		var i: int = rc["i"]
		if rail_modes[rc["key"]] == "over":
			constraints.append({"i0": i - 6, "i1": i + 6, "h": float(rc["rail_h"]) + CLEARANCE + DECK, "type": "min"})
		else:
			constraints.append({"i0": i - 6, "i1": i + 6, "h": float(rc["rail_h"]) - RAIL_DECK - LOW_CLEARANCE, "type": "max"})
	var p := solve_profile(natural, GRADE["highway"], SMOOTH["highway"], fixed, constraints)
	var violation := 0.0
	var limit: float = GRADE["highway"] * STEP * 1.02
	var worst := 0.0
	var worst_at := Vector2.ZERO
	for i in range(1, n):
		var excess := maxf(0.0, absf(p[i] - p[i - 1]) - limit)
		violation += excess
		if excess > worst:
			worst = excess
			worst_at = pts[i]
	for c: Dictionary in constraints:
		for i in range(maxi(int(c["i0"]), 0), mini(int(c["i1"]), n - 1) + 1):
			var excess := (float(c["h"]) - p[i]) if c["type"] == "min" else (p[i] - float(c["h"]))
			violation += maxf(0.0, excess - 0.05) / 8.0
			if excess - 0.05 > worst:
				worst = excess - 0.05
				worst_at = pts[i]
	var earth := 0.0
	for i in n:
		earth += absf(p[i] - natural[i]) * STEP
	return {"heights": p, "violation": violation, "earth": earth, "cost": violation * 1000.0 + earth / 100.0,
			"worst": "%.2f m en (%.0f, %.0f)" % [worst, worst_at.x, worst_at.y]}


func node_base(node_id: String) -> float:
	if _node_base_cache.has(node_id):
		return _node_base_cache[node_id]
	var node: Dictionary = Spec.NODES[node_id]
	var h := ROAD_TOP
	if node["kind"] != "grid":
		var p: Vector2 = node["pos"]
		var total := 0.0
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				total += maxf(terrain.height_at(p + Vector2(dx, dz) * 12.0), TerrainModel.RIVER_BANK_TOP)
		h = total / 25.0 + 0.3
	_node_base_cache[node_id] = h
	return h


func node_axis_height(node_id: String, axis: String) -> float:
	var node: Dictionary = Spec.NODES[node_id]
	var base := node_base(node_id)
	if shape(node_id) == "ring":
		var through := through_axes(node_id)
		if through.has(axis):
			var level: String = levels.get(node_id, "low")
			if through.size() == 1:
				return base + (LEVEL_LOW if level == "low" else LEVEL_HIGH)
			return base + (LEVEL_LOW if level == axis else LEVEL_HIGH)
	elif node["kind"] == "diamond":
		return base + (LEVEL_LOW if levels.get(node_id, "high") == "low" else LEVEL_HIGH)
	return base


func through_axes(node_id: String) -> Array:
	var out: Array = []
	for chain in chains:
		var k: int = (chain["nodes"] as Array).find(node_id)
		if k > 0 and k < (chain["nodes"] as Array).size() - 1:
			out.append(chain["axis"])
	return out


# --- rubans des autoroutes ----------------------------------------------------------------------------------------
func _make_chain_ribbons(chain: Dictionary) -> void:
	var pts: PackedVector2Array = chain["points"]
	var heights: PackedFloat32Array = chain["heights"]
	var n := pts.size()
	var nodes: Array = chain["nodes"]
	var first := 0
	var last := n - 1
	if Spec.NODES[nodes[0]]["kind"] == "interchange":
		first = index_at_distance(pts, 0, TERMINAL_DISTANCE if shape(nodes[0]) == "ring" else JOIN_TRIM, 1)
	if Spec.NODES[nodes[-1]]["kind"] == "interchange":
		last = index_at_distance(pts, n - 1, TERMINAL_DISTANCE if shape(nodes[-1]) == "ring" else JOIN_TRIM, -1)
	var d := _new_ribbon(chain["id"] + ":d", "carriageway", chain["id"])
	var r := _new_ribbon(chain["id"] + ":i", "carriageway", chain["id"])
	var m := _new_ribbon(chain["id"] + ":m", "median", chain["id"])
	m.graph = false
	for rb in [d, r]:
		rb.lanes = PackedFloat32Array([-1.8, 1.8])
	for i in range(first, last + 1):
		var side := right_of(tangent(pts, i))
		d.points.append(Vector3(pts[i].x + side.x * CW_OFFSET, heights[i], pts[i].y + side.y * CW_OFFSET))
		m.points.append(Vector3(pts[i].x, heights[i], pts[i].y))
	for i in range(last, first - 1, -1):
		var side := right_of(tangent(pts, i))
		r.points.append(Vector3(pts[i].x - side.x * CW_OFFSET, heights[i], pts[i].y - side.y * CW_OFFSET))
	chain["first"] = first
	chain["last"] = last
	_chain_ribbons[chain["id"]] = {"d": d, "i": r, "m": m}
	ribbons.append_array([d, r, m])


func _new_ribbon(id: String, kind: String, chain_id: String) -> Ribbon:
	var rb := Ribbon.new()
	rb.id = id
	rb.kind = kind
	rb.width = WIDTHS[kind]
	rb.chain = chain_id
	return rb


# Indice d'échantillon d'une chaussée (d : sens des indices croissants, i : sens inverse) pour un indice de chaîne.
static func _ribbon_index(chain: Dictionary, forward: bool, j: int) -> int:
	return j - int(chain["first"]) if forward else int(chain["last"]) - j


# --- échangeurs en anneau -----------------------------------------------------------------------------------------
func _build_ring(node_id: String) -> void:
	var center := Spec.node_pos(node_id)
	var h0 := node_base(node_id)
	var legs: Array[Dictionary] = []
	for chain in chains:
		var nodes: Array = chain["nodes"]
		var k := nodes.find(node_id)
		if k < 0:
			continue
		var through := k > 0 and k < nodes.size() - 1
		if k > 0:
			legs.append(_make_leg(chain, node_id, k, -1, through))
		if k < nodes.size() - 1:
			legs.append(_make_leg(chain, node_id, k, 1, through))
	# noeuds de l'anneau : entrée et sortie de chaque branche, parcourus dans le sens trigonométrique vu du dessus
	legs = legs.filter(func(l: Dictionary) -> bool: return l["ramps"])
	var ring_angles: Array = []
	for leg in legs:
		leg["entry"] = _map_angle(rotate_ccw(leg["u"], RING_ANGLE))
		leg["exit"] = _map_angle(rotate_ccw(leg["u"], -RING_ANGLE))
		ring_angles.append(leg["entry"])
		ring_angles.append(leg["exit"])
	ring_angles.sort()
	for k in ring_angles.size():
		var gap := fposmod(float(ring_angles[(k + 1) % ring_angles.size()]) - float(ring_angles[k]), TAU) * RING_RADIUS
		if gap < 24.0:
			errors.append("anneau %s : entrée et sortie à %.0f m l'une de l'autre" % [node_id, gap])
	var ring := _new_ribbon("ring_" + node_id, "ring", "")
	ring.closed = true
	ring.lanes = PackedFloat32Array([-2.0, 2.0])
	var angle_index := {}
	for k in ring_angles.size():
		var a0: float = ring_angles[k]
		var a1: float = ring_angles[(k + 1) % ring_angles.size()]
		if a1 <= a0:
			a1 += TAU
		angle_index[snappedf(a0, 0.0001)] = ring.points.size()
		ring.splits[ring.points.size()] = true
		var steps := maxi(1, ceili((a1 - a0) * RING_RADIUS / STEP))
		for s in steps:
			var q := center + _from_map_angle(lerpf(a0, a1, float(s) / steps)) * RING_RADIUS
			ring.points.append(Vector3(q.x, h0, q.y))
	ribbons.append(ring)
	for leg in legs:
		var chain: Dictionary = leg["chain"]
		var ribs: Dictionary = _chain_ribbons[chain["id"]]
		var s: int = leg["sign"]
		var incoming: Ribbon = ribs["d"] if s < 0 else ribs["i"]
		var outgoing: Ribbon = ribs["i"] if s < 0 else ribs["d"]
		var entry_pos: Vector3 = ring.points[angle_index[snappedf(leg["entry"], 0.0001)]]
		var exit_pos: Vector3 = ring.points[angle_index[snappedf(leg["exit"], 0.0001)]]
		var j_center: int = chain["node_index"][node_id]
		var j_flare: int = j_center + s * roundi((RING_RADIUS + RING_FLARE) / STEP)
		var ramp_in: Ribbon
		var ramp_out: Ribbon
		if leg["through"]:
			var j_a: int = clampi(j_center + s * roundi(float(leg["distance"]) / STEP), int(chain["first"]) + 2, int(chain["last"]) - 2)
			var in_i := _ribbon_index(chain, s < 0, j_a)
			var out_i := _ribbon_index(chain, s > 0, j_a)
			incoming.splits[in_i] = true
			outgoing.splits[out_i] = true
			ramp_in = _ring_ramp(node_id + ":sortie", chain, center, s, j_a, j_flare, RAMP_OFFSET, entry_pos, h0, true)
			ramp_out = _ring_ramp(node_id + ":insertion", chain, center, s, j_a, j_flare, RAMP_OFFSET, exit_pos, h0, false)
			# divergent et convergent : chaussée et bretelle accolées sur BLEND m, ouvertes l'une sur l'autre
			var span := ceili((BLEND + 8.0) / STEP)
			attachments.append({"ribbon": incoming, "from": in_i, "to": in_i + span, "side": 1})
			attachments.append({"ribbon": ramp_in, "from": 0, "to": span, "side": -1})
			attachments.append({"ribbon": outgoing, "from": out_i - span, "to": out_i, "side": 1})
			attachments.append({"ribbon": ramp_out, "from": ramp_out.points.size() - 1 - span, "to": ramp_out.points.size() - 1, "side": -1})
		else:
			var j_a: int = chain["last"] if s < 0 else chain["first"]
			incoming.splits[incoming.points.size() - 1] = true
			outgoing.splits[0] = true
			ramp_in = _ring_ramp(node_id + ":arrivee", chain, center, s, j_a, j_flare, CW_OFFSET, entry_pos, h0, true)
			ramp_out = _ring_ramp(node_id + ":depart", chain, center, s, j_a, j_flare, CW_OFFSET, exit_pos, h0, false)
		# raccords à l'anneau : bretelle ouverte des deux côtés sur ses derniers mètres, anneau ouvert côté extérieur
		attachments.append({"ribbon": ramp_in, "from": ramp_in.points.size() - 4, "to": ramp_in.points.size() - 1, "side": 0})
		attachments.append({"ribbon": ramp_out, "from": 0, "to": 3, "side": 0})
		for ring_i: int in [angle_index[snappedf(leg["entry"], 0.0001)], angle_index[snappedf(leg["exit"], 0.0001)]]:
			attachments.append({"ribbon": ring, "from": ring_i - 4, "to": ring_i + 4, "side": 1})


func _make_leg(chain: Dictionary, node_id: String, k: int, s: int, through: bool) -> Dictionary:
	var pts: PackedVector2Array = chain["points"]
	var idx: int = chain["node_index"][node_id]
	var probe := clampi(idx + s * roundi((RING_RADIUS + 20.0) / STEP), 0, pts.size() - 1)
	var leg := {"chain": chain, "sign": s, "through": through, "ramps": true, "u": (pts[probe] - Spec.node_pos(node_id)).normalized()}
	if through:
		var next_id: String = (chain["nodes"] as Array)[k + s]
		if Spec.NODES[next_id]["kind"] == "edge" and _inside_length(chain, idx, s) < EDGE_LEG_MIN:
			leg["ramps"] = false   # branche courte vers un tunnel de sortie : seulement le demi-tour, pas d'échange utile
		else:
			leg["distance"] = _ramp_distance(chain, node_id, k, s)
	return leg


# Longueur d'axe entre l'indice idx et la limite de la zone explorable, dans le sens s.
static func _inside_length(chain: Dictionary, idx: int, s: int) -> float:
	var pts: PackedVector2Array = chain["points"]
	var j := idx
	while j + s >= 0 and j + s < pts.size() and Spec.PLAYABLE.has_point(pts[j + s]):
		j += s
	return absf(j - idx) * STEP


# Distance le long de l'axe entre le centre d'un anneau et le départ de ses bretelles sur une branche traversante :
# laisse la place aux bretelles du noeud suivant et reste dans la zone explorable.
func _ramp_distance(chain: Dictionary, node_id: String, k: int, s: int) -> float:
	var idx: int = chain["node_index"][node_id]
	var next_id: String = (chain["nodes"] as Array)[k + s]
	var gap := absf(int(chain["node_index"][next_id]) - idx) * STEP
	var d := RAMP_DISTANCE
	match String(Spec.NODES[next_id]["kind"]):
		"edge":
			d = minf(d, _inside_length(chain, idx, s) - 30.0)
		"interchange":
			d = minf(d, gap * 0.5 - 20.0)
		_:
			d = minf(d, gap - DIAMOND_CLEAR)
	# un ouvrage (voie ferrée, artère) ne doit pas croiser les bretelles : au-delà de leur départ sur un axe en viaduc
	# (bretelles au sol), ou tant qu'elles sont encore au fond de la tranchée sur un axe en tranchée
	var high := node_axis_height(node_id, chain["axis"]) > node_base(node_id)
	for rc: Dictionary in chain["rails"]:
		var along := (int(rc["i"]) - idx) * s * STEP
		if along <= 0.0 or along > d + 20.0:
			continue
		if high:
			d = minf(d, along - 25.0)
		elif along < d - 30.0:
			errors.append("anneau %s : %s croise les bretelles à %.0f m du centre" % [node_id, rc["with"], along])
	if d < RAMP_MIN_DISTANCE:
		errors.append("anneau %s : bretelles vers %s à %.0f m seulement" % [node_id, next_id, d])
	return maxf(d, RAMP_MIN_DISTANCE)


# Bretelle entre une chaussée (indice de chaîne j_a) et un point de l'anneau : longe l'axe de j_a à j_f en passant du
# décalage latéral t_a à RAMP_OFFSET, puis courbe de Bézier jusqu'à l'anneau, qu'elle aborde entre sa tangente et son
# rayon. inbound : vers l'anneau (côté entrée) ; sinon depuis l'anneau (côté sortie), points parcourus à l'envers.
func _ring_ramp(id: String, chain: Dictionary, center: Vector2, s: int, j_a: int, j_f: int, t_a: float,
		ring_point: Vector3, h_ring: float, inbound: bool) -> Ribbon:
	var pts: PackedVector2Array = chain["points"]
	var heights: PackedFloat32Array = chain["heights"]
	var side_sign := 1.0 if inbound else -1.0
	var line := PackedVector2Array()
	var line_h := PackedFloat32Array()
	var sides := PackedVector2Array()
	var count := absi(j_a - j_f)
	for k in count + 1:
		var j := j_a - s * k
		var side := rotate_ccw(tangent(pts, j) * float(s), PI * 0.5) * side_sign
		line.append(pts[j] + side * lerpf(t_a, RAMP_OFFSET, smoothstep(0.0, float(maxi(count, 1)), float(k))))
		line_h.append(heights[j])
		sides.append(side)
	var q := Vector2(ring_point.x, ring_point.z)
	var radial := (q - center).normalized()
	var ring_dir := rotate_ccw(radial, PI * 0.5) * side_sign
	var end_dir := (ring_dir * 0.8 - radial * 0.6).normalized()
	var p0 := line[count]
	var start_dir := -tangent(pts, j_f) * float(s)
	var gap := p0.distance_to(q)
	var bend := resample(bezier([p0, p0 + start_dir * gap * 0.4, q - end_dir * minf(18.0, gap * 0.35), q], 96), STEP)
	if bend.size() > 2 and bend[bend.size() - 2].distance_to(q) < STEP * 0.6:
		bend.remove_at(bend.size() - 2)
	for k in range(1, bend.size()):
		line.append(bend[k])
		line_h.append(heights[j_f])
		sides.append(sides[count])
	var arc := PackedFloat32Array([0.0])
	for k in range(1, line.size()):
		arc.append(arc[k - 1] + line[k - 1].distance_to(line[k]))
	var total: float = arc[arc.size() - 1]
	# hauteurs : à niveau de la chaussée tant que le trajet passe de l'une à l'autre (BLEND m, bretelle accolée), puis
	# régulièrement vers l'anneau ; tablier au-dessus de l'eau
	var natural := PackedFloat32Array()
	var constraints: Array = []
	for k in line.size():
		var direct := lerpf(line_h[0], h_ring, smoothstep(0.0, total, arc[k]))
		natural.append(lerpf(line_h[k], direct, smoothstep(LEVEL_WITH_CARRIAGEWAY, LEVEL_WITH_CARRIAGEWAY + 30.0, arc[k])))
		if arc[k] <= LEVEL_WITH_CARRIAGEWAY and t_a > CW_OFFSET:
			constraints.append({"i0": k, "i1": k, "h": line_h[k] + 0.01, "type": "max"})
			constraints.append({"i0": k, "i1": k, "h": line_h[k] - 0.01, "type": "min"})
		if is_water(line[k]) or terrain.river_info(line[k]).x < 10.0:
			constraints.append({"i0": k - 2, "i1": k + 2, "h": WATER_DECK, "type": "min"})
	# pente visée un peu sous la limite : l'écart entre échantillons descend à ~3,3 m à l'intérieur des courbes
	var h := solve_profile(natural, GRADE["ramp"] * 0.85, SMOOTH["ramp"], {0: line_h[0], line.size() - 1: h_ring}, constraints)
	var rb := _new_ribbon(id, "ramp", chain["id"])
	rb.lanes = PackedFloat32Array([0.0])
	rb.yield_end = not inbound and t_a > CW_OFFSET
	for k in line.size():
		rb.points.append(Vector3(line[k].x, h[k], line[k].y))
		# trajet : part de l'axe de la chaussée et rejoint celui de la bretelle sur BLEND m
		var pp := line[k] - sides[k] * (t_a - CW_OFFSET) * (1.0 - smoothstep(0.0, BLEND, arc[k]))
		rb.path.append(Vector3(pp.x, h[k] - ROAD_TOP, pp.y))
	rb.path[rb.path.size() - 1] = Vector3(q.x, h_ring - ROAD_TOP, q.y)
	if not inbound:
		rb.points.reverse()
		rb.path.reverse()
	ribbons.append(rb)
	return rb


# --- jonctions et tunnels -----------------------------------------------------------------------------------------
func _build_join(node_id: String) -> void:
	var ending: Array[Dictionary] = []
	for chain in chains:
		if (chain["nodes"] as Array)[-1] == node_id:
			ending.append(chain)
	if ending.size() != 2:
		errors.append("jonction %s : %d axes au lieu de 2" % [node_id, ending.size()])
		return
	var a: Dictionary = _chain_ribbons[ending[0]["id"]]
	var b: Dictionary = _chain_ribbons[ending[1]["id"]]
	for pair in [[a["d"], b["i"]], [b["d"], a["i"]]]:
		var src: Ribbon = pair[0]
		var dst: Ribbon = pair[1]
		var end := src.points.size() - 1
		src.splits[end] = true
		dst.splits[0] = true
		_link(node_id, src.points[end], _ribbon_dir(src, end), dst.points[0], _ribbon_dir(dst, 0), "carriageway")
	var ma: Ribbon = a["m"]
	var mb: Ribbon = b["m"]
	var link := _link(node_id + ":m", ma.points[-1], _ribbon_dir(ma, ma.points.size() - 1), mb.points[-1], -_ribbon_dir(mb, mb.points.size() - 1), "median")
	link.graph = false


func _link(id: String, a: Vector3, a_dir: Vector2, b: Vector3, b_dir: Vector2, kind: String) -> Ribbon:
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var reach := a2.distance_to(b2) * 0.4
	var curve := resample(bezier([a2, a2 + a_dir * reach, b2 - b_dir * reach, b2], 128), STEP)
	var rb := _new_ribbon(id + ":" + str(ribbons.size()), kind, id)
	rb.lanes = PackedFloat32Array([-1.8, 1.8])
	for k in curve.size():
		var t := float(k) / maxf(curve.size() - 1, 1)
		rb.points.append(Vector3(curve[k].x, lerpf(a.y, b.y, smoothstep(0.0, 1.0, t)), curve[k].y))
	ribbons.append(rb)
	return rb


func _build_tunnels() -> void:
	for chain in chains:
		var nodes: Array = chain["nodes"]
		var ribs: Dictionary = _chain_ribbons[chain["id"]]
		var pts: PackedVector2Array = chain["points"]
		var heights: PackedFloat32Array = chain["heights"]
		for end in ["head", "tail"]:
			var node_id: String = nodes[0] if end == "head" else nodes[-1]
			if Spec.NODES[node_id]["kind"] != "edge":
				continue
			var tip := pts.size() - 1 if end == "tail" else 0
			var inward := -1 if end == "tail" else 1
			var arriving: Ribbon = ribs["d"] if end == "tail" else ribs["i"]
			var leaving: Ribbon = ribs["i"] if end == "tail" else ribs["d"]
			var j := tip
			while j + inward >= 0 and j + inward < pts.size() and not Spec.PLAYABLE.has_point(pts[j]):
				j += inward
			var boundary := j
			var portal := -1
			while j != tip:
				if terrain.height_at(pts[j]) - heights[j] >= PORTAL_COVER:
					portal = j
					break
				j -= inward
			if portal < 0 or absi(tip - portal) * STEP < 30.0:
				errors.append("tunnel %s : pas assez de terrain au-dessus de la chaussée" % node_id)
				portal = tip
			arriving.splits[arriving.points.size() - 1] = true
			leaving.splits[0] = true
			tunnels.append({"id": node_id, "chain": chain["id"], "tip_index": tip, "portal_index": portal, "boundary_index": boundary,
					"pos": Vector3(pts[tip].x, heights[tip], pts[tip].y), "dir": tangent(pts, tip) * float(-inward),
					"width": CW_OFFSET * 2.0 + CW_WIDTH + 4.0,
					"arrive": arriving.points[arriving.points.size() - 1], "leave": leaving.points[0]})
		for hit in _boundary_crossings(pts):
			boundary_gaps.append({"pos": hit, "width": CW_OFFSET * 2.0 + CW_WIDTH + 10.0, "chain": chain["id"]})


func _boundary_crossings(pts: PackedVector2Array) -> Array[Vector2]:
	var r := Spec.PLAYABLE
	var edges := [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.end.x, r.position.y), r.end],
			[r.end, Vector2(r.position.x, r.end.y)], [Vector2(r.position.x, r.end.y), r.position]]
	var out: Array[Vector2] = []
	for k in pts.size() - 1:
		for e: Array in edges:
			var hit: Variant = Geometry2D.segment_intersects_segment(pts[k], pts[k + 1], e[0], e[1])
			if hit != null and out.filter(func(o: Vector2) -> bool: return o.distance_to(hit) < 2.0).is_empty():
				out.append(hit)
	return out


# --- graphe -------------------------------------------------------------------------------------------------------
func _finalize_paths() -> void:
	for rb in ribbons:
		if rb.path.is_empty():
			for p: Vector3 in rb.points:
				rb.path.append(Vector3(p.x, p.y - ROAD_TOP, p.z))


func _build_graph() -> void:
	for rb in ribbons:
		if not rb.graph:
			continue
		var n: int = rb.path.size()
		var cuts: Array = rb.splits.keys()
		if not rb.closed:
			cuts.append(0)
			cuts.append(n - 1)
		var unique := {}
		for c in cuts:
			unique[int(c)] = true
		cuts = unique.keys()
		cuts.sort()
		if rb.closed:
			for k in cuts.size():
				var a: int = cuts[k]
				var b: int = cuts[(k + 1) % cuts.size()]
				var pts := PackedVector3Array()
				var i := a
				while true:
					pts.append(rb.path[i])
					if i == b and pts.size() > 1:
						break
					i = (i + 1) % n
				_add_edge(pts, rb)
			for c in cuts:
				var id := _graph_node(rb.path[c])
				if not g_roundabout.has(id):
					g_roundabout.append(id)
		else:
			for k in cuts.size() - 1:
				var pts := PackedVector3Array()
				for i in range(cuts[k], cuts[k + 1] + 1):
					pts.append(rb.path[i])
				var edge_index := _add_edge(pts, rb)
				if rb.yield_end and k == cuts.size() - 2:
					g_yield["%d_%d" % [edge_index, g_edges[edge_index]["b"]]] = true
	for t in tunnels:
		var a: Vector3 = t["arrive"]
		var b: Vector3 = t["leave"]
		var dir: Vector2 = t["dir"]
		var mid := (Vector2(a.x, a.z) + Vector2(b.x, b.z)) * 0.5 + dir * TUNNEL_DEPTH
		var pts := PackedVector3Array([Vector3(a.x, a.y - ROAD_TOP, a.z), Vector3(mid.x, a.y - ROAD_TOP, mid.y), Vector3(b.x, b.y - ROAD_TOP, b.z)])
		var turn := Ribbon.new()
		turn.lanes = PackedFloat32Array([0.0])
		_add_edge(pts, turn)
	for i in g_nodes.size():
		g_unlit.append(i)


func _add_edge(pts: PackedVector3Array, rb: Ribbon) -> int:
	var a := _graph_node(pts[0])
	var b := _graph_node(pts[pts.size() - 1])
	pts[0] = g_nodes[a]
	pts[pts.size() - 1] = g_nodes[b]
	var seg_len := PackedFloat32Array()
	var cum := PackedFloat32Array()
	var total := 0.0
	for k in pts.size() - 1:
		cum.append(total)
		var d := pts[k].distance_to(pts[k + 1])
		seg_len.append(d)
		total += d
	g_edges.append({"a": a, "b": b, "points": pts, "seg_len": seg_len, "cum": cum, "length": total, "one_way": rb.one_way, "lanes": rb.lanes})
	return g_edges.size() - 1


func _graph_node(p: Vector3) -> int:
	var key := Vector3i(roundi(p.x), roundi(p.y), roundi(p.z))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var k2 := key + Vector3i(dx, dy, dz)
				if _node_hash.has(k2):
					for idx: int in _node_hash[k2]:
						if g_nodes[idx].distance_to(p) < 0.75:
							return idx
	g_nodes.append(p)
	if not _node_hash.has(key):
		_node_hash[key] = []
	_node_hash[key].append(g_nodes.size() - 1)
	return g_nodes.size() - 1


# --- contrôles ----------------------------------------------------------------------------------------------------
func _check() -> void:
	var worst := {}
	var where := {}
	var low_deck := 0
	var low_ids := {}
	for rb in ribbons:
		for k in rb.points.size():
			var b: Vector3 = rb.points[k]
			if is_water(Vector2(b.x, b.z)) and b.y < WATER_DECK - 0.35:
				low_deck += 1
				low_ids[rb.id] = true
			if k == 0:
				continue
			var a: Vector3 = rb.points[k - 1]
			var g := absf(b.y - a.y) / maxf(Vector2(b.x - a.x, b.z - a.z).length(), 0.05)
			if g > float(worst.get(rb.kind, 0.0)):
				worst[rb.kind] = g
				where[rb.kind] = "%s[%d] (%.0f, %.0f) %.2f -> %.2f" % [rb.id, k, b.x, b.z, a.y, b.y]
	var parts: PackedStringArray = []
	for kind: String in worst:
		parts.append("%s %.1f %%" % [kind, float(worst[kind]) * 100.0])
		if float(worst[kind]) > float(GRADE_LIMIT[kind]):
			errors.append("pente %s %.1f %% en %s" % [kind, float(worst[kind]) * 100.0, where[kind]])
	report.append("pentes max : " + ", ".join(parts))
	if low_deck > 0:
		errors.append("%d points de chaussée trop bas au-dessus de l'eau (%s)" % [low_deck, ", ".join(PackedStringArray(low_ids.keys()))])
	_check_conflicts()
	report.append("conflits entre rubans : %d" % conflicts.size())
	if not conflicts.is_empty():
		var shown: PackedStringArray = []
		for c in conflicts.slice(0, 8):
			shown.append("(%.0f, %.0f)" % [c.x, c.z])
		errors.append("%d conflits entre rubans, dont %s" % [conflicts.size(), ", ".join(shown)])
	var reach_fwd := _reach(false)
	var reach_back := _reach(true)
	report.append("graphe : %d noeuds, %d arêtes, depuis le noeud 0 : %d atteints, %d qui l'atteignent" % [g_nodes.size(), g_edges.size(), reach_fwd, reach_back])
	if reach_fwd != g_nodes.size() or reach_back != g_nodes.size():
		errors.append("graphe non fortement connexe")


func is_water(p: Vector2) -> bool:
	if terrain.river_info(p).x < 0.0:
		return true
	for lake: Dictionary in Spec.LAKES:
		if ((p - lake["center"]) / lake["radii"]).length() < 1.0:
			return true
	return false


# Deux rubans se chevauchent (en plan, à moins de 5 m de hauteur l'un de l'autre) hors de leurs raccords prévus :
# extrémités communes du trajet (70 m autour), terre-plein contre ses chaussées.
func _check_conflicts() -> void:
	const CELL := 16.0
	var grid := {}
	for r in ribbons.size():
		var rb: Ribbon = ribbons[r]
		for k in rb.points.size():
			var key := Vector2i(floori(rb.points[k].x / CELL), floori(rb.points[k].z / CELL))
			if not grid.has(key):
				grid[key] = []
			grid[key].append(Vector2i(r, k))
	var links := {}
	for r in ribbons.size():
		var rb: Ribbon = ribbons[r]
		for e: Vector3 in [rb.path[0], rb.path[rb.path.size() - 1]]:
			var key := Vector2i(floori(e.x / CELL), floori(e.z / CELL))
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					for hit: Vector2i in grid.get(key + Vector2i(dx, dz), []):
						if hit.x != r and (ribbons[hit.x] as Ribbon).path[hit.y].distance_to(e) < 1.0:
							var pair := Vector2i(mini(r, hit.x), maxi(r, hit.x))
							if not links.has(pair):
								links[pair] = []
							links[pair].append(Vector2(e.x, e.z))
	var seen := {}
	for key: Vector2i in grid:
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var other_key: Vector2i = key + Vector2i(dx, dz)
				if not grid.has(other_key):
					continue
				for a: Vector2i in grid[key]:
					for b: Vector2i in grid[other_key]:
						if a.x >= b.x:
							continue
						var ra: Ribbon = ribbons[a.x]
						var rbb: Ribbon = ribbons[b.x]
						if (ra.kind == "median" or rbb.kind == "median") and ra.chain == rbb.chain:
							continue
						var pa: Vector3 = ra.points[a.y]
						var pb: Vector3 = rbb.points[b.y]
						if absf(pa.y - pb.y) >= 5.0:
							continue
						var flat := Vector2(pa.x, pa.z).distance_to(Vector2(pb.x, pb.z))
						if flat >= (ra.width + rbb.width) * 0.5 - 0.6:
							continue
						var linked := false
						for l: Vector2 in links.get(Vector2i(a.x, b.x), []):
							if l.distance_to(Vector2(pa.x, pa.z)) < 70.0 and l.distance_to(Vector2(pb.x, pb.z)) < 70.0:
								linked = true
								break
						if linked:
							continue
						var cell := Vector2i(floori(pa.x / 20.0), floori(pa.z / 20.0))
						if not seen.has(cell):
							seen[cell] = true
							conflicts.append((pa + pb) * 0.5)


func _reach(reverse: bool) -> int:
	if g_nodes.is_empty():
		return 0
	var adj := {}
	for e in g_edges:
		var a: int = e["b"] if reverse else e["a"]
		var b: int = e["a"] if reverse else e["b"]
		if not adj.has(a):
			adj[a] = []
		adj[a].append(b)
		if not e["one_way"]:
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


func strongly_connected() -> bool:
	return _reach(false) == g_nodes.size() and _reach(true) == g_nodes.size()


# --- géométrie ----------------------------------------------------------------------------------------------------
static func right_of(dir: Vector2) -> Vector2:
	return Vector2(-dir.y, dir.x)


# Rotation dans le sens trigonométrique vu du dessus (nord en haut, est à droite ; z vers le sud).
static func rotate_ccw(v: Vector2, a: float) -> Vector2:
	return Vector2(v.x * cos(a) + v.y * sin(a), -v.x * sin(a) + v.y * cos(a))


static func _map_angle(v: Vector2) -> float:
	return fposmod(atan2(-v.y, v.x), TAU)


static func _from_map_angle(a: float) -> Vector2:
	return Vector2(cos(a), -sin(a))


static func tangent(pts: PackedVector2Array, i: int) -> Vector2:
	var a := pts[maxi(i - 1, 0)]
	var b := pts[mini(i + 1, pts.size() - 1)]
	return (b - a).normalized()


static func _ribbon_dir(rb: Ribbon, i: int) -> Vector2:
	var a: Vector3 = rb.points[maxi(i - 1, 0)]
	var b: Vector3 = rb.points[mini(i + 1, rb.points.size() - 1)]
	return Vector2(b.x - a.x, b.z - a.z).normalized()


static func nearest_index(pts: PackedVector2Array, p: Vector2) -> int:
	var best := 0
	var best_d := INF
	for i in pts.size():
		var d := pts[i].distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = i
	return best


static func index_at_distance(pts: PackedVector2Array, from_index: int, distance: float, step_sign: int) -> int:
	var s := 0.0
	var i := from_index
	while i + step_sign >= 0 and i + step_sign < pts.size() and s < distance:
		s += pts[i].distance_to(pts[i + step_sign])
		i += step_sign
	return i


static func polyline_length(pts: PackedVector2Array) -> float:
	var total := 0.0
	for k in pts.size() - 1:
		total += pts[k].distance_to(pts[k + 1])
	return total


static func polyline_intersections(pa: PackedVector2Array, pb: PackedVector2Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in pa.size() - 1:
		for j in pb.size() - 1:
			var hit: Variant = Geometry2D.segment_intersects_segment(pa[i], pa[i + 1], pb[j], pb[j + 1])
			if hit != null:
				out.append(hit)
	return out


func water_spans(pts: PackedVector2Array, margin: float) -> Array[Vector2i]:
	var spans: Array[Vector2i] = []
	var start := -1
	for i in pts.size():
		var wet := terrain.river_info(pts[i]).x < margin
		for lake: Dictionary in Spec.LAKES:
			var r: float = ((pts[i] - lake["center"]) / (lake["radii"] + Vector2.ONE * margin)).length()
			wet = wet or r < 1.0
		if wet and start < 0:
			start = i
		elif not wet and start >= 0:
			spans.append(Vector2i(start, i - 1))
			start = -1
	if start >= 0:
		spans.append(Vector2i(start, pts.size() - 1))
	return spans


# Profil en long : relief lissé, hauteurs imposées (fixed : indice -> h), contraintes min / max en plateau avec
# rampes à la pente limite, pente limitée partout.
static func solve_profile(natural: PackedFloat32Array, grade: float, window: float, fixed: Dictionary, constraints: Array) -> PackedFloat32Array:
	var n := natural.size()
	var p := moving_average(natural, maxi(1, int(window / STEP)))
	var g := grade * STEP
	var span := int(60.0 / g) + 1
	for iteration in 6:
		for idx in fixed:
			var h: float = fixed[idx]
			for i in range(maxi(0, int(idx) - span), mini(n, int(idx) + span + 1)):
				var d := absf(i - int(idx)) * g
				p[i] = clampf(p[i], h - d, h + d)
		for c: Dictionary in constraints:
			var i0: int = c["i0"]
			var i1: int = c["i1"]
			var h: float = c["h"]
			var is_min: bool = c["type"] == "min"
			for i in range(maxi(0, i0 - span), mini(n, i1 + span + 1)):
				var d := float(maxi(0, maxi(i0 - i, i - i1))) * g
				if is_min:
					p[i] = maxf(p[i], h - d)
				else:
					p[i] = minf(p[i], h + d)
		for i in range(1, n):
			p[i] = clampf(p[i], p[i - 1] - g, p[i - 1] + g)
		for i in range(n - 2, -1, -1):
			p[i] = clampf(p[i], p[i + 1] - g, p[i + 1] + g)
		for idx in fixed:
			p[int(idx)] = fixed[idx]
	return p


static func moving_average(values: PackedFloat32Array, half: int) -> PackedFloat32Array:
	var n := values.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var prefix := PackedFloat64Array()
	prefix.resize(n + 1)
	for i in n:
		prefix[i + 1] = prefix[i] + values[i]
	for i in n:
		var a := maxi(0, i - half)
		var b := mini(n - 1, i + half)
		out[i] = (prefix[b + 1] - prefix[a]) / float(b - a + 1)
	return out


# Catmull-Rom centripète passant par les points de contrôle, rééchantillonné à pas constant.
static func smooth(control: PackedVector2Array, step: float) -> PackedVector2Array:
	var dense := PackedVector2Array()
	var n := control.size()
	for k in n - 1:
		var p0 := control[k - 1] if k > 0 else control[0] * 2.0 - control[1]
		var p1 := control[k]
		var p2 := control[k + 1]
		var p3 := control[k + 2] if k + 2 < n else control[n - 1] * 2.0 - control[n - 2]
		var parts := maxi(2, ceili(p1.distance_to(p2)))
		for s in parts:
			dense.append(_centripetal(p0, p1, p2, p3, float(s) / parts))
	dense.append(control[n - 1])
	return resample(dense, step)


static func _centripetal(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t0 := 0.0
	var t1 := t0 + maxf(sqrt(p0.distance_to(p1)), 0.01)
	var t2 := t1 + maxf(sqrt(p1.distance_to(p2)), 0.01)
	var t3 := t2 + maxf(sqrt(p2.distance_to(p3)), 0.01)
	var tt := lerpf(t1, t2, t)
	var a1 := p0 * (t1 - tt) / (t1 - t0) + p1 * (tt - t0) / (t1 - t0)
	var a2 := p1 * (t2 - tt) / (t2 - t1) + p2 * (tt - t1) / (t2 - t1)
	var a3 := p2 * (t3 - tt) / (t3 - t2) + p3 * (tt - t2) / (t3 - t2)
	var b1 := a1 * (t2 - tt) / (t2 - t0) + a2 * (tt - t0) / (t2 - t0)
	var b2 := a2 * (t3 - tt) / (t3 - t1) + a3 * (tt - t1) / (t3 - t1)
	return b1 * (t2 - tt) / (t2 - t1) + b2 * (tt - t1) / (t2 - t1)


static func bezier(control: Array, parts: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var p0: Vector2 = control[0]
	var p1: Vector2 = control[1]
	var p2: Vector2 = control[2]
	var p3: Vector2 = control[3]
	for s in parts + 1:
		var t := float(s) / parts
		var u := 1.0 - t
		out.append(p0 * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + p3 * t * t * t)
	return out


static func resample(dense: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array([dense[0]])
	var carry := 0.0
	for k in dense.size() - 1:
		var a := dense[k]
		var b := dense[k + 1]
		var seg := a.distance_to(b)
		var pos := step - carry
		while pos <= seg:
			out.append(a.lerp(b, pos / seg))
			pos += step
		carry = seg - (pos - step)
	if out[out.size() - 1].distance_to(dense[dense.size() - 1]) > step * 0.25:
		out.append(dense[dense.size() - 1])
	else:
		out[out.size() - 1] = dense[dense.size() - 1]
	return out
