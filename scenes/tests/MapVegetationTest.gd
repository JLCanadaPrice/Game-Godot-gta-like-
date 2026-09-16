extends Node

# Test headless de la végétation de la carte 3D (étape 6), carte seule (Map.tscn) :
#  - instances : arbres détaillés et silhouettes lointaines en même nombre que vegetation.json ;
#  - emplacements : aucun tronc sur une chaussée ou un plateau (marge 1 m), sur un bâtiment des quartiers ou une
#    emprise de lieu, ni à moins de 12 m d'un point de contrôle du garde-fou ;
#  - collision : un rayon horizontal vers un tronc de la zone explorable le touche (échantillon).
#
# Lancer : Godot --headless --fixed-fps 60 --quit-after 3000 res://scenes/tests/MapVegetationTest.tscn

const MAP := preload("res://scenes/world/map/Map.tscn")
const Spec := preload("res://scenes/world/map/MapSpec.gd")
const Network := preload("res://scenes/world/map/tools/RoadNetwork.gd")
const SUMMARY := "res://scenes/world/map/generated/vegetation/vegetation.json"
const LOTS := "res://scenes/world/map/generated/buildings/lots.json"
const PLACES := "res://scenes/world/map/generated/places/places.json"
const BUCKET := 32.0

var _errors: Array[String] = []


func _ready() -> void:
	print("MAP_VEGETATION_BEGIN")
	if not FileAccess.file_exists(SUMMARY):
		_errors.append("vegetation.json absent")
		_finish()
		return
	var summary: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SUMMARY))
	var map := MAP.instantiate()
	add_child(map)
	for k in 3:
		await get_tree().physics_frame
	var vegetation := map.get_node_or_null("Vegetation")
	if vegetation == null:
		_errors.append("Map/Vegetation absent")
		_finish()
		return
	# positions lues dans les données cuites des champs (le rendu factice du mode headless ne garde pas celles des
	# MultiMesh) ; nombres d'instances lus sur les MultiMesh créés au démarrage
	var near: Array[Vector3] = []
	var near_count := 0
	var far_count := 0
	for node in vegetation.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := node as MultiMeshInstance3D
		if String(mmi.get_parent().get_parent().name).begins_with("TreeCell_"):
			near_count += mmi.multimesh.instance_count
		else:
			far_count += mmi.multimesh.instance_count
	for cell in vegetation.get_children():
		if not String(cell.name).begins_with("TreeCell_"):
			continue
		var field := cell.get_node("Field")
		for data: PackedFloat32Array in field.get("instance_data"):
			for o in range(0, data.size(), 16):
				near.append(Vector3(data[o + 9], data[o + 10], data[o + 11]))
	var expected := int(summary["arbres"])
	print("MAP_VEGETATION_INSTANCES %d arbres attendus : %d détaillés (%d positions cuites), %d silhouettes" % [expected, near_count, near.size(), far_count])
	if near_count != expected or near.size() != expected or far_count != expected or expected == 0:
		_errors.append("instances : %d détaillées, %d silhouettes pour %d arbres" % [near_count, far_count, expected])
	_check_places(near)
	await _check_trunks(near)
	_finish()


