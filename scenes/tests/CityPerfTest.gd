extends Node

# Test de performance headless dans la vraie carte (centre-ville reconstruit), joueur et caméra réels, spawners réels :
#  - volume d'avant (84 voitures / 105 PNJ) sans culling, pour référence ;
#  - volume x3 (252 / 315) sans culling, puis avec SimulationCuller : caméra de départ (vers la mer), caméra tournée
#    vers la ville avec le champ seul (sans test d'occlusion) puis avec occlusion, joueur au croisement Union Street ×
#    Central Boulevard regardant dans l'axe du boulevard (avec et sans culling).
# Par phase : temps réel de frame (moyenne, p95, max), pics process / physique (moniteurs Godot, max sur 1 s),
# voitures et PNJ actifs / endormis, coût du culler et rayons de ligne de vue. Relève aussi la répartition par quart
# du centre-ville (autour de ce croisement) et les voitures qui passent d'un quart à l'autre. Headless = pas de rendu : coûts CPU (scripts +
# physique Jolt), pas le GPU.
#
# Lancer : Godot --headless --fixed-fps 60 --quit-after 25000 res://scenes/tests/CityPerfTest.tscn

const WORLD := preload("res://scenes/world/World.tscn")
const META := &"sim_sleeping"
const CENTER := Vector3(-452.75, 1.5, -161.5)      # coin de trottoir au croisement Union Street × Central Boulevard
const LOOK_TARGETS := {"city": Vector3(-460.0, 0.0, -172.0), "avenue": Vector3(-900.0, 0.0, -161.5)}
const SETTLE := 3.0
const MEASURE := 15.0
const PHASES := [
	{"key": "avant", "name": "volume d'avant (84 voitures / 105 PNJ), sans culling", "cars": 84, "npcs": 105, "culling": false, "occlusion": true, "center": false, "look": "", "fill": 30.0},
	{"key": "off", "name": "x3 (252 voitures / 315 PNJ), sans culling", "cars": 252, "npcs": 315, "culling": false, "occlusion": true, "center": false, "look": "", "fill": 45.0},
	{"key": "on", "name": "x3, avec culling, caméra de départ (vers la mer)", "cars": 252, "npcs": 315, "culling": true, "occlusion": true, "center": false, "look": "", "fill": 0.0},
	{"key": "on_view_frustum", "name": "x3, culling par le champ seul (sans occlusion), caméra tournée vers la ville", "cars": 252, "npcs": 315, "culling": true, "occlusion": false, "center": false, "look": "city", "fill": 0.0},
	{"key": "on_view", "name": "x3, avec culling, caméra tournée vers la ville", "cars": 252, "npcs": 315, "culling": true, "occlusion": true, "center": false, "look": "city", "fill": 0.0},
	{"key": "on_center", "name": "x3, avec culling, croisement Union Street × Central Boulevard, regard dans l'axe du boulevard", "cars": 252, "npcs": 315, "culling": true, "occlusion": true, "center": true, "look": "avenue", "fill": 0.0},
	{"key": "off_center", "name": "x3, sans culling, croisement Union Street × Central Boulevard, regard dans l'axe du boulevard", "cars": 252, "npcs": 315, "culling": false, "occlusion": true, "center": true, "look": "avenue", "fill": 0.0},
]

var _world: Node
var _player: CharacterBody3D
var _culler
var _cars
var _npcs
var _measuring := false
var _last_usec := 0
var _frame_ms := PackedFloat32Array()
var _physics_ms := PackedFloat32Array()
var _process_ms := PackedFloat32Array()
var _culler_us := PackedFloat32Array()
var _rays := PackedFloat32Array()
var _counts := []
var _last_district := {}
var _crossings := 0
var _tick := 0
var _spread := []
var _errors: Array[String] = []


