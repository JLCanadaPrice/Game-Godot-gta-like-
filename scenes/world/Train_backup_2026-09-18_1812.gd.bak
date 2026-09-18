class_name Train
extends Node3D

# Une rame posée sur la voie (RailPath). La rame n'est qu'une abscisse `s` (celle du NEZ de la caisse de tête) et une
# liste de caisses : chaque caisse calcule son propre repère depuis la voie, donc la rame suit les courbes et les
# pentes sans aucune physique.
#
# Les caisses sont des MeshInstance3D sur les maillages cuits par TrainsBake (une surface, un matériau partagé, pas
# d'émission). Elles n'ont pas de collision : rien ne doit pouvoir pousser un train, et le trafic routier est arrêté
# aux passages à niveau par des blocs dédiés (étape 4), pas par le train lui-même.

const MODELS := "res://scenes/world/map/generated/trains/"
const SPECS := MODELS + "trains.json"
const COUPLING := 0.9        # m entre deux caisses
const BUFFER_MARGIN := 14.0  # m gardés devant le heurtoir au terminus

@export var composition: Array = []               # noms de modèles, la tête en premier
@export var speed := 22.0                         # m/s
@export var direction := -1                       # +1 : vers les abscisses croissantes ; -1 : l'inverse
@export var head := 0.0                           # abscisse du nez de la caisse de tête
@export var dwell := 8.0                          # s d'arrêt au terminus avant de repartir du bout opposé

var rake_length := 0.0
var stopped := false

var _start := 0.0
var _dwell := 0.0
var _rail: Node3D
var _cars: Array[MeshInstance3D] = []
var _half: PackedFloat32Array = PackedFloat32Array()   # demi-longueur de chaque caisse
var _offset: PackedFloat32Array = PackedFloat32Array()  # distance du nez de la rame au CENTRE de chaque caisse


func setup(rail: Node3D, models: Array, at_head: float, dir: int, v: float) -> void:
	_rail = rail
	composition = models
	head = at_head
	direction = dir
	speed = v


func _ready() -> void:
	if _rail == null:
		_rail = get_parent() as Node3D
	if _rail == null or composition.is_empty():
		push_error("Train sans voie ou sans composition")
		return
	var specs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SPECS))
	var walked := 0.0
	for name: String in composition:
		var path := MODELS + name + ".res"
		if not ResourceLoader.exists(path) or not specs.has(name):
			push_error("caisse inconnue : %s" % name)
			continue
		var half := float(specs[name]["longueur"]) * 0.5
		var mi := MeshInstance3D.new()
		mi.mesh = load(path)
		mi.name = "%02d_%s" % [_cars.size(), name]
		add_child(mi)
		_cars.append(mi)
		_half.append(half)
		_offset.append(walked + half)
		walked += half * 2.0 + COUPLING
	rake_length = maxf(walked - COUPLING, 0.0)
	_start = head
	_place()


func _physics_process(delta: float) -> void:
	if _rail == null:
		return
	if _dwell > 0.0:
		_dwell -= delta
		if _dwell <= 0.0:
			head = _start
			_place()
		return
	if stopped:
		return
	head += speed * delta * direction
	# terminus : la rame s'arrête avant le heurtoir, marque un arrêt, puis repart du bout opposé, motrice en tête
	# (les vagues à sens unique de l'étape 3 reprendront exactement ce principe)
	var limit: float = (float(_rail.length) - BUFFER_MARGIN) if direction > 0 else BUFFER_MARGIN
	if (direction > 0 and head >= limit) or (direction < 0 and head <= limit):
		head = limit
		_dwell = dwell
	_place()


# Pose chaque caisse : son centre est à `head` moins son décalage, compté dans le sens de la marche.
# RailPath.transform_at() rend un repère MONDE ; la rame et la voie sont à l'origine, donc il s'applique tel quel en
# local. (Un top_level sur les caisses a été essayé et écarté : posé avant l'entrée dans l'arbre, il laissait le
# maillage dessiné loin de la position du nœud.)
func _place() -> void:
	for i in _cars.size():
		var s := head - _offset[i] * direction
		_cars[i].transform = _rail.transform_at(s, _half[i], float(direction))


# Abscisse de l'arrière de la rame (la queue), dans le sens de la marche.
func tail() -> float:
	return head - rake_length * direction
