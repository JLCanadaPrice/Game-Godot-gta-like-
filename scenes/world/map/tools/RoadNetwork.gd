extends RefCounted

# Réseau routier de la carte 3D calculé depuis MapSpec (étape 2a : autoroutes et voies express ; étape 2b : artères,
# dessertes, chemins, losanges, carrefours, rond-point, raccords au centre-ville).
#  - axes : tronçons d'un même axe enchaînés puis lissés (Catmull-Rom centripète), échantillonnés tous les 4 m ;
#  - profils en long : relief naturel lissé (sans la remontée des bords de carte), pente limitée, tablier au-dessus de
#    l'eau ; niveau des axes aux échangeurs (tranchée / viaduc), aux losanges et aux passages de la voie ferrée choisi
#    par recherche locale : d'abord aucune pente dépassée ni contrainte violée, ensuite le moins de terrassement ;
#  - autoroutes : deux chaussées de 2 voies séparées par un terre-plein ;
#  - échangeurs en anneau à trois niveaux : un axe en tranchée, l'anneau au niveau du sol, l'autre axe sur viaduc ;
#    bretelles qui longent leur chaussée puis s'évasent vers l'anneau ; un axe qui s'arrête à l'échangeur se raccorde
#    directement à l'anneau ; jonction continue là où deux axes se prolongent ;
#  - sorties de carte en tranchée puis en tunnel, demi-tour caché au fond ;
#  - artères : chaînes de tronçons à travers les losanges, profil qui suit le relief (pente limitée, ponts sur l'eau,
#    niveau fixé aux passages sous / sur les autoroutes), coupées en rubans à double sens entre stations : raccord à
#    la grille (bord de la tuile en X), carrefour (plateau), carrefour d'extrémité de losange, cul-de-sac, rond-point,
#    sortie de carte ; trottoirs des artères urbaines ; bretelles de losange en S entre chaussée et carrefour ;
#  - graphe de circulation : arêtes avec voies et sens unique, anneaux gérés comme le rond-point existant, noeuds sans
#    feu (autoroutes, carrefours non éclairés), feux aux carrefours éclairés et aux extrémités de losange, bretelles
#    d'insertion qui cèdent le passage, raccords sur plateau (connectors) sans géométrie propre.
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
const TAPER := 70.0                 # m de biseau au bout d'une bretelle accolée à sa chaussée (étape 6)
const LEVEL_WITH_CARRIAGEWAY := 26.0  # m de bretelle accolée à niveau de sa chaussée (le trajet franchit le joint vers 23 m)
const GRADE := {"highway": 0.045, "ramp": 0.08}
const GRADE_LIMIT := {"carriageway": 0.052, "median": 0.052, "ramp": 0.092, "ring": 0.01, "arterial": 0.082, "sidewalk": 0.082, "rail": 0.034}
const SMOOTH := {"highway": 220.0, "ramp": 12.0}
const AXIS_PRIORITY := ["an", "vxo", "as", "vxe"]
const WIDTHS := {"carriageway": CW_WIDTH, "median": MEDIAN_WIDTH, "ramp": RAMP_WIDTH, "ring": RING_WIDTH, "arterial": 9.0, "sidewalk": 3.0, "rail": 5.0}
# voie ferrée (étape 4b) : plateforme ballastée à voie unique, sans circulation
const RAIL_GAUGE := 1.435
const RAIL_GRADE := 0.03
const RAIL_SMOOTH := 160.0
const RAIL_WATER_DECK := Spec.WATER_LEVEL + 4.5
const RAIL_LEVEL_CROSSING := 2.5    # écart max entre la chaussée et le relief pour un passage à niveau
# artères : largeur de chaussée, style d'atlas (RoadTexturesBake), trottoirs
const ROAD_STYLES := {
	"urban": {"width": 10.5, "sidewalk": true},
	"arterial": {"width": 9.0, "sidewalk": false},
	"access": {"width": 6.5, "sidewalk": false},
	"dirt": {"width": 5.0, "sidewalk": false},
}
const SIDEWALK_WIDTH := 3.0
const SIDEWALK_RISE := 0.15
const ARTERIAL_GRADE := 0.07
const ARTERIAL_WATER_DECK := Spec.WATER_LEVEL + 3.5   # ponts d'artères plus bas que ceux des autoroutes
const ARTERIAL_SMOOTH := 60.0
const GRID_TRIM := 7.0              # demi-chaussée des avenues du pourtour du centre-ville (DowntownSpec, 4 voies)
const GRID_FLAT := 2                 # échantillons à plat (ROAD_TOP) depuis un raccord du centre-ville (8 m)
const GRID_RAMP := 0.01              # pente maximale ensuite, jusqu'à la hauteur naturelle de l'artère (pas de marche)
const PAD_MARGIN := 3.0
const TERMINAL_OFFSET := 48.0       # distance entre l'axe de l'autoroute et le carrefour d'extrémité d'un losange
const DIAMOND_BEND := 110.0         # courbe en S d'une bretelle de losange, avant le carrefour d'extrémité
const MINI_RING := {"ring": 30.0, "pad": 42.0, "island": 24.0, "angle": 0.436332, "width": 8.0}   # angle 25°
# rues locales (étape 4) : impasses perpendiculaires aux artères dans les quartiers, bordées de maisons
const DEVELOPED_ZONES := ["suburb", "residential", "mixed", "industrial"]
const LOCAL_SPACING := 110.0        # le long de la rue source, entre deux rues d'un même côté
const LOCAL_LENGTHS := [320.0, 280.0, 240.0, 200.0, 170.0, 140.0, 110.0, 90.0]
const BRANCH_LENGTHS := [160.0, 130.0, 100.0, 80.0]
const BRANCH_START_MARGIN := 60.0   # embranchement : pas trop près de l'artère...
const BRANCH_END_MARGIN := 45.0     # ... ni du plateau du cul-de-sac
const LOCAL_CLEAR := 32.0           # couloir libre de part et d'autre de la rue (maisons et jardins)
const LOCAL_END_MARGIN := 70.0      # pas de rue trop près des bouts d'un ruban d'artère (carrefours)
const LOCAL_END_FLAT := 14.0        # m de rue à plat avant le plateau du cul-de-sac
const LOCAL_TURN_RADIUS := 3.8      # boucle de demi-tour du graphe sur le plateau (rayon ~8 m)


class Ribbon:
	var id := ""
	var kind := ""                          # carriageway, median, ramp, ring, arterial, sidewalk, rail
	var style := ""                         # colonne d'atlas des artères : urban, arterial, access, dirt
	var width := 0.0
	var chain := ""                         # chaîne d'origine (autoroute ou artère)
	var chain_start := 0                    # indice de chaîne de l'échantillon 0 et pas (+1 / -1) : tunnels
	var chain_step := 1
	var mesh := true                        # faux : trajet seul (anneau de rond-point dessiné par son plateau)
	var points := PackedVector3Array()      # axe géométrique (x, surface de chaussée, z)
	var path := PackedVector3Array()        # trajet de circulation (même nombre d'échantillons, y = surface - ROAD_TOP)
	var one_way := true
	var lanes := PackedFloat32Array()
	var graph := true
	var closed := false
	var taper := 0.0                        # m de biseau d'insertion / de sortie au bout accolé à la chaussée
	var taper_at_end := false               # le biseau est au dernier échantillon plutôt qu'au premier
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
var arterial_chains: Array[Dictionary] = []
var stations := {}                          # id -> {"id", "kind", "pos": Vector3, "node", "lit", "ends": [{"left", "right", "dir"}]}
var pads: Array[Dictionary] = []            # plateaux : {"id", "kind", "center": Vector3, "rim": PackedVector3Array, "island": float}
var connectors: Array[Dictionary] = []      # trajets sur plateau : {"points": PackedVector3Array, "one_way", "lanes"}
var local_streets: Array[Dictionary] = []   # {"id", "zone", "ribbon": Ribbon, "side": Vector2 (vers le fond de la rue)}
var rail_line := PackedVector2Array()       # axe de la voie ferrée dans la zone explorable (pas de 4 m)
var rail_heights := PackedFloat32Array()    # dessus de plateforme
var level_crossings: Array[Dictionary] = [] # {"pos": Vector3, "index", "road": Ribbon, "rail_dir": Vector2, "road_dir": Vector2, "half_gap": m le long de la voie}
var rail_ends: Array[Dictionary] = []       # {"pos": Vector3, "dir": Vector2 vers l'extérieur, "rise": relief au-delà (m)}
var g_lit: Array[int] = []                  # noeuds du graphe à feux (carrefours éclairés, extrémités de losange)
var g_grid: Array[int] = []                 # noeuds du graphe confondus avec la grille du centre-ville
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
	_build_arterials()
	_build_rail()
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
		var h := terrain.height_at(q)
		if is_water(q):
			h = maxf(h, TerrainModel.RIVER_BANK_TOP)   # le lit ne tire pas le profil vers le fond
		out.append(h + 0.3)
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
	d.chain_start = first
	m.chain_start = first
	r.chain_start = last
	r.chain_step = -1
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
	var q := Vector2(ring_point.x, ring_point.z)
	var radial := (q - center).normalized()
	var ring_dir := rotate_ccw(radial, PI * 0.5) * (1.0 if inbound else -1.0)
	var end_dir := (ring_dir * 0.8 - radial * 0.6).normalized()
	return _branch_ramp(id, chain, s, j_a, j_f, t_a, Vector3(q.x, h_ring, q.y), end_dir, 0.35, 18.0, inbound)


