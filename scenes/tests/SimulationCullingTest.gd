extends Node

# Test headless du SimulationCuller dans la vraie carte, avec une caméra de test et le joueur figé servant de repère
# de distance. Spawners coupés : seules les entités du test circulent.
#  1. voiture arrêtée au feu rouge, loin et hors champ -> endormie, position et état figés pendant que son feu passe
#     au vert ; réveillée par la distance (joueur à 20 m) : relit le feu et repart sans saut de position ;
#  2. voiture endormie au rouge, réveillée par la vue (caméra dans l'axe de sa rue, loin du joueur) alors que le feu
#     est encore rouge : reste à sa ligne d'arrêt, puis repart au vert ;
#  3. voiture dans le champ mais cachée par les bâtiments (caméra dans la rue parallèle) : endormie et le reste ;
#     vue depuis sa rue : réveillée ;
#  4. file : voiture visible qui arrive derrière une voiture endormie hors champ -> la voiture de tête est réveillée
#     (Car._keep_awake) et les deux repartent au vert ;
#  5. PNJ loin et hors champ : endormi (process, physique, animation), immobile, jamais supprimé ; réveil -> repart.
#
# Lancer : Godot --headless --fixed-fps 60 --quit-after 9000 res://scenes/tests/SimulationCullingTest.tscn

const WORLD := preload("res://scenes/world/World.tscn")
const META := &"sim_sleeping"

var _world: Node
var _circuit: CircuitPath
var _graph: PathGraph
var _culler
var _car_spawner
var _npc_spawner
var _player: Node3D
var _cam: Camera3D
var _spawn_pos: Vector3
var _used_nodes := []
var _errors: Array[String] = []


func _ready() -> void:
	print("SIM_CULLING_BEGIN")
	_world = WORLD.instantiate()
	add_child(_world)
	_circuit = _world.get_node("Circuit")
	_graph = _world.get_node("PedGraph")
	_culler = _world.get_node("SimulationCuller")
	_car_spawner = _world.get_node("CarSpawner")
	_npc_spawner = _world.get_node("NpcSpawner")
	_car_spawner.set_process(false)
	_npc_spawner.set_process(false)
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_player.process_mode = Node.PROCESS_MODE_DISABLED   # simple repère de distance pour le culler
	_spawn_pos = _player.global_position
	_cam = Camera3D.new()
	add_child(_cam)
	_look_at_sea()
	_cam.make_current()
	_culler.enabled = false
	await get_tree().physics_frame
	await _car_wake_by_distance()
	await _car_wake_by_view()
	await _car_hidden_by_buildings()
	await _queue_behind_sleeping_car()
	await _npc_freeze()
	print("SIM_CULLING_RESULT %s %s" % ["OK" if _errors.is_empty() else "FAIL", " | ".join(_errors)])
	get_tree().quit(0 if _errors.is_empty() else 1)


func _car_wake_by_distance() -> void:
	var a := await _stopped_car_at_red("scénario 1")
	if a.is_empty():
		return
	var car = a.car
	var remaining: float = float(a.len) - car._edge_progress
	_culler.enabled = true
	var asleep := await _wait_until(func(): return _sleeping(car) and not car.is_physics_processing(), 1.0)
	var pos: Vector3 = car.global_position
	var state := [car._edge_progress, car._ai_speed, car._cur_edge, car._from_node, car._committed_to_stop]
	_set_light(a, true)   # le feu passe au vert pendant le sommeil
	await _wait(3.0)
	var frozen: bool = is_instance_valid(car) and _sleeping(car) and car.global_position.distance_to(pos) < 0.001 \
			and [car._edge_progress, car._ai_speed, car._cur_edge, car._from_node, car._committed_to_stop] == state
	_player.global_position = car.global_position + car.global_transform.basis.x * 20.0
	var woke := await _wait_until(func(): return not _sleeping(car) and car.is_physics_processing(), 0.5)
	var max_step := 0.0
	var last: Vector3 = car.global_position
	var t := 0.0
	while t < 4.0 and is_instance_valid(car):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		max_step = maxf(max_step, car.global_position.distance_to(last))
		last = car.global_position
	var departed: bool = is_instance_valid(car) and car._from_node == a.node
	print("SIM_CULLING_1 carrefour %d à %.0f m du joueur | arrêt au rouge à %.1f m du centre | endormie : %s | figée 3 s pendant le passage au vert : %s | réveil par la distance (20 m) : %s | repart et franchit le carrefour : %s | plus grand pas par frame %.2f m"
			% [a.node, a.dist, remaining, asleep, frozen, woke, departed, max_step])
	if not (asleep and frozen and woke and departed and max_step < 0.6):
		_errors.append("scénario 1 : rouge -> sommeil -> vert -> réveil par la distance")
	_free(car)