func _ready() -> void:
	print("CITY_PERF_BEGIN")
	_world = WORLD.instantiate()
	add_child(_world)
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	_culler = _world.get_node("SimulationCuller")
	_cars = _world.get_node("CarSpawner")
	_npcs = _world.get_node("NpcSpawner")
	await get_tree().physics_frame
	var spawn := _player.global_position
	print("CITY_PERF_SCENE %d nœuds dans l'arbre au chargement" % Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var results := {}
	for phase: Dictionary in PHASES:
		_cars.max_active = phase.cars
		_npcs.max_active = phase.npcs
		_culler.enabled = phase.culling
		_culler.occlusion = phase.occlusion
		if not phase.culling:
			_culler.wake_all()
		var target: Vector3 = CENTER if phase.center else spawn
		if _player.global_position.distance_to(target) > 5.0:
			_player.global_position = target
			_player.velocity = Vector3.ZERO
		_player.rotation.y = 0.0
		if phase.look != "":
			var look: Vector3 = LOOK_TARGETS[phase.look]
			_player.look_at(Vector3(look.x, _player.global_position.y, look.z), Vector3.UP)
		if float(phase.fill) > 0.0:
			var f0 := Engine.get_physics_frames()
			await _wait_until(func(): return _group("vehicle").size() >= phase.cars and _group("npc").size() >= phase.npcs, phase.fill)
			print("CITY_PERF_FILL %d voitures / %d PNJ après %.1f s de jeu" % [_group("vehicle").size(), _group("npc").size(), (Engine.get_physics_frames() - f0) / 60.0])
		await get_tree().create_timer(SETTLE).timeout
		_frame_ms.clear()
		_physics_ms.clear()
		_process_ms.clear()
		_culler_us.clear()
		_rays.clear()
		_counts.clear()
		_last_usec = 0
		_measuring = true
		await get_tree().create_timer(MEASURE).timeout
		_measuring = false
		results[phase.key] = _summary(phase)
		if phase.key == "on":
			_spread = _population_spread()
	_verdict(results)


func _physics_process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _measuring and _last_usec > 0:
		_frame_ms.append((now - _last_usec) / 1000.0)
		_physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		_process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		_culler_us.append(float(_culler.last_cost_usec))
		_rays.append(float(_culler.rays_last_frame))
	_last_usec = now
	_tick += 1
	if _tick % 10 != 0 or _culler == null:
		return
	var sample := [0, 0, 0, 0]   # voitures actives, endormies, PNJ actifs, endormis
	for v in _group("vehicle"):
		var asleep := bool(v.get_meta(META, false))
		sample[1 if asleep else 0] += 1
		var d := _district(v.global_position, 12.0)
		if d != "" and not asleep:
			var id: int = v.get_instance_id()
			if _last_district.has(id) and _last_district[id] != d:
				_crossings += 1
			_last_district[id] = d
	for n in _group("npc"):
		sample[3 if bool(n.get_meta(META, false)) else 2] += 1
	if _measuring:
		_counts.append(sample)


func _summary(phase: Dictionary) -> Dictionary:
	var sorted := _frame_ms.duplicate()
	sorted.sort()
	var avg := [0.0, 0.0, 0.0, 0.0]
	for s in _counts:
		for k in 4:
			avg[k] += float(s[k]) / maxf(_counts.size(), 1.0)
	var r := {"frame": _mean(_frame_ms), "p95": sorted[int(sorted.size() * 0.95)], "max": sorted[sorted.size() - 1],
			"process": _mean(_process_ms), "physics": _mean(_physics_ms), "culler_us": _mean(_culler_us), "rays": _mean(_rays),
			"cars": _group("vehicle").size(), "npcs": _group("npc").size(), "avg": avg, "frames": _frame_ms.size()}
	print("CITY_PERF %s | %d voitures (%.0f actives / %.0f endormies), %d PNJ (%.0f actifs / %.0f endormis) | frame %.2f ms en moyenne (%.0f fps CPU), p95 %.2f ms, max %.2f ms sur %d frames | pics sur 1 s : process %.2f ms, physique %.2f ms | culler %.0f µs/frame, %.0f rayons/frame"
			% [phase.name, r.cars, avg[0], avg[1], r.npcs, avg[2], avg[3], r.frame, 1000.0 / r.frame, r.p95, r.max, r.frames, r.process, r.physics, r.culler_us, r.rays])
	return r


func _population_spread() -> Array:
	var cars := {"nord-est": 0, "nord-ouest": 0, "sud-est": 0, "sud-ouest": 0}
	var npcs := cars.duplicate()
	for v in _group("vehicle"):
		cars[_district(v.global_position, 0.0)] += 1
	for n in _group("npc"):
		npcs[_district(n.global_position, 0.0)] += 1
	print("CITY_PERF_SPREAD voitures par quart %s | PNJ par quart %s" % [cars, npcs])
	return [cars, npcs]


func _verdict(results: Dictionary) -> void:
	var off: Dictionary = results.off
	var on: Dictionary = results.on
	var on_view: Dictionary = results.on_view
	var on_center: Dictionary = results.on_center
	var off_center: Dictionary = results.off_center
	print("CITY_PERF_GAIN à 252 / 315, frame moyenne : sans culling %.2f ms (%.2f au croisement) | avec culling %.2f ms caméra de départ, %.2f ms caméra vers la ville (%.2f avec le champ seul), %.2f ms au croisement | volume d'avant sans culling %.2f ms | budget 60 fps 16.67 ms"
			% [off.frame, off_center.frame, on.frame, on_view.frame, results.on_view_frustum.frame, on_center.frame, results.avant.frame])
	print("CITY_PERF_SEAMS %d passages de voitures (actives) d'un quart du centre-ville à l'autre pendant le test" % _crossings)
	if int(on.cars) < 240 or int(on.npcs) < 300:
		_errors.append("population x3 non atteinte : %d voitures, %d PNJ" % [on.cars, on.npcs])
	if float(on.frame) >= float(off.frame) or float(on_view.frame) >= float(off.frame) or float(on_center.frame) >= float(off_center.frame):
		_errors.append("le culling ne réduit pas le temps de frame")
	if _crossings == 0:
		_errors.append("aucune voiture n'est passée d'un quart à l'autre")
	for i in 2:
		for d in _spread[i]:
			if int(_spread[i][d]) < (25 if i == 0 else 30):
				_errors.append("%s : trop peu de %s" % [d, "voitures" if i == 0 else "PNJ"])
	print("CITY_PERF_RESULT %s %s" % ["OK" if _errors.is_empty() else "FAIL", " | ".join(_errors)])
	get_tree().quit(0 if _errors.is_empty() else 1)


func _district(p: Vector3, margin: float) -> String:
	if absf(p.x + 460.0) < margin or absf(p.z + 172.0) < margin:
		return ""
	if p.z <= -172.0:
		return "nord-est" if p.x >= -460.0 else "nord-ouest"
	return "sud-est" if p.x >= -460.0 else "sud-ouest"


func _group(group: StringName) -> Array[Node]:
	return get_tree().get_nodes_in_group(group)


func _mean(values: PackedFloat32Array) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total / maxf(values.size(), 1.0)


func _wait_until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	return cond.call()