# Bretelle générique : partie qui longe l'axe (voir _ring_ramp) puis Bézier jusqu'à `end_point`, abordé dans la
# direction `end_dir` (sens de construction, de la chaussée vers le bout) ; portée d'arrivée end_ratio x écart,
# plafonnée à end_cap m.
func _branch_ramp(id: String, chain: Dictionary, s: int, j_a: int, j_f: int, t_a: float, end_point: Vector3,
		end_dir: Vector2, end_ratio: float, end_cap: float, inbound: bool) -> Ribbon:
	var pts: PackedVector2Array = chain["points"]
	var heights: PackedFloat32Array = chain["heights"]
	var h_ring := end_point.y
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
	var q := Vector2(end_point.x, end_point.z)
	var p0 := line[count]
	var start_dir := -tangent(pts, j_f) * float(s)
	var gap := p0.distance_to(q)
	var bend := resample(bezier([p0, p0 + start_dir * gap * 0.4, q - end_dir * minf(end_cap, gap * end_ratio), q], 96), STEP)
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
	# bretelle accolée à une chaussée : son bout côté chaussée s'ouvre en biseau (voie d'accélération ou de
	# décélération) au lieu d'apparaître d'un coup sur toute sa largeur (chantier des routes, étape 6)
	if t_a > CW_OFFSET:
		rb.taper = TAPER
		rb.taper_at_end = not inbound
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


# --- artères, dessertes et chemins ------------------------------------------------------------------------------
func _build_arterials() -> void:
	for chain in _arterial_chain_specs():
		_profile_arterial(chain)
		arterial_chains.append(chain)
	for chain in arterial_chains:
		_arterial_stations(chain)
	for chain in arterial_chains:
		_arterial_ribbons(chain)
	for node_id: String in Spec.NODES:
		match String(Spec.NODES[node_id]["kind"]):
			"diamond":
				_diamond_ramps(node_id)
			"roundabout":
				_mini_roundabout(node_id)
	_build_local_streets()
	_station_pads()


# Chaînes d'artères : tronçons consécutifs à travers les losanges où deux artères se prolongent.
func _arterial_chain_specs() -> Array[Dictionary]:
	var roads: Array = Spec.ROADS.filter(func(r: Dictionary) -> bool: return r["class"] != "highway")
	var at_diamond := {}
	for r: Dictionary in roads:
		for end in ["from", "to"]:
			var node_id: String = r[end]
			if Spec.NODES[node_id]["kind"] == "diamond":
				if not at_diamond.has(node_id):
					at_diamond[node_id] = []
				at_diamond[node_id].append(r)
	var used := {}
	var out: Array[Dictionary] = []
	for r: Dictionary in roads:
		if used.has(r["id"]):
			continue
		var head: Dictionary = r
		for guard in 20:
			var from_id: String = head["from"]
			var prev := _other_road(at_diamond, from_id, head)
			if prev.is_empty() or prev["to"] != from_id or used.has(prev["id"]):
				break
			head = prev
		var seq: Array[Dictionary] = [head]
		used[head["id"]] = true
		for guard in 20:
			var to_id: String = seq[-1]["to"]
			var next := _other_road(at_diamond, to_id, seq[-1])
			if next.is_empty() or next["from"] != to_id or used.has(next["id"]):
				break
			seq.append(next)
			used[next["id"]] = true
		out.append(_make_arterial_chain(seq))
	return out


static func _other_road(at_diamond: Dictionary, node_id: String, road: Dictionary) -> Dictionary:
	if Spec.NODES[node_id]["kind"] != "diamond" or (at_diamond[node_id] as Array).size() != 2:
		return {}
	var pair: Array = at_diamond[node_id]
	return pair[1] if pair[0]["id"] == road["id"] else pair[0]


func _make_arterial_chain(seq: Array[Dictionary]) -> Dictionary:
	var control := PackedVector2Array()
	var nodes: Array[String] = []
	var road_ids: Array[String] = []
	for road in seq:
		if control.is_empty():
			control.append(Spec.node_pos(road["from"]))
			nodes.append(road["from"])
		for v: Vector2 in road["via"]:
			control.append(v)
		control.append(Spec.node_pos(road["to"]))
		nodes.append(road["to"])
		road_ids.append(road["id"])
	# losange en bout de chaîne : l'artère franchit l'autoroute jusqu'au carrefour d'extrémité de l'autre côté
	var stub_head: bool = Spec.NODES[nodes[0]]["kind"] == "diamond"
	var stub_tail: bool = Spec.NODES[nodes[-1]]["kind"] == "diamond"
	if stub_head:
		control.insert(0, control[0] + (control[0] - control[1]).normalized() * TERMINAL_OFFSET)
	if stub_tail:
		control.append(control[control.size() - 1] + (control[control.size() - 1] - control[control.size() - 2]).normalized() * TERMINAL_OFFSET)
	var points := smooth(control, STEP)
	var node_index := {}
	for node_id in nodes:
		node_index[node_id] = nearest_index(points, Spec.node_pos(node_id))
	var styles := PackedStringArray()
	styles.resize(points.size())
	for road in seq:
		var style := _road_style(road)
		var i0: int = node_index[road["from"]]
		var i1: int = node_index[road["to"]]
		for i in range(mini(i0, i1), maxi(i0, i1) + 1):
			styles[i] = style
	for i in points.size():
		if styles[i] == "":
			styles[i] = _road_style(seq[0]) if i < points.size() / 2 else _road_style(seq[-1])
	return {"id": "art_" + String(seq[0]["id"]), "roads": road_ids, "nodes": nodes, "points": points, "node_index": node_index,
			"styles": styles, "stub_head": stub_head, "stub_tail": stub_tail, "heights": PackedFloat32Array(), "first": 0, "last": points.size() - 1}


static func _road_style(road: Dictionary) -> String:
	match String(road["class"]):
		"arterial":
			return "urban" if road.get("urban", false) else "arterial"
		"access":
			return "access"
		_:
			return "dirt"


