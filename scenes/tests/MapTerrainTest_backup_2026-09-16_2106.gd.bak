extends Node

# Test headless du terrain et de l'eau de la carte 3D (étape 1 et suivantes) :
#  - couverture : rayon vertical tous les 16 m sur toute la zone explorable, aucun trou dans le sol ;
#  - raccord au centre-ville : juste à l'extérieur du sol des districts, le terrain est au niveau de leur sol ;
#  - pentes : répartition des pentes entre points voisins (hors lit et berges de la rivière) ;
#  - eau : le joueur posé au milieu de la rivière, du lac et du bassin existant passe en nage.
#
# Lancer : Godot --headless --fixed-fps 60 --quit-after 20000 res://scenes/tests/MapTerrainTest.tscn

const WORLD := preload("res://scenes/world/World.tscn")
const Spec := preload("res://scenes/world/map/MapSpec.gd")
const Model := preload("res://scenes/world/map/tools/TerrainModel.gd")
const STEP := 16.0

var _errors: Array[String] = []
var _player: CharacterBody3D


func _ready() -> void:
	print("MAP_TERRAIN_BEGIN")
	var world := WORLD.instantiate()
	add_child(world)
	for spawner_name in ["CarSpawner", "NpcSpawner"]:
		world.get_node(spawner_name).set_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if world.get_node_or_null("Map") == null:
		_errors.append("Map absente de World.tscn")
	_check_coverage_and_slopes()
	_check_downtown_seam()
	await _check_swimming()
	print("MAP_TERRAIN_RESULT %s %s" % ["OK" if _errors.is_empty() else "FAIL", " | ".join(_errors)])
	get_tree().quit(0 if _errors.is_empty() else 1)


func _check_coverage_and_slopes() -> void:
	var model := Model.new()
	var nx := int(Spec.PLAYABLE.size.x / STEP)
	var nz := int(Spec.PLAYABLE.size.y / STEP)
	var grid := PackedFloat32Array()
	grid.resize((nx + 1) * (nz + 1))
	var terrain := PackedFloat32Array()   # hauteur du seul terrain (tuiles), pour les pentes
	terrain.resize(grid.size())
	var misses := 0
	var first_miss := ""
	for j in nz + 1:
		for i in nx + 1:
			var p := Spec.PLAYABLE.position + Vector2(i, j) * STEP
			var hit := _hit(p)
			var y: float = -INF if hit.is_empty() else (hit["position"] as Vector3).y
			grid[j * (nx + 1) + i] = y
			terrain[j * (nx + 1) + i] = y if not hit.is_empty() and String((hit["collider"] as Node).name).begins_with("Chunk_") else -INF
			if y == -INF:
				misses += 1
				if first_miss == "":
					first_miss = "(%.0f, %.0f)" % [p.x, p.y]
	grid = terrain
	var slopes: Array[float] = []
	for j in nz:
		for i in nx:
			var p := Spec.PLAYABLE.position + Vector2(i, j) * STEP
			if model.river_info(p).x < 45.0 or Model.HARBOR_WATER.grow(20.0).has_point(p) or Spec.DOWNTOWN.grow(24.0).has_point(p):
				continue
			var a := grid[j * (nx + 1) + i]
			var b := grid[j * (nx + 1) + i + 1]
			var c := grid[(j + 1) * (nx + 1) + i]
			if a == -INF or b == -INF or c == -INF:
				continue
			slopes.append(maxf(absf(b - a), absf(c - a)) / STEP * 100.0)
	slopes.sort()
	var p50 := slopes[slopes.size() / 2]
	var p99 := slopes[int(slopes.size() * 0.99)]
	var max_slope := slopes[slopes.size() - 1]
	print("MAP_TERRAIN_COVERAGE %d rayons tous les %.0f m, %d sans sol %s | pentes : médiane %.1f %%, 99e centile %.1f %%, max %.1f %%"
			% [grid.size(), STEP, misses, first_miss, p50, p99, max_slope])
	if misses > 0:
		_errors.append("%d trous dans le sol, premier en %s" % [misses, first_miss])
	if p99 > 45.0:
		_errors.append("relief trop raide (99e centile %.0f %%)" % p99)


func _check_downtown_seam() -> void:
	var r := Spec.DOWNTOWN.grow(3.0)
	var samples: Array[Vector2] = []
	var x := r.position.x
	while x <= r.end.x:
		samples.append(Vector2(x, r.position.y))
		samples.append(Vector2(x, r.end.y))
		x += 8.0
	var z := r.position.y
	while z <= r.end.y:
		samples.append(Vector2(r.position.x, z))
		samples.append(Vector2(r.end.x, z))
		z += 8.0
	var worst := 0.0
	var bad := 0
	var on_roads := 0
	for p in samples:
		if Spec.HARBOR.grow(12.0).has_point(p):
			continue
		var hit := _hit(p)
		# chaussées de la carte qui sortent du centre-ville : leur hauteur suit leur propre profil (MapRoadsTest)
		if not hit.is_empty() and String((hit["collider"] as Node).name).begins_with("RoadCell_"):
			on_roads += 1
			continue
		var y := -INF if hit.is_empty() else (hit["position"] as Vector3).y
		var dev := absf(y) if y != -INF else 99.0
		worst = maxf(worst, dev)
		if dev > 0.5:
			bad += 1
			if bad <= 5:
				print("MAP_TERRAIN_SEAM_OFF (%.0f, %.0f) sol %.2f sur %s" % [p.x, p.y, y, "rien" if hit.is_empty() else String((hit["collider"] as Node).name)])
	print("MAP_TERRAIN_SEAM %d points au bord du centre-ville (%d sur les routes de la carte), écart max au niveau du sol %.2f m, %d au-delà de 0,5 m" % [samples.size(), on_roads, worst, bad])
	if bad > 0:
		_errors.append("%d points de raccord au centre-ville décalés" % bad)


func _check_swimming() -> void:
	var model := Model.new()
	var places := [
		["rivière face au centre-ville", Vector2(-1150, -24), Spec.WATER_LEVEL],
		["rivière au sud", Vector2(-760, 652), Spec.WATER_LEVEL],
		["Willow Lake", Vector2(-1760, -90), float(model.lake_levels["willow_lake"])],
		["bassin existant", Vector2(-250, -575), Spec.WATER_LEVEL],
	]
	for place: Array in places:
		var p: Vector2 = place[1]
		_player.velocity = Vector3.ZERO
		_player.global_position = Vector3(p.x, float(place[2]) + 1.5, p.y)
		for k in 45:
			await get_tree().physics_frame
		var swimming := bool(_player.get("_swimming"))
		print("MAP_TERRAIN_SWIM %s (%.0f, %.0f) : nage %s, y %.2f" % [place[0], p.x, p.y, swimming, _player.global_position.y])
		if not swimming:
			_errors.append("pas de nage : " + String(place[0]))


func _ground(p: Vector2) -> float:
	var hit := _hit(p)
	return -INF if hit.is_empty() else (hit["position"] as Vector3).y


func _hit(p: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(Vector3(p.x, 300.0, p.y), Vector3(p.x, -60.0, p.y), 1)
	query.exclude = [_player.get_rid()]
	return _player.get_world_3d().direct_space_state.intersect_ray(query)
