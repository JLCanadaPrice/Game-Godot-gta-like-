class_name RailPath
extends Node3D

# Voie ferrée du monde : charge le tracé cuit par RoadBake (generated/roads/rail_path.tres), sert de repère à toutes
# les rames, et joue le rôle de poste d'aiguillage. Même rôle que CircuitPath pour les voitures, en beaucoup plus
# simple : la voie est UNIQUE, sans aiguillage ni évitement, et se termine par deux culs-de-sac.
#
# L'abscisse curviligne `s` va de 0 (bout est) à `length` (bout ouest). Tout le chantier des trains ne manipule que
# des `s` : la position et l'orientation d'une caisse sortent de `transform_at()`.
#
# Exploitation (étape 3), sur une voie unique sans évitement :
#  - VAGUES À SENS UNIQUE : tous les trains d'une vague partent du même bout et roulent dans le même sens. Quand la
#    vague est arrivée et la voie libre, la vague suivante part de l'autre bout. Deux trains ne peuvent donc jamais
#    se croiser, ce qu'une voie unique ne permettrait pas.
#  - CANTONS de BLOCK m : un train ne peut entrer dans un canton que si aucun autre ne l'occupe. Sinon il freine pour
#    s'arrêter à l'entrée du canton, exactement comme devant un signal fermé. Le terminus est traité comme un canton
#    définitivement occupé.

const RES := "res://scenes/world/map/generated/roads/rail_path.tres"
const TRAIN_SCRIPT := preload("res://scenes/world/Train.gd")

const HIGH_SPEED := ["HighSpeed_Front", "HighSpeed_Wagon", "HighSpeed_Wagon", "HighSpeed_Wagon", "HighSpeed_Wagon"]
const FREIGHT := ["CargoTrain_Front",
	"CargoTrain_Wagon", "CargoTrain_Container", "CargoTrain_CoalContainer", "CargoTrain_Container",
	"CargoTrain_CoalContainer", "CargoTrain_Wagon", "CargoTrain_Container", "CargoTrain_CoalContainer",
	"CargoTrain_Container", "CargoTrain_Wagon", "CargoTrain_CoalContainer", "CargoTrain_Container",
	"CargoTrain_CoalContainer", "CargoTrain_Container"]

@export var run_trains := true
@export var block_length := 280.0        # m : longueur d'un canton
@export var wave_size := 3               # trains par vague
@export var max_trains := 4              # plafond absolu
@export var headway := 16.0              # s entre deux départs d'une même vague
@export var turnaround := 30.0           # s entre l'arrivée d'une vague et le départ de la suivante
@export var buffer_margin := 14.0        # m gardés devant le heurtoir
@export var block_margin := 6.0          # m gardés avant l'entrée d'un canton occupé
@export var high_speed_kmh := 90.0
@export var freight_kmh := 55.0

var data: MapRailPath
var length := 0.0
var trains: Array = []

var _dir := -1                # sens de la vague en cours (-1 : du bout ouest vers l'est)
var _left := 0                # trains restant à lancer dans la vague
var _timer := 0.0
var _launched := 0            # total lancé depuis le début, sert à alterner les compositions
var _occupied := {}           # index de canton -> rame qui l'occupe


func _ready() -> void:
	if not ResourceLoader.exists(RES):
		push_error("rail_path.tres absent : relancer RoadBake")
		return
	data = load(RES)
	length = data.length
	if run_trains:
		_left = wave_size
		_timer = 1.0


func _physics_process(delta: float) -> void:
	if data == null or not run_trains:
		return
	_timer -= delta
	_retire()
	_mark_blocks()
	_signal()
	if _left > 0 and _timer <= 0.0 and trains.size() < max_trains and _departure_clear():
		_launch()
	elif _left == 0 and trains.is_empty() and _timer <= 0.0:
		_dir = -_dir
		_left = wave_size
		_timer = headway


# --- exploitation -----------------------------------------------------------------------------------------------

