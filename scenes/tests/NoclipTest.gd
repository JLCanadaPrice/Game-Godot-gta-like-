extends Node

# Test headless du point de départ et du noclip (touche V), dans le vrai monde (World.tscn, spawners coupés) :
#  - départ : joueur debout au sol sur Founders Plaza au lancement, sans chute ;
#  - V (vrai événement clavier, raccourci de project.godot) : noclip actif, corps et caméra sans collision, bandeau ;
#  - sans gravité : immobile en l'air sans touche ; Espace / Ctrl montent / descendent, Maj accélère ;
#  - traverse un gratte-ciel et une voiture posée (obstacles vérifiés par rayon sur le trajet), et le sol ;
#  - V à nouveau : collision, caméra et gravité rétablies (retombe et se pose) ; sorti du noclip sous le sol ou dans
#    un bâtiment, reposé sur la surface la plus haute à sa verticale ;
#  - zones quittées en vol : plus de nage une fois sorti de l'eau, plus de voiture à portée une fois loin.
#
# Lancer : Godot --headless --fixed-fps 60 --quit-after 6000 res://scenes/tests/NoclipTest.tscn

const WORLD := preload("res://scenes/world/World.tscn")
const CAR := preload("res://scenes/vehicles/Car.tscn")
const FOUNDERS_PLAZA := Rect2(-532, -244, 144, 72)
const TOWER := Vector2(-568.0, -208.0)     # Mk2 (244 m), à l'ouest de la place, de l'autre côté de Main Street
const WEST := PI / 2.0                     # cap : regard vers -X

var _errors: Array[String] = []
var _player: CharacterBody3D


func _ready() -> void:
	print("NOCLIP_TEST_BEGIN")
	var world := WORLD.instantiate()
	add_child(world)
	for spawner in ["CarSpawner", "NpcSpawner"]:
		world.get_node(spawner).set_process(false)
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	await _frames(60)
	_check_spawn()
	await _check_toggle_on()
	await _check_no_gravity()
	await _check_through_tower()
	await _check_through_car(world)
	await _check_through_ground_and_exit()
	await _check_exit_in_air()
	await _check_exit_in_tower()
	await _check_zones_left(world)
	print("NOCLIP_TEST_RESULT %s %s" % ["OK" if _errors.is_empty() else "FAIL", " | ".join(_errors)])
	get_tree().quit(0 if _errors.is_empty() else 1)


func _check_spawn() -> void:
	var p := _player.global_position
	var ground := _ground_at(Vector2(p.x, p.z))
	var ok: bool = _player.is_on_floor() and absf(p.y - 0.9 - ground) < 0.1 and FOUNDERS_PLAZA.has_point(Vector2(p.x, p.z))
	print("NOCLIP_TEST_SPAWN joueur en %s, cap %.0f°, sol %.2f m, au sol %s, sur Founders Plaza %s | %s"
			% [p.snappedf(0.01), rad_to_deg(_player.rotation.y), ground, _player.is_on_floor(), FOUNDERS_PLAZA.has_point(Vector2(p.x, p.z)), _ok(ok)])
	if not ok:
		_errors.append("départ")


func _check_toggle_on() -> void:
	await _press_v()
	var arm := _player.get_node("SpringArm3D") as SpringArm3D
	var shape := _player.get_node("CollisionShape3D") as CollisionShape3D
	var hint := _player.get_node_or_null("NoclipHint") as CanvasLayer
	var ok: bool = _player.is_noclip() and _player.collision_layer == 0 and _player.collision_mask == 0 and arm.collision_mask == 0 \
			and shape.disabled and hint != null and hint.visible
	print("NOCLIP_TEST_ON V -> noclip %s | couches corps %d / %d, caméra %d, forme coupée %s, bandeau %s | %s"
			% [_player.is_noclip(), _player.collision_layer, _player.collision_mask, arm.collision_mask, shape.disabled, hint != null and hint.visible, _ok(ok)])
	if not ok:
		_errors.append("activation par V")


func _check_no_gravity() -> void:
	_place(Vector3(-403.0, 12.0, -199.0), WEST)
	await _frames(5)
	var y0 := _player.global_position.y
	await _frames(60)
	var hover := _player.global_position.y - y0
	await _hold(["noclip_up"], 60)
	var up := _player.global_position.y - y0 - hover
	var y1 := _player.global_position.y
	await _hold(["noclip_down"], 30)
	var down := _player.global_position.y - y1
	var y2 := _player.global_position.y
	await _hold(["noclip_up", "sprint"], 30)
	var fast := _player.global_position.y - y2
	var ok: bool = absf(hover) < 0.01 and absf(up - 20.0) < 1.0 and absf(down + 10.0) < 1.0 and absf(fast - 45.0) < 2.0
	print("NOCLIP_TEST_FLY 1 s sans touche : %+.2f m | Espace 1 s : %+.1f m | Ctrl 0,5 s : %+.1f m | Espace + Maj 0,5 s : %+.1f m | %s"
			% [hover, up, down, fast, _ok(ok)])
	if not ok:
		_errors.append("vol sans gravité")


