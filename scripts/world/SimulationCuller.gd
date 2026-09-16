extends Node

# Coupe le calcul des voitures et PNJ que le joueur ne peut pas voir : à la fois loin de lui (> sleep_distance) et
# hors de sa vue, c'est-à-dire hors du frustum de la caméra active ou cachés par le décor (rayon caméra -> entité sur
# le calque du décor statique, même critère de ligne de vue que l'anti-spawn de LoopSpawner). Process, physique et
# animation à l'arrêt (set_simulation_active), sans suppression ni déplacement ; réveil dès que l'entité redevient
# visible ou à portée, avec reprise exacte de son état (une voiture arrêtée au feu relit le feu du moment, cf.
# Car.set_simulation_active).
# Le frustum seul (critère d'un VisibleOnScreenNotifier3D) ne suffit pas en ville : caméra tournée vers les rues,
# 222 voitures et 265 PNJ sur 252 / 315 restaient "à l'écran" derrière les bâtiments, pour le même coût CPU que sans
# culling (38 ms par frame, cf. CityPerfTest).
# Une entité vue récemment reste active linger_seconds (pas de bascule au ras d'un coin de bâtiment ou d'un bord
# d'écran), et une voiture retenue par une voiture endormie la garde éveillée (Car._keep_awake) : une file dont la
# tête est hors de vue avance quand même.

const META := &"sim_sleeping"
const SEEN_META := &"sim_seen_frame"
const KEEP_AWAKE_META := &"sim_keep_awake_frame"   # posé par Car._keep_awake

@export var groups: PackedStringArray = ["vehicle", "npc"]
@export var sleep_distance := 50.0   # m : au-delà ET hors de vue -> endormi
@export var wake_distance := 45.0    # m : en deçà -> réveillé (hystérésis contre le clignotement)
@export var view_margin := 24.0      # m ajoutés autour du frustum : au moins la portée de détection d'obstacle
                                     # d'une voiture (22 m)
@export var occlusion := true        # rayon de ligne de vue caméra -> entité
@export var occlusion_mask := 1      # décor statique : route, trottoirs, terrain, bâtiments
@export var target_height := 1.0     # m au-dessus de l'origine de l'entité visés par le rayon
@export var linger_seconds := 2.0    # reste active ce temps après avoir été vue
@export var slices := 3              # entités réévaluées par tiers à chaque frame physique
@export var enabled := true

var active_count := 0
var sleeping_count := 0
var rays_last_frame := 0
var last_cost_usec := 0              # coût de la dernière passe (mesures de perf)
var _frame := 0
var _ray := PhysicsRayQueryParameters3D.new()
var _driven: Node3D                  # voiture conduite par le joueur : jamais endormie, ignorée par les rayons


func _physics_process(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_frame += 1
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var cam := get_viewport().get_camera_3d()
	var planes: Array[Plane] = []
	var eye := Vector3.ZERO
	var space: PhysicsDirectSpaceState3D = null
	if cam != null:
		planes.assign(cam.get_frustum())
		eye = cam.global_position
		if occlusion:
			space = cam.get_world_3d().direct_space_state
			_ray.collision_mask = occlusion_mask
			_ray.exclude = _excluded_rids(player)
	var origin := player.global_position if player != null else Vector3.ZERO
	var physics_frame := Engine.get_physics_frames()
	rays_last_frame = 0
	var active := 0
	var sleeping := 0
	var index := 0
	for group in groups:
		for e in get_tree().get_nodes_in_group(group):
			index += 1
			var body := e as Node3D
			if body == null:
				continue
			var was_sleeping := bool(body.get_meta(META, false))
			if (index + _frame) % maxi(slices, 1) == 0:
				var sleep := enabled and player != null and _should_sleep(body, origin, eye, planes, space, physics_frame, was_sleeping)
				if sleep != was_sleeping:
					_set_active(body, not sleep)
					was_sleeping = sleep
			if was_sleeping:
				sleeping += 1
			else:
				active += 1
	active_count = active
	sleeping_count = sleeping
	last_cost_usec = Time.get_ticks_usec() - t0


# Réveille tout de suite toutes les entités endormies (désactivation du culling, fin de test).
func wake_all() -> void:
	for group in groups:
		for e in get_tree().get_nodes_in_group(group):
			if bool(e.get_meta(META, false)):
				_set_active(e, true)


func _should_sleep(body: Node3D, origin: Vector3, eye: Vector3, planes: Array[Plane], space: PhysicsDirectSpaceState3D, frame: int, was_sleeping: bool) -> bool:
	if body.get("driven_by_player") == true:
		_driven = body
		return false
	if int(body.get_meta(KEEP_AWAKE_META, 0)) > frame:
		return false
	var pos := body.global_position
	if pos.distance_to(origin) <= (wake_distance if was_sleeping else sleep_distance):
		return false
	if _in_view(pos, eye, planes, space):
		body.set_meta(SEEN_META, frame)
		return false
	return frame - int(body.get_meta(SEEN_META, -1000000)) > int(linger_seconds * Engine.physics_ticks_per_second)


# Dans le frustum élargi de view_margin et, avec occlusion, sans décor entre la caméra et l'entité.
func _in_view(pos: Vector3, eye: Vector3, planes: Array[Plane], space: PhysicsDirectSpaceState3D) -> bool:
	if planes.is_empty():
		return false
	var radius := view_margin + 3.0
	for plane in planes:
		if plane.distance_to(pos) > radius:
			return false
	if space == null:
		return true
	var target := pos + Vector3.UP * target_height
	_ray.from = eye
	_ray.to = target
	rays_last_frame += 1
	var hit := space.intersect_ray(_ray)
	return hit.is_empty() or eye.distance_to(hit.position) >= eye.distance_to(target) - 2.0


func _excluded_rids(player: Node3D) -> Array[RID]:
	var rids: Array[RID] = []
	if player is CollisionObject3D:
		rids.append((player as CollisionObject3D).get_rid())
	if is_instance_valid(_driven) and _driven.get("driven_by_player") == true:
		rids.append((_driven as CollisionObject3D).get_rid())
	return rids


func _set_active(body: Node, active: bool) -> void:
	body.set_meta(META, not active)
	if body.has_method("set_simulation_active"):
		body.set_simulation_active(active)
	else:
		body.set_process(active)
		body.set_physics_process(active)
