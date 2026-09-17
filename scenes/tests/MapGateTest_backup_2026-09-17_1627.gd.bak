extends Node

# Garde-fou des étapes de la carte 3D, lancé après chaque étape avant son commit :
#  1. World.tscn chargée dans l'arbre : joueur, caméra active, graphes de circulation et culler présents ;
#  2. au point de départ, tourné vers la ville : marche avant 2 s puis sprint 1,5 s, déplacement mesuré, pas de chute ;
#  3. points de contrôle : deux trottoirs du centre-ville, puis MapSpec.GATE_SPOTS dès que la carte existe (routes,
#     ponts, quartiers) : joueur posé au-dessus du sol, il doit y atterrir puis marcher.
# Spawners coupés : aucune voiture ni PNJ ne gêne la marche.
#
# Lancer : Godot --headless --fixed-fps 60 --quit-after 60000 res://scenes/tests/MapGateTest.tscn

const WORLD := preload("res://scenes/world/World.tscn")
const SPEC_PATH := "res://scenes/world/map/MapSpec.gd"
const CITY_SPOTS := [
	{"name": "trottoir du croisement des 4 districts", "pos": Vector2(-452.0, -179.5), "yaw": -90.0},
	{"name": "trottoir de l'avenue sud du centre-ville", "pos": Vector2(-290.0, 108.5), "yaw": -90.0},
]
const WALK_SECONDS := 2.0
const SPRINT_SECONDS := 1.5
const MIN_WALK := 6.0         # m en 2 s de marche (5 m/s attendus)
const MIN_SPOT_WALK := 4.0    # m sur un point de contrôle (obstacle possible en fin de trajet)

var _errors: Array[String] = []
var _player: CharacterBody3D


func _ready() -> void:
	print("MAP_GATE_BEGIN")
	var world := WORLD.instantiate()
	add_child(world)
	for spawner_name in ["CarSpawner", "NpcSpawner"]:
		var spawner := world.get_node_or_null(spawner_name)
		if spawner != null:
			spawner.set_process(false)
	await _frames(10)
	for node_path in ["Circuit", "PedGraph", "SimulationCuller"]:
		if world.get_node_or_null(node_path) == null:
			_errors.append(node_path + " absent")
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _player == null:
		_errors.append("joueur absent")
		_finish()
		return
	if get_viewport().get_camera_3d() == null:
		_errors.append("aucune caméra active")
	await _spawn_walk()
	var spots: Array = CITY_SPOTS.duplicate()
	if ResourceLoader.exists(SPEC_PATH):
		var constants: Dictionary = (load(SPEC_PATH) as GDScript).get_script_constant_map()
		for spot: Dictionary in constants.get("GATE_SPOTS", []):
			if float(spot.get("min_stage", 0.0)) <= float(constants.get("BUILT_STAGE", 0.0)):
				spots.append(spot)
	for spot: Dictionary in spots:
		await _spot_walk(spot)
	print("MAP_GATE_SPOTS %d points de contrôle testés" % spots.size())
	_finish()


func _spawn_walk() -> void:
	_player.rotation.y = PI   # dos au bassin, face à la ville (+Z)
	await _frames(30)
	var start := _player.global_position
	await _hold(["move_forward"], WALK_SECONDS)
	var walked := _flat(_player.global_position - start)
	var mid := _player.global_position
	await _hold(["move_forward", "sprint"], SPRINT_SECONDS)
	var sprinted := _flat(_player.global_position - mid)
	var ok := walked >= MIN_WALK and sprinted > walked and _player.global_position.y > start.y - 3.0
	print("MAP_GATE_SPAWN départ %s | marche %.1f m en %.1f s | sprint %.1f m en %.1f s | y %.2f -> %.2f | %s"
			% [start.snapped(Vector3.ONE * 0.1), walked, WALK_SECONDS, sprinted, SPRINT_SECONDS, start.y, _player.global_position.y, "OK" if ok else "ÉCHEC"])
	if not ok:
		_errors.append("déplacement au point de départ")


func _spot_walk(spot: Dictionary) -> void:
	var p: Vector2 = spot["pos"]
	var ground := _ground_at(p)
	if ground == INF:
		print("MAP_GATE_SPOT %s (%.0f, %.0f) : pas de sol | ÉCHEC" % [spot["name"], p.x, p.y])
		_errors.append("pas de sol : " + String(spot["name"]))
		return
	_player.velocity = Vector3.ZERO
	_player.global_position = Vector3(p.x, ground + 1.2, p.y)
	_player.rotation.y = deg_to_rad(float(spot.get("yaw", 0.0)))
	await _frames(45)
	var landed := _player.is_on_floor() and absf(_player.global_position.y - ground) < 2.5
	var start := _player.global_position
	await _hold(["move_forward"], WALK_SECONDS)
	var walked := _flat(_player.global_position - start)
	var fell := _player.global_position.y < ground - 4.0
	var ok := landed and walked >= MIN_SPOT_WALK and not fell
	print("MAP_GATE_SPOT %s (%.0f, %.0f) sol %.2f m | posé %s | marche %.1f m | %s"
			% [spot["name"], p.x, p.y, ground, landed, walked, "OK" if ok else "ÉCHEC"])
	if not ok:
		_errors.append("point de contrôle : " + String(spot["name"]))


func _ground_at(p: Vector2) -> float:
	var query := PhysicsRayQueryParameters3D.create(Vector3(p.x, 400.0, p.y), Vector3(p.x, -150.0, p.y), 1)
	query.exclude = [_player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	return INF if hit.is_empty() else (hit["position"] as Vector3).y


func _hold(actions: Array, seconds: float) -> void:
	for action in actions:
		Input.action_press(action)
	await _frames(roundi(seconds * Engine.physics_ticks_per_second))
	for action in actions:
		Input.action_release(action)
	await _frames(5)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _finish() -> void:
	print("MAP_GATE_RESULT %s %s" % ["OK" if _errors.is_empty() else "FAIL", " | ".join(_errors)])
	get_tree().quit(0 if _errors.is_empty() else 1)
