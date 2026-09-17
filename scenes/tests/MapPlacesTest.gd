extends Node

# Test headless des lieux de la carte 3D (étape 5), monde complet (World.tscn, spawners coupés) :
#  - ancres : un noeud Map/Places/Place_<id> par lieu de MapSpec.POIS, métadonnées et entrée (places.json identique) ;
#  - entrée : sol sous l'entrée, route (plateau ou ruban) à moins de 15 m hors centre-ville, trottoir ou chaussée du
#    centre-ville à moins de 25 m ;
#  - routes et trottoirs dégagés : aucun élément d'un lieu sur une chaussée de la carte (rayons sur les rubans proches)
#    ni sur le réseau piéton du centre-ville, ni dans leur gabarit ;
#  - collisions : chaque bâtiment posé par un lieu arrête un rayon descendant.
#
# Lancer : Godot --headless --fixed-fps 60 --quit-after 3000 res://scenes/tests/MapPlacesTest.tscn

const WORLD := preload("res://scenes/world/World.tscn")
const Spec := preload("res://scenes/world/map/MapSpec.gd")
const Network := preload("res://scenes/world/map/tools/RoadNetwork.gd")
const PLACES_JSON := "res://scenes/world/map/generated/places/places.json"
const NEAR := 160.0
const GAUGE := 4.5
const WALK_GAUGE := 2.2

var _errors: Array[String] = []


func _ready() -> void:
	print("MAP_PLACES_BEGIN")
	var world := WORLD.instantiate()
	add_child(world)
	for spawner_name in ["CarSpawner", "NpcSpawner"]:
		var spawner := world.get_node_or_null(spawner_name)
		if spawner != null:
			spawner.set_process(false)
	for k in 4:
		await get_tree().physics_frame
	var places_node := world.get_node_or_null("Map/Places")
	if places_node == null or not FileAccess.file_exists(PLACES_JSON):
		_errors.append("Map/Places ou places.json absent")
		_finish()
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PLACES_JSON))
	var net := Network.new()
	net.build()
	var space := get_viewport().world_3d.direct_space_state
	_check_anchors(places_node, data)
	_check_entrances(space, net, data)
	_check_roads_clear(space, net, data)
	_check_walks_clear(space, world, data)
	_check_buildings(space, places_node)
	_finish()


func _check_anchors(places_node: Node, data: Dictionary) -> void:
	var missing: PackedStringArray = []
	for poi: Dictionary in Spec.POIS:
		var node := places_node.get_node_or_null("Place_" + String(poi["id"]))
		if node == null or String(node.get_meta("place_id", "")) != poi["id"] or String(node.get_meta("display_name", "")) != poi["name"] or node.get_node_or_null("Entrance") == null:
			missing.append(poi["id"])
	var listed: Array = data.get("places", [])
	print("MAP_PLACES_ANCHORS %d lieux dans MapSpec, %d ancres, %d dans places.json, manquants : %s" % [Spec.POIS.size(), places_node.get_child_count(), listed.size(), missing])
	if not missing.is_empty() or listed.size() != Spec.POIS.size():
		_errors.append("ancres manquantes ou incomplètes : %s" % ", ".join(missing))


func _check_entrances(space: PhysicsDirectSpaceState3D, net: Network, data: Dictionary) -> void:
	var parts: PackedStringArray = []
	for place: Dictionary in data["places"]:
		var e := Vector3(float(place["entrance"][0]), float(place["entrance"][1]), float(place["entrance"][2]))
		var ground := _ray(space, e + Vector3.UP * 20.0, e + Vector3.DOWN * 20.0)
		var ground_ok := not ground.is_empty() and absf((ground["position"] as Vector3).y - e.y) < 1.5
		var access := INF
		var q := Vector2(e.x, e.z)
		if Spec.DOWNTOWN.grow(50.0).has_point(q):
			for r in range(0, 26, 1):
				for k in 16:
					var s := q + Vector2(cos(TAU * k / 16.0), sin(TAU * k / 16.0)) * r
					var hit := _ray(space, Vector3(s.x, e.y + 10.0, s.y), Vector3(s.x, e.y - 10.0, s.y))
					if not hit.is_empty():
						var n := String((hit["collider"] as Node).name)
						if n.begins_with("Sidewalk") or n.begins_with("Road") or String((hit["collider"] as Node).get_path()).contains("/Downtown/Streets/"):
							access = minf(access, float(r))
				if access < INF:
					break
		else:
			for rb in net.ribbons:
				if rb.kind in ["arterial", "carriageway", "ramp"]:
					for p: Vector3 in rb.points:
						access = minf(access, maxf(0.0, Vector2(p.x, p.z).distance_to(q) - float(rb.width) * 0.5))
			for pad: Dictionary in net.pads:
				var c: Vector3 = pad["center"]
				var radius := 0.0
				for rim: Vector3 in pad["rim"]:
					radius = maxf(radius, Vector2(rim.x - c.x, rim.z - c.z).length())
				access = minf(access, maxf(0.0, Vector2(c.x, c.z).distance_to(q) - radius))
		var limit := 25.0 if Spec.DOWNTOWN.grow(50.0).has_point(q) else 15.0
		parts.append("%s sol %s accès %.0f m" % [place["id"], "oui" if ground_ok else "NON", access])
		if not ground_ok or access > limit:
			_errors.append("entrée de %s : sol %s, accès à %.0f m" % [place["id"], ground_ok, access])
	print("MAP_PLACES_ENTRANCES " + " | ".join(parts))


