extends SceneTree

# Étape 0 : contrôle de cohérence du plan de masse (MapSpec) et aperçu vu du dessus.
#  - réseau : noeuds existants, graphe d'un seul tenant (la grille du centre-ville relie ses noeuds de raccord),
#    longueurs par classe et par axe ;
#  - eau : franchissements de la rivière (ponts attendus), aucune route dans un lac ;
#  - emprises : aucune route dans le bassin, et dans le centre-ville seulement le raccord d'un noeud de grille ;
#  - croisements sans noeud commun (ouvrages dénivelés) et voisinages trop serrés entre tronçons ;
#  - rayons de courbure, lieux et points de contrôle hors de l'eau et des chaussées ;
#  - distances depuis le croisement des 4 districts.
# Aperçu : scenes/world/map/preview/plan_de_masse.png (0,25 px/m) ; avec --reference=<png>, une version
# superposée à l'image de référence est écrite dans --out=<dossier> (hors projet : elle porte les noms d'origine).
#
# Lancer : Godot --headless --path <projet> --script res://scenes/world/map/tools/MapSpecCheck.gd [-- --reference=... --out=...]

const Spec := preload("res://scenes/world/map/MapSpec.gd")
const PREVIEW_DIR := "res://scenes/world/map/preview"
const PX_PER_M := 0.25
const HALF_WIDTH := {"highway": 14.0, "arterial": 7.0, "access": 4.0, "dirt": 3.0}
const MIN_RADIUS := {"highway": 180.0, "arterial": 45.0, "access": 12.0, "dirt": 10.0}
const CROSSROADS := Vector2(-460, -172)
const EXPECTED_RIVER_CROSSINGS := ["an_o2", "a1_w", "a2_w", "as_o2", "a10"]

var _errors: PackedStringArray = []
var _warnings: PackedStringArray = []


func _initialize() -> void:
	var args := _user_args()
	_check_nodes_and_graph()
	_check_lengths()
	_check_water()
	_check_footprints()
	_check_crossings()
	_check_radii()
	_check_places()
	_print_distances()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEW_DIR))
	var ignore := PREVIEW_DIR.path_join(".gdignore")
	if not FileAccess.file_exists(ignore):
		FileAccess.open(ignore, FileAccess.WRITE).store_string("")
	var img := _render(null)
	img.save_png(PREVIEW_DIR.path_join("plan_de_masse.png"))
	print("SPEC_PREVIEW %s (%dx%d px, %.2f px/m)" % [PREVIEW_DIR.path_join("plan_de_masse.png"), img.get_width(), img.get_height(), PX_PER_M])
	if args.has("reference") and args.has("out"):
		var ref := Image.load_from_file(args["reference"])
		if ref != null:
			var overlay := _render(ref)
			var out_path := String(args["out"]).path_join("plan_de_masse_sur_reference.png")
			overlay.save_png(out_path)
			print("SPEC_OVERLAY %s" % out_path)
	for w in _warnings:
		print("SPEC_WARNING " + w)
	for e in _errors:
		print("SPEC_ERROR " + e)
	print("SPEC_CHECK_RESULT %s (%d erreur(s), %d avertissement(s))" % ["OK" if _errors.is_empty() else "FAIL", _errors.size(), _warnings.size()])
	quit(0 if _errors.is_empty() else 1)


# --- contrôles --------------------------------------------------------------------------------------------------
func _check_nodes_and_graph() -> void:
	var adj := {}
	for node_id: String in Spec.NODES:
		adj[node_id] = []
	var used := {}
	for road: Dictionary in Spec.ROADS:
		for key in ["from", "to"]:
			if not Spec.NODES.has(road[key]):
				_errors.append("%s : noeud %s inconnu" % [road["id"], road[key]])
				return
			used[road[key]] = true
		adj[road["from"]].append(road["to"])
		adj[road["to"]].append(road["from"])
	var grid: Array = []
	for node_id: String in Spec.NODES:
		if not used.has(node_id):
			_errors.append("noeud %s relié à aucun tronçon" % node_id)
		if Spec.NODES[node_id]["kind"] == "grid":
			grid.append(node_id)
	for a in grid:   # la grille existante du centre-ville relie tous ses noeuds de raccord
		for b in grid:
			if a != b:
				adj[a].append(b)
	var seen := {grid[0]: true}
	var stack: Array = [grid[0]]
	while not stack.is_empty():
		for n in adj[stack.pop_back()]:
			if not seen.has(n):
				seen[n] = true
				stack.append(n)
	var missing: Array = []
	for node_id: String in Spec.NODES:
		if not seen.has(node_id):
			missing.append(node_id)
	print("SPEC_GRAPH %d noeuds, %d tronçons, %d noeuds de raccord au centre-ville, %d noeud(s) isolé(s) %s"
			% [Spec.NODES.size(), Spec.ROADS.size(), grid.size(), missing.size(), missing])
	if not missing.is_empty():
		_errors.append("réseau coupé : " + str(missing))


