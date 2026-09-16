extends Node3D

# Bâtiment de boutique construit sur Blender (assets/shops) et posé à sa vraie place dans le District : on y
# entre à pied par la porte ; murs, vitrines et parvis ont leurs collisions dans la coquille (Shell). Ce script
# ajoute :
#  - le toit (Roof) masqué pour la caméra quand le joueur est dans le volume intérieur, ombre conservée ;
#  - le comptoir : table + PC d'appartement sur Socket_Counter, [E] ouvre le panneau de la boutique (même
#    call_group que le téléphone) ;
#  - les voitures exposées sur Socket_Car_*, les lumières sur Socket_Light_*, et pour le concessionnaire la
#    place de livraison des achats (Socket_Delivery, lue par CarDealershipPanel).

const InteractionZone := preload("res://scenes/buildings/InteractionZone.gd")
const TABLE := preload("res://assets/apartments/props/Apt_Table.glb")
const COMPUTER := preload("res://assets/apartments/props/Apt_Computer.glb")
const COUNTER_ZONE_SIZE := Vector3(3.2, 2.4, 3.2)

@export var panel_group := ""                        # groupe du panneau ouvert au comptoir
@export var counter_prompt := "[E] Comptoir"
@export var delivers_cars := false                   # CarDealershipPanel livre alors les achats sur Socket_Delivery
@export var display_models: PackedStringArray = []   # .glb posés sur Socket_Car_1, Socket_Car_2...
@export var light_energy := 1.5
@export var light_range := 9.0

@onready var shell: Node3D = $Shell
@onready var roof: Node3D = $Roof

var counter_zone: InteractionZone
var _interior := AABB()                              # volume sous le toit, repère du bâtiment
var _roof_meshes: Array[GeometryInstance3D] = []
var _roof_hidden := false
var _player: Node3D = null


func _ready() -> void:
	if delivers_cars:
		add_to_group("car_delivery_shop")
	_interior = AABB(to_local(_socket("Socket_InteriorMin").global_position), Vector3.ZERO) \
			.expand(to_local(_socket("Socket_InteriorMax").global_position))
	for n in roof.find_children("*", "GeometryInstance3D", true, false):
		_roof_meshes.append(n as GeometryInstance3D)
	_place_counter()
	for i in display_models.size():
		_place_display(display_models[i], _socket("Socket_Car_%d" % (i + 1)))
	for n in shell.find_children("Socket_Light_*", "Node3D", true, false):
		var light := OmniLight3D.new()
		light.omni_range = light_range
		light.light_energy = light_energy
		add_child(light)
		light.global_position = (n as Node3D).global_position


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var hide := is_player_inside(_player)
	if hide == _roof_hidden:
		return
	_roof_hidden = hide
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if hide else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for mesh in _roof_meshes:
		mesh.cast_shadow = mode


func is_player_inside(player: Node3D) -> bool:
	return is_player_inside_point(player.global_position)


# Vrai si un point monde est dans le volume intérieur (sous le toit, entre les murs).
func is_player_inside_point(point: Vector3) -> bool:
	return _interior.has_point(to_local(point))


func is_roof_hidden() -> bool:
	return _roof_hidden


# Place de livraison d'une voiture achetée ici : son -Z est l'avant de la voiture.
func delivery_transform() -> Transform3D:
	return _socket("Socket_Delivery").global_transform


func _socket(socket_name: String) -> Node3D:
	return shell.find_child(socket_name, true, false) as Node3D


func _place_counter() -> void:
	var socket := _socket("Socket_Counter")
	var table := TABLE.instantiate() as Node3D
	add_child(table)
	table.global_transform = socket.global_transform
	var computer := COMPUTER.instantiate() as Node3D
	add_child(computer)
	computer.global_transform = (table.find_child("Socket_PC", true, false) as Node3D).global_transform
	counter_zone = InteractionZone.new()
	counter_zone.prompt_text = counter_prompt
	counter_zone.zone_size = COUNTER_ZONE_SIZE
	add_child(counter_zone)
	counter_zone.global_position = socket.global_position
	counter_zone.interacted.connect(_on_counter)


func _on_counter(_by: Node3D) -> void:
	if panel_group != "":
		get_tree().call_group(panel_group, "show_ui")   # même appel que PhonePanel


# Voiture d'exposition : le .glb posé sur son repère, avec une boîte de collision à sa taille.
func _place_display(path: String, socket: Node3D) -> void:
	var scene := load(path) as PackedScene
	if scene == null or socket == null:
		push_warning("%s : voiture exposée impossible (%s)" % [name, path])
		return
	var car := scene.instantiate() as Node3D
	add_child(car)
	car.global_transform = socket.global_transform
	var to_car := car.global_transform.affine_inverse()
	var bounds := AABB()
	var has := false
	for n in car.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var b := (to_car * mi.global_transform) * mi.mesh.get_aabb()
		bounds = bounds.merge(b) if has else b
		has = true
	if not has:
		return
	var box := BoxShape3D.new()
	box.size = bounds.size
	var collision := CollisionShape3D.new()
	collision.shape = box
	collision.position = bounds.get_center()
	var body := StaticBody3D.new()
	body.add_child(collision)
	car.add_child(body)