func _check_through_tower() -> void:
	var from := Vector3(-530.0, 30.0, TOWER.y)
	var to := Vector3(-620.0, 30.0, TOWER.y)
	var solid := _ray(from, to, 1)
	_place(from, WEST)
	await _frames(3)
	await _hold(["move_forward"], 240)
	var p := _player.global_position
	var ok: bool = not solid.is_empty() and p.x < -605.0 and absf(p.z - TOWER.y) < 0.5 and absf(p.y - 30.0) < 0.5
	print("NOCLIP_TEST_TOWER mur du gratte-ciel sur le trajet en %s | 4 s vers l'ouest depuis x -530 -> %s | %s"
			% [(solid["position"] as Vector3).snappedf(0.1) if not solid.is_empty() else "rien", p.snappedf(0.1), _ok(ok)])
	if not ok:
		_errors.append("traversée d'un bâtiment")


func _check_through_car(world: Node) -> void:
	var car := CAR.instantiate() as Node3D
	world.add_child(car)
	car.global_position = Vector3(-440.0, 0.9, -186.0)
	car.rotation.y = WEST
	await _frames(10)
	var car_pos := car.global_position
	var from := Vector3(-425.0, car_pos.y + 0.2, car_pos.z)
	var solid := _ray(from, from + Vector3(-30.0, 0.0, 0.0), 4)
	_place(from, WEST)
	await _frames(3)
	await _hold(["move_forward"], 90)
	var p := _player.global_position
	var ok: bool = not solid.is_empty() and p.x < car_pos.x - 10.0 and car.global_position.distance_to(car_pos) < 0.05
	print("NOCLIP_TEST_CAR voiture en %s, sa collision sur le trajet %s | joueur 1,5 s vers l'ouest -> %s, voiture déplacée de %.2f m | %s"
			% [car_pos.snappedf(0.1), not solid.is_empty(), p.snappedf(0.1), car.global_position.distance_to(car_pos), _ok(ok)])
	if not ok:
		_errors.append("traversée d'une voiture")
	car.queue_free()


func _check_through_ground_and_exit() -> void:
	var ground := _ground_at(Vector2(-403.0, -199.0))
	_place(Vector3(-403.0, ground + 0.9, -199.0), WEST)
	await _frames(3)
	await _hold(["noclip_down"], 90)
	var under := _player.global_position.y
	await _press_v()
	var placed := _player.global_position.y
	await _frames(60)
	var p := _player.global_position
	var ok: bool = under < ground - 25.0 and not _player.is_noclip() and absf(placed - ground - 0.95) < 0.05 and _player.is_on_floor() and absf(p.y - ground - 0.9) < 0.1
	print("NOCLIP_TEST_GROUND descente 1,5 s depuis le sol (%.2f m) -> y %.1f | V sous le sol -> reposé à y %.2f, 1 s après %.2f, au sol %s | %s"
			% [ground, under, placed, p.y, _player.is_on_floor(), _ok(ok)])
	if not ok:
		_errors.append("traversée du sol et sortie dessous")


func _check_exit_in_air() -> void:
	await _press_v()
	var ground := _ground_at(Vector2(-403.0, -199.0))
	_place(Vector3(-403.0, ground + 15.0, -199.0), WEST)
	await _frames(3)
	await _press_v()
	var arm := _player.get_node("SpringArm3D") as SpringArm3D
	var shape := _player.get_node("CollisionShape3D") as CollisionShape3D
	var hint := _player.get_node("NoclipHint") as CanvasLayer
	var restored: bool = not _player.is_noclip() and _player.collision_layer == 1 and _player.collision_mask == 7 and arm.collision_mask == 1 \
			and not shape.disabled and not hint.visible
	var start_y := _player.global_position.y
	await _frames(20)
	var falling := _player.global_position.y < start_y - 0.5
	await _frames(140)
	var p := _player.global_position
	var ok: bool = restored and falling and _player.is_on_floor() and absf(p.y - ground - 0.9) < 0.1
	print("NOCLIP_TEST_OFF V à 15 m -> couches corps %d / %d, caméra %d, forme active %s, bandeau masqué %s | tombe %s, posé au sol %s (y %.2f) | %s"
			% [_player.collision_layer, _player.collision_mask, arm.collision_mask, not shape.disabled, not hint.visible, falling, _player.is_on_floor(), p.y, _ok(ok)])
	if not ok:
		_errors.append("retour au mode normal")