func _profile_arterial(chain: Dictionary) -> void:
	var pts: PackedVector2Array = chain["points"]
	var natural := _natural_profile(pts)
	var fixed := {}
	var constraints: Array = []
	for node_id: String in chain["nodes"]:
		var idx: int = chain["node_index"][node_id]
		match String(Spec.NODES[node_id]["kind"]):
			"grid":
				# raccord au centre-ville : à plat au niveau de ses rues jusqu'au-delà de son trottoir, puis rampe douce
				for j in range(maxi(idx - GRID_FLAT - 10, 0), mini(idx + GRID_FLAT + 10, pts.size() - 1) + 1):
					var steps := absi(j - idx)
					if steps <= GRID_FLAT:
						fixed[j] = ROAD_TOP
					else:
						constraints.append({"i0": j, "i1": j, "h": ROAD_TOP + GRID_RAMP * STEP * (steps - GRID_FLAT), "type": "max"})
			"edge":
				pass
			"roundabout":
				# plateau plat du rond-point : les bras arrivent à sa hauteur
				var reach := ceili((float(MINI_RING["pad"]) + STEP) / STEP)
				for j in range(maxi(idx - reach, 0), mini(idx + reach, pts.size() - 1) + 1):
					fixed[j] = node_base(node_id)
			_:
				fixed[idx] = node_base(node_id)
	for span in water_spans(pts, 10.0):
		constraints.append({"i0": span.x - 3, "i1": span.y + 3, "h": ARTERIAL_WATER_DECK, "type": "min"})
	# passages sous / sur une autoroute : l'artère reste à la hauteur prévue par le profil de l'autoroute
	for entry: Dictionary in road_crossings:
		if not (chain["roads"] as Array).has(entry["with"]):
			continue
		var i := nearest_index(pts, entry["pos"])
		var h: float = entry["rail_height"]
		constraints.append({"i0": i - 3, "i1": i + 3, "h": h + 0.2, "type": "max"})
		if entry["mode"] == "under":
			constraints.append({"i0": i - 3, "i1": i + 3, "h": h - 0.2, "type": "min"})
	chain["heights"] = solve_profile(natural, ARTERIAL_GRADE, ARTERIAL_SMOOTH, fixed, constraints)


func _chain_point(chain: Dictionary, i: int) -> Vector3:
	var pts: PackedVector2Array = chain["points"]
	return Vector3(pts[i].x, (chain["heights"] as PackedFloat32Array)[i], pts[i].y)


# Stations le long d'une chaîne : ses deux bouts et les carrefours d'extrémité des losanges traversés.
func _arterial_stations(chain: Dictionary) -> void:
	var pts: PackedVector2Array = chain["points"]
	var nodes: Array = chain["nodes"]
	var list: Array[Dictionary] = []
	for end_index in [0, pts.size() - 1]:
		var stub: bool = chain["stub_head"] if end_index == 0 else chain["stub_tail"]
		var node_id: String = nodes[0] if end_index == 0 else nodes[-1]
		if stub:
			list.append({"index": end_index, "station": _diamond_terminal(node_id, chain, end_index)})
		else:
			list.append({"index": end_index, "station": _station(node_id, String(Spec.NODES[node_id]["kind"]), _chain_point(chain, chain["node_index"][node_id]))})
	for node_id: String in nodes:
		if Spec.NODES[node_id]["kind"] != "diamond":
			continue
		var j0: int = chain["node_index"][node_id]
		var highway := _highway_chain_of(node_id)
		for dir: int in [-1, 1]:
			var j := j0
			var reached := false
			while j + dir > 0 and j + dir < pts.size() - 1:
				j += dir
				if _distance_to_chain(highway, pts[j]) >= TERMINAL_OFFSET:
					reached = true
					break
			if not reached:
				continue   # bout de chaîne (déjà station)
			var terminal := _diamond_terminal(node_id, chain, j)
			if not terminal.is_empty():
				list.append({"index": j, "station": terminal})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["index"] < b["index"])
	chain["stations"] = list


func _station(id: String, kind: String, pos: Vector3) -> Dictionary:
	if not stations.has(id):
		var lit: bool = kind == "terminal" or (Spec.NODES.has(id) and Spec.NODES[id].get("lit", false))
		stations[id] = {"id": id, "kind": kind, "pos": pos, "lit": lit, "ends": []}
	return stations[id]


# Carrefour d'extrémité d'un losange du côté de l'axe où se trouve l'échantillon j ; station vide si ce côté n'a pas
# de bretelle (l'artère passe simplement).
func _diamond_terminal(node_id: String, chain: Dictionary, j: int) -> Dictionary:
	var highway := _highway_chain_of(node_id)
	var hp: PackedVector2Array = highway["points"]
	var hj: int = highway["node_index"][node_id]
	var p := (chain["points"] as PackedVector2Array)[j]
	var side := "d" if right_of(tangent(hp, hj)).dot(p - hp[hj]) > 0.0 else "i"
	var wanted := false
	for code: String in Spec.NODES[node_id].get("ramps", []):
		wanted = wanted or code.begins_with(side)
	if not wanted:
		if j == 0 or j == (chain["points"] as PackedVector2Array).size() - 1:
			return _station("%s:%s" % [node_id, side], "end", _chain_point(chain, j))
		return {}
	return _station("%s:%s" % [node_id, side], "terminal", _chain_point(chain, j))


func _highway_chain_of(node_id: String) -> Dictionary:
	for chain in chains:
		if (chain["nodes"] as Array).has(node_id):
			return chain
	return {}


static func _distance_to_chain(chain: Dictionary, p: Vector2) -> float:
	var pts: PackedVector2Array = chain["points"]
	var i := nearest_index(pts, p)
	var best := INF
	for k in range(maxi(i - 1, 0), mini(i + 1, pts.size() - 2) + 1):
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[k], pts[k + 1])))
	return best


# Distance de coupe d'un ruban d'artère au bord d'une station.
func _station_trim(station: Dictionary, hw: float) -> float:
	match String(station["kind"]):
		"grid":
			return GRID_TRIM
		"edge":
			return 0.0
		"roundabout":
			return MINI_RING["pad"]
		"end":
			return hw + 2.0
		"terminal":
			return maxf(hw, RAMP_WIDTH * 0.5) + PAD_MARGIN + 6.0   # place pour une bretelle arrivée en biais
		_:
			return _junction_radius(station["id"])


# Rayon d'un carrefour : les chaussées qui y arrivent ne se recouvrent pas avant le plateau.
func _junction_radius(node_id: String) -> float:
	var dirs: Array[Vector2] = []
	var widest := 0.0
	for road: Dictionary in Spec.ROADS:
		if road["class"] == "highway" or (road["from"] != node_id and road["to"] != node_id):
			continue
		var line := Spec.road_polyline(road)
		var other := line[1] if road["from"] == node_id else line[line.size() - 2]
		dirs.append((other - Spec.node_pos(node_id)).normalized())
		widest = maxf(widest, float(ROAD_STYLES[_road_style(road)]["width"]) * 0.5)
	var min_angle := PI
	for a in dirs.size():
		for b in range(a + 1, dirs.size()):
			min_angle = minf(min_angle, absf(dirs[a].angle_to(dirs[b])))
	return clampf(widest / tan(maxf(min_angle, 0.35) * 0.5) + 2.0, widest + PAD_MARGIN, 30.0)


