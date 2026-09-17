extends Node

# Test headless des boutiques construites sur Blender, dans la vraie carte (World.tscn) :
#  1. plus de téléportation : ni nœud Interiors ni porte ShopEntrance, l'ancien bâtiment d'angle retiré ;
#  2. le joueur marche (vraie action move_forward) depuis le parvis à travers la porte et arrive dans le
#     volume intérieur : toit masqué pour la caméra (ombre conservée) ;
#  3. face à un mur ou une vitrine hors porte, il reste dehors (collisions) ;
#  4. au comptoir, [E] ouvre le panneau de la boutique ; concessionnaire : un achat serait livré sur la
#     place du parvis, au sol, hors du bâtiment ;
#  5. il ressort à pied par la porte : toit réaffiché ;
#  6. le téléphone ouvre toujours le panneau ; l'empreinte du bâtiment reste lisible par la carte.
#
# Lancer : Godot --headless --fixed-fps 60 --quit-after 4000 res://scenes/tests/ShopBuildingsTest.tscn

const WORLD := preload("res://scenes/world/World.tscn")
const MapTexture := preload("res://scenes/ui/DistrictMapTexture.gd")
const SHOPS := [
	{"path": "District/Buildings/Dealership_Building", "panel": "car_dealership_panel", "phone": "_on_dealership_pressed", "cars": 2},
	{"path": "District/Buildings/Agency_Building", "panel": "apartment_agency_panel", "phone": "_on_agency_pressed", "cars": 0},
]

var _errors: Array[String] = []
var _world: Node
var _player: CharacterBody3D


func _ready() -> void:
	print("SHOP_BUILDINGS_BEGIN")
	_world = WORLD.instantiate()
	add_child(_world)
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	await _frames(10)
	if _world.get_node_or_null("Interiors") != null or _world.find_child("ShopEntrance", true, false) != null \
			or _world.get_node_or_null("District/Buildings/Building_Small_1_152") != null:
		_errors.append("restes de l'ancien système (Interiors / ShopEntrance / bâtiment d'angle)")
	for shop: Dictionary in SHOPS:
		await _check_shop(shop)
	print("SHOP_BUILDINGS_RESULT %s %s" % ["OK" if _errors.is_empty() else "FAIL", " | ".join(_errors)])
	get_tree().quit(0 if _errors.is_empty() else 1)


