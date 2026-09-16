extends Node3D
class_name TrafficLight

# Feu tricolore visuel : bascule le matériau du modèle selon l'état
# (rouge/orange/vert). Trois matériaux, un par état, partagés par TOUS les
# feux (cf. _state_materials) : un feu change d'état en changeant de
# matériau, jamais en modifiant un matériau, donc l'état visuel d'un feu
# reste indépendant des autres. Auparavant un matériau dupliqué par feu dont
# on changeait la texture : 378 matériaux distincts = 378 appels de dessin ;
# partagés, les feux d'un même état sont dessinés ensemble (instanciation
# automatique du moteur).
#
# Ancienne approche (abandonnée) : garder tl_texture.png comme albedo fixe
# et superposer une texture d'émission (masque couleur) par-dessus. Cause
# du "boîtier tout blanc" jamais résolue malgré émission correcte (texture
# swap vérifié, energy calibrée, calque dédié pour exclure le spot de rue
# proche, matériau non-métallique) : confirmé par un test isolé (lumière du
# spot coupée à 0) que ce n'était PAS un problème de lumière/exposition.
# Cause exacte encore non identifiée (import/shader), donc contournée :
# 3 textures albedo complètes et autonomes (boîtier + lentille déjà fusionnés
# pixel par pixel), une par état, sans aucune dépendance à l'émission.
#
# Purement visuel : ne décide rien elle-même. L'état réel vient toujours de
# CircuitPath (déjà géré par Car.gd pour la logique de conduite) via
# circuit_path + circuit_node + circuit_edge, réglés par le script de
# placement au moment de la construction (cf. plan de placement).

enum State { RED, YELLOW, GREEN }

const TEX_RED := preload("res://assets/traffic_light/albedo_red_bright.png")
const TEX_YELLOW := preload("res://assets/traffic_light/albedo_yellow_bright.png")
const TEX_GREEN := preload("res://assets/traffic_light/albedo_green_bright.png")

const POLL_INTERVAL := 0.25   # l'état ne change que toutes les quelques secondes, pas besoin de 60 Hz

@export var circuit_path: NodePath      # vers le noeud "Circuit" (CircuitPath) du monde
@export var circuit_node: int = -1      # index du noeud de carrefour contrôlé
@export var circuit_edge: int = -1      # index de l'arête (direction d'approche) contrôlée

# matériau importé du FBX -> [rouge, orange, vert] (indexé par State), créé au premier feu
static var _state_materials := {}

var _circuit: CircuitPath
var _mesh: MeshInstance3D
var _materials: Array = []              # les 3 matériaux partagés de ce modèle
var _current_state := -1
var _poll_timer := 0.0

func _ready() -> void:
	_mesh = find_child("trafic light", true, false) as MeshInstance3D
	if _mesh == null:
		push_warning("TrafficLight: modèle 'trafic light' introuvable sous " + str(get_path()))
		return
	# Calque visuel dédié (2), distinct du calque par défaut (1) utilisé par
	# tout le reste (route, bâtiments, etc.) : le lampadaire de rue placé à
	# ~2.5m de ce boîtier (cône de 44°, énergie 16) le surexposait en blanc
	# uni. Son light_cull_mask exclut désormais ce calque (cf. build script),
	# donc il n'éclaire plus le feu directement ; le soleil (DirectionalLight3D,
	# cull_mask par défaut = tous les calques) continue lui de l'éclairer
	# normalement, donc pas d'effet "plat/non éclairé".
	_mesh.layers = 2
	var base := _mesh.get_active_material(0) as StandardMaterial3D
	if base == null:
		push_warning("TrafficLight: matériau de base introuvable")
		return
	if not _state_materials.has(base):
		var mats := []
		for tex in [TEX_RED, TEX_YELLOW, TEX_GREEN]:
			var mat := base.duplicate() as StandardMaterial3D
			# Émission plus utilisée du tout : la couleur vient désormais directement
			# de l'albedo_texture, qui contient déjà le boîtier ET la lentille
			# allumée fusionnés dans une seule image par état.
			mat.emission_enabled = false
			mat.albedo_texture = tex
			mats.append(mat)
		_state_materials[base] = mats
	_materials = _state_materials[base]

	_circuit = get_node_or_null(circuit_path) as CircuitPath
	set_state(State.RED)   # état de repli tant que le premier sondage n'a pas eu lieu
	_poll_timer = randf_range(0.0, POLL_INTERVAL)   # déphasage aléatoire : évite que tous les feux se recalculent la même frame

func _process(delta: float) -> void:
	if _circuit == null or circuit_node < 0 or circuit_edge < 0:
		return
	_poll_timer -= delta
	if _poll_timer > 0.0:
		return
	_poll_timer = POLL_INTERVAL
	set_state(_circuit.light_color(circuit_edge, circuit_node))

# Pose le matériau de l'état (rouge/orange/vert) : chaque texture contient
# déjà le boîtier complet avec la bonne lentille allumée intégrée.
# N'agit que si l'état a réellement changé, pour éviter une réaffectation de
# matériau inutile à chaque sondage.
func set_state(state: int) -> void:
	if state == _current_state or _materials.is_empty():
		return
	_current_state = state
	match state:
		State.RED, State.YELLOW, State.GREEN:
			_mesh.set_surface_override_material(0, _materials[state])