func _arterial_ribbons(chain: Dictionary) -> void:
	var pts: PackedVector2Array = chain["points"]
	var heights: PackedFloat32Array = chain["heights"]
	var styles: PackedStringArray = chain["styles"]
	var list: Array = chain["stations"]
	for k in list.size() - 1:
		var s1: Dictionary = list[k]["station"]
		var s2: Dictionary = list[k + 1]["station"]
		var i1: int = list[k]["index"]
		var i2: int = list[k + 1]["index"]
		var style := styles[(i1 + i2) / 2]
		var width: float = ROAD_STYLES[style]["width"]
		var hw := width * 0.5
		var start := _cut(chain, i1, _station_trim(s1, hw), 1)
		var stop := _cut(chain, i2, _station_trim(s2, hw), -1)
		var a: int = start["index"]
		var b: int = stop["index"]
		if b - a < 1:
			errors.append("artère %s : tronçon trop court entre %s et %s" % [chain["id"], s1["id"], s2["id"]])
			continue
		# bouts exacts à la distance de coupe (plateaux, tuile du centre-ville) puis échantillons de la chaîne entre eux
		var line: Array[Vector3] = [start["point"]]
		var dirs: Array[Vector2] = [start["dir"]]
		for i in range(a, b + 1):
			var p3 := Vector3(pts[i].x, heights[i], pts[i].y)
			if p3.distance_to(line[line.size() - 1]) > 1.0 and p3.distance_to(stop["point"]) > 1.0:
				line.append(p3)
				dirs.append(tangent(pts, i))
		line.append(stop["point"])
		dirs.append(stop["dir"])
		var rb := _new_ribbon("%s:%d" % [chain["id"], k], "arterial", chain["id"])
		rb.style = style
		rb.width = width
		rb.one_way = false
		rb.chain_start = a - 1
		for p3 in line:
			rb.points.append(p3)
		ribbons.append(rb)
		_register_end(s1, rb, 0)
		_register_end(s2, rb, rb.points.size() - 1)
		if ROAD_STYLES[style]["sidewalk"]:
			for side_sign: float in [-1.0, 1.0]:
				var walk := _new_ribbon("%s:trottoir%d" % [rb.id, int(side_sign)], "sidewalk", chain["id"])
				walk.graph = false
				walk.chain_start = a - 1
				for n in line.size():
					var side := right_of(dirs[n]) * side_sign * (hw + SIDEWALK_WIDTH * 0.5)
					walk.points.append(Vector3(line[n].x + side.x, line[n].y + SIDEWALK_RISE, line[n].z + side.y))
				ribbons.append(walk)
				attachments.append({"ribbon": walk, "from": 0, "to": walk.points.size() - 1, "side": -1 if side_sign > 0.0 else 1})


# Point de la chaîne à `distance` m (le long de l'axe) de l'indice `from_index`, dans le sens `step_sign` : position et
# hauteur interpolées, direction, premier indice d'échantillon au-delà.
func _cut(chain: Dictionary, from_index: int, distance: float, step_sign: int) -> Dictionary:
	var pts: PackedVector2Array = chain["points"]
	var heights: PackedFloat32Array = chain["heights"]
	var i := from_index
	var walked := 0.0
	while i + step_sign >= 0 and i + step_sign < pts.size():
		var seg := pts[i].distance_to(pts[i + step_sign])
		if walked + seg >= distance:
			var t := (distance - walked) / maxf(seg, 0.001)
			var q := pts[i].lerp(pts[i + step_sign], t)
			var h := lerpf(heights[i], heights[i + step_sign], t)
			return {"point": Vector3(q.x, h, q.y), "index": i + step_sign, "dir": tangent(pts, i)}
		walked += seg
		i += step_sign
	return {"point": Vector3(pts[i].x, heights[i], pts[i].y), "index": i, "dir": tangent(pts, i)}


# Bout de ruban posé sur une station : coins pour le plateau et raccord du trajet vers le centre de la station.
func _register_end(station: Dictionary, rb: Ribbon, k: int) -> void:
	var p: Vector3 = rb.points[k]
	var dir := _ribbon_dir(rb, k) * (-1.0 if k == 0 else 1.0)   # vers la station
	var side := right_of(dir) * rb.width * 0.5
	if station["kind"] == "end":
		var c0: Vector3 = station["pos"]
		station["pos"] = Vector3(c0.x, p.y, c0.z)   # cul-de-sac plat, à la hauteur du bout de chaussée
	# pente et trottoirs du bras : RoadBake s'en sert pour poser le marquage sur la chaussée et arrondir les angles
	var neighbour: Vector3 = rb.points[mini(1, rb.points.size() - 1)] if k == 0 else rb.points[maxi(rb.points.size() - 2, 0)]
	var flat := Vector2(neighbour.x - p.x, neighbour.z - p.z).length()
	var has_walk: bool = rb.kind == "arterial" and ROAD_STYLES.has(rb.style) and bool(ROAD_STYLES[rb.style]["sidewalk"])
	(station["ends"] as Array).append({"left": Vector3(p.x - side.x, p.y, p.z - side.y), "right": Vector3(p.x + side.x, p.y, p.z + side.y),
			"tip": p, "dir": dir, "kind": rb.kind, "style": rb.style, "sidewalk": has_walk,
			"slope": (neighbour.y - p.y) / maxf(flat, 0.001)})
	var center: Vector3 = station["pos"]
	match String(station["kind"]):
		"edge", "roundabout":
			pass
		_:
			var a := Vector3(p.x, p.y - ROAD_TOP, p.z)
			var c := Vector3(center.x, center.y - ROAD_TOP, center.z)
			if a.distance_to(c) > 0.75:   # bout de cul-de-sac confondu avec la station : boucle de demi-tour (_build_graph)
				connectors.append({"points": PackedVector3Array([a, c]), "one_way": false, "lanes": PackedFloat32Array(), "station": station["id"]})


# Bretelles d'un losange : sortie et entrée par chaussée, en S entre la chaussée et le carrefour d'extrémité.
func _diamond_ramps(node_id: String) -> void:
	var chain := _highway_chain_of(node_id)
	if chain.is_empty():
		errors.append("losange %s : aucune autoroute" % node_id)
		return
	var pts: PackedVector2Array = chain["points"]
	var ribs: Dictionary = _chain_ribbons[chain["id"]]
	var j_center: int = chain["node_index"][node_id]
	var axis_dir := tangent(pts, j_center)
	for code: String in Spec.NODES[node_id].get("ramps", []):
		var side := code.substr(0, 1)
		var off := code.ends_with("off")
		var terminal: Dictionary = stations.get("%s:%s" % [node_id, side], {})
		if terminal.is_empty():
			errors.append("losange %s : pas de carrefour d'extrémité côté %s" % [node_id, side])
			continue
		# branche : côté de l'axe où se trouve la bretelle (avant / après le croisement dans le sens de la chaussée)
		var s := -1 if (side == "d") == off else 1
		var carriageway: Ribbon = ribs[side]
		var j_a := clampi(j_center + s * roundi(_diamond_ramp_distance(chain, node_id, s) / STEP), int(chain["first"]) + 2, int(chain["last"]) - 2)
		var t_pos: Vector3 = terminal["pos"]
		var j_t := nearest_index(pts, Vector2(t_pos.x, t_pos.z))
		var j_f := j_t + s * roundi(DIAMOND_BEND / STEP)
		if (j_a - j_f) * s <= 2:
			errors.append("losange %s : bretelle %s trop courte" % [node_id, code])
			continue
		var art_hw := 5.25
		for end: Dictionary in terminal["ends"]:
			art_hw = maxf(art_hw, Vector3(end["left"]).distance_to(end["right"]) * 0.5)
		var end_dir := axis_dir * float(-s)
		var end_point := t_pos - Vector3(end_dir.x, 0.0, end_dir.y) * (art_hw + 1.5)
		var cw_index := _ribbon_index(chain, side == "d", j_a)
		carriageway.splits[cw_index] = true
		var rb := _branch_ramp("%s:%s" % [node_id, code], chain, s, j_a, j_f, RAMP_OFFSET, end_point, end_dir, 0.4, 60.0, off)
		var span := ceili((BLEND + 8.0) / STEP)
		if off:
			attachments.append({"ribbon": carriageway, "from": cw_index, "to": cw_index + span, "side": 1})
			attachments.append({"ribbon": rb, "from": 0, "to": span, "side": -1})
			attachments.append({"ribbon": rb, "from": rb.points.size() - 3, "to": rb.points.size() - 1, "side": 0})
			connectors.append({"points": PackedVector3Array([rb.path[rb.path.size() - 1], Vector3(t_pos.x, t_pos.y - ROAD_TOP, t_pos.z)]), "one_way": true, "lanes": PackedFloat32Array([0.0]), "station": terminal["id"]})
		else:
			attachments.append({"ribbon": carriageway, "from": cw_index - span, "to": cw_index, "side": 1})
			attachments.append({"ribbon": rb, "from": rb.points.size() - 1 - span, "to": rb.points.size() - 1, "side": -1})
			attachments.append({"ribbon": rb, "from": 0, "to": 2, "side": 0})
			connectors.append({"points": PackedVector3Array([Vector3(t_pos.x, t_pos.y - ROAD_TOP, t_pos.z), rb.path[0]]), "one_way": true, "lanes": PackedFloat32Array([0.0]), "station": terminal["id"]})
		var tip: Vector3 = rb.points[rb.points.size() - 1] if off else rb.points[0]
		var dir := end_dir
		var hw := RAMP_WIDTH * 0.5
		var lateral := right_of(end_dir) * hw
		(terminal["ends"] as Array).append({"left": tip - Vector3(lateral.x, 0.0, lateral.y), "right": tip + Vector3(lateral.x, 0.0, lateral.y),
				"tip": tip, "dir": dir, "kind": "ramp", "style": "", "sidewalk": false, "slope": 0.0})