func _check_places(trees: Array[Vector3]) -> void:
	var net := Network.new()
	net.build()
	var buckets := {}
	for rb in net.ribbons:
		for p: Vector3 in rb.points:
			_add(buckets, Vector2(p.x, p.z), float(rb.width) * 0.5)
	for pad: Dictionary in net.pads:
		var c: Vector3 = pad["center"]
		var radius := 0.0
		for p: Vector3 in pad["rim"]:
			radius = maxf(radius, Vector2(p.x - c.x, p.z - c.z).length())
		_add(buckets, Vector2(c.x, c.z), radius)
	var rects: Array = []   # [centre, droite, avant, demi-tailles]
	for lot: Dictionary in JSON.parse_string(FileAccess.get_file_as_string(LOTS)):
		var yaw := float(lot["yaw"])
		var front := Vector2(sin(yaw), cos(yaw))
		rects.append([Vector2(float(lot["x"]), float(lot["z"])), Vector2(-front.y, front.x), front, Vector2(float(lot["size"][0]), float(lot["size"][2])) * 0.5])
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PLACES))
	for fp: Dictionary in data["footprints"]:
		var lo := Vector2(INF, INF)
		var hi := -lo
		for q: Array in fp["poly"]:
			lo = lo.min(Vector2(float(q[0]), float(q[1])))
			hi = hi.max(Vector2(float(q[0]), float(q[1])))
		rects.append([(lo + hi) * 0.5, Vector2(1, 0), Vector2(0, 1), (hi - lo) * 0.5])
	var on_road := 0
	var on_building := 0
	var near_spot := 0
	var first := ""
	for t in trees:
		var q := Vector2(t.x, t.z)
		var key := Vector2i(floori(q.x / BUCKET), floori(q.y / BUCKET))
		var hit_road := false
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				for e: Vector3 in buckets.get(key + Vector2i(dx, dz), []):
					hit_road = hit_road or Vector2(e.x, e.y).distance_to(q) < e.z + 1.0
		if hit_road:
			on_road += 1
			if first == "":
				first = "route en (%.0f, %.0f)" % [q.x, q.y]
		for r: Array in rects:
			var d: Vector2 = q - r[0]
			var h: Vector2 = r[3]
			if absf(d.dot(r[1])) < h.x and absf(d.dot(r[2])) < h.y:
				on_building += 1
				if first == "":
					first = "bâtiment ou lieu en (%.0f, %.0f)" % [q.x, q.y]
				break
		for spot: Dictionary in Spec.GATE_SPOTS:
			if (spot["pos"] as Vector2).distance_to(q) < 12.0:
				near_spot += 1
	print("MAP_VEGETATION_PLACES %d arbres sur une chaussée, %d sur un bâtiment ou un lieu, %d près d'un point de contrôle %s" % [on_road, on_building, near_spot, first])
	if on_road + on_building + near_spot > 0:
		_errors.append("arbres mal placés : %d chaussée, %d bâtiment/lieu, %d point de contrôle, premier %s" % [on_road, on_building, near_spot, first])


func _add(buckets: Dictionary, p: Vector2, half: float) -> void:
	var key := Vector2i(floori(p.x / BUCKET), floori(p.y / BUCKET))
	if not buckets.has(key):
		buckets[key] = []
	buckets[key].append(Vector3(p.x, p.y, half))


func _check_trunks(trees: Array[Vector3]) -> void:
	var space := get_viewport().world_3d.direct_space_state
	var checked := 0
	var missed := 0
	var first := ""
	var step := maxi(1, trees.size() / 400)
	for k in range(0, trees.size(), step):
		var t := trees[k]
		if not Spec.PLAYABLE.has_point(Vector2(t.x, t.z)):
			continue
		checked += 1
		var from := t + Vector3(2.0, 1.4, 0.0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, t + Vector3(0, 1.4, 0), 1))
		if hit.is_empty() or not String((hit["collider"] as Node).name).begins_with("Trunks"):
			missed += 1
			if first == "":
				first = "(%.0f, %.1f, %.0f) %s" % [t.x, t.y, t.z, "rien" if hit.is_empty() else String((hit["collider"] as Node).name)]
	print("MAP_VEGETATION_TRUNKS %d troncs sondés, %d sans collision %s" % [checked, missed, first])
	if checked == 0 or missed > checked / 50:
		_errors.append("%d troncs sur %d sans collision, premier %s" % [missed, checked, first])


func _finish() -> void:
	print("MAP_VEGETATION_RESULT %s %s" % ["OK" if _errors.is_empty() else "FAIL", " | ".join(_errors)])
	get_tree().quit(0 if _errors.is_empty() else 1)