func _check_lengths() -> void:
	var by_class := {}
	var by_axis := {}
	for road: Dictionary in Spec.ROADS:
		var length := _length(Spec.road_polyline(road))
		by_class[road["class"]] = float(by_class.get(road["class"], 0.0)) + length
		if road.has("axis"):
			by_axis[Spec.AXES[road["axis"]]] = float(by_axis.get(Spec.AXES[road["axis"]], 0.0)) + length
	var parts: PackedStringArray = []
	for k in by_class:
		parts.append("%s %.1f km" % [k, by_class[k] / 1000.0])
	var axes: PackedStringArray = []
	for k in by_axis:
		axes.append("%s %.1f km" % [k, by_axis[k] / 1000.0])
	print("SPEC_LENGTHS %s | axes : %s | voie ferrée %.1f km" % [", ".join(parts), ", ".join(axes), _length(PackedVector2Array(Spec.RAIL)) / 1000.0])


func _check_water() -> void:
	var crossings: PackedStringArray = []
	var crossing_ids: Array = []
	for road: Dictionary in Spec.ROADS:
		var spans := _water_spans(Spec.road_polyline(road))
		for span: Vector2 in spans:
			crossings.append("%s (%.0f m)" % [road["id"], span.y - span.x])
			crossing_ids.append(road["id"])
		for p in _samples(Spec.road_polyline(road), 5.0):
			for lake: Dictionary in Spec.LAKES:
				if _in_ellipse(p, lake["center"], lake["radii"] + Vector2.ONE * HALF_WIDTH[road["class"]]):
					_errors.append("%s traverse %s" % [road["id"], lake["id"]])
					break
	var rail_spans := _water_spans(PackedVector2Array(Spec.RAIL))
	print("SPEC_WATER franchissements de la rivière : %s | voie ferrée : %d" % [", ".join(crossings), rail_spans.size()])
	for expected in EXPECTED_RIVER_CROSSINGS:
		if not crossing_ids.has(expected):
			_errors.append("pont attendu absent : " + expected)
	for id in crossing_ids:
		if not EXPECTED_RIVER_CROSSINGS.has(id):
			_errors.append("franchissement imprévu : " + String(id))
	if rail_spans.size() != 1:
		_errors.append("la voie ferrée devrait franchir la rivière une fois (%d)" % rail_spans.size())


func _check_footprints() -> void:
	for road: Dictionary in Spec.ROADS:
		var poly := Spec.road_polyline(road)
		var from_grid: bool = Spec.NODES[road["from"]]["kind"] == "grid"
		var start := Spec.node_pos(road["from"])
		for p in _samples(poly, 4.0):
			if from_grid and p.distance_to(start) < 90.0:
				continue   # prolongement de la rue existante jusqu'au bord du centre-ville
			if Spec.HARBOR.grow(3.0).has_point(p):   # axe à 3 m au moins du quai (la chaussée peut longer son bord)
				_errors.append("%s passe dans le bassin (%.0f, %.0f)" % [road["id"], p.x, p.y])
				break
			if Spec.DOWNTOWN.has_point(p):
				_errors.append("%s entre dans le centre-ville (%.0f, %.0f)" % [road["id"], p.x, p.y])
				break
		if not Spec.TERRAIN.has_point(Spec.node_pos(road["to"])):
			_errors.append("%s sort du terrain" % road["id"])


func _check_crossings() -> void:
	var grade: PackedStringArray = []
	var roads: Array = Spec.ROADS
	for i in roads.size():
		var a: Dictionary = roads[i]
		var pa := Spec.road_polyline(a)
		for j in range(i + 1, roads.size()):
			var b: Dictionary = roads[j]
			var shared := _shared_nodes(a, b)
			var pb := Spec.road_polyline(b)
			for hit in _intersections(pa, pb):
				var near_shared := false
				for node_id in shared:
					if hit.distance_to(Spec.node_pos(node_id)) < 60.0:
						near_shared = true
				if not near_shared:
					grade.append("%s × %s (%.0f, %.0f)" % [a["id"], b["id"], hit.x, hit.y])
			if shared.is_empty():
				var gap := _min_gap(pa, pb, HALF_WIDTH[a["class"]] + HALF_WIDTH[b["class"]] + 6.0)
				if gap.x >= 0.0 and _intersections(pa, pb).is_empty():
					_warnings.append("%s et %s à %.0f m l'un de l'autre sans se croiser (%.0f, %.0f)" % [a["id"], b["id"], gap.x, gap.y, gap.z])
	for road: Dictionary in roads:
		for hit in _intersections(Spec.road_polyline(road), PackedVector2Array(Spec.RAIL)):
			grade.append("%s × voie ferrée (%.0f, %.0f)" % [road["id"], hit.x, hit.y])
	print("SPEC_CROSSINGS %d croisements dénivelés ou passages à niveau : %s" % [grade.size(), "; ".join(grade)])