# Rues locales : depuis les artères des quartiers (hors chemins), tous les LOCAL_SPACING m de chaque côté, une impasse
# perpendiculaire aussi longue que possible (LOCAL_LENGTHS) dont le couloir reste dans la zone, loin de l'eau et des
# autres routes, sur un relief modéré ; puis des embranchements plus courts (BRANCH_LENGTHS) sur les rues assez
# longues. Raccord : noeud coupé sur la rue source, trajet qui traverse le trottoir ; cul-de-sac au bout (plateau).
func _build_local_streets() -> void:
	var obstacles := {}
	for rb in ribbons:
		_index_obstacle(obstacles, rb)
	for p in smooth(PackedVector2Array(Spec.RAIL), STEP):   # voie ferrée construite ensuite
		var key := Vector2i(floori(p.x / 32.0), floori(p.y / 32.0))
		if not obstacles.has(key):
			obstacles[key] = []
		obstacles[key].append([p, WIDTHS["rail"] * 0.5 + 4.0, null])
	var sources: Array = ribbons.filter(func(r: Ribbon) -> bool: return r.kind == "arterial" and r.style != "dirt")
	for zone: Dictionary in Spec.ZONES:
		if not DEVELOPED_ZONES.has(zone["type"]):
			continue
		var poly := Spec.zone_polygon(zone)
		for rb: Ribbon in sources:
			_grow_streets(zone, poly, rb, LOCAL_LENGTHS, LOCAL_END_MARGIN, LOCAL_END_MARGIN, obstacles)
	var first_pass := local_streets.duplicate()
	for street: Dictionary in first_pass:
		var zone: Dictionary = {}
		for z: Dictionary in Spec.ZONES:
			if z["id"] == street["zone"]:
				zone = z
		_grow_streets(zone, Spec.zone_polygon(zone), street["ribbon"], BRANCH_LENGTHS, BRANCH_START_MARGIN, BRANCH_END_MARGIN, obstacles)


func _grow_streets(zone: Dictionary, poly: PackedVector2Array, rb: Ribbon, lengths: Array, start_margin: float, end_margin: float, obstacles: Dictionary) -> void:
	var pts: PackedVector3Array = rb.points
	var arc := PackedFloat32Array([0.0])
	for k in range(1, pts.size()):
		arc.append(arc[k - 1] + Vector2(pts[k].x - pts[k - 1].x, pts[k].z - pts[k - 1].z).length())
	var total: float = arc[arc.size() - 1]
	for side_sign: float in [-1.0, 1.0]:
		var last := -INF
		for k in pts.size():
			if arc[k] < start_margin or total - arc[k] < end_margin or arc[k] - last < LOCAL_SPACING:
				continue
			var p := Vector2(pts[k].x, pts[k].z)
			if not Geometry2D.is_point_in_polygon(p, poly):
				continue
			var normal := right_of(_ribbon_dir(rb, k)) * side_sign
			var start := p + normal * (rb.width * 0.5 + (SIDEWALK_WIDTH if rb.style == "urban" else 0.0))
			for length: float in lengths:
				if _street_fits(start, normal, length, poly, obstacles, rb):
					var street := _add_local_street(zone, rb, k, start, start + normal * length)
					_index_obstacle(obstacles, street)
					last = arc[k]
					break


func _index_obstacle(obstacles: Dictionary, rb: Ribbon) -> void:
	for p: Vector3 in rb.points:
		var key := Vector2i(floori(p.x / 32.0), floori(p.z / 32.0))
		if not obstacles.has(key):
			obstacles[key] = []
		obstacles[key].append([Vector2(p.x, p.z), rb.width * 0.5, rb])


func _street_fits(start: Vector2, normal: Vector2, length: float, poly: PackedVector2Array, obstacles: Dictionary, source: Ribbon) -> bool:
	var end := start + normal * length
	var steps := ceili(length / 8.0)
	var h0 := terrain.height_at(start)
	if absf(terrain.height_at(end) - h0) / length > 0.09:
		return false
	for s in steps + 1:
		var q := start.lerp(end, float(s) / steps)
		if not Geometry2D.is_point_in_polygon(q, poly) or not Spec.PLAYABLE.grow(-60.0).has_point(q):
			return false
		if terrain.river_info(q).x < 25.0 or is_water(q):
			return false
		for lake: Dictionary in Spec.LAKES:
			if ((q - lake["center"]) / (lake["radii"] + Vector2.ONE * 30.0)).length() < 1.0:
				return false
		if Spec.DOWNTOWN.grow(40.0).has_point(q):
			return false
		# couloir des maisons libre (sauf l'artère de départ près du raccord)
		var key := Vector2i(floori(q.x / 32.0), floori(q.y / 32.0))
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				for entry: Array in obstacles.get(key + Vector2i(dx, dz), []):
					# la rue source et ses trottoirs, que la rue traverse au raccord
					var own: bool = entry[2] == source or (entry[2] != null and entry[2].kind == "sidewalk" and entry[2].chain == source.chain)
					if own and q.distance_to(start) < 30.0:
						continue
					if q.distance_to(entry[0]) < LOCAL_CLEAR + float(entry[1]):
						return false
	for poi: Dictionary in Spec.POIS:
		var half: Vector2 = poi["size"] * 0.5 + Vector2.ONE * 30.0
		var c: Vector2 = poi["pos"]
		for s in steps + 1:
			var q := start.lerp(end, float(s) / steps)
			if absf(q.x - c.x) < half.x and absf(q.y - c.y) < half.y:
				return false
	return true


func _add_local_street(zone: Dictionary, source: Ribbon, k: int, start: Vector2, end: Vector2) -> Ribbon:
	var id := "rue_%s_%d" % [zone["id"], local_streets.size()]
	var line := resample(PackedVector2Array([start, end]), STEP)
	if line.size() > 2 and line[line.size() - 2].distance_to(end) < STEP * 0.6:
		line.remove_at(line.size() - 2)   # pas de dernier segment trop court (pente mesurée sur quelques centimètres)
	var natural := _natural_profile(line)
	var anchor: Vector3 = source.points[k]
	var h := solve_profile(natural, 0.07, 24.0, {0: anchor.y}, [])
	# cul-de-sac plat : les derniers LOCAL_END_FLAT m restent au niveau où ils commencent, sinon le disque du plateau
	# (plat, rayon ~8 m) déborde au-dessus de la rue en pente et forme une marche
	var last := line.size() - 1
	var flat_from := last
	while flat_from > 1 and line[flat_from - 1].distance_to(line[last]) <= LOCAL_END_FLAT:
		flat_from -= 1
	for i in range(flat_from + 1, line.size()):
		h[i] = h[flat_from]
	var street := _new_ribbon(id, "arterial", id)
	street.style = "access"
	street.width = ROAD_STYLES["access"]["width"]
	street.one_way = false
	for i in line.size():
		street.points.append(Vector3(line[i].x, h[i], line[i].y))
		street.path.append(Vector3(line[i].x, h[i] - ROAD_TOP, line[i].y))
	street.path[0] = Vector3(anchor.x, anchor.y - ROAD_TOP, anchor.z)   # le trajet part de l'axe de l'artère
	ribbons.append(street)
	source.splits[k] = true
	var station := _station(id + ":bout", "end", street.points[street.points.size() - 1])
	_register_end(station, street, street.points.size() - 1)
	local_streets.append({"id": id, "zone": zone["id"], "ribbon": street, "side": (end - start).normalized()})
	return street


