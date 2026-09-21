extends Node3D

# Spawner générique multi-points.
#
#  - kind = "vehicle" : spawn sur CircuitPath (graphe routier), à chaque
#    noeud (carrefour) de `spawn_nodes`. L'entité reçoit
#    setup(circuit, node_index, speed, lateral, edges_budget) et choisit
#    elle-même une arête de départ au hasard depuis ce noeud.
#  - kind = "npc"     : spawn sur PathGraph (réseau piéton), à chaque index de
#    `spawn_nodes`. L'entité reçoit setup(graph, node_index, 0, 0, edges_budget).
#
# Chaque point d'apparition a SON PROPRE compte à rebours et SA PROPRE
# vérification de distance : les points sont indépendants et répartis tout
# autour du circuit / du réseau. `max_active` plafonne le total pour le FPS.
#
# proximity = true (carte 3D) : les points d'apparition sont tous les noeuds
# du graphe (y compris ceux ajoutés par la carte) situés entre proximity_min
# et proximity_max du joueur, relus régulièrement ; les entités endormies par
# SimulationCuller au-delà de recycle_distance sont supprimées pour que le
# quota suive le joueur (jamais une voiture conduite ou achetée par le joueur).

@export var spawn_scene: PackedScene
@export var kind: String = "vehicle"

@export var circuit_path: NodePath           # utilisé si kind == "vehicle"
@export var graph_path: NodePath             # utilisé si kind == "npc"

@export var spawn_nodes: Array[int] = [0]    # points d'apparition (index de noeud du graphe)

@export var max_active: int = 12
@export var interval_min: float = 1.5
@export var interval_max: float = 4.5
@export var min_gap: float = 12.0            # rayon libre exigé autour du point

@export var speed_min: float = 11.0          # voitures seulement
@export var speed_max: float = 13.0
@export var laterals: Array[float] = [2.0]   # voitures : décalage de voie

@export var vehicle_edges_budget: int = 30   # voitures : arêtes parcourues avant despawn
@export var npc_edges_budget: int = 10       # PNJ : segments avant despawn

# PNJ : faction visuelle tirée au sort à chaque apparition (poids relatifs, cf. NPC.faction).
# Mettre police / police_riot à 0 pour ne faire apparaître que des civils.
@export var npc_faction_weights: Dictionary = {&"civil": 90, &"police": 7, &"police_riot": 3}

@export var proximity := false
@export var proximity_min := 60.0
@export var proximity_max := 400.0
@export var recycle_distance := 700.0
const PROXIMITY_REFRESH := 1.0
const SLEEP_META := &"sim_sleeping"   # posé par SimulationCuller

var _circuit: CircuitPath
var _graph: PathGraph
var _cooldowns: PackedFloat32Array = PackedFloat32Array()
var _points := 0
var _near: PackedInt32Array = PackedInt32Array()   # proximity : noeuds dans l'anneau autour du joueur
var _refresh := 0.0

func _ready() -> void:
	_circuit = get_node_or_null(circuit_path) as CircuitPath
	_graph = get_node_or_null(graph_path) as PathGraph
	_points = spawn_nodes.size()
	_cooldowns.resize(_points)
	for i in _points:
		_cooldowns[i] = randf_range(interval_min, interval_max)

func _process(delta: float) -> void:
	if spawn_scene == null:
		return
	if kind == "vehicle" and _circuit == null:
		return
	if kind == "npc" and _graph == null:
		return
	if proximity:
		_process_proximity(delta)
		return
	if _points == 0:
		return

	for i in _points:
		_cooldowns[i] -= delta
		if _cooldowns[i] > 0.0:
			continue
		_cooldowns[i] = randf_range(interval_min, interval_max)
		if _actifs() >= max_active:
			continue
		_try_spawn(i)

