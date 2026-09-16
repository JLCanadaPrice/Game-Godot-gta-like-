extends Node

# Test headless des quartiers de la carte 3D (étape 4), carte seule (Map.tscn) :
#  - lots (generated/buildings/lots.json) : emprise hors des routes du modèle RoadNetwork (marge au bord des rubans et
#    des plateaux), hors de l'eau, du centre-ville et des lieux réservés, sans chevauchement entre lots ;
#  - affichage : les BuildingField ont créé une instance GPU par lot ;
#  - collision : un rayon descendant au centre de chaque bâtiment touche sa collision au-dessus du sol ;
#  - terrain aplani : sous chaque emprise (quatre points intérieurs), le sol est au niveau du lot.
#
# Lancer : Godot --headless --fixed-fps 60 --quit-after 3000 res://scenes/tests/MapDistrictsTest.tscn

const MAP := preload("res://scenes/world/map/Map.tscn")
const Spec := preload("res://scenes/world/map/MapSpec.gd")
const Network := preload("res://scenes/world/map/tools/RoadNetwork.gd")
const LOTS := "res://scenes/world/map/generated/buildings/lots.json"
const ROAD_CLEAR := 1.0            # m libres entre l'emprise et le bord d'un ruban
const BUCKET := 32.0
const GROUND_TOLERANCE := 0.5
const TRIMESH := ["Business_GasStation"]

var _errors: Array[String] = []


func _ready() -> void:
	print("MAP_DISTRICTS_BEGIN")
	if not FileAccess.file_exists(LOTS):
		_errors.append("lots.json absent")
		_finish()
		return
	var lots: Array = JSON.parse_string(FileAccess.get_file_as_string(LOTS))
	var map := MAP.instantiate()
	add_child(map)
	for k in 3:
		await get_tree().physics_frame
	var net := Network.new()
	net.build()
	_check_layout(net, lots)
	_check_instances(map, lots)
	_check_physics(lots)
	_finish()


func _rect(lot: Dictionary) -> Dictionary:
	var yaw := float(lot["yaw"])
	var front := Vector2(sin(yaw), cos(yaw))
	return {"c": Vector2(float(lot["x"]), float(lot["z"])), "f": front, "r": Vector2(-front.y, front.x),
			"h": Vector2(float(lot["size"][0]) * 0.5, float(lot["size"][2]) * 0.5)}


func _rect_distance(rect: Dictionary, p: Vector2) -> float:
	var d: Vector2 = p - rect["c"]
	var h: Vector2 = rect["h"]
	return Vector2(maxf(0.0, absf(d.dot(rect["r"])) - h.x), maxf(0.0, absf(d.dot(rect["f"])) - h.y)).length()


func _corners(rect: Dictionary) -> PackedVector2Array:
	var c: Vector2 = rect["c"]
	var r: Vector2 = rect["r"] * float(rect["h"].x)
	var f: Vector2 = rect["f"] * float(rect["h"].y)
	return PackedVector2Array([c + r + f, c - r + f, c - r - f, c + r - f])


func _check_layout(net: Network, lots: Array) -> void:
	var buckets := {}
	var samples := 0
	for rb in net.ribbons:
		var pts: PackedVector3Array = rb.points
		for k in pts.size():
			var p := Vector2(pts[k].x, pts[k].z)
			_bucket_add(buckets, p, float(rb.width) * 0.5)
			samples += 1
			if k > 0:
				_bucket_add(buckets, (p + Vector2(pts[k - 1].x, pts[k - 1].z)) * 0.5, float(rb.width) * 0.5)
	var pad_polys: Array[PackedVector2Array] = []
	for pad: Dictionary in net.pads:
		var poly := PackedVector2Array()
		for p: Vector3 in pad["rim"]:
			poly.append(Vector2(p.x, p.z))
		pad_polys.append(poly)
		for k in poly.size():
			var a := poly[k]
			var b := poly[(k + 1) % poly.size()]
			var n := maxi(1, ceili(a.distance_to(b) / 2.0))
			for s in n:
				_bucket_add(buckets, a.lerp(b, float(s) / n), 0.0)
	var on_road := 0
	var in_water := 0
	var reserved := 0
	var first := ""
	var rects: Array[Dictionary] = []
	for lot: Dictionary in lots:
		var rect := _rect(lot)
		rects.append(rect)
		var c: Vector2 = rect["c"]
		var reach := (rect["h"] as Vector2).length() + 20.0
		var worst := INF
		for bj in range(floori((c.y - reach) / BUCKET), floori((c.y + reach) / BUCKET) + 1):
			for bi in range(floori((c.x - reach) / BUCKET), floori((c.x + reach) / BUCKET) + 1):
				for entry: Vector3 in buckets.get(Vector2i(bi, bj), []):
					worst = minf(worst, _rect_distance(rect, Vector2(entry.x, entry.y)) - entry.z)
		var corners := _corners(rect)
		for poly in pad_polys:
			for q in corners:
				if Geometry2D.is_point_in_polygon(q, poly):
					worst = -1.0
		if worst < ROAD_CLEAR:
			on_road += 1
			if first == "":
				first = "%s (%.0f, %.0f) à %.1f m d'une chaussée" % [lot["name"], c.x, c.y, worst]
		var wet := net.is_water(c)
		var blocked := Spec.DOWNTOWN.has_point(c)
		for q in corners:
			wet = wet or net.is_water(q)
			blocked = blocked or Spec.DOWNTOWN.has_point(q)
			for poi: Dictionary in Spec.POIS:
				var half: Vector2 = poi["size"] * 0.5
				var d: Vector2 = q - poi["pos"]
				blocked = blocked or (absf(d.x) < half.x and absf(d.y) < half.y)
		if wet:
			in_water += 1
		if blocked:
			reserved += 1
	var overlaps := 0
	for a in rects.size():
		for b in range(a + 1, rects.size()):
			var ra: Dictionary = rects[a]
			var rbb: Dictionary = rects[b]
			if (ra["c"] as Vector2).distance_to(rbb["c"]) > (ra["h"] as Vector2).length() + (rbb["h"] as Vector2).length():
				continue
			if _rects_overlap(ra, rbb):
				overlaps += 1
	print("MAP_DISTRICTS_LAYOUT %d lots, %d échantillons de chaussée : %d trop près d'une chaussée %s, %d dans l'eau, %d sur un lieu réservé, %d chevauchements"
			% [lots.size(), samples, on_road, first, in_water, reserved, overlaps])
	if lots.is_empty():
		_errors.append("aucun lot")
	if on_road > 0:
		_errors.append("%d lots trop près d'une chaussée, premier %s" % [on_road, first])
	if in_water > 0:
		_errors.append("%d lots dans l'eau" % in_water)
	if reserved > 0:
		_errors.append("%d lots sur le centre-ville ou un lieu réservé" % reserved)
	if overlaps > 0:
		_errors.append("%d chevauchements de lots" % overlaps)