# Longueur d'axe laissée aux bretelles d'un losange vers le noeud suivant : moitié de l'écart avec un autre losange,
# place des bretelles d'un anneau (qui s'arrêtent à DIAMOND_CLEAR), fin des chaussées avant une jonction, limite.
func _diamond_ramp_distance(chain: Dictionary, node_id: String, s: int) -> float:
	var nodes: Array = chain["nodes"]
	var k := nodes.find(node_id)
	var idx: int = chain["node_index"][node_id]
	if k + s < 0 or k + s >= nodes.size():
		return DIAMOND_CLEAR
	var next_id: String = nodes[k + s]
	var gap := absf(int(chain["node_index"][next_id]) - idx) * STEP
	match String(Spec.NODES[next_id]["kind"]):
		"diamond":
			return minf(DIAMOND_CLEAR, gap * 0.5 - 10.0)
		"edge":
			return minf(DIAMOND_CLEAR, _inside_length(chain, idx, s) - 30.0)
		_:
			return DIAMOND_CLEAR if shape(next_id) == "ring" else minf(DIAMOND_CLEAR, gap - JOIN_TRIM - 30.0)


# Petit rond-point : anneau à une voie (trajet seul, dessiné par le plateau et son îlot), entrées et sorties de chaque
# branche d'artère arrivée au bord du plateau.
func _mini_roundabout(node_id: String) -> void:
	var station: Dictionary = stations.get(node_id, {})
	if station.is_empty():
		return
	var center: Vector3 = station["pos"]
	var c2 := Vector2(center.x, center.z)
	var ring := _new_ribbon("ring_" + node_id, "ring", "")
	ring.width = MINI_RING["width"]
	ring.closed = true
	ring.mesh = false
	ring.lanes = PackedFloat32Array([0.0])
	var angles: Array = []
	var legs: Array[Dictionary] = []
	for end: Dictionary in station["ends"]:
		var tip: Vector3 = end["tip"]
		var u := (Vector2(tip.x, tip.z) - c2).normalized()
		var leg := {"tip": tip, "entry": _map_angle(rotate_ccw(u, MINI_RING["angle"])), "exit": _map_angle(rotate_ccw(u, -MINI_RING["angle"]))}
		legs.append(leg)
		angles.append(leg["entry"])
		angles.append(leg["exit"])
	angles.sort()
	var angle_index := {}
	var radius: float = MINI_RING["ring"]
	for k in angles.size():
		var a0: float = angles[k]
		var a1: float = angles[(k + 1) % angles.size()]
		if a1 <= a0:
			a1 += TAU
		angle_index[snappedf(a0, 0.0001)] = ring.points.size()
		ring.splits[ring.points.size()] = true
		var steps := maxi(1, ceili((a1 - a0) * radius / STEP))
		for s in steps:
			var q := c2 + _from_map_angle(lerpf(a0, a1, float(s) / steps)) * radius
			ring.points.append(Vector3(q.x, center.y, q.y))
	ribbons.append(ring)
	for leg in legs:
		var tip: Vector3 = leg["tip"]
		var entry: Vector3 = ring.points[angle_index[snappedf(leg["entry"], 0.0001)]]
		var exit: Vector3 = ring.points[angle_index[snappedf(leg["exit"], 0.0001)]]
		var down := Vector3(0.0, -ROAD_TOP, 0.0)
		connectors.append({"points": _curve3(tip + down, entry + down, center + down), "one_way": true, "lanes": PackedFloat32Array([0.0]), "station": node_id})
		connectors.append({"points": _curve3(exit + down, tip + down, center + down), "one_way": true, "lanes": PackedFloat32Array([0.0]), "station": node_id})


# Raccord courbe de a à b qui s'écarte de `center` (quadratique, 6 points).
static func _curve3(a: Vector3, b: Vector3, center: Vector3) -> PackedVector3Array:
	var mid := (a + b) * 0.5
	var away := Vector3(mid.x - center.x, 0.0, mid.z - center.z).normalized() * a.distance_to(b) * 0.25
	var control := mid + away
	var out := PackedVector3Array()
	for s in 6:
		var t := s / 5.0
		out.append(a.lerp(control, t).lerp(control.lerp(b, t), t))
	return out


# Plateaux des stations : polygone des coins des rubans qui y arrivent (complété en arc), disque pour les culs-de-sac
# et les ronds-points (avec îlot).
func _station_pads() -> void:
	for id: String in stations:
		var station: Dictionary = stations[id]
		var center: Vector3 = station["pos"]
		var kind: String = station["kind"]
		if kind == "grid" or kind == "edge":
			continue
		var rim := PackedVector3Array()
		var island := 0.0
		var gaps: Array[Dictionary] = []   # portions de pourtour entre deux bras (angles de trottoir, étape 2)
		if kind == "roundabout":
			# disque un peu plus large et 1 cm plus bas : recouvre le bout plat des bras sans jour ni scintillement
			rim = _disc(center - Vector3(0, 0.01, 0), float(MINI_RING["pad"]) + 1.2, 48)
			island = MINI_RING["island"]
		elif kind == "end":
			var radius := 8.0
			for end: Dictionary in station["ends"]:
				radius = maxf(radius, Vector3(end["left"]).distance_to(end["right"]) * 0.5 + 5.0)
			rim = _disc(center, radius, 20)
		else:
			var corners: Array[Vector3] = []
			var arms: Array[int] = []
			for end: Dictionary in station["ends"]:
				corners.append(end["left"])
				corners.append(end["right"])
				arms.append_array([arms.size() / 2, arms.size() / 2])
			# arcs entre deux bras éloignés (jamais entre les deux coins d'un même bras) : le plateau reste arrondi.
			# Le rayon de l'arc suit les deux coins qu'il relie (et sa hauteur aussi) : le plateau ne déborde plus de
			# l'enveloppe des chaussées et se raccorde sans marche (chantier des routes, étape 2).
			var angles: Array[float] = []
			for c in corners:
				angles.append(fposmod(atan2(c.z - center.z, c.x - center.x), TAU))
			var order := range(corners.size())
			order.sort_custom(func(a: int, b: int) -> bool: return angles[a] < angles[b])
			for n in order.size():
				var a: int = order[n]
				var b: int = order[(n + 1) % order.size()]
				var start := rim.size()
				rim.append(corners[a])
				var gap := fposmod(angles[b] - angles[a], TAU)
				if arms[a] != arms[b] and gap > 0.6:
					var ra := Vector2(corners[a].x - center.x, corners[a].z - center.z).length()
					var rb := Vector2(corners[b].x - center.x, corners[b].z - center.z).length()
					var fill := int(gap / 0.35)
					for f in range(1, fill):
						var t := float(f) / fill
						var ang := angles[a] + gap * t
						var rad := lerpf(ra, rb, t)
						rim.append(Vector3(center.x + cos(ang) * rad, lerpf(corners[a].y, corners[b].y, t), center.z + sin(ang) * rad))
				if arms[a] != arms[b]:
					gaps.append({"from": start, "count": rim.size() - start, "arm_a": arms[a], "arm_b": arms[b]})
		pads.append({"id": id, "kind": kind, "center": center, "rim": rim, "island": island, "gaps": gaps})