func _car_wake_by_view() -> void:
	var a := await _stopped_car_at_red("scénario 2")
	if a.is_empty():
		return
	var car = a.car
	_culler.enabled = true
	var asleep := await _wait_until(func(): return _sleeping(car), 1.0)
	await _wait(2.0)
	var pos: Vector3 = car.global_position
	_street_view(a, pos, 60.0)
	var woke := await _wait_until(func(): return not _sleeping(car), 0.5)
	var dist := pos.distance_to(_player.global_position)
	await _wait(2.0)
	var held: bool = car._ai_speed < 0.1 and car.global_position.distance_to(pos) < 0.3 and car._committed_to_stop
	_set_light(a, true)
	var departed := await _wait_until(func(): return car._ai_speed > 3.0, 4.0)
	print("SIM_CULLING_2 carrefour %d | endormie au rouge : %s | réveil par la vue (caméra dans sa rue, à %.0f m du joueur) : %s | reste arrêtée au rouge 2 s après le réveil : %s | repart au vert : %s"
			% [a.node, asleep, dist, woke, held, departed])
	if not (asleep and woke and dist > 50.0 and held and departed):
		_errors.append("scénario 2 : sommeil au rouge -> réveil par la vue au rouge -> vert")
	_free(car)


func _car_hidden_by_buildings() -> void:
	var a := await _stopped_car_at_red("scénario 3")
	if a.is_empty():
		return
	var car = a.car
	var pos: Vector3 = car.global_position
	if not _hide_camera_behind_buildings(a, pos):
		_errors.append("scénario 3 : aucun point de vue caché par les bâtiments trouvé")
		_free(car)
		return
	_culler.enabled = true
	var asleep := await _wait_until(func(): return _sleeping(car), 1.0)
	var flicker := false
	var t := 0.0
	while t < 2.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		flicker = flicker or not _sleeping(car)
	_street_view(a, pos, 60.0)
	var woke := await _wait_until(func(): return not _sleeping(car), 0.5)
	print("SIM_CULLING_3 carrefour %d | dans le champ mais derrière les bâtiments : endormie %s, sans réveil pendant 2 s %s | vue depuis sa rue : réveillée %s"
			% [a.node, asleep, not flicker, woke])
	if not (asleep and not flicker and woke):
		_errors.append("scénario 3 : occlusion par les bâtiments")
	_free(car)


func _queue_behind_sleeping_car() -> void:
	var a := await _stopped_car_at_red("scénario 4")
	if a.is_empty():
		return
	var lead = a.car
	var old_fov := _cam.fov
	var old_margin: float = _culler.view_margin
	_cam.fov = 2.0                 # caméra étroite au-dessus de la suiveuse : la voiture de tête reste hors champ
	_culler.view_margin = 0.0
	_hover_camera(a, _circuit.sample_offset(a.edge, a.from, 8.0, 2.0))
	_culler.enabled = true
	var lead_asleep := await _wait_until(func(): return _sleeping(lead), 1.0)
	var follower = _spawn_car(a, 8.0)
	var waited := false
	var lead_woke := false
	var t := 0.0
	while t < 12.0 and not lead_woke:
		_hover_camera(a, follower.global_position)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		waited = waited or (follower.global_position.distance_to(lead.global_position) < 14.0 and follower._ai_speed < 1.0)
		lead_woke = waited and not _sleeping(lead)
	_set_light(a, true)
	var both_go := false
	t = 0.0
	while t < 6.0 and not both_go:
		_hover_camera(a, follower.global_position)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		both_go = lead._ai_speed > 3.0 and follower._ai_speed > 2.0
	print("SIM_CULLING_4 carrefour %d | voiture de tête endormie hors champ : %s | la suiveuse visible s'arrête derrière : %s | tête réveillée par la file : %s | les deux repartent au vert : %s"
			% [a.node, lead_asleep, waited, lead_woke, both_go])
	if not (lead_asleep and waited and lead_woke and both_go):
		_errors.append("scénario 4 : file derrière une voiture endormie")
	_cam.fov = old_fov
	_culler.view_margin = old_margin
	_free(lead)
	_free(follower)


