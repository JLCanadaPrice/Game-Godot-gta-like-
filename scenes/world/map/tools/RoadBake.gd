extends SceneTree

# Étapes 2a et 2b : cuisson des routes de la carte 3D à partir de RoadNetwork (autoroutes, voies express, artères,
# dessertes, chemins, losanges, carrefours et rond-point) :
#  - plateaux de carrefour (éventail depuis le centre, îlot de rond-point), trottoirs surélevés des artères urbaines ;
#  - graphe de circulation (generated/roads/traffic_graph.tres) et noeud Traffic (MapTraffic.gd) qui l'ajoute au
#    Circuit du monde au démarrage ;
#  - terrain : grille de hauteurs d'origine (TerrainModel) creusée et remblayée sous les chaussées (accotement plat,
#    talus), enregistrée dans generated/terrain/heights.res ; TerrainBake --from-heights recuit ensuite les tuiles ;
#  - chaussées : rubans maillés (atlas d'enrobé et de marquages dans le style des routes du centre-ville), rebords ;
#    terre-plein central avec glissière en béton ;
#  - ouvrages : tablier, garde-corps et piles là où la chaussée ne repose plus sur le sol (eau, autre route en
#    dessous, viaduc), murs le long des tranchées et des remblais tenus, culées aux changements ;
#  - sorties de carte : tranchée, portail, tunnel fermé avec toit de terrain, murs invisibles entre la limite et le
#    tunnel ;
#  - cellules de 256 m : enrobé, béton (et toit de tunnel) avec portée de visibilité, collision par cellule ;
#  - generated/Roads.tscn instanciée dans Map.tscn, generated/roads/boundary_gaps.json pour les brèches des limites.
#
# Lancer : Godot --headless --path <projet> --script res://scenes/world/map/tools/RoadBake.gd
# puis    : Godot --headless --path <projet> --script res://scenes/world/map/tools/TerrainBake.gd -- --from-heights

const Spec := preload("res://scenes/world/map/MapSpec.gd")
const Model := preload("res://scenes/world/map/tools/TerrainModel.gd")
const Network := preload("res://scenes/world/map/tools/RoadNetwork.gd")
const GEN := "res://scenes/world/map/generated"
const OUT := "res://scenes/world/map/generated/roads"
const TEXTURES := "res://scenes/world/map/roads/textures"
const MAP_SCENE := "res://scenes/world/map/Map.tscn"
const ROADS_SCENE := "res://scenes/world/map/generated/Roads.tscn"
const GROUP := 256.0
const ROAD_UNDER := 0.3             # terrain sous la surface de chaussée
const SHOULDER := 2.5               # accotement plat au-delà du bord
const HARD_MARGIN := 5.0            # terrain jamais au-dessus de la chaussée jusqu'à cette distance du bord
const CUT_SLOPE := 1.0              # talus de déblai (1/1)
const FILL_SLOPE := 0.6             # talus de remblai (1/1,7)
const FILL_MAX := 3.0               # au-delà : ouvrage plutôt que remblai
const SLOPE_REACH := 16.0
const LIP := 0.45                   # rebord vertical sous le bord de chaussée
const WALL_MIN := 0.9               # écart avec le terrain voisin à partir duquel le bord devient un mur
const BRIDGE_GAP := 1.2             # vide sous l'axe à partir duquel la chaussée devient un tablier
const PARAPET_HEIGHT := 0.9
const PARAPET_WIDTH := 0.35
const PIER_SPACING := 32.0
const PIER_MIN_HEIGHT := 3.0
const TEX_LENGTH := 12.0
const TUNNEL_HEIGHT := 7.0
const TUNNEL_BACK := 16.0           # fond du tunnel au-delà du demi-tour du graphe
const PORTAL_SAMPLES := 2           # entrée du tunnel : dalle du portail au-dessus
const PORTAL_ROOF := 6.0            # dalle au-dessus de l'entrée (cache la cellule de terrain à cheval sur le portail)
const TUNNEL_CARVE := 8.0           # creusement au-delà du bord de chaussée dans le tube (talus hors des parois)
const ROOF_BAND := 8.0              # toit de terrain (TerrainBake) au-delà du creusement : bords jamais creusés
const PORTAL_WING := 16.0           # portail : largeur au-delà des parois du tube
const RANGE_ASPHALT := 2000.0
const RANGE_CONCRETE := 1500.0
# colonnes de l'atlas roads.png (bornes en u affichées par RoadTexturesBake)
const ATLAS := {"highway": Vector2(0.0, 0.125), "ramp": Vector2(0.125, 0.206787), "median": Vector2(0.207031, 0.242188),
		"urban": Vector2(0.25, 0.372559), "arterial": Vector2(0.375, 0.480225), "access": Vector2(0.488281, 0.564209),
		"dirt": Vector2(0.572266, 0.630615), "sidewalk": Vector2(0.638672, 0.673828), "rail": Vector2(0.683594, 0.741943)}
# voie ferrée (étape 4b) : rails en acier sans collision, passages à niveau, bouts de ligne
const RAIL_HEAD := 0.07
const RAIL_TOP := 0.17
const RANGE_STEEL := 600.0
const STEEL := Color(0.3, 0.29, 0.28)
const SIGN_POST := Color(0.55, 0.55, 0.53)
const SIGN_BOARD := Color(0.92, 0.92, 0.9)
const BUFFER_RED := Color(0.5, 0.13, 0.1)
const PORTAL_RISE := 6.0             # relief au-delà du bout de ligne à partir duquel on pose un portail
const ISLAND_RISE := 0.25
# lampadaires du kit de routes (sans lumière, en MultiMesh par cellule) : trottoirs des artères urbaines en quinconce,
# terre-plein des viaducs et des approches d'échangeur (double crosse), bord extérieur des anneaux
const LAMP_SINGLE := "res://assets/modular_roads/lamp_1.glb"
const LAMP_DOUBLE := "res://assets/modular_roads/lamp_2.glb"
const LAMP_SPACING := {"sidewalk": 30.0, "median": 45.0, "ring": 36.0}
const LAMP_NEAR_RING := 320.0
const LAMP_RANGE := 650.0           # mesurée au centre de la cellule de 256 m : ~350 m pour le lampadaire le plus loin
const TrafficGraph := preload("res://scenes/world/map/MapTrafficGraph.gd")
const TRAFFIC_SCRIPT := preload("res://scenes/world/map/MapTraffic.gd")
const JERSEY := [Vector2(-0.3, 0.0), Vector2(-0.22, 0.28), Vector2(-0.1, 0.85), Vector2(0.1, 0.85), Vector2(0.22, 0.28), Vector2(0.3, 0.0)]


class Batch:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()