func _launch() -> void:
	var freight := _launched % 2 == 1
	var models: Array = FREIGHT if freight else HIGH_SPEED
	var v: float = (freight_kmh if freight else high_speed_kmh) / 3.6
	var t := place_rake(models, NAN, _dir, v, "fret" if freight else "grande vitesse")
	t.name = "Train%d" % _launched
	_left -= 1
	_launched += 1
	_timer = headway


# Pose une rame sur la voie. `at_head` à NAN la met à quai au terminus de départ : la rame s'étend DERRIÈRE son nez,
# donc le nez est décalé de toute la longueur de la rame, sinon un fret de 156 m dépasse le bout de la voie.
# Publique pour les tests et les sondes de capture.
func place_rake(models: Array, at_head: float, dir: int, v: float, label: String) -> Node3D:
	var t: Node3D = TRAIN_SCRIPT.new()
	t.name = "Rame%d" % trains.size()
	t.setup(self, models, 0.0, dir, v, label)
	add_child(t)
	var back: float = float(t.rake_length)
	if is_nan(at_head):
		t.head = (buffer_margin + back) if dir > 0 else (length - buffer_margin - back)
	else:
		t.head = at_head
	t.call("_place")
	trains.append(t)
	return t


# Un train qui a atteint son terminus et s'y est arrêté est retiré de la voie.
func _retire() -> void:
	for i in range(trains.size() - 1, -1, -1):
		var t: Node3D = trains[i]
		if not is_instance_valid(t):
			trains.remove_at(i)
			continue
		var arrived: bool = (float(t.head) >= length - buffer_margin - 0.5) if int(t.direction) > 0 else (float(t.head) <= buffer_margin + 0.5)
		if arrived and t.speed <= 0.01:
			trains.remove_at(i)
			t.queue_free()
			if trains.is_empty() and _left == 0:
				_timer = turnaround


# Le départ n'est libre que si aucune rame n'occupe encore le premier canton du bout de départ.
func _departure_clear() -> bool:
	var terminus: float = buffer_margin if _dir > 0 else length - buffer_margin
	for t: Node3D in trains:
		var lo: float = minf(float(t.head), float(t.tail()))
		var hi: float = maxf(float(t.head), float(t.tail()))
		if terminus >= lo - block_length and terminus <= hi + block_length:
			return false
	return true


func _mark_blocks() -> void:
	_occupied.clear()
	for t: Node3D in trains:
		var a: float = minf(t.head, t.tail())
		var b: float = maxf(t.head, t.tail())
		for k in range(_block_of(a), _block_of(b) + 1):
			_occupied[k] = t


# Vitesse maximale de chaque rame : elle doit pouvoir s'arrêter à l'entrée du premier canton occupé devant elle, ou
# devant le heurtoir du terminus. v = sqrt(2 a d), avec la décélération de service de Train.DECEL.
func _signal() -> void:
	for t: Node3D in trains:
		var dir := int(t.direction)
		var stop_at: float = (length - buffer_margin) if dir > 0 else buffer_margin
		var here := _block_of(float(t.head))
		for step in range(1, 5):
			var k: int = here + step * dir
			var other: Variant = _occupied.get(k)
			if other != null and other != t:
				var entry: float = float(k) * block_length if dir > 0 else float(k + 1) * block_length
				stop_at = entry - block_margin * float(dir)
				break
		var gap: float = (stop_at - float(t.head)) * float(dir)
		t.limit = 0.0 if gap <= 0.0 else sqrt(2.0 * TRAIN_SCRIPT.DECEL * gap)


func _block_of(s: float) -> int:
	return floori(s / block_length)


# --- géométrie de la voie ---------------------------------------------------------------------------------------

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


func crossings() -> Array:
	return [] if data == null else data.crossings


# Relevé pour les tests et les sondes : état de chaque rame en circulation.
func report() -> Array:
	var out: Array = []
	for t: Node3D in trains:
		out.append({"nom": String(t.name), "type": String(t.kind), "sens": t.direction, "tete": t.head,
				"queue": t.tail(), "longueur": t.rake_length, "vitesse": t.speed, "limite": t.limit,
				"caisses": t.get_child_count()})
	return out