# Mode proximity : un compte à rebours par noeud du graphe, seuls les noeuds de l'anneau autour du joueur tentent une
# apparition ; recyclage des entités endormies trop loin.
func _process_proximity(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var count := _node_count()
	if _cooldowns.size() != count:
		var old := _cooldowns.size()
		_cooldowns.resize(count)
		for i in range(old, count):
			_cooldowns[i] = randf_range(interval_min, interval_max)
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = PROXIMITY_REFRESH
		_near.clear()
		var origin := player.global_position
		for i in count:
			var d := _node_position(i).distance_to(origin)
			if d >= proximity_min and d <= proximity_max:
				_near.append(i)
		_recycle(origin)
	var active := get_tree().get_nodes_in_group(kind).size()
	for i in _near:
		_cooldowns[i] -= delta
		if _cooldowns[i] > 0.0:
			continue
		_cooldowns[i] = randf_range(interval_min, interval_max)
		if active >= max_active:
			continue
		if _spawn_at(i):
			active += 1

func _node_count() -> int:
	return _circuit.node_count() if kind == "vehicle" else _graph.nodes.size()

func _node_position(i: int) -> Vector3:
	return _circuit.node_pos(i) if kind == "vehicle" else _graph.node_pos(i)

func _recycle(origin: Vector3) -> void:
	for e in get_tree().get_nodes_in_group(kind):
		var body := e as Node3D
		if body == null or body.get_parent() != self or not bool(body.get_meta(SLEEP_META, false)):
			continue
		if body.get("driven_by_player") == true or body.get("is_player_owned") == true:
			continue   # (propriétés absentes des PNJ : get() renvoie null)
		if body.global_position.distance_to(origin) > recycle_distance:
			body.queue_free()

func _try_spawn(point_index: int) -> void:
	_spawn_at(spawn_nodes[point_index])

# Apparition au noeud `node` du graphe si la place est libre et hors de vue du joueur ; vrai si une entité est née.
func _spawn_at(node: int) -> bool:
	var spawn_pos: Vector3
	var lateral := 0.0
	if kind == "vehicle":
		lateral = laterals[randi() % laterals.size()]
		spawn_pos = _circuit.node_pos(node)
	else:
		spawn_pos = _graph.node_pos(node)

	for e in get_tree().get_nodes_in_group(kind):
		if e is Node3D and e.global_position.distance_to(spawn_pos) < min_gap:
			return false   # ce point d'apparition est encore occupé

	if _is_visible_to_player(spawn_pos):
		return false   # anti-spawn visible : le joueur regarde déjà ce point, on retente au prochain cooldown

	var ent := spawn_scene.instantiate()
	if kind == "npc" and "faction" in ent:
		ent.faction = _pick_faction()   # avant add_child : NPC._ready charge la tenue de la faction
	add_child(ent)
	if not ent.has_method("setup"):
		return true
	if kind == "vehicle":
		ent.setup(_circuit, node, randf_range(speed_min, speed_max), lateral, vehicle_edges_budget)
	else:
		ent.setup(_graph, node, 0.0, 0.0, npc_edges_budget)
	return true

# Tirage pondéré dans npc_faction_weights ; civil si la table est vide ou à zéro.
func _pick_faction() -> StringName:
	var total := 0.0
	for w in npc_faction_weights.values():
		total += float(w)
	var roll := randf() * total
	for f in npc_faction_weights:
		roll -= float(npc_faction_weights[f])
		if roll < 0.0:
			return StringName(f)
	return &"civil"

# Anti-spawn visible : vrai si `spawn_pos` est à la fois dans le cône de
# vision du joueur (devant la caméra, cos > 0.5 ~ 60° de demi-angle) ET en
# ligne de vue directe (aucun obstacle -- calque 1 = décor statique :
# route/trottoir/terrain/bâtiments -- entre les deux). Si un bâtiment (ou
# autre décor) masque déjà le point, ce n'est PAS considéré visible -> le
# spawn est autorisé, conformément à la consigne.
func _is_visible_to_player(spawn_pos: Vector3) -> bool:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return false

	var cam := player.get("camera") as Camera3D
	var eye_pos: Vector3 = cam.global_position if cam != null else (player as Node3D).global_position
	var forward: Vector3 = -cam.global_transform.basis.z if cam != null else -(player as Node3D).global_transform.basis.z

	var to_spawn := spawn_pos - eye_pos
	var dist := to_spawn.length()
	if dist < 0.01:
		return true
	var dir := to_spawn / dist

	if dir.dot(forward) < 0.5:
		return false   # hors du cône de vision -> inutile de raycaster

	var space_state := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(eye_pos, spawn_pos)
	params.collision_mask = 1
	params.exclude = [player.get_rid()]
	var hit := space_state.intersect_ray(params)
	if hit.is_empty():
		return true   # rien entre la caméra et le point -> vraiment visible

	var hit_dist: float = eye_pos.distance_to(hit["position"] as Vector3)
	return hit_dist >= dist - 0.5   # un obstacle plus proche que le point = masqué, pas visible


# Entités que CE spawner a fait naître. Compter tout le groupe `vehicle` était juste tant que
# personne d'autre n'en posait ; depuis, les véhicules garés des lieux (commissariat, hôpital,
# casernes, aéroport) en font partie et sont là en permanence. Les compter dans le plafond revenait à
# retirer autant de voitures à la circulation de fond — le même effet de bord que les blocs d'arrêt
# des passages à niveau, corrigé ici une fois pour toutes. Même critère que _recycle : le parent.
func _actifs() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group(kind):
		if e is Node and (e as Node).get_parent() == self:
			n += 1
	return n