func _check_shop(shop: Dictionary) -> void:
	var building = _world.get_node_or_null(shop.path)
	var panel := get_tree().get_first_node_in_group(shop.panel) as CanvasItem
	if building == null or panel == null:
		_errors.append("%s : bâtiment ou panneau introuvable" % shop.path)
		return
	var tag := String(building.name)
	var shell := building.get_node("Shell") as Node3D
	var outside := (shell.find_child("Socket_DoorOutside", true, false) as Node3D).global_position
	var inside := (shell.find_child("Socket_DoorInside", true, false) as Node3D).global_position

	# 2. entrée à pied
	var frames: int = await _walk(outside, inside, 300, func() -> bool: return building.is_player_inside(_player))
	await _frames(3)
	var roof_ok: bool = building.is_roof_hidden() and _roof_mode(building) == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	print("SHOP_BUILDINGS_WALK_IN %s frames=%d dedans=%s toit_masqué=%s" % [tag, frames, building.is_player_inside(_player), roof_ok])
	if frames < 0:
		_errors.append("%s : le joueur n'entre pas à pied par la porte" % tag)
	elif not roof_ok:
		_errors.append("%s : toit pas masqué à l'intérieur" % tag)

	# 3. mur / vitrine hors porte
	var side: Vector3 = building.global_transform.basis.x * -4.5
	await _walk(outside + side, inside + side, 180, func() -> bool: return false)
	var blocked: bool = not building.is_player_inside(_player)
	print("SHOP_BUILDINGS_WALL %s bloqué=%s" % [tag, blocked])
	if not blocked:
		_errors.append("%s : on traverse la façade hors de la porte" % tag)

	# 4. comptoir (+ livraison pour le concessionnaire)
	var counter: Vector3 = building.counter_zone.global_position
	var toward_door := Vector3(inside.x - counter.x, 0.0, inside.z - counter.z).normalized()
	_place(counter + toward_door * 1.3, counter)
	await _frames(6)
	await _press_interact()
	if not panel.visible:
		_errors.append("%s : [E] au comptoir n'ouvre pas le panneau" % tag)
	if shop.cars > 0:
		var cars := 0
		for c in building.get_children():
			if String(c.scene_file_path).ends_with(".glb") and String(c.scene_file_path).contains("lowpoly_cars"):
				cars += 1
		var spot: Transform3D = panel.call("purchase_spawn_transform", _player)
		var expected: Transform3D = building.delivery_transform()
		var q := PhysicsRayQueryParameters3D.create(spot.origin + Vector3.UP * 3.0, spot.origin + Vector3.DOWN * 3.0)
		var hit := _player.get_world_3d().direct_space_state.intersect_ray(q)
		var ground: float = (hit.position as Vector3).y if not hit.is_empty() else -99.0
		print("SHOP_BUILDINGS_DELIVERY %s voitures_exposées=%d livraison=(%.1f, %.1f, %.1f) sol=%.2f" % [tag, cars, spot.origin.x, spot.origin.y, spot.origin.z, ground])
		if cars != shop.cars:
			_errors.append("%s : %d voitures exposées au lieu de %d" % [tag, cars, shop.cars])
		if spot.origin.distance_to(expected.origin) > 0.01 or building.is_player_inside_point(spot.origin) or absf(ground - 0.41) > 0.05:
			_errors.append("%s : livraison hors de la place du parvis" % tag)
	panel.call("hide_ui")
	await _frames(2)

	# 5. sortie à pied
	frames = await _walk(inside, outside, 300, func() -> bool: return not building.is_player_inside(_player))
	await _frames(20)
	var roof_back: bool = not building.is_roof_hidden() and _roof_mode(building) == GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	print("SHOP_BUILDINGS_WALK_OUT %s frames=%d toit_réaffiché=%s" % [tag, frames, roof_back])
	if frames < 0 or not roof_back:
		_errors.append("%s : sortie à pied ou retour du toit en échec" % tag)

	# 6. téléphone et carte
	var phone := get_tree().get_first_node_in_group("phone_panel")
	if phone == null or not phone.has_method(shop.phone):
		_errors.append("%s : bouton du téléphone introuvable" % tag)
	else:
		phone.call(shop.phone)
		await _frames(2)
		if not panel.visible:
			_errors.append("%s : le téléphone n'ouvre plus le panneau" % tag)
		panel.call("hide_ui")
	if MapTexture._get_building_footprint(building).is_empty():
		_errors.append("%s : empreinte absente de la carte" % tag)
	await _frames(2)


# Place le joueur en from face à target, maintient « avancer » jusqu'à stop() (max frames) : frames utilisées, -1 si jamais.
func _walk(from: Vector3, target: Vector3, max_frames: int, stop: Callable) -> int:
	_place(from, target)
	await _frames(6)
	Input.action_press("move_forward")
	var used := -1
	for i in max_frames:
		await get_tree().physics_frame
		if stop.call():
			used = i
			break
	Input.action_release("move_forward")
	await _frames(4)
	return used


func _place(pos: Vector3, look_at_point: Vector3) -> void:
	_player.global_position = pos + Vector3.UP * 1.0
	_player.velocity = Vector3.ZERO
	var d := look_at_point - pos
	_player.rotation = Vector3(0.0, atan2(-d.x, -d.z), 0.0)
	_player.spring_arm.rotation.y = 0.0


func _roof_mode(building: Node) -> int:
	for n in (building.get_node("Roof") as Node).find_children("*", "GeometryInstance3D", true, false):
		return (n as GeometryInstance3D).cast_shadow
	return -1


func _press_interact() -> void:
	var press := InputEventAction.new()
	press.action = "interact"
	press.pressed = true
	Input.parse_input_event(press)
	await _frames(2)
	var release := InputEventAction.new()
	release.action = "interact"
	release.pressed = false
	Input.parse_input_event(release)
	await _frames(2)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