static func _disc(center: Vector3, radius: float, segments: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for k in segments:
		var a := TAU * k / segments
		out.append(Vector3(center.x + cos(a) * radius, center.y, center.z + sin(a) * radius))
	return out


# --- voie ferrée (étape 4b) -------------------------------------------------------------------------------------
# Tracé de MapSpec.RAIL lissé, limité à la zone explorable. Profil : relief lissé à pente limitée, au niveau des
# artères franchies (passages à niveau), au-dessus des chaussées plus basses avec le gabarit d'un pont (autoroutes en
# tranchée, bretelles), au-dessus de l'eau. Plateforme en rubans "rail" coupés à la traversée des chaussées et de
# leurs trottoirs ; bouts à la limite de la carte (relief au-delà mesuré pour un portail).
func _build_rail() -> void:
	var full := smooth(PackedVector2Array(Spec.RAIL), STEP)
	var inner := Spec.PLAYABLE.grow(-2.0)
	var first := 0
	while first < full.size() - 1 and not inner.has_point(full[first]):
		first += 1
	var last := full.size() - 1
	while last > first and not inner.has_point(full[last]):
		last -= 1
	rail_line = full.slice(first, last + 1)
	var line := rail_line
	var n := line.size()
	var natural := _natural_profile(line)
	var fixed := {}
	var constraints: Array = []
	var found: Array[Dictionary] = []
	for rb: Ribbon in ribbons:
		if not rb.mesh or rb.kind == "sidewalk":
			continue
		var pts := PackedVector2Array()
		for p: Vector3 in rb.points:
			pts.append(Vector2(p.x, p.z))
		if rb.closed:
			pts.append(pts[0])
		for hit in polyline_intersections(line, pts):
			var i := nearest_index(line, hit)
			var road_y := _height_on(rb, hit)
			if rb.kind == "arterial" and absf(road_y - natural[i]) <= RAIL_LEVEL_CROSSING:
				fixed[i] = road_y
				found.append({"index": i, "road": rb, "pos": Vector3(hit.x, road_y, hit.y)})
			elif road_y < natural[i]:
				constraints.append({"i0": i - 4, "i1": i + 4, "h": road_y + LOW_CLEARANCE + RAIL_DECK, "type": "min"})
			else:
				errors.append("voie ferrée sous %s en (%.0f, %.0f) : passage non prévu" % [rb.id, hit.x, hit.y])
	for span: Vector2i in water_spans(line, 10.0):
		constraints.append({"i0": span.x - 3, "i1": span.y + 3, "h": RAIL_WATER_DECK, "type": "min"})
	rail_heights = solve_profile(natural, RAIL_GRADE, RAIL_SMOOTH, fixed, constraints)
	for c: Dictionary in constraints:
		for i in range(maxi(0, int(c["i0"])), mini(n, int(c["i1"]) + 1)):
			if rail_heights[i] < float(c["h"]) - 0.05:
				errors.append("voie ferrée : plateforme à %.2f m sous le minimum %.2f m en (%.0f, %.0f)" % [rail_heights[i], c["h"], line[i].x, line[i].y])
				break
	var arc := PackedFloat32Array([0.0])
	for i in range(1, n):
		arc.append(arc[i - 1] + line[i].distance_to(line[i - 1]))
	# passages à niveau : la plateforme s'arrête au bord extérieur des trottoirs, quel que soit l'angle
	var gaps: Array[Vector2] = []
	for f: Dictionary in found:
		var road: Ribbon = f["road"]
		var hit := Vector2((f["pos"] as Vector3).x, (f["pos"] as Vector3).z)
		var road_pts := PackedVector2Array()
		for p: Vector3 in road.points:
			road_pts.append(Vector2(p.x, p.z))
		var rail_dir := tangent(line, int(f["index"]))
		var road_dir := tangent(road_pts, nearest_index(road_pts, hit))
		var sin_a := maxf(absf(rail_dir.cross(road_dir)), 0.25)
		var cos_a := absf(rail_dir.dot(road_dir))
		var band := road.width * 0.5 + (SIDEWALK_WIDTH if road.style == "urban" else 0.0) + 0.3
		var half_gap := band / sin_a + WIDTHS["rail"] * 0.5 * cos_a / sin_a
		var s := _arc_at(line, arc, hit)
		gaps.append(Vector2(s - half_gap, s + half_gap))
		level_crossings.append({"pos": f["pos"], "index": f["index"], "road": road, "rail_dir": rail_dir, "road_dir": road_dir, "half_gap": half_gap, "s": s})
	gaps.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var total := arc[n - 1]
	var pieces: Array[Vector2] = []
	var cursor := 0.0
	for g: Vector2 in gaps:
		if g.x > cursor + STEP:
			pieces.append(Vector2(cursor, g.x))
		cursor = maxf(cursor, g.y)
	if total > cursor + STEP:
		pieces.append(Vector2(cursor, total))
	for piece: Vector2 in pieces:
		var rb := _new_ribbon("rail_%d" % ribbons.size(), "rail", "rail")
		rb.style = "rail"
		rb.graph = false
		rb.one_way = false
		rb.points.append(_rail_point(arc, piece.x))
		for i in n:
			if arc[i] > piece.x + STEP * 0.4 and arc[i] < piece.y - STEP * 0.4:
				rb.points.append(Vector3(line[i].x, rail_heights[i], line[i].y))
		rb.points.append(_rail_point(arc, piece.y))
		ribbons.append(rb)
	# bouts de ligne à la limite : relief au-delà (portail s'il remonte)
	for end: int in [0, n - 1]:
		var dir := (line[0] - line[1]).normalized() if end == 0 else (line[n - 1] - line[n - 2]).normalized()
		var top := -INF
		for d: float in [10.0, 20.0, 30.0]:
			top = maxf(top, terrain.height_at(line[end] + dir * d))
		rail_ends.append({"pos": Vector3(line[end].x, rail_heights[end], line[end].y), "dir": dir, "rise": top - rail_heights[end]})
	for pad: Dictionary in pads:
		var c: Vector3 = pad["center"]
		var radius := 0.0
		for p: Vector3 in pad["rim"]:
			radius = maxf(radius, Vector2(p.x - c.x, p.z - c.z).length())
		var q := Vector2(c.x, c.z)
		if q.distance_to(line[nearest_index(line, q)]) < radius + WIDTHS["rail"] * 0.5 + 1.0:
			errors.append("plateau %s sur la voie ferrée" % pad["id"])
	var lo := INF
	var hi := -INF
	for h in rail_heights:
		lo = minf(lo, h)
		hi = maxf(hi, h)
	var rises: PackedStringArray = []
	for e: Dictionary in rail_ends:
		rises.append("%.0f m" % e["rise"])
	report.append("voie ferrée : %.0f m, %d passages à niveau, %d tronçons de plateforme, hauteur %.1f à %.1f m, relief au-delà des bouts %s"
			% [total, level_crossings.size(), pieces.size(), lo, hi, ", ".join(rises)])


func _rail_point(arc: PackedFloat32Array, s: float) -> Vector3:
	var n := rail_line.size()
	for k in n - 1:
		if arc[k + 1] >= s:
			var t := clampf((s - arc[k]) / maxf(arc[k + 1] - arc[k], 0.001), 0.0, 1.0)
			var p := rail_line[k].lerp(rail_line[k + 1], t)
			return Vector3(p.x, lerpf(rail_heights[k], rail_heights[k + 1], t), p.y)
	return Vector3(rail_line[n - 1].x, rail_heights[n - 1], rail_line[n - 1].y)


static func _arc_at(line: PackedVector2Array, arc: PackedFloat32Array, p: Vector2) -> float:
	var i := nearest_index(line, p)
	var best := arc[i]
	var best_d := line[i].distance_to(p)
	for k: int in [i - 1, i]:
		if k < 0 or k + 1 >= line.size():
			continue
		var q := Geometry2D.get_closest_point_to_segment(p, line[k], line[k + 1])
		if q.distance_to(p) < best_d:
			best_d = q.distance_to(p)
			best = arc[k] + line[k].distance_to(q)
	return best


# Hauteur de l'axe d'un ruban au point de son tracé le plus proche de p.
static func _height_on(rb: Ribbon, p: Vector2) -> float:
	var pts: PackedVector3Array = rb.points
	var best := INF
	var y := pts[0].y
	for k in pts.size() - 1:
		var a := Vector2(pts[k].x, pts[k].z)
		var b := Vector2(pts[k + 1].x, pts[k + 1].z)
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		if q.distance_squared_to(p) < best:
			best = q.distance_squared_to(p)
			y = lerpf(pts[k].y, pts[k + 1].y, a.distance_to(q) / maxf(a.distance_to(b), 0.001))
	return y


func _at_level_crossing(ra: Ribbon, rbb: Ribbon, p: Vector3) -> bool:
	var other: Ribbon = rbb if ra.kind == "rail" else ra
	for lc: Dictionary in level_crossings:
		var road: Ribbon = lc["road"]
		var c: Vector3 = lc["pos"]
		if (other == road or (other.kind == "sidewalk" and other.chain == road.chain)) and Vector2(p.x, p.z).distance_to(Vector2(c.x, c.z)) < float(lc["half_gap"]) + 20.0:
			return true
	return false


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
					"width": CW_OFFSET * 2.0 + CW_WIDTH + 4.0, "road_half": CW_OFFSET + CW_WIDTH * 0.5,
					"arrive": arriving.points[arriving.points.size() - 1], "leave": leaving.points[0]})
		for hit in _boundary_crossings(pts):
			boundary_gaps.append({"pos": hit, "width": (CW_OFFSET + CW_WIDTH * 0.5 + 1.1) * 2.0, "chain": chain["id"]})
	# artères : un seul ruban à double sens jusqu'au fond (cul-de-sac)
	for chain in arterial_chains:
		var pts: PackedVector2Array = chain["points"]
		var heights: PackedFloat32Array = chain["heights"]
		var nodes: Array = chain["nodes"]
		for end in ["head", "tail"]:
			var node_id: String = nodes[0] if end == "head" else nodes[-1]
			if Spec.NODES[node_id]["kind"] != "edge":
				continue
			var tip := pts.size() - 1 if end == "tail" else 0
			var inward := -1 if end == "tail" else 1
			var width: float = ROAD_STYLES[(chain["styles"] as PackedStringArray)[tip]]["width"]
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
			tunnels.append({"id": node_id, "chain": chain["id"], "tip_index": tip, "portal_index": portal, "boundary_index": boundary,
					"pos": Vector3(pts[tip].x, heights[tip], pts[tip].y), "dir": tangent(pts, tip) * float(-inward),
					"width": width + 4.0, "road_half": width * 0.5})
		for hit in _boundary_crossings(pts):
			boundary_gaps.append({"pos": hit, "width": width_of_chain_end(chain, hit) + 2.2, "chain": chain["id"]})


