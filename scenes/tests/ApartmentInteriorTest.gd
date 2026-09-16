extends Node3D

# Test des intérieurs d'appartement et de la caméra intérieure.
#  - headless : vérifie les 4 appartements (ApartmentData.shell_size -> bonne coquille, table et PC
#    sur leurs repères, collisions importées, taille de la zone intérieure), puis le fondu de caméra
#    du Player en entrant / sortant et le masquage du plafond. Quitte avec le code 0 ou 1.
#  - dans l'éditeur (F6) : charge l'appartement `apartment_id` et place le joueur à l'entrée.
#
# Lancer : Godot --headless --fixed-fps 60 res://scenes/tests/ApartmentInteriorTest.tscn

const INTERIOR_SCENE := preload("res://scenes/apartments/ApartmentInterior.tscn")
const PLAYER_SCENE := preload("res://scenes/player/Player.tscn")
const EXPECTED_SHELL := {"studio": "Small", "apt_2pieces": "Medium", "loft": "Large", "penthouse": "Large"}
const INTERIOR_SIZE := {"Small": Vector2(11.68, 13.95), "Medium": Vector2(13.91, 11.94), "Large": Vector2(20.10, 16.10)}

@export var apartment_id := "studio"

var interior: Node3D
var player: Node3D
var _errors: Array[String] = []


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		_play(apartment_id)
		return
	print("APARTMENT_TEST_BEGIN")
	await _run()
	print("APARTMENT_TEST_RESULT %s %s" % ["OK" if _errors.is_empty() else "FAIL", " | ".join(_errors)])
	get_tree().quit(0 if _errors.is_empty() else 1)


func _play(id: String) -> void:
	interior = INTERIOR_SCENE.instantiate() as Node3D
	interior.apartment = AgencyRegistry.get_apartment(id)
	add_child(interior)
	player = PLAYER_SCENE.instantiate() as Node3D
	add_child(player)
	player.global_transform = interior.entrance_transform()
	player.global_position.y += 0.95  # capsule posée sur le sol fini


func _run() -> void:
	for data: ApartmentData in AgencyRegistry.all_apartments:
		if EXPECTED_SHELL.get(data.id, "") != data.shell_size:
			_errors.append("%s -> %s au lieu de %s" % [data.id, data.shell_size, EXPECTED_SHELL.get(data.id, "?")])
		var check := INTERIOR_SCENE.instantiate() as Node3D
		check.apartment = data
		add_child(check)
		await get_tree().process_frame
		_check_interior(check, data)
		check.free()

	_play("studio")
	await _physics_frames(120)
	var arm := player.spring_arm as SpringArm3D
	print("  entrée     : indoor=%s bras=%.2f pivot_y=%.2f épaule=%.2f" % [player.is_indoor(), arm.spring_length, arm.position.y, player._shoulder])
	if not player.is_indoor():
		_errors.append("zone intérieure non détectée à l'entrée")
	if absf(arm.spring_length - 1.8) > 0.05 or absf(arm.position.y - 1.45) > 0.02 or absf(player._shoulder - 0.4) > 0.02:
		_errors.append("caméra intérieure non appliquée")

	player.global_position = Vector3(0.0, 0.95, 0.0)  # centre de la pièce : place libre derrière la caméra
	var states := {}
	for pitch in [-70.0, 45.0]:
		arm.rotation.x = deg_to_rad(pitch)
		await _physics_frames(30)
		await get_tree().process_frame
		var cam_y := (player.camera as Camera3D).global_position.y
		var visible: bool = interior.ceiling.visible
		print("  plafond    : tangage=%+.0f caméra_y=%.2f visible=%s" % [pitch, cam_y, visible])
		if visible != (cam_y < 2.75):
			_errors.append("plafond visible=%s avec caméra à %.2f m" % [visible, cam_y])
		states[visible] = true
	if states.size() < 2:
		_errors.append("le cas caméra au-dessus du plafond n'a pas été atteint")
	arm.rotation.x = deg_to_rad(-10.0)

	player.global_position = Vector3(40.0, 0.95, 0.0)  # dehors, loin des murs
	await _physics_frames(120)
	print("  dehors     : indoor=%s bras=%.2f pivot_y=%.2f épaule=%.2f" % [player.is_indoor(), arm.spring_length, arm.position.y, player._shoulder])
	if player.is_indoor() or absf(arm.spring_length - 4.0) > 0.05 or absf(arm.position.y - 1.6) > 0.02 or absf(player._shoulder) > 0.02:
		_errors.append("caméra extérieure non restaurée")


func _check_interior(check: Node3D, data: ApartmentData) -> void:
	var table_sock := check.shell.find_child("Socket_Table", true, false) as Node3D
	var pc_sock := check.table.find_child("Socket_PC", true, false) as Node3D
	var box := (check.zone.get_child(0) as CollisionShape3D).shape as BoxShape3D
	var expected: Vector2 = INTERIOR_SIZE[data.shell_size]
	var bodies: int = check.shell.find_children("*", "StaticBody3D", true, false).size()
	var table_gap: float = check.table.global_position.distance_to(table_sock.global_position)
	var pc_gap: float = check.computer.global_position.distance_to(pc_sock.global_position)
	print("  %-12s coquille=%-6s zone=%.2f x %.2f x %.2f collisions=%d table=%.4f pc=%.4f" % [
		data.id, data.shell_size, box.size.x, box.size.y, box.size.z, bodies, table_gap, pc_gap])
	if table_gap > 0.001 or pc_gap > 0.001:
		_errors.append("%s : table ou PC hors de son repère" % data.id)
	if absf(box.size.x - expected.x) > 0.02 or absf(box.size.z - expected.y) > 0.02 or absf(box.size.y - 2.8) > 0.001:
		_errors.append("%s : zone intérieure %s" % [data.id, box.size])
	if bodies < 7 or check.shell.find_child("Socket_Entrance", true, false) == null:
		_errors.append("%s : collisions (%d) ou Socket_Entrance manquants" % [data.id, bodies])


func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