func _check_radii() -> void:
	for road: Dictionary in Spec.ROADS:
		var poly := Spec.road_polyline(road)
		for k in range(1, poly.size() - 1):
			var d1 := poly[k] - poly[k - 1]
			var d2 := poly[k + 1] - poly[k]
			var turn := absf(d1.angle_to(d2))
			if turn < 0.02:
				continue
			var reach := minf(d1.length(), d2.length()) * 0.5
			var radius := reach / tan(turn * 0.5)
			if radius < MIN_RADIUS[road["class"]]:
				_warnings.append("%s : virage au point %d (%.0f, %.0f) de rayon %.0f m possible au plus (%.0f conseillé)"
						% [road["id"], k, poly[k].x, poly[k].y, radius, MIN_RADIUS[road["class"]]])


func _check_places() -> void:
	for poi: Dictionary in Spec.POIS:
		var p: Vector2 = poi["pos"]
		if not Spec.PLAYABLE.has_point(p):
			_errors.append("%s hors de la zone explorable" % poi["id"])
		if _river_distance(p) < 0.0:
			_errors.append("%s dans la rivière" % poi["id"])
		if poi["kind"] == "airport" or poi["kind"] == "plaza":
			continue
		var half: Vector2 = poi["size"] * 0.5
		for road: Dictionary in Spec.ROADS:
			if road["class"] == "dirt" or road["class"] == "access":
				continue
			for q in _samples(Spec.road_polyline(road), 4.0):
				if absf(q.x - p.x) < half.x + HALF_WIDTH[road["class"]] and absf(q.y - p.y) < half.y + HALF_WIDTH[road["class"]]:
					_errors.append("%s empiète sur %s (%.0f, %.0f)" % [poi["id"], road["id"], q.x, q.y])
					break
	for spot: Dictionary in Spec.GATE_SPOTS:
		if _river_distance(spot["pos"]) < 10.0 and not spot.get("bridge", false):
			_errors.append("point de contrôle dans l'eau : " + String(spot["name"]))


func _print_distances() -> void:
	var parts: PackedStringArray = []
	for poi: Dictionary in Spec.POIS:
		parts.append("%s %.2f km" % [poi["name"], CROSSROADS.distance_to(poi["pos"]) / 1000.0])
	print("SPEC_DISTANCES depuis le croisement des 4 districts : " + ", ".join(parts))