func _check_exit_in_tower() -> void:
	await _press_v()
	var roof := _ray(Vector3(TOWER.x, 3000.0, TOWER.y), Vector3(TOWER.x, -100.0, TOWER.y), 1)
	_place(Vector3(TOWER.x, 30.0, TOWER.y), WEST)
	await _frames(3)
	await _press_v()
	await _frames(60)
	var p := _player.global_position
	var top: float = (roof["position"] as Vector3).y if not roof.is_empty() else INF
	var ok: bool = not roof.is_empty() and not _player.is_noclip() and _player.is_on_floor() and absf(p.y - top - 0.9) < 0.15
	print("NOCLIP_TEST_INSIDE V dans le gratte-ciel à 30 m -> reposé sur le toit (%.1f m) : y %.2f, au sol %s | %s"
			% [top, p.y, _player.is_on_floor(), _ok(ok)])
	if not ok:
		_errors.append("sortie dans un bâtiment")


# Zones quittées en noclip : nage dans la rivière puis vol jusqu'à la place (ne nage plus, marche) ; voiture à portée
# puis vol à 60 m (plus à portée, E ne fait pas monter dedans).
func _check_zones_left(world: Node) -> void:
	_place(Vector3(-1150.0, 1.3, -24.0), WEST)
	await _frames(45)
	var swam: bool = _player.get("_swimming")
	await _press_v()
	_place(Vector3(-403.0, 4.0, -199.0), WEST)
	await _frames(3)
	await _press_v()
	await _frames(90)
	var swimming_after: bool = _player.get("_swimming")
	var start := _player.global_position
	await _hold(["move_forward"], 60)
	var walked := Vector2(_player.global_position.x - start.x, _player.global_position.z - start.z).length()
	var car := CAR.instantiate() as Node3D
	world.add_child(car)
	car.global_position = Vector3(-440.0, 0.9, -186.0)
	await _frames(5)
	_place(Vector3(-440.0, 1.1, -189.5), WEST)
	await _frames(20)
	var in_range: bool = (_player.get("_cars_in_range") as Array).has(car)
	await _press_v()
	_place(Vector3(-500.0, 3.0, -199.0), WEST)
	await _frames(3)
	await _press_v()
	await _frames(60)
	var still_in_range: bool = (_player.get("_cars_in_range") as Array).has(car)
	var interact := InputEventAction.new()
	interact.action = "interact"
	interact.pressed = true
	Input.parse_input_event(interact)
	await _frames(3)
	interact = InputEventAction.new()
	interact.action = "interact"
	Input.parse_input_event(interact)
	await _frames(3)
	var driving: bool = _player.get("_driving")
	var ok: bool = swam and not swimming_after and walked > 3.0 and in_range and not still_in_range and not driving
	print("NOCLIP_TEST_ZONES nage dans la rivière %s -> après vol et V sur la place : nage %s, marche %.1f m en 1 s | voiture à portée %s -> à 60 m après V : à portée %s, E fait monter %s | %s"
			% [swam, swimming_after, walked, in_range, still_in_range, driving, _ok(ok)])
	if not ok:
		_errors.append("zones quittées en noclip")
	car.queue_free()


# --- outils ---

func _press_v() -> void:
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.physical_keycode = KEY_V
		key.keycode = KEY_V
		key.pressed = pressed
		Input.parse_input_event(key)
		await _frames(2)


func _place(pos: Vector3, yaw: float) -> void:
	_player.velocity = Vector3.ZERO
	_player.global_position = pos
	_player.rotation = Vector3(0.0, yaw, 0.0)
	(_player.get_node("SpringArm3D") as Node3D).rotation = Vector3.ZERO


func _hold(actions: Array, frames: int) -> void:
	for action: String in actions:
		Input.action_press(action)
	await _frames(frames)
	for action: String in actions:
		Input.action_release(action)
	await _frames(1)


func _ray(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask, [_player.get_rid()])
	return _player.get_world_3d().direct_space_state.intersect_ray(query)


func _ground_at(p: Vector2) -> float:
	var hit := _ray(Vector3(p.x, 400.0, p.y), Vector3(p.x, -150.0, p.y), 1)
	return INF if hit.is_empty() else (hit["position"] as Vector3).y


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _ok(ok: bool) -> String:
	return "OK" if ok else "ÉCHEC"