static func width_of_chain_end(chain: Dictionary, p: Vector2) -> float:
	var styles: PackedStringArray = chain["styles"]
	return ROAD_STYLES[styles[nearest_index(chain["points"], p)]]["width"]


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
		if not t.has("arrive"):
			continue   # artère à double sens : cul-de-sac au fond du tunnel
		var a: Vector3 = t["arrive"]
		var b: Vector3 = t["leave"]
		var dir: Vector2 = t["dir"]
		var mid := (Vector2(a.x, a.z) + Vector2(b.x, b.z)) * 0.5 + dir * TUNNEL_DEPTH
		var pts := PackedVector3Array([Vector3(a.x, a.y - ROAD_TOP, a.z), Vector3(mid.x, a.y - ROAD_TOP, mid.y), Vector3(b.x, b.y - ROAD_TOP, b.z)])
		var turn := Ribbon.new()
		turn.lanes = PackedFloat32Array([0.0])
		_add_edge(pts, turn)
	for c: Dictionary in connectors:
		var link := Ribbon.new()
		link.one_way = c["one_way"]
		link.lanes = c["lanes"]
		_add_edge((c["points"] as PackedVector3Array).duplicate(), link)
	# culs-de-sac (un seul bras arrivé sur la station) : boucle de demi-tour sur le plateau, cercle qui passe par le bout
	# du trajet, au lieu d'un demi-tour sur place où deux véhicules qui se suivent se chevauchent
	for sid: String in stations:
		var station: Dictionary = stations[sid]
		if station["kind"] != "end" or (station["ends"] as Array).size() != 1:
			continue
		var end: Dictionary = station["ends"][0]
		var tip_p: Vector3 = end["tip"]
		var tip := Vector3(tip_p.x, tip_p.y - ROAD_TOP, tip_p.z)
		var station_pos: Vector3 = station["pos"]
		if station_pos.distance_to(tip_p) > 0.75 or _find_graph_node(tip) < 0:
			continue
		var dir: Vector2 = end["dir"]
		var right := right_of(dir)
		var center := Vector2(tip.x, tip.z) + dir * LOCAL_TURN_RADIUS
		var loop_pts := PackedVector3Array([tip])
		for s in range(1, 16):
			var angle := TAU * s / 16.0   # vers la droite d'abord : le centre du plateau reste à gauche (circulation à droite)
			var q := center + (-dir * cos(angle) + right * sin(angle)) * LOCAL_TURN_RADIUS
			loop_pts.append(Vector3(q.x, tip.y, q.y))
		loop_pts.append(tip)
		var loop := Ribbon.new()
		loop.one_way = true
		loop.lanes = PackedFloat32Array([0.0])
		_add_edge(loop_pts, loop)
	# feux : carrefours éclairés et extrémités de losange ; noeuds de la grille laissés au centre-ville ; les autres sans feu
	var lit := {}
	var grid := {}
	for id: String in stations:
		var station: Dictionary = stations[id]
		var c: Vector3 = station["pos"]
		var node := _find_graph_node(Vector3(c.x, c.y - ROAD_TOP, c.z))
		if node < 0:
			continue
		if station["kind"] == "grid":
			grid[node] = true
		elif station["lit"]:
			lit[node] = true
	for i in g_nodes.size():
		if grid.has(i):
			g_grid.append(i)
		elif lit.has(i):
			g_lit.append(i)
		else:
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


func _find_graph_node(p: Vector3) -> int:
	var key := Vector3i(roundi(p.x), roundi(p.y), roundi(p.z))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for idx: int in _node_hash.get(key + Vector3i(dx, dy, dz), []):
					if g_nodes[idx].distance_to(p) < 0.75:
						return idx
	return -1


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
			var deck := WATER_DECK
			if rb.kind in ["arterial", "sidewalk"]:
				deck = ARTERIAL_WATER_DECK
			elif rb.kind == "rail":
				deck = RAIL_WATER_DECK
			if is_water(Vector2(b.x, b.z)) and b.y < deck - 0.35:
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
		var missing: PackedStringArray = []
		for reverse in [false, true]:
			var seen := _reach_set(reverse)
			for i in g_nodes.size():
				if not seen.has(i) and missing.size() < 12:
					missing.append("%s(%.0f, %.1f, %.0f)" % ["<-" if reverse else "->", g_nodes[i].x, g_nodes[i].y, g_nodes[i].z])
		errors.append("graphe non fortement connexe : " + ", ".join(missing))


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
						if (ra.kind in ["median", "sidewalk"] or rbb.kind in ["median", "sidewalk"]) and ra.chain == rbb.chain:
							continue
						# trottoir qui traverse l'entrée d'une rue locale
						if (ra.kind == "sidewalk" and String(rbb.id).begins_with("rue_")) or (rbb.kind == "sidewalk" and String(ra.id).begins_with("rue_")):
							continue
						# plateforme de la voie ferrée arrêtée au bord d'un passage à niveau
						if (ra.kind == "rail") != (rbb.kind == "rail") and _at_level_crossing(ra, rbb, ra.points[a.y]):
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
	return _reach_set(reverse).size()


func _reach_set(reverse: bool) -> Dictionary:
	if g_nodes.is_empty():
		return {}
	var adj := {}
	# les noeuds de la grille sont reliés entre eux par les rues du centre-ville
	for a in g_grid:
		adj[a] = g_grid.filter(func(b: int) -> bool: return b != a)
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
	return seen


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