func _npc_freeze() -> void:
	_player.global_position = _spawn_pos
	_look_at_sea()
	_culler.enabled = false
	var node := _pick_ped_node()
	var npc = (_npc_spawner.spawn_scene as PackedScene).instantiate()
	if "faction" in npc:
		npc.faction = &"civil"
	_npc_spawner.add_child(npc)
	npc.setup(_graph, node, 0.0, 0.0, 50)
	var start: Vector3 = npc.global_position
	await _wait(1.5)
	var walked: float = npc.global_position.distance_to(start)
	_culler.enabled = true
	var asleep := await _wait_until(func(): return _sleeping(npc), 1.0)
	var anim: AnimationPlayer = npc._anim
	var pos: Vector3 = npc.global_position
	await _wait(3.0)
	var frozen: bool = is_instance_valid(npc) and _sleeping(npc) and not npc.is_physics_processing() and not npc.is_processing() \
			and npc.global_position.distance_to(pos) < 0.001 and (anim == null or not anim.active)
	_player.global_position = pos + Vector3(15, 0, 15)
	var woke := await _wait_until(func(): return not _sleeping(npc), 0.5)
	var p2: Vector3 = npc.global_position
	await _wait(1.5)
	var resumed: bool = is_instance_valid(npc) and npc.global_position.distance_to(p2) > 1.0 and (anim == null or anim.active)
	print("SIM_CULLING_5 PNJ : marche %.1f m avant | endormi (process + physique + animation) : %s | immobile et conservé 3 s : %s | réveil par la distance : %s | repart : %s"
			% [walked, asleep, frozen, woke, resumed])
	if not (walked > 1.0 and asleep and frozen and woke and resumed):
		_errors.append("scénario 5 : PNJ")


# Voiture posée 45 m avant un carrefour à feu loin du joueur et derrière la caméra, feu forcé au rouge, culler coupé
# le temps qu'elle s'arrête à sa ligne. Renvoie l'approche complétée de "car", ou {} en cas d'échec.
func _stopped_car_at_red(label: String) -> Dictionary:
	_player.global_position = _spawn_pos
	_look_at_sea()
	_culler.enabled = false
	var a := _pick_approach()
	if a.is_empty():
		_errors.append(label + " : aucune approche de feu loin et hors champ")
		return {}
	_set_light(a, false)
	var car = _spawn_car(a, float(a.len) - 45.0)
	var stopped := await _wait_until(func(): return car._committed_to_stop and car._ai_speed < 0.05, 15.0)
	if not stopped:
		_errors.append(label + " : la voiture ne s'arrête pas au rouge")
		_free(car)
		return {}
	a["car"] = car
	return a


func _spawn_car(a: Dictionary, progress: float) -> Variant:
	var car = (_car_spawner.spawn_scene as PackedScene).instantiate()
	_car_spawner.add_child(car)
	car.setup(_circuit, a.from, 12.0, 2.0, 30)
	car._cur_edge = a.edge
	car._from_node = a.from
	car._edge_progress = progress
	car._snap_to_path()
	return car