var model: Model
var net: Network
var pristine := PackedFloat32Array()
var heights := PackedFloat32Array()
var excluded := PackedByteArray()
var groups := {}                  # Vector2i -> {"asphalt": Batch, "concrete": Batch, "roof": Batch, "faces": PackedVector3Array}
var road_index := {}              # cellule de 16 m -> [[ruban, échantillon], ...] (piles)
var tunnel_spans := {}            # id de chaîne -> [[indice du portail, indice du bout], ...]
var corridors: Array[Dictionary] = []
var stats := {"cellules": 0, "tablier_m": 0.0, "murs_m": 0.0, "piles": 0, "tunnels": 0, "sommets_creuses": 0, "sommets_remblayes": 0, "triangles": 0}


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	model = Model.new()
	net = Network.new(model)
	net.build()
	if not net.errors.is_empty():
		for line in net.errors:
			print("ROAD_BAKE_ERROR " + line)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	pristine = model.build_heights()
	heights = pristine.duplicate()
	excluded.resize(model.width * model.depth)
	for j in model.depth:
		for i in model.width:
			excluded[j * model.width + i] = 1 if model.is_excluded(model.grid_to_world(i, j)) else 0
	for t: Dictionary in net.tunnels:
		if not tunnel_spans.has(t["chain"]):
			tunnel_spans[t["chain"]] = []
		tunnel_spans[t["chain"]].append([int(t["portal_index"]), int(t["tip_index"])])
	var modes := {}
	for rb in net.ribbons:
		if rb.mesh:
			modes[rb] = _modes(rb)
	_carve(modes)
	_index_roads()
	for rb in modes:
		modes[rb] = _unsupported_to_bridges(rb, modes[rb])
	ResourceSaver.save(Image.create_from_data(model.width, model.depth, false, Image.FORMAT_RF, heights.to_byte_array()), GEN + "/terrain/heights.res")
	# copie « routes seules » : DistrictsBake repart de celle-ci pour aplanir les lots (cuisson rejouable)
	ResourceSaver.save(Image.create_from_data(model.width, model.depth, false, Image.FORMAT_RF, heights.to_byte_array()), GEN + "/terrain/heights_roads.res")
	for rb in modes:
		_ribbon(rb, modes[rb])
	for pad: Dictionary in net.pads:
		_pad(pad)
	_place_lamps(modes)
	for lc: Dictionary in net.level_crossings:
		_level_crossing(lc)
	for e: Dictionary in net.rail_ends:
		_rail_end(e)
	var roof := PackedByteArray()
	roof.resize(model.width * model.depth)
	for t: Dictionary in net.tunnels:
		_tunnel(t, roof)
	ResourceSaver.save(Image.create_from_data(model.width, model.depth, false, Image.FORMAT_L8, roof), GEN + "/terrain/roof_mask.res")
	_write_traffic_graph()
	_write_scene()
	_write_boundary_gaps()
	_ensure_in_map()
	print("ROAD_BAKE %s en %.1f s" % [stats, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0)


# --- terrain ----------------------------------------------------------------------------------------------------
# État de chaque échantillon d'un ruban : 0 posé (déblai / remblai), 1 ouvrage (eau, trop haut), 2 dans un tunnel
# (terrain intact au-dessus du tube), 3 entrée de tunnel (terrain creusé derrière le portail).
func _modes(rb) -> PackedByteArray:
	var pts: PackedVector3Array = rb.points
	var out := PackedByteArray()
	out.resize(pts.size())
	for k in pts.size():
		var p: Vector3 = pts[k]
		var q := Vector2(p.x, p.z)
		var inside := _tunnel_depth(rb, k)
		if inside > PORTAL_SAMPLES:
			out[k] = 2
		elif inside > 0:
			out[k] = 3
		elif net.is_water(q) or model.river_info(q).x < 3.0 or p.y - _sample(pristine, q) > FILL_MAX:
			out[k] = 1
		else:
			out[k] = 0
	return out


# Nombre d'échantillons d'axe entre le portail et ce point du ruban, 0 hors tunnel.
func _tunnel_depth(rb, k: int) -> int:
	if not tunnel_spans.has(rb.chain) or rb.kind == "ramp":
		return 0
	var j: int = rb.chain_start + rb.chain_step * k
	for span: Array in tunnel_spans[rb.chain]:
		var portal: int = span[0]
		var tip: int = span[1]
		var depth := (j - portal) * signi(tip - portal)
		if depth > 0:
			return depth
	return 0


func _chain(id: String) -> Dictionary:
	for chain in net.chains + net.arterial_chains:
		if chain["id"] == id:
			return chain
	return {}


# Bornes par sommet de la grille : sous une chaussée (et 1 m autour) le terrain passe sous la surface (borne dure) ;
# au-delà, accotement plat puis talus de déblai (borne souple) ; une chaussée posée retient aussi le terrain à son
# niveau par talus de remblai. Ordre : talus de déblai, puis remblai qui porte une chaussée voisine, puis borne dure :
# une chaussée plus basse l'emporte toujours, celle du dessus reçoit un mur ou un tablier. Sous un ouvrage le terrain
# reste sous le tablier. Dans un tunnel il est creusé jusqu'au sol du tube (collision) sur toute sa longueur ; le rendu
# de ces cellules est remplacé par un toit au relief d'origine (roof_mask.res, repris par TerrainBake).
func _carve(modes: Dictionary) -> void:
	var n := model.width * model.depth
	var lo := PackedFloat32Array()
	var soft := PackedFloat32Array()
	var hard := PackedFloat32Array()
	lo.resize(n)
	soft.resize(n)
	hard.resize(n)
	lo.fill(-INF)
	soft.fill(INF)
	hard.fill(INF)
	for rb in modes:
		var pts: PackedVector3Array = rb.points
		var count := pts.size()
		var mode: PackedByteArray = modes[rb]
		var hw: float = rb.width * 0.5
		for k in (count if rb.closed else count - 1):
			var k2 := (k + 1) % count
			var m := maxi(mode[k], mode[k2])
			_carve_segment(pts[k], pts[k2], hw, m, lo, soft, hard)
	for pad: Dictionary in net.pads:
		var center: Vector3 = pad["center"]
		var radius := 0.0
		for p: Vector3 in pad["rim"]:
			radius = maxf(radius, Vector2(p.x - center.x, p.z - center.z).length())
		_carve_segment(center, center, radius, 0, lo, soft, hard)
	for t: Dictionary in net.tunnels:
		var a: Vector3 = t["pos"]
		var dir: Vector2 = t["dir"]
		var b := a + Vector3(dir.x, 0.0, dir.y) * (Network.TUNNEL_DEPTH + TUNNEL_BACK)
		_carve_segment(a, b, float(t["width"]) * 0.5 - 2.0, 2, lo, soft, hard)
	for idx in n:
		if excluded[idx] == 1:
			continue
		var h := pristine[idx]
		var carved := minf(maxf(minf(h, soft[idx]), lo[idx]), hard[idx])
		if carved < h - 0.05:
			stats["sommets_creuses"] += 1
		elif carved > h + 0.05:
			stats["sommets_remblayes"] += 1
		heights[idx] = carved


# Après creusement : un échantillon posé qui franchit une autre chaussée (passant sous son axe) et dont l'axe et les deux
# bords ne reposent plus sur le terrain devient tablier. Une chaussée seulement longée par une plus basse garde ses murs.
func _unsupported_to_bridges(rb, mode: PackedByteArray) -> PackedByteArray:
	var pts: PackedVector3Array = rb.points
	var hw: float = rb.width * 0.5
	for k in pts.size():
		if mode[k] != 0:
			continue
		var p: Vector3 = pts[k]
		var a := pts[maxi(k - 1, 0)]
		var b := pts[mini(k + 1, pts.size() - 1)]
		var dir := Vector2(b.x - a.x, b.z - a.z).normalized()
		var side := Vector2(-dir.y, dir.x) * (hw - 0.5)
		var q := Vector2(p.x, p.z)
		var low := p.y - BRIDGE_GAP
		if _sample(heights, q) < low and _sample(heights, q + side) < low and _sample(heights, q - side) < low and _road_under(p, rb):
			mode[k] = 1
	return mode


func _carve_segment(a: Vector3, b: Vector3, hw: float, mode: int, lo: PackedFloat32Array, soft: PackedFloat32Array, hard: PackedFloat32Array) -> void:
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var reach := hw + SHOULDER + (SLOPE_REACH if mode == 0 else 2.0)
	var box := Rect2(a2, Vector2.ZERO).expand(b2).grow(reach)
	var origin := Spec.TERRAIN.position
	var i0 := maxi(0, floori((box.position.x - origin.x) / Model.CELL))
	var i1 := mini(model.width - 1, ceili((box.end.x - origin.x) / Model.CELL))
	var j0 := maxi(0, floori((box.position.y - origin.y) / Model.CELL))
	var j1 := mini(model.depth - 1, ceili((box.end.y - origin.y) / Model.CELL))
	var ab := b2 - a2
	var len2 := maxf(ab.length_squared(), 0.0001)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var p := origin + Vector2(i, j) * Model.CELL
			var t := clampf((p - a2).dot(ab) / len2, 0.0, 1.0)
			var dist := p.distance_to(a2 + ab * t)
			if dist > reach:
				continue
			var y := lerpf(a.y, b.y, t)
			var idx := j * model.width + i
			match mode:
				0:
					var beyond := maxf(0.0, dist - hw - HARD_MARGIN)
					# une cellule entière au-delà du bord : si une chaussée plus haute est accolée, la transition de
					# terrain passe sous elle (cachée) au lieu d'apparaître en dents de scie devant son mur
					if dist <= hw + HARD_MARGIN:
						hard[idx] = minf(hard[idx], y - ROAD_UNDER)
					soft[idx] = minf(soft[idx], y - ROAD_UNDER + beyond * CUT_SLOPE)
					lo[idx] = maxf(lo[idx], y - ROAD_UNDER - beyond * FILL_SLOPE)
				1:
					if dist <= hw + 1.0:
						hard[idx] = minf(hard[idx], y - Network.DECK - 0.6)
					soft[idx] = minf(soft[idx], y - Network.DECK - 0.6 + maxf(0.0, dist - hw - 1.0) * CUT_SLOPE)
				_:
					if dist <= hw + TUNNEL_CARVE:
						hard[idx] = minf(hard[idx], y - ROAD_UNDER)


func _sample(grid: PackedFloat32Array, p: Vector2) -> float:
	var fx := (p.x - Spec.TERRAIN.position.x) / Model.CELL
	var fz := (p.y - Spec.TERRAIN.position.y) / Model.CELL
	var i := clampi(floori(fx), 0, model.width - 2)
	var j := clampi(floori(fz), 0, model.depth - 2)
	var tx := clampf(fx - i, 0.0, 1.0)
	var tz := clampf(fz - j, 0.0, 1.0)
	var w: int = model.width
	var top := lerpf(grid[j * w + i], grid[j * w + i + 1], tx)
	var bottom := lerpf(grid[(j + 1) * w + i], grid[(j + 1) * w + i + 1], tx)
	return lerpf(top, bottom, tz)


# --- chaussées et ouvrages --------------------------------------------------------------------------------------
func _index_roads() -> void:
	for r in net.ribbons.size():
		var rb = net.ribbons[r]
		var pts: PackedVector3Array = rb.points
		for k in pts.size():
			var key := Vector2i(floori(pts[k].x / 16.0), floori(pts[k].z / 16.0))
			if not road_index.has(key):
				road_index[key] = []
			road_index[key].append(Vector2i(r, k))


# Vrai si une autre chaussée passe sous le point p (plus bas que `below` de plus de 3 m) : pas de pile ici.
func _road_under(p: Vector3, owner) -> bool:
	var key := Vector2i(floori(p.x / 16.0), floori(p.z / 16.0))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for hit: Vector2i in road_index.get(key + Vector2i(dx, dz), []):
				var other = net.ribbons[hit.x]
				if other == owner:
					continue
				var q: Vector3 = other.points[hit.y]
				if q.y < p.y - 3.0 and Vector2(q.x - p.x, q.z - p.z).length() < float(other.width) * 0.5 + 2.5:
					return true
	return false


func _ribbon(rb, mode: PackedByteArray) -> void:
	var pts: PackedVector3Array = rb.points
	var n := pts.size()
	var closed: bool = rb.closed
	var hw: float = rb.width * 0.5
	var kind: String = rb.kind
	var column := "highway"
	match kind:
		"median", "ramp", "sidewalk", "rail":
			column = kind
		"arterial":
			column = rb.style
	var atlas: Vector2 = ATLAS[column]
	var sides := PackedVector3Array()
	var arc := PackedFloat32Array()
	var total := 0.0
	for k in n:
		var prev: Vector3 = pts[(k - 1 + n) % n] if closed or k > 0 else pts[k]
		var next: Vector3 = pts[(k + 1) % n] if closed or k < n - 1 else pts[k]
		var dir := Vector3(next.x - prev.x, 0.0, next.z - prev.z).normalized()
		sides.append(Vector3(-dir.z, 0.0, dir.x))
		if k > 0:
			total += Vector2(pts[k].x - pts[k - 1].x, pts[k].z - pts[k - 1].z).length()
		arc.append(total)
	var segs := n if closed else n - 1
	var open := _open_edges(rb)
	# surface
	for k in segs:
		var k2 := (k + 1) % n
		var v1 := arc[k] / TEX_LENGTH
		var v2 := (arc[k2] if k2 > k else total + Vector2(pts[k2].x - pts[k].x, pts[k2].z - pts[k].z).length()) / TEX_LENGTH
		var l1 := pts[k] - sides[k] * hw
		var r1 := pts[k] + sides[k] * hw
		var l2 := pts[k2] - sides[k2] * hw
		var r2 := pts[k2] + sides[k2] * hw
		_quad("asphalt", l1, l2, r2, r1, Vector3.UP, [Vector2(atlas.x, v1), Vector2(atlas.x, v2), Vector2(atlas.y, v2), Vector2(atlas.y, v1)])
	if kind == "median":
		_jersey(pts, sides, segs)
	if kind == "rail":
		for k in segs:
			for offset: float in [-Network.RAIL_GAUGE * 0.5, Network.RAIL_GAUGE * 0.5]:
				_rail_bar(pts[k] + sides[k] * offset, pts[k + 1] + sides[k + 1] * offset, sides[k], sides[k + 1], 0.0, RAIL_TOP)
	# bords : rebord ou flanc de tablier, mur de soutènement, garde-corps
	for side_sign: float in [-1.0, 1.0]:
		if kind == "median" or (kind == "carriageway" and side_sign < 0.0):
			continue   # côté terre-plein
		var depth := PackedFloat32Array()
		var retain := PackedFloat32Array()
		var parapet := PackedByteArray()
		var open_bit := 1 if side_sign < 0.0 else 2
		for k in n:
			var p := pts[k]
			var out := sides[k] * side_sign
			var edge := p + out * hw
			var d := LIP
			var r := 0.0
			var guard := 0
			if (open[k] & open_bit) != 0:
				d = Network.DECK if mode[k] == 1 else LIP
			elif mode[k] == 1:
				d = Network.DECK
				guard = 1
			elif mode[k] == 0:
				# terrain juste au-delà du bord : plusieurs relevés, pour un mur continu malgré la grille de 4 m
				var lowest := INF
				var highest := -INF
				for reach: float in [0.6, 1.5, 2.5, 3.5]:
					var ground := _sample(heights, Vector2(edge.x + out.x * reach, edge.z + out.z * reach))
					lowest = minf(lowest, ground)
					highest = maxf(highest, ground)
				if lowest < p.y - WALL_MIN:
					d = p.y - lowest + 0.3
					guard = 1 if p.y - lowest > 2.0 else 0
				elif highest > p.y + WALL_MIN:
					r = highest - p.y + 0.3
			depth.append(d)
			retain.append(r)
			parapet.append(guard)
		for k in segs:
			var k2 := (k + 1) % n
			var o1 := sides[k] * side_sign
			var o2 := sides[k2] * side_sign
			var e1 := pts[k] + o1 * hw
			var e2 := pts[k2] + o2 * hw
			var seg_len := Vector2(e2.x - e1.x, e2.z - e1.z).length()
			if kind == "rail" and mode[k] == 0 and mode[k2] == 0 and depth[k] <= LIP + 0.01 and depth[k2] <= LIP + 0.01:
				# plateforme posée : talus de ballast au lieu du rebord en béton
				var u := atlas.x + 0.003 if side_sign < 0.0 else atlas.y - 0.003
				_quad("asphalt", e1, e2, e2 + o2 * 0.9 - Vector3(0, LIP, 0), e1 + o1 * 0.9 - Vector3(0, LIP, 0), ((o1 + o2).normalized() + Vector3.UP).normalized(),
						[Vector2(u, arc[k] / TEX_LENGTH), Vector2(u, arc[k2] / TEX_LENGTH), Vector2(u, arc[k2] / TEX_LENGTH), Vector2(u, arc[k] / TEX_LENGTH)])
			else:
				_quad("concrete", e1, e2, e2 - Vector3(0, depth[k2], 0), e1 - Vector3(0, depth[k], 0), (o1 + o2).normalized())
			if depth[k] > LIP + 0.5 or depth[k2] > LIP + 0.5:
				stats["murs_m"] += seg_len
			if retain[k] > 0.0 or retain[k2] > 0.0:
				var w1 := e1 + o1 * 0.3
				var w2 := e2 + o2 * 0.3
				var t1 := w1 + Vector3(0, retain[k], 0)
				var t2 := w2 + Vector3(0, retain[k2], 0)
				_quad("concrete", w1 - Vector3(0, 0.4, 0), w2 - Vector3(0, 0.4, 0), t2, t1, -(o1 + o2).normalized())
				_quad("concrete", t1, t2, t2 + o2 * 1.5, t1 + o1 * 1.5, Vector3.UP)
				stats["murs_m"] += seg_len
			if parapet[k] == 1 and parapet[k2] == 1:
				var i1 := e1 - o1 * PARAPET_WIDTH
				var i2 := e2 - o2 * PARAPET_WIDTH
				var up := Vector3(0, PARAPET_HEIGHT, 0)
				_quad("concrete", i1, i2, i2 + up, i1 + up, -(o1 + o2).normalized())
				_quad("concrete", i1 + up, i2 + up, e2 + up, e1 + up, Vector3.UP)
				_quad("concrete", e1, e2, e2 + up, e1 + up, (o1 + o2).normalized())
	# dessous de tablier, culées, piles
	var since_pier := PIER_SPACING * 0.5
	for k in segs:
		var k2 := (k + 1) % n
		var l1 := pts[k] - sides[k] * hw - Vector3(0, Network.DECK, 0)
		var r1 := pts[k] + sides[k] * hw - Vector3(0, Network.DECK, 0)
		var l2 := pts[k2] - sides[k2] * hw - Vector3(0, Network.DECK, 0)
		var r2 := pts[k2] + sides[k2] * hw - Vector3(0, Network.DECK, 0)
		if mode[k] == 1 and mode[k2] == 1:
			_quad("concrete", l1, l2, r2, r1, Vector3.DOWN)
			stats["tablier_m"] += Vector2(pts[k2].x - pts[k].x, pts[k2].z - pts[k].z).length()
		if (mode[k] == 1) != (mode[k2] == 1) and mode[k] < 2 and mode[k2] < 2:
			var g := k if mode[k] == 0 else k2
			var toward := (pts[k2] - pts[k]).normalized() * (1.0 if g == k else -1.0)
			var left := pts[g] - sides[g] * hw
			var right := pts[g] + sides[g] * hw
			var bottom := minf(_sample(heights, Vector2(left.x, left.z)), _sample(heights, Vector2(right.x, right.z))) - 0.5
			_quad("concrete", left - Vector3(0, 0.05, 0), right - Vector3(0, 0.05, 0), Vector3(right.x, bottom, right.z), Vector3(left.x, bottom, left.z), toward)
		if kind == "median":
			continue
		since_pier += Vector2(pts[k2].x - pts[k].x, pts[k2].z - pts[k].z).length()
		if mode[k] == 1 and since_pier >= PIER_SPACING:
			var ground := _sample(heights, Vector2(pts[k].x, pts[k].z))
			if pts[k].y - Network.DECK - ground > PIER_MIN_HEIGHT and not _road_under(pts[k], rb):
				_pier(pts[k], sides[k], 1.2 if kind == "ramp" else 1.8, ground - 0.5, pts[k].y - Network.DECK)
				since_pier = 0.0


# Bords ouverts d'un ruban (bit 1 gauche, bit 2 droite) le long des raccords décrits par RoadNetwork.attachments.
func _open_edges(rb) -> PackedByteArray:
	var n: int = rb.points.size()
	var out := PackedByteArray()
	out.resize(n)
	for a: Dictionary in net.attachments:
		if a["ribbon"] != rb:
			continue
		var bits := 3 if int(a["side"]) == 0 else (1 if int(a["side"]) < 0 else 2)
		for k in range(int(a["from"]), int(a["to"]) + 1):
			var idx := posmod(k, n) if rb.closed else clampi(k, 0, n - 1)
			out[idx] = out[idx] | bits
	return out


# Plateau de carrefour : éventail depuis le centre jusqu'au pourtour (coins des rubans), rebord vertical ; îlot en herbe
# surélevé pour un rond-point.
func _pad(pad: Dictionary) -> void:
	var center: Vector3 = pad["center"]
	var rim: PackedVector3Array = pad["rim"]
	var n := rim.size()
	if n < 3:
		return
	var atlas: Vector2 = ATLAS["median"]
	var u := (atlas.x + atlas.y) * 0.5
	for k in n:
		var a := rim[k]
		var b := rim[(k + 1) % n]
		_tri("asphalt", center, a, b, Vector3.UP, [Vector2(u, center.z / TEX_LENGTH), Vector2(u, a.z / TEX_LENGTH), Vector2(u, b.z / TEX_LENGTH)])
		var out := Vector3((a + b).x * 0.5 - center.x, 0.0, (a + b).z * 0.5 - center.z).normalized()
		_quad("concrete", a, b, b - Vector3(0, LIP, 0), a - Vector3(0, LIP, 0), out)
	var island: float = pad["island"]
	if island > 0.0:
		var grass := Color(0.85, 0.1, 0.05, 0.0)
		var top := center + Vector3(0, ISLAND_RISE, 0)
		var ring := Network._disc(top, island, 32)
		for k in ring.size():
			var a := ring[k]
			var b := ring[(k + 1) % ring.size()]
			_tri("roof", top, a, b, Vector3.UP, [], grass)
			var out := Vector3((a + b).x * 0.5 - center.x, 0.0, (a + b).z * 0.5 - center.z).normalized()
			_quad("concrete", a, b, b - Vector3(0, ISLAND_RISE + 0.1, 0), a - Vector3(0, ISLAND_RISE + 0.1, 0), out)


func _tri(part: String, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, uv: Array = [], color := Color.BLACK) -> void:
	var g := _group((a + b + c) / 3.0)
	if not g.has(part):
		g[part] = Batch.new()
	var batch: Batch = g[part]
	var geometric := (b - a).cross(c - a)
	if geometric.length_squared() < 0.000001:
		return
	var order := [a, b, c] if geometric.dot(normal) < 0.0 else [a, c, b]
	var uv_order := uv
	if not uv.is_empty() and geometric.dot(normal) >= 0.0:
		uv_order = [uv[0], uv[2], uv[1]]
	var nrm := geometric.normalized() * (1.0 if geometric.dot(normal) > 0.0 else -1.0)
	var base := batch.verts.size()
	for i in 3:
		batch.verts.append(order[i])
		batch.normals.append(nrm)
		batch.uvs.append(uv_order[i] if not uv_order.is_empty() else Vector2.ZERO)
		batch.colors.append(color)
	batch.indices.append_array(PackedInt32Array([base, base + 1, base + 2]))
	var faces: PackedVector3Array = g["faces"]
	faces.append_array(PackedVector3Array([order[0], order[1], order[2]]))
	g["faces"] = faces
	stats["triangles"] += 1


func _place_lamps(modes: Dictionary) -> void:
	var ring_centers: Array[Vector2] = []
	for node_id: String in Spec.NODES:
		if Network.shape(node_id) == "ring":
			ring_centers.append(Spec.node_pos(node_id))
	for rb in modes:
		var kind: String = rb.kind
		if not LAMP_SPACING.has(kind) or (kind == "ring" and rb.width < Network.RING_WIDTH):
			continue
		var pts: PackedVector3Array = rb.points
		var mode: PackedByteArray = modes[rb]
		var spacing: float = LAMP_SPACING[kind]
		var outer_sign := 1.0
		var since := spacing * 0.5
		if kind == "sidewalk":
			outer_sign = 1.0 if String(rb.id).ends_with("trottoir1") else -1.0
			since = spacing * (0.5 if outer_sign > 0.0 else 0.0)   # quinconce d'un trottoir à l'autre
		for k in pts.size():
			if k > 0:
				since += Vector2(pts[k].x - pts[k - 1].x, pts[k].z - pts[k - 1].z).length()
			if since < spacing or mode[k] >= 2:
				continue
			var a := pts[maxi(k - 1, 0)]
			var b := pts[mini(k + 1, pts.size() - 1)]
			var dir := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
			var side := Vector3(-dir.z, 0.0, dir.x)
			match kind:
				"sidewalk":
					# bord extérieur du trottoir, crosse vers la chaussée
					var base: Vector3 = pts[k] + side * outer_sign * (float(rb.width) * 0.5 - 0.5)
					_lamp("lamp_single", base, -side * outer_sign)
				"median":
					var near_ring := false
					for c in ring_centers:
						near_ring = near_ring or c.distance_to(Vector2(pts[k].x, pts[k].z)) < LAMP_NEAR_RING
					if mode[k] != 1 and not near_ring:
						continue
					_lamp("lamp_double", pts[k] + Vector3(0, 0.85, 0), side)
				"ring":
					# anneau parcouru dans le sens trigonométrique : l'extérieur est à droite
					_lamp("lamp_single", pts[k] + side * (rb.width * 0.5 + 0.8), -side)
			since = 0.0


func _lamp(part: String, base: Vector3, arm: Vector3) -> void:
	var g := _group(base)
	if not g.has(part):
		g[part] = []
	(g[part] as Array).append(Transform3D(Basis(arm, Vector3.UP, arm.cross(Vector3.UP)), base))
	stats["lampadaires"] = int(stats.get("lampadaires", 0)) + 1


# Graphe de circulation de la carte pour MapTraffic : noeuds, arêtes (trajet, voies, sens unique), anneaux, noeuds sans
# feu, noeuds de la grille du centre-ville, approches qui cèdent le passage.
func _write_traffic_graph() -> void:
	var graph := TrafficGraph.new()
	graph.nodes = net.g_nodes
	var edges: Array[Dictionary] = []
	for e: Dictionary in net.g_edges:
		edges.append({"a": e["a"], "b": e["b"], "points": e["points"], "one_way": e["one_way"], "lanes": e["lanes"]})
	graph.edges = edges
	graph.roundabout = PackedInt32Array(net.g_roundabout)
	graph.unlit = PackedInt32Array(net.g_unlit)
	graph.grid = PackedInt32Array(net.g_grid)
	graph.lit = PackedInt32Array(net.g_lit)
	graph.yields = net.g_yield.duplicate()
	var path := OUT.path_join("traffic_graph.tres")
	ResourceSaver.save(graph, path)
	stats["graphe"] = "%d noeuds, %d arêtes" % [net.g_nodes.size(), net.g_edges.size()]


func _jersey(pts: PackedVector3Array, sides: PackedVector3Array, segs: int) -> void:
	var n := pts.size()
	for k in segs:
		var k2 := (k + 1) % n
		for f in JERSEY.size() - 1:
			var a: Vector2 = JERSEY[f]
			var b: Vector2 = JERSEY[f + 1]
			var a1 := pts[k] + sides[k] * a.x + Vector3(0, a.y, 0)
			var b1 := pts[k] + sides[k] * b.x + Vector3(0, b.y, 0)
			var a2 := pts[k2] + sides[k2] * a.x + Vector3(0, a.y, 0)
			var b2 := pts[k2] + sides[k2] * b.x + Vector3(0, b.y, 0)
			var mid := (a + b) * 0.5
			var nrm := (sides[k] * signf(mid.x) * absf(b.y - a.y) + Vector3.UP * absf(b.x - a.x)).normalized()
			_quad("concrete", a1, a2, b2, b1, nrm)


func _pier(p: Vector3, side: Vector3, size: float, bottom: float, top: float) -> void:
	var fwd := Vector3(side.z, 0.0, -side.x)
	var h := size * 0.5
	var corners := [p + side * h + fwd * h, p - side * h + fwd * h, p - side * h - fwd * h, p + side * h - fwd * h]
	for c in 4:
		var a: Vector3 = corners[c]
		var b: Vector3 = corners[(c + 1) % 4]
		var mid := (a + b) * 0.5 - p
		_quad("concrete", Vector3(a.x, bottom, a.z), Vector3(b.x, bottom, b.z), Vector3(b.x, top, b.z), Vector3(a.x, top, a.z), Vector3(mid.x, 0.0, mid.z).normalized())
	stats["piles"] += 1


# --- voie ferrée ------------------------------------------------------------------------------------------------
# Rail en acier de a à b (tête de RAIL_HEAD m) : dessus et flancs de `bottom` à `top` au-dessus des points.
func _rail_bar(a: Vector3, b: Vector3, sa: Vector3, sb: Vector3, bottom: float, top: float) -> void:
	var h := RAIL_HEAD * 0.5
	var t := Vector3(0, top, 0)
	var d := Vector3(0, bottom, 0)
	_quad("steel", a - sa * h + t, b - sb * h + t, b + sb * h + t, a + sa * h + t, Vector3.UP, [], STEEL)
	_quad("steel", a - sa * h + d, b - sb * h + d, b - sb * h + t, a - sa * h + t, -(sa + sb).normalized(), [], STEEL)
	_quad("steel", a + sa * h + d, b + sb * h + d, b + sb * h + t, a + sa * h + t, (sa + sb).normalized(), [], STEEL)


# Pavé orienté (centre de la base, axe avant, demi-tailles) dans la partie "steel", couleur unie, sans dessous.
func _steel_box(base: Vector3, fwd: Vector3, side: Vector3, half: Vector3, color: Color) -> void:
	var up := Vector3(0, half.y * 2.0, 0)
	var c := [base + side * half.x + fwd * half.z, base - side * half.x + fwd * half.z, base - side * half.x - fwd * half.z, base + side * half.x - fwd * half.z]
	for k in 4:
		var a: Vector3 = c[k]
		var b: Vector3 = c[(k + 1) % 4]
		var out := ((a + b) * 0.5 - base)
		_quad("steel", a, b, b + up, a + up, Vector3(out.x, 0.0, out.z).normalized(), [], color)
	_quad("steel", c[0] + up, c[1] + up, c[2] + up, c[3] + up, Vector3.UP, [], color)


# Passage à niveau : rails noyés dans la chaussée et les trottoirs (2 cm au-dessus), croix de Saint-André à droite de
# la route avant les voies, dans chaque sens.
func _level_crossing(lc: Dictionary) -> void:
	var road = lc["road"]
	var c: Vector3 = lc["pos"]
	var rail_dir: Vector2 = lc["rail_dir"]
	var half: float = lc["half_gap"]
	var fwd := Vector3(rail_dir.x, 0.0, rail_dir.y)
	var side := Vector3(-rail_dir.y, 0.0, rail_dir.x)
	var steps := maxi(2, ceili(half * 2.0))
	for s in steps:
		var p1 := c + fwd * (-half + half * 2.0 * s / steps)
		var p2 := c + fwd * (-half + half * 2.0 * (s + 1) / steps)
		for offset: float in [-Network.RAIL_GAUGE * 0.5, Network.RAIL_GAUGE * 0.5]:
			var a := p1 + side * offset
			var b := p2 + side * offset
			a.y = _crossing_surface(road, Vector2(a.x, a.z))
			b.y = _crossing_surface(road, Vector2(b.x, b.z))
			_rail_bar(a, b, side, side, -0.06, 0.02)
	var road_dir: Vector2 = lc["road_dir"]
	var sin_a := maxf(absf(rail_dir.cross(road_dir)), 0.25)
	var lateral: float = float(road.width) * 0.5 + (Network.SIDEWALK_WIDTH if road.style == "urban" else 0.0) + 0.7
	for approach: float in [-1.0, 1.0]:
		var d := road_dir * approach                  # sens de marche vers les voies
		var right := Network.right_of(d)
		var before := (Network.WIDTHS["rail"] * 0.5 + 2.5) / sin_a
		# le long de la route, l'axe des voies croise la ligne du panneau (à `lateral` m de l'axe) en t_rail
		var t_rail := -lateral * right.cross(rail_dir) / (d.cross(rail_dir) if absf(d.cross(rail_dir)) > 0.01 else 0.01)
		var p := Vector2(c.x, c.z) + right * lateral + d * (t_rail - before)
		var ground := _crossing_surface(road, p)
		_crossbuck(Vector3(p.x, ground - 0.3, p.y), Vector3(d.x, 0.0, d.y))


# Hauteur de surface à la traversée : axe de la route, trottoir surélevé au-delà de la chaussée.
func _crossing_surface(road, q: Vector2) -> float:
	var y := Network._height_on(road, q)
	var pts: PackedVector3Array = road.points
	var lateral := INF
	for k in pts.size() - 1:
		var close := Geometry2D.get_closest_point_to_segment(q, Vector2(pts[k].x, pts[k].z), Vector2(pts[k + 1].x, pts[k + 1].z))
		lateral = minf(lateral, close.distance_to(q))
	if road.style == "urban" and lateral > float(road.width) * 0.5:
		y += Network.SIDEWALK_RISE
	return y


# Croix de Saint-André : poteau gris et deux planches blanches croisées, face aux véhicules qui arrivent (sens `toward`).
func _crossbuck(base: Vector3, toward: Vector3) -> void:
	var side := Vector3(-toward.z, 0.0, toward.x)
	_steel_box(base, toward, side, Vector3(0.06, 1.85, 0.06), SIGN_POST)
	var center := base + Vector3(0, 3.35, 0) - toward * 0.08
	for tilt: float in [-1.0, 1.0]:
		var along := (side + Vector3.UP * tilt).normalized() * 0.65
		var across := (side * -tilt + Vector3.UP).normalized() * 0.11
		_quad("steel", center - along - across, center + along - across, center + along + across, center - along + across, -toward, [], SIGN_BOARD)
		center -= toward * 0.02


# Bout de ligne à la limite de la carte : portail de tunnel si le relief remonte au-delà, heurtoir sinon.
func _rail_end(e: Dictionary) -> void:
	var p: Vector3 = e["pos"]
	var d: Vector2 = e["dir"]
	var fwd := Vector3(d.x, 0.0, d.y)
	var side := Vector3(-d.y, 0.0, d.x)
	if float(e["rise"]) < PORTAL_RISE:
		_steel_box(p + fwd * 0.8 - Vector3(0, 0.1, 0), fwd, side, Vector3(1.4, 0.6, 0.35), BUFFER_RED)
		stats["heurtoirs"] = int(stats.get("heurtoirs", 0)) + 1
		return
	# façade en béton (piédroits, linteau) autour d'une ouverture de 6,4 x 6,2 m, niche de 4 m au fond noir
	var face := p + fwd * 0.5
	var bottom := p.y - 2.0
	var top := p.y + 9.5
	var open_w := 3.2
	var open_h := p.y + 6.2
	var wing := 13.0
	var y_of := func(q: Vector3, y: float) -> Vector3: return Vector3(q.x, y, q.z)
	for s: float in [-1.0, 1.0]:
		var inner: Vector3 = face + side * s * open_w
		var outer: Vector3 = face + side * s * wing
		_quad("concrete", y_of.call(inner, bottom), y_of.call(outer, bottom), y_of.call(outer, top), y_of.call(inner, top), -fwd)
		_quad("concrete", y_of.call(inner, bottom), y_of.call(inner + fwd * 4.0, bottom), y_of.call(inner + fwd * 4.0, open_h), y_of.call(inner, open_h), -side * s)
		# rails jusqu'au fond de la niche
		var rail_a := p + side * s * Network.RAIL_GAUGE * 0.5
		_rail_bar(rail_a, rail_a + fwd * 4.5, side, side, 0.0, RAIL_TOP)
	var l := face - side * open_w
	var r := face + side * open_w
	_quad("concrete", y_of.call(l, open_h), y_of.call(r, open_h), y_of.call(r, top), y_of.call(l, top), -fwd)
	_quad("concrete", y_of.call(l, open_h), y_of.call(r, open_h), y_of.call(r + fwd * 4.0, open_h), y_of.call(l + fwd * 4.0, open_h), Vector3.DOWN)
	_quad("concrete", y_of.call(face - side * wing, top), y_of.call(face + side * wing, top), y_of.call(face + side * wing + fwd * 2.0, top), y_of.call(face - side * wing + fwd * 2.0, top), Vector3.UP)
	_quad("steel", y_of.call(l + fwd * 4.0, bottom), y_of.call(r + fwd * 4.0, bottom), y_of.call(r + fwd * 4.0, open_h), y_of.call(l + fwd * 4.0, open_h), -fwd, [], Color(0.02, 0.02, 0.02))
	_quad("concrete", y_of.call(l, p.y - 0.25), y_of.call(r, p.y - 0.25), y_of.call(r + fwd * 4.0, p.y - 0.25), y_of.call(l + fwd * 4.0, p.y - 0.25), Vector3.UP)
	stats["portails_voie_ferree"] = int(stats.get("portails_voie_ferree", 0)) + 1


# --- tunnels ----------------------------------------------------------------------------------------------------
func _tunnel(t: Dictionary, roof: PackedByteArray) -> void:
	var chain := _chain(t["chain"])
	var pts: PackedVector2Array = chain["points"]
	var hts: PackedFloat32Array = chain["heights"]
	var portal: int = t["portal_index"]
	var tip: int = t["tip_index"]
	var boundary: int = t["boundary_index"]
	var outward := signi(tip - portal)
	var dir: Vector2 = t["dir"]
	var hw := float(t["width"]) * 0.5
	# axe du tube : de l'entrée au bout de la chaîne, puis tout droit jusqu'au fond
	var axis := PackedVector3Array()
	var j := portal
	while true:
		axis.append(Vector3(pts[j].x, hts[j], pts[j].y))
		if j == tip:
			break
		j += outward
	var end_len := Network.TUNNEL_DEPTH + TUNNEL_BACK
	var s := Network.STEP
	while s <= end_len + 0.01:
		var q := pts[tip] + dir * s
		axis.append(Vector3(q.x, hts[tip], q.y))
		s += Network.STEP
	var sides := PackedVector3Array()
	for k in axis.size():
		var a := axis[maxi(k - 1, 0)]
		var b := axis[mini(k + 1, axis.size() - 1)]
		var d := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		sides.append(Vector3(-d.z, 0.0, d.x))
	var up := Vector3(0, TUNNEL_HEIGHT, 0)
	var tip_k := absi(tip - portal)
	for k in axis.size() - 1:
		var p1 := axis[k]
		var p2 := axis[k + 1]
		var s1 := sides[k]
		var s2 := sides[k + 1]
		for side_sign: float in [-1.0, 1.0]:
			var w1 := p1 + s1 * hw * side_sign
			var w2 := p2 + s2 * hw * side_sign
			_quad("concrete", w1 - Vector3(0, 0.5, 0), w2 - Vector3(0, 0.5, 0), w2 + up, w1 + up, -s1 * side_sign)
			# sol entre la chaussée et la paroi (et tout le fond au-delà du bout des chaussées)
			var inner := float(t["road_half"]) if k < tip_k else 0.0
			var f1 := p1 + s1 * inner * side_sign
			var f2 := p2 + s2 * inner * side_sign
			var atlas: Vector2 = ATLAS["median"]
			_quad("asphalt", f1, f2, w2, w1, Vector3.UP, [Vector2(atlas.x, 0.0), Vector2(atlas.x, 0.33), Vector2(atlas.y, 0.33), Vector2(atlas.y, 0.0)])
		_quad("concrete", p1 - s1 * hw + up, p2 - s2 * hw + up, p2 + s2 * hw + up, p1 + s1 * hw + up, Vector3.DOWN)
	# toit : sommets de la grille dans la bande du tube (sans débordement avant le portail ni après le fond)
	var band := hw + TUNNEL_CARVE + ROOF_BAND
	var origin := Spec.TERRAIN.position
	for k in axis.size() - 1:
		var a2 := Vector2(axis[k].x, axis[k].z)
		var b2 := Vector2(axis[k + 1].x, axis[k + 1].z)
		var ab := b2 - a2
		var box := Rect2(a2, Vector2.ZERO).expand(b2).grow(band)
		for gj in range(maxi(0, floori((box.position.y - origin.y) / Model.CELL)), mini(model.depth - 1, ceili((box.end.y - origin.y) / Model.CELL)) + 1):
			for gi in range(maxi(0, floori((box.position.x - origin.x) / Model.CELL)), mini(model.width - 1, ceili((box.end.x - origin.x) / Model.CELL)) + 1):
				var p := origin + Vector2(gi, gj) * Model.CELL
				var along := (p - a2).dot(ab) / maxf(ab.length_squared(), 0.0001)
				if along >= 0.0 and along <= 1.0 and p.distance_to(a2 + ab * along) <= band:
					roof[gj * model.width + gi] = 1
	var last := axis[axis.size() - 1]
	var ls := sides[axis.size() - 1]
	_quad("concrete", last - ls * hw - Vector3(0, 0.5, 0), last + ls * hw - Vector3(0, 0.5, 0), last + ls * hw + up, last - ls * hw + up, -Vector3(dir.x, 0.0, dir.y))
	# portail : deux piédroits et un linteau jusqu'au-dessus du terrain, dalle qui couvre l'entrée creusée derrière
	var p0 := axis[0]
	var s0 := sides[0]
	var face := -Vector3(dir.x, 0.0, dir.y)
	var top := p0.y + TUNNEL_HEIGHT + 1.5
	var wing := hw + PORTAL_WING
	for u in range(-6, 7):
		for back in [0.0, PORTAL_ROOF]:
			var q := p0 + s0 * wing * u / 6.0 + Vector3(dir.x, 0.0, dir.y) * float(back)
			top = maxf(top, _sample(pristine, Vector2(q.x, q.z)) + 0.6)
	var depth := Vector3(dir.x, 0.0, dir.y) * PORTAL_ROOF
	for block: Array in [[-wing, -hw, p0.y - 1.0], [hw, wing, p0.y - 1.0], [-hw, hw, p0.y + TUNNEL_HEIGHT]]:
		var a := p0 + s0 * float(block[0])
		var b := p0 + s0 * float(block[1])
		var bottom: float = block[2]
		_quad("concrete", Vector3(a.x, bottom, a.z), Vector3(b.x, bottom, b.z), Vector3(b.x, top, b.z), Vector3(a.x, top, a.z), face)
		_quad("concrete", Vector3(a.x, top, a.z), Vector3(b.x, top, b.z), Vector3(b.x, top, b.z) + depth, Vector3(a.x, top, a.z) + depth, Vector3.UP)
	for edge_sign: float in [-1.0, 1.0]:
		var a := p0 + s0 * wing * edge_sign
		_quad("concrete", Vector3(a.x, p0.y - 1.0, a.z), Vector3(a.x, p0.y - 1.0, a.z) + depth, Vector3(a.x, top, a.z) + depth, Vector3(a.x, top, a.z), s0 * edge_sign)
	# couloir entre la limite de la zone explorable et le portail : murs invisibles de part et d'autre
	var half := float(t["road_half"]) + 1.1
	var k0 := boundary
	while (k0 - portal) * outward < 0:
		var k1 := k0 + outward * 6
		if (k1 - portal) * outward > 0:
			k1 = portal
		var a2 := pts[k0]
		var b2 := pts[k1]
		var mid := (a2 + b2) * 0.5
		var along := b2 - a2
		var nrm := Vector2(-along.y, along.x).normalized()
		for side_sign: float in [-1.0, 1.0]:
			var c := mid + nrm * half * side_sign
			corridors.append({"pos": Vector3(c.x, (hts[k0] + hts[k1]) * 0.5 + 4.0, c.y), "yaw": atan2(along.x, along.y), "length": along.length() + 2.0})
		if k1 == portal:
			break
		k0 = k1
	stats["tunnels"] += 1


# --- maillage ---------------------------------------------------------------------------------------------------
func _group(p: Vector3) -> Dictionary:
	var key := Vector2i(floori(p.x / GROUP), floori(p.z / GROUP))
	if not groups.has(key):
		groups[key] = {"faces": PackedVector3Array()}
	return groups[key]


# Quadrilatère a-b-c-d (dans l'ordre du pourtour), face visible du côté de `normal` (sommets en sens horaire vu de ce
# côté, convention de Godot), ajouté au maillage `part` de sa cellule et à la collision.
func _quad(part: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, uv: Array = [], color := Color.BLACK) -> void:
	if (c - a).length_squared() < 0.0001 and (d - b).length_squared() < 0.0001:
		return
	var g := _group((a + c) * 0.5)
	if not g.has(part):
		g[part] = Batch.new()
	var batch: Batch = g[part]
	var geometric := (b - a).cross(c - a) + (c - a).cross(d - a)
	var nrm := geometric.normalized() * (1.0 if geometric.dot(normal) > 0.0 else -1.0)
	if geometric.length_squared() < 0.000001:
		nrm = normal.normalized()
	var order := [a, b, c, d] if geometric.dot(normal) < 0.0 else [a, d, c, b]
	var uv_order := uv
	if not uv.is_empty() and geometric.dot(normal) >= 0.0:
		uv_order = [uv[0], uv[3], uv[2], uv[1]]
	var base := batch.verts.size()
	for i in 4:
		batch.verts.append(order[i])
		batch.normals.append(nrm)
		batch.uvs.append(uv_order[i] if not uv_order.is_empty() else Vector2.ZERO)
		batch.colors.append(color)
	batch.indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	if part != "steel":   # rails et panneaux : sans collision (pas de marche pour le joueur ni les roues)
		var faces: PackedVector3Array = g["faces"]
		faces.append_array(PackedVector3Array([order[0], order[1], order[2], order[0], order[2], order[3]]))
		g["faces"] = faces
	stats["triangles"] += 2


func _materials() -> Dictionary:
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_texture = load(TEXTURES.path_join("roads.png"))
	asphalt.roughness = 0.95
	asphalt.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var concrete := StandardMaterial3D.new()
	concrete.albedo_texture = load(TEXTURES.path_join("concrete.png"))
	concrete.roughness = 0.9
	concrete.cull_mode = BaseMaterial3D.CULL_DISABLED
	concrete.uv1_triplanar = true
	concrete.uv1_world_triplanar = true
	concrete.uv1_scale = Vector3(0.25, 0.25, 0.25)
	var steel := StandardMaterial3D.new()
	steel.vertex_color_use_as_albedo = true
	steel.metallic = 0.45
	steel.roughness = 0.45
	steel.cull_mode = BaseMaterial3D.CULL_DISABLED
	var out := {}
	for pair in [["asphalt", asphalt], ["concrete", concrete], ["steel", steel]]:
		var path := OUT.path_join("%s_material.tres" % pair[0])
		ResourceSaver.save(pair[1], path)
		out[pair[0]] = load(path)
	out["roof"] = load(GEN + "/terrain/terrain_material.tres")
	return out


var lamp_meshes := {}
var pole_shape: CylinderShape3D


func _write_scene() -> void:
	var mats := _materials()
	for pair in [["lamp_single", LAMP_SINGLE], ["lamp_double", LAMP_DOUBLE]]:
		var inst: Node = (load(pair[1]) as PackedScene).instantiate()
		lamp_meshes[pair[0]] = (inst.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
		inst.free()
	pole_shape = CylinderShape3D.new()
	pole_shape.radius = 0.15
	pole_shape.height = 6.0
	ResourceSaver.save(pole_shape, OUT.path_join("lamp_pole_shape.tres"))
	pole_shape = load(OUT.path_join("lamp_pole_shape.tres"))
	var root := Node3D.new()
	root.name = "Roads"
	var keys := groups.keys()
	keys.sort()
	for key: Vector2i in keys:
		var g: Dictionary = groups[key]
		var body := StaticBody3D.new()
		body.name = "RoadCell_%02d_%02d" % [key.x + 10, key.y + 10]
		root.add_child(body)
		for part in ["asphalt", "concrete", "roof", "steel"]:
			if not g.has(part):
				continue
			var batch: Batch = g[part]
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = batch.verts
			arrays[Mesh.ARRAY_NORMAL] = batch.normals
			arrays[Mesh.ARRAY_TEX_UV] = batch.uvs
			if part == "roof" or part == "steel":
				arrays[Mesh.ARRAY_COLOR] = batch.colors
			arrays[Mesh.ARRAY_INDEX] = batch.indices
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(0, mats[part])
			var mesh_path := OUT.path_join("%s_%02d_%02d.res" % [part, key.x + 10, key.y + 10])
			ResourceSaver.save(mesh, mesh_path)
			var mi := MeshInstance3D.new()
			mi.name = part.capitalize()
			mi.mesh = load(mesh_path)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = RANGE_CONCRETE if part == "concrete" else (RANGE_STEEL if part == "steel" else RANGE_ASPHALT)
			body.add_child(mi)
		if not (g["faces"] as PackedVector3Array).is_empty():
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(g["faces"])
			shape.backface_collision = true
			var shape_path := OUT.path_join("shape_%02d_%02d.res" % [key.x + 10, key.y + 10])
			ResourceSaver.save(shape, shape_path)
			var cs := CollisionShape3D.new()
			cs.name = "Shape"
			cs.shape = load(shape_path)
			body.add_child(cs)
		for part in ["lamp_single", "lamp_double"]:
			if not g.has(part):
				continue
			# copies du lampadaire fusionnées en un maillage statique (un MultiMesh cuit sans rendu perd ses positions)
			var transforms: Array = g[part]
			var source: Mesh = lamp_meshes[part]
			var src := source.surface_get_arrays(0)
			var src_verts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
			var src_normals: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
			var src_uvs: PackedVector2Array = src[Mesh.ARRAY_TEX_UV] if src[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var src_indices: PackedInt32Array = src[Mesh.ARRAY_INDEX] if src[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(src_verts.size()))
			var verts := PackedVector3Array()
			var normals := PackedVector3Array()
			var uvs := PackedVector2Array()
			var indices := PackedInt32Array()
			for t: Transform3D in transforms:
				var base := verts.size()
				for v in src_verts.size():
					verts.append(t * src_verts[v])
					normals.append((t.basis * src_normals[v]).normalized())
					if not src_uvs.is_empty():
						uvs.append(src_uvs[v])
				for idx in src_indices:
					indices.append(base + idx)
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = normals
			if not uvs.is_empty():
				arrays[Mesh.ARRAY_TEX_UV] = uvs
			arrays[Mesh.ARRAY_INDEX] = indices
			var merged := ArrayMesh.new()
			merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			merged.surface_set_material(0, source.surface_get_material(0))
			var lamp_path := OUT.path_join("%s_%02d_%02d.res" % [part, key.x + 10, key.y + 10])
			ResourceSaver.save(merged, lamp_path)
			var lamps := MeshInstance3D.new()
			lamps.name = "Lamps" + ("Double" if part == "lamp_double" else "")
			lamps.mesh = load(lamp_path)
			lamps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			lamps.visibility_range_end = LAMP_RANGE
			body.add_child(lamps)
			for i in transforms.size():
				var pole := CollisionShape3D.new()
				pole.name = "%s_%d" % [lamps.name, i]
				pole.shape = pole_shape
				pole.position = (transforms[i] as Transform3D).origin + Vector3(0, 3.0, 0)
				body.add_child(pole)
		stats["cellules"] += 1
	var traffic := Node.new()
	traffic.name = "Traffic"
	traffic.set_script(TRAFFIC_SCRIPT)
	traffic.set("graph", load(OUT.path_join("traffic_graph.tres")))
	root.add_child(traffic)
	var walls := StaticBody3D.new()
	walls.name = "TunnelCorridors"
	root.add_child(walls)
	for c in corridors.size():
		var entry: Dictionary = corridors[c]
		var box := BoxShape3D.new()
		box.size = Vector3(1.0, 12.0, float(entry["length"]))
		var cs := CollisionShape3D.new()
		cs.name = "Wall_%d" % c
		cs.shape = box
		cs.position = entry["pos"]
		cs.rotation.y = float(entry["yaw"])
		walls.add_child(cs)
	_pack(root, ROADS_SCENE)


func _write_boundary_gaps() -> void:
	var r := Spec.PLAYABLE
	var gaps: Array = []
	for gap: Dictionary in net.boundary_gaps:
		var p: Vector2 = gap["pos"]
		var side := "north"
		var best := absf(p.y - r.position.y)
		for pair in [["south", absf(p.y - r.end.y)], ["west", absf(p.x - r.position.x)], ["east", absf(p.x - r.end.x)]]:
			if float(pair[1]) < best:
				best = pair[1]
				side = pair[0]
		gaps.append({"side": side, "x": p.x, "z": p.y, "width": float(gap["width"])})
	var f := FileAccess.open(OUT.path_join("boundary_gaps.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(gaps, "\t"))
	f.close()


func _ensure_in_map() -> void:
	var text := FileAccess.get_file_as_string(MAP_SCENE)
	if text.contains(ROADS_SCENE):
		return
	var ext := '[ext_resource type="PackedScene" path="%s" id="4_roads"]\n' % ROADS_SCENE
	var last_ext := text.rfind("[ext_resource")
	var insert_at := text.find("\n", last_ext) + 1
	text = text.substr(0, insert_at) + ext + text.substr(insert_at)
	text = text.strip_edges() + '\n\n[node name="Roads" type="Node3D" parent="." unique_id=1718200424 instance=ExtResource("4_roads")]\n'
	var f := FileAccess.open(MAP_SCENE, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("ROAD_BAKE Map.tscn : Roads ajoutée")


func _pack(root: Node, path: String) -> void:
	_own(root, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	print("ROAD_BAKE_SCENE %s : %s" % [path, error_string(err)])
	root.free()


func _own(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		if child.scene_file_path == "":
			_own(child, root)
