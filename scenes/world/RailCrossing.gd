extends Node3D

# Passage à niveau (chantier des trains, étape 4). Deux mécanismes, indépendants du trafic routier :
#
#  - BLOCS D'ARRÊT INVISIBLES : un Node3D par sens de circulation, posé sur l'axe de la voie de ce sens, en amont du
#    passage. Ils sont AJOUTÉS au groupe "vehicle" quand le passage se ferme et RETIRÉS quand il se rouvre. Les
#    voitures freinent déjà toutes seules derrière un membre de ce groupe (Car._obstacle_speed_limit) : aucune ligne
#    de Car.gd, de CircuitPath ni du graphe de circulation n'est touchée.
#    Vérifié avant de s'y brancher : WorldTrafficSmokeTest ne retient que les vrais véhicules (_is_ai exige une
#    propriété `_path`, que ces blocs n'ont pas), et SimulationCuller sait endormir un noeud sans
#    set_simulation_active (il se rabat sur set_process). Les blocs ne sont donc comptés ni comme voitures ni comme
#    paires qui se chevauchent, et ils ne sont dans le groupe que pendant la fermeture.
#
#  - BARRIÈRES EN DÉCOR : un mât et une lisse de chaque côté, la lisse pivotant de la verticale à l'horizontale.
#    Purement visuelles, sans collision : ce sont les blocs qui arrêtent le trafic. Un seul matériau pour les quatre
#    mâts et les quatre lisses de la carte.

const STOP_CLEAR := 3.0        # m entre le bord de la coupure de plateforme et le bloc d'arrêt
const BOOM_LENGTH := 5.2
const POST_HEIGHT := 1.25
const SWING := 1.6             # s pour lever ou baisser une lisse

var closed := false
var pos := Vector3.ZERO
var s := 0.0                   # abscisse du passage sur la voie
var road_name := ""

var _blocks: Array[Node3D] = []
var _booms: Array[Node3D] = []
var _t := 0.0                  # 0 = lisse levée, 1 = lisse baissée


func setup(crossing: Dictionary, material: Material) -> void:
	pos = crossing["pos"]
	s = float(crossing["s"])
	road_name = String(crossing["road"])
	name = "Passage_%s" % road_name.replace(":", "_")
	var rd: Vector2 = crossing["road_dir"]
	var road := Vector3(rd.x, 0.0, rd.y).normalized()
	var width := float(crossing["road_width"])
	var stop := float(crossing["half_gap"]) + STOP_CLEAR
	for way: float in [1.0, -1.0]:
		# sens de marche `d` : la voiture arrive du côté -d et roule sur sa droite (circulation à droite)
		var d := road * way
		var right := d.cross(Vector3.UP).normalized()
		var block := Node3D.new()
		block.name = "Bloc%s" % ("A" if way > 0.0 else "B")
		add_child(block)
		block.position = pos - d * stop + right * (width * 0.25)
		_blocks.append(block)
		var mast := Node3D.new()
		mast.name = "Mat%s" % ("A" if way > 0.0 else "B")
		add_child(mast)
		mast.position = pos - d * stop + right * (width * 0.5 + 0.9)
		# la lisse se rabat vers l'intérieur de la chaussée : le mât regarde vers -right
		mast.basis = Basis(Vector3.UP, atan2(-right.x, -right.z))
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.22, POST_HEIGHT, 0.22)
		post.mesh = pm
		post.material_override = material
		post.position = Vector3(0, POST_HEIGHT * 0.5, 0)
		mast.add_child(post)
		var pivot := Node3D.new()
		pivot.name = "Lisse"
		pivot.position = Vector3(0, POST_HEIGHT, 0)
		mast.add_child(pivot)
		_booms.append(pivot)
		var boom := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.16, 0.26, BOOM_LENGTH)   # assez épaisse pour se lire depuis une voiture qui arrive
		boom.mesh = bm
		boom.material_override = material
		boom.position = Vector3(0, 0, -BOOM_LENGTH * 0.5)
		pivot.add_child(boom)
	_apply(0.0)


func set_closed(value: bool) -> void:
	if value == closed:
		return
	closed = value
	for b: Node3D in _blocks:
		if closed:
			b.add_to_group("vehicle")
		else:
			b.remove_from_group("vehicle")


func _physics_process(delta: float) -> void:
	var target := 1.0 if closed else 0.0
	if is_equal_approx(_t, target):
		return
	_t = move_toward(_t, target, delta / SWING)
	_apply(_t)


# t = 0 : lisse verticale, passage ouvert ; t = 1 : lisse horizontale au-dessus de la chaussée.
# Rotation de +90° autour de X : la lisse, posée sur -Z, se dresse vers le haut.
func _apply(t: float) -> void:
	for pivot: Node3D in _booms:
		pivot.rotation = Vector3(deg_to_rad(lerpf(90.0, 0.0, t)), 0.0, 0.0)


func report() -> Dictionary:
	var blocks: Array = []
	for b: Node3D in _blocks:
		blocks.append({"pos": b.global_position, "dans_groupe": b.is_in_group("vehicle")})
	return {"route": road_name, "pos": pos, "ferme": closed, "lisse": snappedf(_t, 0.01), "blocs": blocks}
