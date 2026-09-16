extends Node3D

# Intérieur d'appartement assemblé depuis un ApartmentData : coquille et plafond de la bonne taille
# (ApartmentData.shell_size), table et PC par défaut posés sur les repères de la coquille
# (Socket_Table, puis Socket_PC de la table) et zone intérieure qui passe la caméra du joueur en
# mode intérieur (Player.set_indoor). Le plafond n'a pas de collision : il est seulement masqué quand
# la caméra passe au-dessus.
# Pas encore relié à la carte : entrer/sortir depuis la ville est le chantier suivant.

const TABLE := preload("res://assets/apartments/props/Apt_Table.glb")
const COMPUTER := preload("res://assets/apartments/props/Apt_Computer.glb")
const WALL_THICKNESS := 0.20  # murs des coquilles (apt_shells.py)
const CEILING_HEIGHT := 2.80
const CEILING_HIDE_MARGIN := 0.05

@export var apartment: ApartmentData

var shell: Node3D
var ceiling: Node3D
var table: Node3D
var computer: Node3D
var zone: Area3D
var _players := {}


func _ready() -> void:
	if apartment != null:
		build(apartment)


func build(data: ApartmentData) -> void:
	apartment = data
	shell = _instance(data.shell_path())
	ceiling = _instance(data.ceiling_path())
	table = TABLE.instantiate() as Node3D
	add_child(table)
	table.global_transform = _socket(shell, "Socket_Table").global_transform
	computer = COMPUTER.instantiate() as Node3D
	add_child(computer)
	computer.global_transform = _socket(table, "Socket_PC").global_transform
	_build_zone()


# Point d'apparition derrière la porte ; son avant (-Z) regarde vers l'intérieur de la pièce.
func entrance_transform() -> Transform3D:
	return _socket(shell, "Socket_Entrance").global_transform


func _instance(path: String) -> Node3D:
	var node := (load(path) as PackedScene).instantiate() as Node3D
	add_child(node)
	return node


func _socket(root: Node, socket_name: String) -> Node3D:
	return root.find_child(socket_name, true, false) as Node3D


func _build_zone() -> void:
	var footprint := AABB()
	for mi in shell.find_children("*", "MeshInstance3D", true, false):
		footprint = footprint.merge((mi as MeshInstance3D).get_aabb())
	var box := BoxShape3D.new()
	box.size = Vector3(footprint.size.x - 2.0 * WALL_THICKNESS, CEILING_HEIGHT, footprint.size.z - 2.0 * WALL_THICKNESS)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = Vector3(0.0, CEILING_HEIGHT / 2.0, 0.0)
	zone = Area3D.new()
	zone.name = "InteriorZone"
	zone.collision_layer = 0
	zone.collision_mask = 1  # le Player est sur le calque 1
	zone.add_child(shape)
	add_child(zone)
	zone.body_entered.connect(_on_body_entered)
	zone.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and body.has_method("set_indoor") and not _players.has(body):
		_players[body] = true
		body.set_indoor(true)


func _on_body_exited(body: Node3D) -> void:
	if _players.erase(body):
		body.set_indoor(false)


func _exit_tree() -> void:
	for p in _players:
		if is_instance_valid(p):
			p.set_indoor(false)
	_players.clear()


func _process(_delta: float) -> void:
	if ceiling == null:
		return
	var cam := get_viewport().get_camera_3d()
	ceiling.visible = cam == null or cam.global_position.y < global_position.y + CEILING_HEIGHT - CEILING_HIDE_MARGIN