func _check_roads_clear(space: PhysicsDirectSpaceState3D, net: Network, data: Dictionary) -> void:
	var centers: Array[Vector2] = []
	for place: Dictionary in data["places"]:
		centers.append(Vector2(float(place["center"][0]), float(place["center"][1])))
		centers.append(Vector2(float(place["entrance"][0]), float(place["entrance"][2])))
	var samples := 0
	var blocked := 0
	var first := ""
	for rb in net.ribbons:
		if not rb.mesh or rb.kind in ["median", "rail"]:
			continue
		var pts: PackedVector3Array = rb.points
		for k in pts.size():
			var p := pts[k]
			var near := false
			for c in centers:
				near = near or c.distance_to(Vector2(p.x, p.z)) < NEAR
			if not near:
				continue
			samples += 1
			var down := _ray(space, p + Vector3.UP * GAUGE, p + Vector3.DOWN * 1.0)
			var up := _ray(space, p + Vector3.UP * 0.3, p + Vector3.UP * GAUGE)
			for hit: Dictionary in [down, up]:
				if not hit.is_empty() and _in_places(hit["collider"]) and (hit["position"] as Vector3).y > p.y + 0.25:
					blocked += 1
					if first == "":
						first = "%s (%.0f, %.1f, %.0f) par %s" % [rb.id, p.x, p.y, p.z, (hit["collider"] as Node).get_path()]
					break
	print("MAP_PLACES_ROADS %d points de chaussée près des lieux, %d encombrés %s" % [samples, blocked, first])
	if blocked > 0:
		_errors.append("%d points de chaussée encombrés par un lieu, premier %s" % [blocked, first])


func _check_walks_clear(space: PhysicsDirectSpaceState3D, world: Node, data: Dictionary) -> void:
	var ped := world.get_node_or_null("PedGraph")
	var circuit := world.get_node_or_null("Circuit")
	var centers: Array[Vector2] = []
	for place: Dictionary in data["places"]:
		centers.append(Vector2(float(place["center"][0]), float(place["center"][1])))
	var checked := 0
	var blocked := 0
	var first := ""
	for graph in [ped, circuit]:
		if graph == null:
			continue
		for p: Vector3 in graph.nodes:
			var near := false
			for c in centers:
				near = near or c.distance_to(Vector2(p.x, p.z)) < 90.0
			if not near:
				continue
			checked += 1
			var hit := _ray(space, p + Vector3.UP * WALK_GAUGE, p + Vector3.DOWN * 0.5)
			if not hit.is_empty() and _in_places(hit["collider"]) and (hit["position"] as Vector3).y > p.y + 0.3:
				blocked += 1
				if first == "":
					first = "(%.0f, %.1f, %.0f) par %s" % [p.x, p.y, p.z, (hit["collider"] as Node).get_path()]
	print("MAP_PLACES_WALKS %d noeuds piétons et de circulation près des lieux, %d encombrés %s" % [checked, blocked, first])
	if blocked > 0:
		_errors.append("%d noeuds du centre-ville encombrés par un lieu, premier %s" % [blocked, first])


func _check_buildings(space: PhysicsDirectSpaceState3D, places_node: Node) -> void:
	var checked := 0
	var missing: PackedStringArray = []
	for place in places_node.get_children():
		for child in place.get_children():
			var mi := child as MeshInstance3D
			if mi == null or not String(mi.name).contains("_"):
				continue   # maillages fusionnés du lieu (Paint, Asphalt...) : surfaces, pas des bâtiments
			checked += 1
			var box := mi.global_transform * mi.get_aabb()
			var c := box.get_center()
			var hit := _ray(space, Vector3(c.x, box.end.y + 20.0, c.z), Vector3(c.x, box.position.y - 5.0, c.z))
			if hit.is_empty() or not _in_places(hit["collider"]):
				missing.append(String(mi.name))
	print("MAP_PLACES_BUILDINGS %d bâtiments de lieux, sans collision : %s" % [checked, missing])
	if not missing.is_empty():
		_errors.append("bâtiments sans collision : %s" % ", ".join(missing))


func _in_places(node: Object) -> bool:
	return node is Node and String((node as Node).get_path()).contains("/Places/")


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))


func _finish() -> void:
	print("MAP_PLACES_RESULT %s %s" % ["OK" if _errors.is_empty() else "FAIL", " | ".join(_errors)])
	get_tree().quit(0 if _errors.is_empty() else 1)
