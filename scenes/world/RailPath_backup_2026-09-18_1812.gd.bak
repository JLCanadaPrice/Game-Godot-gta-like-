class_name RailPath
extends Node3D

# Voie ferrée du monde : charge le tracé cuit par RoadBake (generated/roads/rail_path.tres) et sert de repère à tous
# les trains. Même rôle que CircuitPath pour les voitures, en beaucoup plus simple : la voie est UNIQUE, sans
# aiguillage ni évitement, et se termine par deux culs-de-sac.
#
# L'abscisse curviligne `s` va de 0 (bout est, vers Eastgate) à `length` (bout ouest). Tout le reste du chantier des
# trains ne manipule que des `s` : la position et l'orientation d'une caisse sortent de `transform_at()`.

const RES := "res://scenes/world/map/generated/roads/rail_path.tres"
const TRAIN_SCRIPT := preload("res://scenes/world/Train.gd")
const HIGH_SPEED := ["HighSpeed_Front", "HighSpeed_Wagon", "HighSpeed_Wagon", "HighSpeed_Wagon", "HighSpeed_Wagon"]

@export var run_trains := true
@export var high_speed_kmh := 90.0

var data: MapRailPath
var length := 0.0
var trains: Array = []


func _ready() -> void:
	if not ResourceLoader.exists(RES):
		push_error("rail_path.tres absent : relancer RoadBake")
		return
	data = load(RES)
	length = data.length
	if run_trains:
		# étape 2 : une seule rame grande vitesse, 1 motrice + 4 remorques, partie du bout ouest vers l'est.
		# L'étape 3 remplacera cette pose unique par des vagues de plusieurs trains.
		_add(HIGH_SPEED, length - 40.0, -1, high_speed_kmh / 3.6)


func _add(models: Array, at_head: float, dir: int, v: float) -> Node3D:
	var t: Node3D = TRAIN_SCRIPT.new()
	t.name = "Train%d" % trains.size()
	t.setup(self, models, at_head, dir, v)
	add_child(t)
	trains.append(t)
	return t


func at(s: float) -> Vector3:
	return Vector3.ZERO if data == null else data.at(s)


func heading(s: float) -> Vector3:
	return Vector3.FORWARD if data == null else data.heading(s)


# Repère d'une caisse dont le CENTRE est à l'abscisse `s` et dont la demi-longueur est `half` : l'assiette est prise
# sur les deux bogies (avant et arrière), pas sur le seul point central, sinon une caisse de 11 m coupe la corde dans
# les courbes et son nez sort de la voie. `sign` vaut +1 si la caisse avance vers les abscisses croissantes.
func transform_at(s: float, half: float, sign: float) -> Transform3D:
	var bogie := half * 0.75
	var rear := at(s - bogie * sign)
	var front := at(s + bogie * sign)
	var dir := front - rear
	if dir.length_squared() < 0.000001:
		dir = heading(s) * sign
	dir = dir.normalized()
	var right := dir.cross(Vector3.UP)
	if right.length_squared() < 0.000001:
		right = Vector3.RIGHT
	right = right.normalized()
	# Base de Godot : colonnes (droite, haut, ARRIÈRE), l'avant étant -Z. Le haut se déduit de l'arrière et de la
	# droite, dans cet ordre : up = back x right. L'écrire right.cross(back) donne une base MIROIR (déterminant
	# négatif), qui retourne le sens de toutes les faces — le train devient invisible sous tous les angles.
	var back := -dir
	var basis := Basis(right, back.cross(right).normalized(), back)
	return Transform3D(basis, (rear + front) * 0.5)


# Abscisse du passage à niveau le plus proche de `s`, ou -1 s'il n'y en a pas. Sert à l'étape 4.
func crossings() -> Array:
	return [] if data == null else data.crossings