func _bucket_add(buckets: Dictionary, p: Vector2, half_width: float) -> void:
	var key := Vector2i(floori(p.x / BUCKET), floori(p.y / BUCKET))
	if not buckets.has(key):
		buckets[key] = []
	buckets[key].append(Vector3(p.x, p.y, half_width))


# Axes séparateurs de deux rectangles orientés.
func _rects_overlap(a: Dictionary, b: Dictionary) -> bool:
	var ca := _corners(a)
	var cb := _corners(b)
	for axis: Vector2 in [a["r"], a["f"], b["r"], b["f"]]:
		var amin := INF
		var amax := -INF
		var bmin := INF
		var bmax := -INF
		for q in ca:
			amin = minf(amin, q.dot(axis))
			amax = maxf(amax, q.dot(axis))
		for q in cb:
			bmin = minf(bmin, q.dot(axis))
			bmax = maxf(bmax, q.dot(axis))
		if amax <= bmin or bmax <= amin:
			return false
	return true


func _check_instances(map: Node, lots: Array) -> void:
	var total := 0
	var fields := 0
	for node in map.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := node as MultiMeshInstance3D
		if mmi.multimesh != null and mmi.multimesh.mesh != null:
			total += mmi.multimesh.instance_count
			fields += 1
	print("MAP_DISTRICTS_INSTANCES %d instances GPU dans %d MultiMesh pour %d lots" % [total, fields, lots.size()])
	if total != lots.size():
		_errors.append("%d instances GPU pour %d lots" % [total, lots.size()])


func _check_physics(lots: Array) -> void:
	var space := get_viewport().world_3d.direct_space_state
	var no_roof := 0
	var bad_ground := 0
	var first_roof := ""
	var first_ground := ""
	var worst := 0.0
	for lot: Dictionary in lots:
		var rect := _rect(lot)
		var c: Vector2 = rect["c"]
		var base := float(lot["base"])
		var hit := _ray(space, Vector3(c.x, base + float(lot["size"][1]) + 30.0, c.y), Vector3(c.x, base - 5.0, c.y))
		var body: Node = null if hit.is_empty() else hit["collider"]
		if body == null or not String(body.get_parent().name).begins_with("BuildingCell_") or (hit["position"] as Vector3).y < base + 2.0:
			no_roof += 1
			if first_roof == "":
				first_roof = "%s (%.0f, %.0f) : %s" % [lot["name"], c.x, c.y, "rien" if body == null else "%s à %.1f m" % [body.name, (hit["position"] as Vector3).y]]
		if lot["name"] in TRIMESH:
			continue
		for sx: float in [-0.35, 0.35]:
			for sz: float in [-0.35, 0.35]:
				var h: Vector2 = rect["h"]
				var q: Vector2 = c + (rect["r"] as Vector2) * h.x * sx + (rect["f"] as Vector2) * h.y * sz
				var ground := _ray(space, Vector3(q.x, base + 1.0, q.y), Vector3(q.x, base - 4.0, q.y))
				var gap := INF if ground.is_empty() else absf((ground["position"] as Vector3).y - base)
				worst = maxf(worst, gap if gap != INF else 99.0)
				if gap > GROUND_TOLERANCE:
					bad_ground += 1
					if first_ground == "":
						first_ground = "%s (%.0f, %.0f) sol %s pour %.2f" % [lot["name"], q.x, q.y, "absent" if ground.is_empty() else "%.2f" % (ground["position"] as Vector3).y, base]
	print("MAP_DISTRICTS_PHYSICS toits sans collision %d %s | points d'emprise hors niveau %d %s | pire écart %.2f m"
			% [no_roof, first_roof, bad_ground, first_ground, worst])
	if no_roof > 0:
		_errors.append("%d bâtiments sans collision, premier %s" % [no_roof, first_roof])
	if bad_ground > 0:
		_errors.append("%d points d'emprise hors niveau, premier %s" % [bad_ground, first_ground])


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))


func _finish() -> void:
	print("MAP_DISTRICTS_RESULT %s %s" % ["OK" if _errors.is_empty() else "FAIL", " | ".join(_errors)])
	get_tree().quit(0 if _errors.is_empty() else 1)