# Feu de l'approche forcé rouge ou vert pour longtemps (même état que celui lu par Car.gd et TrafficLight.gd).
func _set_light(a: Dictionary, green: bool) -> void:
	var phase: int = _circuit._light_edge_phase[a.edge]
	_circuit._light_state[a.node] = {"phase": phase if green else 1 - phase, "timer": 1000.0, "green": true}


# Approche de carrefour à feu la plus proche qui soit à plus de 120 m du joueur et bien derrière la caméra de départ.
func _pick_approach() -> Dictionary:
	var eye := _player.global_position
	var fwd := -_cam.global_transform.basis.z
	var best := {}
	for n in _circuit._light_state.keys():
		if n in _used_nodes:
			continue
		var center: Vector3 = _circuit.nodes[n]
		for e in _circuit.node_edges(n):
			if _circuit.is_edge_one_way(e) or _circuit.edge_length(e) < 60.0:
				continue
			var from := _circuit.edge_other_node(e, n)
			var start := _circuit.sample(e, from, _circuit.edge_length(e) - 45.0)
			if minf(start.distance_to(eye), center.distance_to(eye)) < 120.0 or maxf((start - eye).dot(fwd), (center - eye).dot(fwd)) > -60.0:
				continue
			if best.is_empty() or center.distance_to(eye) < float(best.dist):
				best = {"node": n, "edge": e, "from": from, "len": _circuit.edge_length(e), "dist": center.distance_to(eye)}
	if not best.is_empty():
		_used_nodes.append(best.node)
	return best


func _pick_ped_node() -> int:
	var eye := _player.global_position
	var fwd := -_cam.global_transform.basis.z
	var best := -1
	for i in _graph.nodes.size():
		var p: Vector3 = _graph.nodes[i]
		if p.distance_to(eye) > 120.0 and (p - eye).dot(fwd) < -60.0 and (best < 0 or p.distance_to(eye) < _graph.nodes[best].distance_to(eye)):
			best = i
	return best


func _travel_dir(a: Dictionary) -> Vector3:
	return _circuit.direction_at(a.edge, a.from, float(a.len) - 20.0)


# Caméra à 3 m de haut dans la rue de la voiture, `back` mètres derrière elle, regard sur elle.
func _street_view(a: Dictionary, target: Vector3, back: float) -> void:
	_cam.global_position = target - _travel_dir(a) * back + Vector3.UP * 3.0
	_cam.look_at(target + Vector3.UP, Vector3.UP)


# Caméra dans une rue parallèle, voiture au milieu du champ mais derrière les bâtiments (vérifié par un rayon).
func _hide_camera_behind_buildings(a: Dictionary, target: Vector3) -> bool:
	var dir := _travel_dir(a)
	var side := dir.cross(Vector3.UP).normalized()
	var aim := target + Vector3.UP
	var space := _cam.get_world_3d().direct_space_state
	for s in [1.0, -1.0]:
		for along in [0.0, -20.0, 20.0]:
			_cam.global_position = target + side * (72.0 * s) + dir * along + Vector3.UP * 3.0
			_cam.look_at(aim, Vector3.UP)
			var inside := true
			for plane in _cam.get_frustum():
				inside = inside and plane.distance_to(target) < -2.0
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(_cam.global_position, aim, 1))
			if inside and not hit.is_empty() and _cam.global_position.distance_to(hit.position) < _cam.global_position.distance_to(aim) - 5.0:
				return true
	return false


# Caméra 40 m au-dessus du point, écran orienté dans le sens de la rue (la voiture de tête sort du champ par le haut).
func _hover_camera(a: Dictionary, p: Vector3) -> void:
	_cam.global_position = p + Vector3.UP * 40.0
	_cam.look_at(p, _travel_dir(a))


func _look_at_sea() -> void:
	_cam.global_position = _spawn_pos + Vector3(0, 3, 0)
	_cam.look_at(_cam.global_position + Vector3(0, -0.15, -1), Vector3.UP)


func _sleeping(e) -> bool:
	return is_instance_valid(e) and bool(e.get_meta(META, false))


func _free(e) -> void:
	if is_instance_valid(e):
		e.queue_free()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _wait_until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	return cond.call()