# --- géométrie 2D -----------------------------------------------------------------------------------------------
func _samples(poly: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in poly.size() - 1:
		var a := poly[k]
		var b := poly[k + 1]
		var n := maxi(1, ceili(a.distance_to(b) / step))
		for s in n:
			out.append(a.lerp(b, float(s) / n))
	out.append(poly[poly.size() - 1])
	return out


func _length(poly: PackedVector2Array) -> float:
	var total := 0.0
	for k in poly.size() - 1:
		total += poly[k].distance_to(poly[k + 1])
	return total


# Distance signée au bord de la rivière : négative dans l'eau.
func _river_distance(p: Vector2) -> float:
	var best := INF
	var river: Array = Spec.RIVER
	for k in river.size() - 1:
		var a: Vector2 = river[k][0]
		var b: Vector2 = river[k + 1][0]
		var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		var half := lerpf(river[k][1], river[k + 1][1], t) * 0.5
		best = minf(best, p.distance_to(a.lerp(b, t)) - half)
	return best


# Portions d'une polyligne dans la rivière : [abscisse d'entrée, abscisse de sortie] en m.
func _water_spans(poly: PackedVector2Array) -> Array[Vector2]:
	var spans: Array[Vector2] = []
	var inside := false
	var start := 0.0
	var s := 0.0
	var prev := poly[0]
	for p in _samples(poly, 4.0):
		s += prev.distance_to(p)
		prev = p
		var wet := _river_distance(p) < 0.0
		if wet and not inside:
			start = s
		elif not wet and inside:
			spans.append(Vector2(start, s))
		inside = wet
	if inside:
		spans.append(Vector2(start, s))
	return spans


func _in_ellipse(p: Vector2, center: Vector2, radii: Vector2) -> bool:
	var d := (p - center) / radii
	return d.length_squared() <= 1.0


func _shared_nodes(a: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	for key_a in ["from", "to"]:
		for key_b in ["from", "to"]:
			if a[key_a] == b[key_b]:
				out.append(a[key_a])
	return out


func _intersections(pa: PackedVector2Array, pb: PackedVector2Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in pa.size() - 1:
		for j in pb.size() - 1:
			var hit: Variant = Geometry2D.segment_intersects_segment(pa[i], pa[i + 1], pb[j], pb[j + 1])
			if hit != null:
				out.append(hit)
	return out


# Plus petit écart entre deux polylignes s'il est sous `limit` : Vector3(écart, x, z), sinon x = −1.
func _min_gap(pa: PackedVector2Array, pb: PackedVector2Array, limit: float) -> Vector3:
	var best := Vector3(-1, 0, 0)
	for p in _samples(pa, 10.0):
		for j in pb.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(p, pb[j], pb[j + 1])
			var d := p.distance_to(q)
			if d < limit and (best.x < 0.0 or d < best.x):
				best = Vector3(d, p.x, p.y)
	return best


# --- aperçu -----------------------------------------------------------------------------------------------------
const COLORS := {
	"land": Color("dfe5d0"), "suburb": Color("ecd78f"), "residential": Color("e8cf7d"), "mixed": Color("e5b9a4"),
	"industrial": Color("c9bcdc"), "airport": Color("cbd1d3"), "farmland": Color("e8e4bf"), "forest": Color("9dba8e"),
	"downtown": Color("d8d1c3"), "water": Color("6ea5c3"), "highway": Color("d89b1d"), "arterial": Color("5f6b67"),
	"access": Color("8a7a60"), "dirt": Color("a08658"), "rail": Color("33403c"), "poi": Color("b8342a"),
	"spot": Color("c0268f"), "grid": Color("9f9483"), "frame": Color("3a4643"),
}


func _render(reference: Image) -> Image:
	var w := int(Spec.TERRAIN.size.x * PX_PER_M)
	var h := int(Spec.TERRAIN.size.y * PX_PER_M)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var alpha := 1.0
	if reference != null:
		var scaled := reference.duplicate() as Image
		scaled.convert(Image.FORMAT_RGBA8)
		scaled.resize(int(reference.get_width() * 2.6 * PX_PER_M), int(reference.get_height() * 2.6 * PX_PER_M), Image.INTERPOLATE_BILINEAR)
		img.fill(Color.BLACK)
		img.blit_rect(scaled, Rect2i(Vector2i.ZERO, scaled.get_size()), _px(Vector2(-2174, -1480)))
		alpha = 0.5
	else:
		img.fill(COLORS["land"])
	if reference == null:
		for zone: Dictionary in Spec.ZONES:
			_fill_polygon(img, Spec.zone_polygon(zone), COLORS[zone["type"]], 1.0)
		_draw_downtown_grid(img)
	for p in _samples(Spec.river_polyline(), 4.0):
		_disc(img, p, _river_half_width(p), COLORS["water"], alpha)
	for lake: Dictionary in Spec.LAKES:
		_ellipse(img, lake["center"], lake["radii"], COLORS["water"], alpha)
	if reference == null:
		_fill_rect_world(img, Rect2(-500, -644, 500, 150), COLORS["water"])
	_polyline(img, PackedVector2Array(Spec.RAIL), 1.5, COLORS["rail"], alpha, 14.0)
	for cls in ["dirt", "access", "arterial", "highway"]:
		for road: Dictionary in Spec.ROADS:
			if road["class"] == cls:
				_polyline(img, Spec.road_polyline(road), HALF_WIDTH[cls], COLORS[cls], alpha, 0.0)
	for node_id: String in Spec.NODES:
		var node: Dictionary = Spec.NODES[node_id]
		if node["kind"] in ["interchange", "diamond", "roundabout"]:
			_ring(img, node["pos"], 30.0 if node["kind"] == "interchange" else 18.0, COLORS["frame"])
	for poi: Dictionary in Spec.POIS:
		_disc(img, poi["pos"], 22.0, COLORS["poi"], 1.0)
	for spot: Dictionary in Spec.GATE_SPOTS:
		_disc(img, spot["pos"], 10.0, COLORS["spot"], 1.0)
	_frame(img, Spec.PLAYABLE, COLORS["frame"])
	return img


func _px(p: Vector2) -> Vector2i:
	return Vector2i(int((p.x - Spec.TERRAIN.position.x) * PX_PER_M), int((p.y - Spec.TERRAIN.position.y) * PX_PER_M))


func _river_half_width(p: Vector2) -> float:
	return _river_distance(p) * 0.0 + _nearest_river_width(p) * 0.5


func _nearest_river_width(p: Vector2) -> float:
	var river: Array = Spec.RIVER
	var best := INF
	var width := 150.0
	for k in river.size() - 1:
		var a: Vector2 = river[k][0]
		var b: Vector2 = river[k + 1][0]
		var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		var d := p.distance_to(a.lerp(b, t))
		if d < best:
			best = d
			width = lerpf(river[k][1], river[k + 1][1], t)
	return width


func _blend(img: Image, x: int, y: int, color: Color, alpha: float) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, color if alpha >= 1.0 else img.get_pixel(x, y).lerp(color, alpha))


func _disc(img: Image, center: Vector2, radius_m: float, color: Color, alpha: float) -> void:
	var c := _px(center)
	var r := maxi(1, int(radius_m * PX_PER_M))
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if x * x + y * y <= r * r:
				_blend(img, c.x + x, c.y + y, color, alpha)


func _ellipse(img: Image, center: Vector2, radii: Vector2, color: Color, alpha: float) -> void:
	var c := _px(center)
	var rx := maxi(1, int(radii.x * PX_PER_M))
	var ry := maxi(1, int(radii.y * PX_PER_M))
	for y in range(-ry, ry + 1):
		for x in range(-rx, rx + 1):
			if float(x * x) / (rx * rx) + float(y * y) / (ry * ry) <= 1.0:
				_blend(img, c.x + x, c.y + y, color, alpha)


func _ring(img: Image, center: Vector2, radius_m: float, color: Color) -> void:
	var c := _px(center)
	var r := radius_m * PX_PER_M
	for k in 64:
		var a := TAU * k / 64.0
		_blend(img, c.x + int(cos(a) * r), c.y + int(sin(a) * r), color, 1.0)


func _polyline(img: Image, poly: PackedVector2Array, half_width_m: float, color: Color, alpha: float, dash_m: float) -> void:
	var r := maxi(0, int(half_width_m * PX_PER_M))
	var s := 0.0
	for p in _samples(poly, 1.0 / PX_PER_M):
		s += 1.0 / PX_PER_M
		if dash_m > 0.0 and fmod(s, dash_m * 2.0) > dash_m:
			continue
		var c := _px(p)
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				_blend(img, c.x + x, c.y + y, color, alpha)


func _fill_rect_world(img: Image, rect: Rect2, color: Color) -> void:
	var a := _px(rect.position)
	var b := _px(rect.end)
	img.fill_rect(Rect2i(a, b - a), color)


func _fill_polygon(img: Image, poly: PackedVector2Array, color: Color, alpha: float) -> void:
	var pts: Array[Vector2] = []
	for p in poly:
		var q := _px(p)
		pts.append(Vector2(q))
	var y0 := int(pts.map(func(v): return v.y).min())
	var y1 := int(pts.map(func(v): return v.y).max())
	for y in range(maxi(y0, 0), mini(y1 + 1, img.get_height())):
		var xs: Array[float] = []
		for k in pts.size():
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[(k + 1) % pts.size()]
			if (a.y <= y and b.y > y) or (b.y <= y and a.y > y):
				xs.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			for x in range(maxi(int(xs[k]), 0), mini(int(xs[k + 1]) + 1, img.get_width())):
				_blend(img, x, y, color, alpha)


func _draw_downtown_grid(img: Image) -> void:
	for k in 13:
		var x := -892.0 + 72.0 * k
		_polyline(img, PackedVector2Array([Vector2(x, -460), Vector2(x, 116)]), 2.0, COLORS["grid"], 1.0, 0.0)
	for k in 9:
		var z := -460.0 + 72.0 * k
		_polyline(img, PackedVector2Array([Vector2(-892, z), Vector2(-28, z)]), 2.0, COLORS["grid"], 1.0, 0.0)


func _frame(img: Image, rect: Rect2, color: Color) -> void:
	var a := _px(rect.position)
	var b := _px(rect.end)
	for x in range(a.x, b.x + 1):
		_blend(img, x, a.y, color, 1.0)
		_blend(img, x, b.y, color, 1.0)
	for y in range(a.y, b.y + 1):
		_blend(img, a.x, y, color, 1.0)
		_blend(img, b.x, y, color, 1.0)


func _user_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			out[arg.substr(2, arg.find("=") - 2)] = arg.substr(arg.find("=") + 1)
	return out
