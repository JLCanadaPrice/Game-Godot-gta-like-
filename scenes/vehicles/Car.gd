extends CharacterBody3D

# Voiture arcade (CharacterBody3D, pas de VehicleBody3D).
#  - En circulation : suit CircuitPath (spawn/despawn via LoopSpawner).
#  - Conduite : le joueur monte (E via InteractZone), la voiture quitte sa
#    trajectoire scriptée. À la descente -> épave inerte, despawn après 25 s.
#  - Réactions de choc (recul / tilt) : SCRIPTÉES, pas de vraie physique de
#    collision (cf. note du groupe 2 point 8).

# Hauteur d'origine PAR DÉFAUT en circulation (fallback si le modèle FBX ne
# charge pas). En temps normal `_ride_height` est recalculé par
# _fit_collision_to_model() à partir de la vraie boîte de collision ajustée au
# modèle, pour que le bas de caisse repose pile sur la chaussée (dessus à 0.05).
const RIDE_HEIGHT := 0.66
const ROAD_TOP_Y := 0.05         # = CityKitBuilder.SURFACE_Y (surface roulable au-dessus de l'herbe)
const LANE_SNAP := 4.0

# Calque visuel (doit correspondre à Car.tscn et au cull_mask exclu par les
# décalques de passage piéton dans World.tscn) : exclut cette voiture de la
# projection des décalques, qui sinon "fuient" sur la caisse. Le placeholder
# MeshInstance3D de la scène l'a déjà via son propre `layers`, mais il est
# caché (visible=false) dès qu'un modèle FBX aléatoire est chargé -> il faut
# le réappliquer explicitement sur CHAQUE mesh du modèle réellement affiché.
const DECAL_EXCLUDE_LAYERS := 4

const CAR_MODELS := [
	"res://assets/vehicle_models/NormalCar1.fbx",
	"res://assets/vehicle_models/NormalCar2.fbx",
	"res://assets/vehicle_models/SportsCar.fbx",
	"res://assets/vehicle_models/SportsCar2.fbx",
	"res://assets/vehicle_models/SUV.fbx",
	"res://assets/vehicle_models/Taxi.fbx",
]
# "Cop.fbx" volontairement exclu -> réservé police
# Repli seulement : la circulation tire ses modèles dans le catalogue ci-dessous.

# Catalogue des réglages par modèle (resources/vehicle_models/*.tres) : variantes
# de couleur, échelle, orientation, décalage Y, rôle et poids dans la circulation.
const VehicleCatalog := preload("res://scripts/data/VehicleCatalog.gd")

# Modèle imposé (concessionnaire : le joueur choisit un modèle précis dans
# CarDealershipPanel) -- doit être défini AVANT add_child() (donc avant
# _ready()/_setup_model()) puisque c'est là qu'il est lu. Vide = modèle
# tiré au sort dans le catalogue (rôle civil, pondéré par traffic_weight),
# comme pour une voiture de circulation normale.
@export var forced_model_path: String = ""

# Réglages du modèle visuel : remplacés au chargement par ceux du catalogue
# quand le modèle y figure ; ces valeurs ne servent qu'aux modèles absents.
@export var model_scale := 1.0
@export var model_yaw_deg := 180.0        # orientation native du FBX (comme le modèle Player)
# Décalage vertical du modèle visuel par rapport à l'origine. -0.6 posait
# l'origine du FBX pile sur le bas de la BoxShape3D -> la caisse visible
# s'enfonçait dans la route. Relevé à -0.45 pour qu'elle repose dessus. À
# peaufiner par modèle dans resources/vehicle_models/*.tres.
@export var model_y_offset := -0.45
@export var debug_hitbox := false         # imprime la taille de boîte ajustée par modèle
@export var wheel_spin_axis := Vector3(1, 0, 0)   # axe de roulement d'une roue (repère local roue)
# Axe de braquage des roues avant. IMPORTANT : exprimé dans le repère de la
# CAISSE (pas de la roue) -> (0,1,0) = verticale voiture = pivot de direction.
# Appliqué en pré-multiplication dans _update_visuals pour que le braquage se
# fasse toujours autour d'un axe vertical, quelle que soit l'orientation native
# du noeud de roue dans le modèle importé (sinon la roue "cabre" au lieu de braquer).
@export var wheel_steer_axis := Vector3(0, 1, 0)

# --- conduite ---
const DRIVE_ACCEL := 16.0
const DRIVE_MAX_SPEED := 24.0
const DRIVE_REVERSE_MAX := 8.0
const DRIVE_FRICTION := 9.0
const DRIVE_BRAKE := 26.0
const TURN_RATE := 2.4
# Franchissement de bordure, JOUEUR SEULEMENT (cf. _try_step_up). 0,22 m : les bordures de la carte font
# 0,150 m mesurés sur la collision cuite, la marge couvre les raccords de tuiles sans rendre franchissable un
# muret. 0,32 m d'avance testée : un peu plus que ce que la voiture parcourt en une frame à pleine vitesse.
const STEP_UP_MAX := 0.22
const STEP_UP_AHEAD := 0.32
const ABANDON_DESPAWN := 25.0
const GRAVITY := 18.0
const WHEEL_RADIUS := 0.34
const MAX_STEER_RAD := 0.52       # ~30° de braquage visuel
const KNOCK_TIME := 1.2           # durée pendant laquelle une voiture percutée est "sonnée"
const CRUSH_MIN_SPEED := 5.0      # vitesse mini pour écraser un PNJ
const MAX_STAINS := 8

# --- circulation IA : accélération / freinage / virage progressifs ---
const AI_ACCEL := 3.5             # m/s² pour rejoindre la vitesse de croisière
const BRAKE_EPS := 0.05           # m/s de marge : en deçà, la consigne "descend" par simple bruit
const BRAKE_STOP_SPEED := 0.4     # m/s sous quoi la voiture compte comme arrêtée, feux allumés
const AI_DECEL := 12.0            # m/s² pour freiner (obstacle, arrêt) — DOIT correspondre à la
								   # décélération utilisée dans la formule de distance de freinage
								   # ci-dessous, sinon la voiture peut dépasser la marge de sécurité.
const AI_TURN_RATE_DEG := 100.0   # °/s de rotation max -> virage fluide, pas de snap
# Taux de virage PROPORTIONNEL à la vitesse actuelle (rayon de braquage
# réaliste) plutôt qu'un taux fixe : évite l'effet "pivote sur place" quand
# la voiture est encore lente en sortie de carrefour/d'arrêt, tout en
# gardant une trajectoire large et naturelle une fois lancée.
const MIN_TURN_RADIUS := 6.5      # rayon de braquage visé à vitesse de croisière (m)
const MIN_TURN_RATE_DEG := 35.0   # plancher : peut quand même finir un virage à très basse vitesse
const MAX_TURN_RATE_DEG := 130.0  # plafond : jamais un virage plus serré que ça, même très vite

# --- circulation IA : pas de dépassement, suit la voiture/l'obstacle devant ---
# Détection large : à la vitesse de croisière max (~14 m/s), la distance de
# freinage réelle (v²/2a) est d'environ 12 m -> il faut voir l'obstacle bien
# avant pour avoir le temps de ralentir sans dépasser OBSTACLE_BUMPER_GAP.
const OBSTACLE_LOOK_AHEAD := 22.0     # distance de détection devant soi (m)
# Espace visé entre pare-chocs à l'arrêt, longueurs RÉELLES des deux véhicules
# comprises (bus, camions du catalogue) ; remplace l'ancien écart fixe de 5.5 m de
# centre à centre, calibré pour deux voitures de ~4.2 m (5.5 - 2 x 2.1 = 1.3).
const OBSTACLE_BUMPER_GAP := 1.3        # m
const OBSTACLE_DEFAULT_HALF_LENGTH := 2.0 # véhicule sans _half_length : demi-boîte par défaut de Car.tscn
const OBSTACLE_LANE_HALF_WIDTH := 2.5 # tolérance latérale pour considérer "sur ma voie"
# Voiture qui en retient une autre (file, cédez-le-passage) : gardée éveillée par SimulationCuller tant que l'autre
# attend, même si elle est hors de vue du joueur, pour que la file avance au lieu de rester figée.
const SIM_KEEP_AWAKE_META := &"sim_keep_awake_frame"
const SIM_KEEP_AWAKE_FRAMES := 120

var _path: CircuitPath
var _cur_edge := -1
var _from_node := -1
var _edge_progress := 0.0
var _speed := 10.0
var _lateral := 2.0
var _edges_left := 20
var _ai_speed := 0.0              # vitesse réelle actuelle (rampe vers _speed, ou vers 0 si bloquée)
# Vrai tant que la voiture décélère vers une consigne plus basse (carrefour, obstacle, véhicule
# suivi). Lu par VehicleLights pour les feux de freinage ; sans aucun effet sur la conduite.
var _braking := false
var _heading_deg := 0.0           # cap actuel lissé (degrés autour de Y), tourne à AI_TURN_RATE_DEG max
# Vrai dès que la voiture s'est engagée dans un carrefour à feu VERT (déjà
# dans la marge d'arrêt à ce moment-là) : le feu ne peut plus la faire
# s'arrêter pour CETTE traversée, même s'il passe à l'orange/rouge entre
# temps. Remis à faux à chaque nouvelle arête (nouvelle traversée).
var _committed_to_cross := false
# Vrai dès que la voiture a décidé, à son point de décision, de freiner pour
# s'arrêter à ce carrefour : reste vraie jusqu'à l'arrêt complet (ou la
# nouvelle arête suivante), ne revient pas en arrière même si le feu change
# entre-temps -> évite de changer d'avis en pleine décélération.
var _committed_to_stop := false

# Prochaine arête déjà décidée à l'avance (dès l'approche d'un carrefour à
# feu, cf. _intersection_speed_limit) au lieu d'être tirée au hasard pile au
# moment d'atteindre le noeud. Nécessaire pour la priorité de virage
# ci-dessous : il faut savoir SI et COMMENT la voiture va tourner avant
# qu'elle n'entre dans le bloc, pas seulement au moment d'y entrer.
var _planned_next_edge := -1

# Priorité de virage entre 2 voitures qui tournent en même temps au même
# carrefour (pas concerné si l'une des deux va tout droit) : la voiture
# arrivée en premier dans la zone (rang le plus bas) passe en premier,
# l'autre attend qu'elle ait dégagé le bloc -> règle simple et déterministe,
# pas un tirage au hasard.
var _turn_priority_node := -1        # noeud pour lequel une priorité est active (-1 = aucune)
var _turn_priority_seq := -1         # rang d'arrivée pour CE passage (plus petit = arrivé avant)
var _turn_priority_is_turn := false  # ce passage est-il un vrai virage (pas tout droit) ?
static var _turn_priority_counter := 0
const TURN_DOT_THRESHOLD := 0.7      # < ce cos(angle) entre direction entrante/sortante = virage

# détection d'obstacle : recalculée ~10x/s (pas 60x/s) et avec un léger
# déphasage aléatoire par voiture pour étaler le coût sur plusieurs frames
# plutôt que de le concentrer -> coût CPU quasi divisé par 6 à densité de
# trafic élevée (84 voitures), le freinage restant fluide entre deux recalculs
# grâce à la rampe move_toward sur _ai_speed.
const OBSTACLE_RECHECK_INTERVAL := 0.033
var _obstacle_recheck_timer := 0.0
var _cached_obstacle_speed_limit := 999.0

# liste des véhicules, mise en cache UNE fois par frame physique et partagée
# entre toutes les voitures (évite 84 appels redondants à get_nodes_in_group).
static var _vehicle_cache: Array = []
static var _vehicle_cache_frame: int = -1

# Index spatial des véhicules, reconstruit en même temps que la liste ci-dessus.
#
# Le suivi de voiture (_obstacle_speed_limit) et le cédez-le-passage du rond-point
# parcouraient les 252 véhicules pour CHAQUE voiture, ~30 fois par seconde chacune :
# ~32 000 itérations par frame, dont deux lectures de propriété par réflexion
# ("_half_length" in o, puis o.get(...)) à chaque itération. Mesuré à ~15 ms par
# frame sur les ~22 ms de scripts voiture (CityPerfTest headless, 252 voitures) :
# de loin le premier poste de coût du jeu.
#
# La grille range les véhicules par cellule de GRID_CELL m ; une voiture n'examine
# plus que les 3x3 cellules autour du point cherché. La cellule (24 m) est plus
# large que la plus longue portée de recherche (OBSTACLE_LOOK_AHEAD = 22 m), et le
# bloc 3x3 déborde d'au moins une cellule entière dans chaque direction : tout
# véhicule à portée y est donc TOUJOURS présent. Le résultat est le même qu'avec le
# parcours complet, ce n'est pas une approximation.
#
# Les positions servent uniquement à choisir les candidats ; le calcul lui-même relit
# la position réelle du véhicule, donc rien ne dépend de la fraîcheur de la grille.
# Marge : 24 - 22 = 2 m, alors qu'une voiture parcourt ~0,2 m par frame à 12 m/s.
const GRID_CELL := 24.0
static var _grid: Dictionary = {}   # clé entière de cellule (cf. _cell_key) -> Array d'indices dans _vehicle_cache

var driven_by_player := false
var has_npc_driver := false
# Vrai pour une voiture achetée au concessionnaire (CarDealershipPanel) :
# jamais spawnée via LoopSpawner/CircuitPath (donc jamais concernée par le
# budget d'arêtes de circulation), et exemptée du despawn d'abandon de 25s
# qui s'applique normalement à une voiture IA laissée à l'arrêt.
var is_player_owned := false
var _abandoned := false
var _drive_speed := 0.0
var _player_braking := false
var _player_near := false
var _steer_input := 0.0

# choc
var _knock_time := 0.0
var _knock_vel := Vector3.ZERO
var _recoil_vel := Vector3.ZERO
var _tilt_pitch := 0.0
var _tilt_roll := 0.0
var _stains := 0

# visuel
var _model: Node3D
var model_path := ""                  # modèle réellement chargé (tirage de circulation ou forced_model_path)
var _wheels: Array[Node3D] = []
var _wheels_front: Array[Node3D] = []
var _wheel_rest: Dictionary = {}
var _wheel_spin := 0.0
var _steer_visual := 0.0
var _ride_height := RIDE_HEIGHT       # recalculé selon la boîte ajustée au modèle
var _half_length := 2.0               # demi-longueur (axe -Z avant) de la caisse, recalculée au modèle réel ; 2.0 = moitié de la boîte par défaut de Car.tscn (size.z=4)

@onready var _prompt: Label3D = $EnterPrompt

func _ready() -> void:
	add_to_group("vehicle")
	# garde la caisse collée au sol sur les pentes (rampes de bordure) : évite le
	# décollement au sommet et le rebond en redescendant
	floor_snap_length = 0.5
	has_npc_driver = randf() < 0.5
	_setup_model()
	$InteractZone.body_entered.connect(_on_zone_entered)
	$InteractZone.body_exited.connect(_on_zone_exited)
	$CrushZone.body_entered.connect(_on_crush_zone_entered)
	call_deferred("_print_ride_diag")

# Diagnostic ponctuel : compare la géométrie de collision de la voiture au sol
# réellement sous elle. Imprimé pour la 1re voiture spawnée seulement.
# À retirer une fois la hauteur validée.
static var _diag_done := false
func _print_ride_diag() -> void:
	if _diag_done:
		return
	_diag_done = true
	var cs := $CollisionShape3D as CollisionShape3D
	var box := cs.shape as BoxShape3D
	if box == null:
		return
	var bottom_offset := cs.position.y - box.size.y * 0.5      # bas de caisse / origine
	var bottom_global := global_position.y + bottom_offset
	print("[Car diag] BoxShape3D taille=%s  offset local Y=%.3f  -> bas de caisse à %.3f sous l'origine"
		% [box.size, cs.position.y, -bottom_offset])
	print("[Car diag] origine Y=%.3f  ride_height=%.2f  -> bas de caisse Y global=%.3f"
		% [global_position.y, _ride_height, bottom_global])
	var st := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.5, global_position + Vector3.DOWN * 4.0)
	q.exclude = [get_rid()]
	q.collision_mask = 1
	var h := st.intersect_ray(q)
	if h.is_empty():
		print("[Car diag] aucun sol détecté sous la voiture")
		return
	var ground_y := float((h["position"] as Vector3).y)
	print("[Car diag] sol sous la voiture Y=%.3f  -> écart bas-de-caisse/sol=%.3f (négatif = pénètre)"
		% [ground_y, bottom_global - ground_y])

func _setup_model() -> void:
	var path := forced_model_path
	if path == "":
		path = VehicleCatalog.pick_traffic_path()
	if path == "":   # catalogue vide ou illisible : ancien tirage uniforme
		path = CAR_MODELS[randi() % CAR_MODELS.size()]
	model_path = path
	_apply_model_settings(path)
	var scene := load(path) as PackedScene
	if scene == null:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(randf(), randf(), randf())
		$MeshInstance3D.material_override = mat
		return
	$MeshInstance3D.visible = false
	_model = scene.instantiate() as Node3D
	add_child(_model)
	_model.scale = Vector3.ONE * model_scale
	_model.rotation_degrees.y = model_yaw_deg
	_model.position.y = model_y_offset

	# le placeholder caché avait déjà le bon calque (cf. DECAL_EXCLUDE_LAYERS) :
	# le modèle réellement affiché doit l'avoir aussi, sur CHAQUE mesh (un FBX
	# de voiture a souvent plusieurs MeshInstance3D : caisse, roues, vitres...).
	var model_meshes := _model.find_children("*", "MeshInstance3D", true, false)
	if _model is MeshInstance3D:
		model_meshes.append(_model)
	for mm in model_meshes:
		(mm as MeshInstance3D).layers = DECAL_EXCLUDE_LAYERS

	# repère les roues (best-effort ; si le modèle est monobloc -> rien ne se passe)
	for w in _model.find_children("*heel*", "", true, false):
		var w3 := w as Node3D
		if w3 == null:
			continue
		_wheels.append(w3)
		_wheel_rest[w3] = w3.transform.basis
		var wn := String(w3.name).to_lower()
		var front_by_name := wn.contains("front") or wn.contains("_f") or wn.contains("fl") or wn.contains("fr")
		var front_by_pos := w3.position.z > 0.0   # +Z local = avant (modèle tourné de 180°)
		if front_by_name or front_by_pos:
			_wheels_front.append(w3)

	_fit_collision_to_model()

# Réglages visuels propres au modèle (resources/vehicle_models/*.tres) : échelle,
# orientation native et décalage vertical. Un modèle absent du catalogue garde
# les valeurs de l'inspecteur.
func _apply_model_settings(path: String) -> void:
	var data := VehicleCatalog.find_by_path(path)
	if data == null:
		return
	model_scale = data.model_scale
	model_yaw_deg = data.model_yaw_deg
	model_y_offset = data.model_y_offset

# Ajuste la BoxShape3D de la caisse aux dimensions RÉELLES du modèle chargé
# (SUV, SportsCar, Taxi... ont des gabarits différents) au lieu d'une boîte
# unique. On calcule l'AABB combinée de tous les MeshInstance3D du modèle dans
# le repère de la voiture, puis on en fait une boîte + on recale la hauteur de
# circulation. Ne touche NI CrushZone NI InteractZone : le comportement de
# collision (choc, écrasement PNJ, poussée) est inchangé, seule la boîte de
# caisse est mieux dimensionnée.
func _fit_collision_to_model() -> void:
	if _model == null:
		return
	var cs := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs == null:
		return

	# AABB combinée de tous les meshes du modèle, exprimée dans le repère de la
	# voiture (invariant de la position/rotation courante de la voiture).
	var world_to_car := global_transform.affine_inverse()
	var meshes := _model.find_children("*", "MeshInstance3D", true, false)
	if _model is MeshInstance3D:
		meshes.append(_model)   # cas d'un modèle monobloc
	var aabb := AABB()
	var has := false
	for n in meshes:
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var b := (world_to_car * mi.global_transform) * mi.mesh.get_aabb()
		if has:
			aabb = aabb.merge(b)
		else:
			aabb = b
			has = true
	if not has:
		return

	var size := aabb.size
	# garde-fou : AABB aberrante (mesh helper parasite, échelle folle) -> on
	# garde la boîte par défaut de Car.tscn
	if size.x <= 0.05 or size.z <= 0.05 or size.length() > 40.0:
		if debug_hitbox:
			print("[Car hitbox] AABB inexploitable %s -> boîte par défaut conservée" % size)
		return
	size += Vector3(0.04, 0.04, 0.04)   # micro-marge, la boîte ne dépasse pas du modèle

	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box                      # ressource neuve -> pas de partage entre voitures
	cs.position = aabb.get_center()     # la caisse peut ne pas être centrée sur l'origine
	_half_length = size.z * 0.5         # pour arrêter la voiture AVANT le carrefour, pas son origine dessus

	# repose le bas de la boîte sur la chaussée (+1 cm) pour la circulation
	var box_bottom_local := cs.position.y - size.y * 0.5
	_ride_height = ROAD_TOP_Y + 0.01 - box_bottom_local
	if debug_hitbox:
		print("[Car hitbox] %s -> L=%.2f l=%.2f h=%.2f  centre=(%.2f,%.2f,%.2f)  ride_h=%.2f"
			% [String(_model.name), size.z, size.x, size.y,
				cs.position.x, cs.position.y, cs.position.z, _ride_height])

# --- circulation scriptée -----------------------------------------

func setup(path: CircuitPath, start_node: int, speed: float, lateral: float, edges_budget := 20) -> void:
	_path = path
	_from_node = start_node
	_speed = speed
	_lateral = lateral
	_edges_left = edges_budget
	_cur_edge = _path.pick_next_edge(_from_node, -1)
	_edge_progress = 0.0
	_snap_to_path()

func _physics_process(delta: float) -> void:
	if driven_by_player:
		_drive_physics(delta)
		_update_visuals(delta, _drive_speed, _steer_input)
		return

	if _knock_time > 0.0:
		_knock_time -= delta
		_knock_vel = _knock_vel.lerp(Vector3.ZERO, clampf(delta * 2.5, 0.0, 1.0))
		velocity = _knock_vel
		velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
		move_and_slide()
		_update_visuals(delta, _speed * 0.3, 0.0)
		return

	if _abandoned:
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
			move_and_slide()
		_update_visuals(delta, 0.0, 0.0)
		return

	if _path == null or _cur_edge < 0:
		return

	# avance selon la vitesse RÉELLE actuelle (rampe), pas la vitesse de
	# croisière cible -> l'accélération/le freinage se répercutent sur la
	# progression le long de la route, pas juste sur l'affichage.
	_edge_progress += _ai_speed * delta
	var edge_len := _path.edge_length(_cur_edge)
	if _edge_progress >= edge_len:
		_edge_progress -= edge_len
		_from_node = _path.edge_other_node(_cur_edge, _from_node)
		_edges_left -= 1
		if _edges_left <= 0:
			queue_free()
			return
		# Réutilise l'arête déjà décidée à l'avance à l'approche du carrefour
		# (cf. _intersection_speed_limit) si elle existe, pour rester cohérent
		# avec la décision qui a servi à établir la priorité de virage ; sinon
		# (rond-point, simple passage...) tire au hasard comme d'habitude.
		var next_edge: int = _planned_next_edge if _planned_next_edge >= 0 else _path.pick_next_edge(_from_node, _cur_edge)
		if next_edge < 0:
			queue_free()
			return
		_cur_edge = next_edge
		_committed_to_cross = false   # nouvelle arête -> nouvelle traversée, nouvelle décision
		_committed_to_stop = false
		_planned_next_edge = -1

	var target_dir := _path.direction_at(_cur_edge, _from_node, _edge_progress)
	var turn_rate_deg := clampf(rad_to_deg(_ai_speed / MIN_TURN_RADIUS), MIN_TURN_RATE_DEG, MAX_TURN_RATE_DEG)
	_heading_deg = _turn_toward(_heading_deg, _heading_from_dir(target_dir), turn_rate_deg * delta)
	var heading_dir := _dir_from_heading(_heading_deg)

	_obstacle_recheck_timer -= delta
	if _obstacle_recheck_timer <= 0.0:
		_obstacle_recheck_timer = OBSTACLE_RECHECK_INTERVAL + randf_range(-0.02, 0.02)
		_cached_obstacle_speed_limit = minf(
			_obstacle_speed_limit(heading_dir, _speed),
			_intersection_speed_limit(_speed))
	var desired_speed: float = _cached_obstacle_speed_limit
	var accel := AI_ACCEL if desired_speed > _ai_speed else AI_DECEL
	# Feux de freinage : c'est ICI que la voiture décide de ralentir, et nulle part ailleurs. Il
	# n'existait aucun indicateur de freinage sur Car — seul _committed_to_stop existait, et il ne
	# couvre que l'arrêt à un carrefour, pas le suivi de véhicule. On le relève donc sur la rampe
	# elle-même : la consigne est sous la vitesse actuelle, donc on décélère. Rien d'inventé.
	_braking = desired_speed < _ai_speed - BRAKE_EPS
	_ai_speed = move_toward(_ai_speed, desired_speed, accel * delta)

	velocity = heading_dir * _ai_speed
	velocity.y = 0.0
	move_and_slide()

	# trajet en 3D (ponts, bretelles de la carte) : hauteur du graphe + hauteur de caisse (graphe du centre-ville à y = 0)
	var ideal := _path.sample_offset(_cur_edge, _from_node, _edge_progress, _path.lane_offset(_cur_edge, _lateral))
	ideal.y += _ride_height
	global_position = global_position.lerp(ideal, clampf(delta * LANE_SNAP, 0.0, 1.0))
	rotation_degrees.y = _heading_deg
	_update_visuals(delta, _ai_speed, 0.0)

func _snap_to_path() -> void:
	if _path == null or _cur_edge < 0:
		return
	var ideal := _path.sample_offset(_cur_edge, _from_node, _edge_progress, _path.lane_offset(_cur_edge, _lateral))
	ideal.y += _ride_height
	global_position = ideal
	_heading_deg = _heading_from_dir(_path.direction_at(_cur_edge, _from_node, _edge_progress))
	_ai_speed = 0.0   # départ à l'arrêt -> accélération progressive dès la 1re frame
	_committed_to_cross = false
	_committed_to_stop = false
	_planned_next_edge = -1
	_turn_priority_node = -1
	rotation_degrees.y = _heading_deg

# --- helpers cap/vitesse IA -----------------------------------------

static func _heading_from_dir(dir: Vector3) -> float:
	return rad_to_deg(atan2(-dir.x, -dir.z))

static func _dir_from_heading(deg: float) -> Vector3:
	var r := deg_to_rad(deg)
	return Vector3(-sin(r), 0.0, -cos(r))

static func _turn_toward(current_deg: float, target_deg: float, max_step_deg: float) -> float:
	var diff := wrapf(target_deg - current_deg, -180.0, 180.0)
	return current_deg + clampf(diff, -max_step_deg, max_step_deg)

# Cellule encodée en un seul entier plutôt qu'en Vector2i : clé de dictionnaire
# nettement moins chère à hacher, et cette fonction est appelée pour chaque
# véhicule à chaque frame. CELL_BIAS recentre les coordonnées négatives (la ville
# est en X/Z négatifs) ; sa plage couvre +/- 49 km, très au-delà de la carte.
const CELL_BIAS := 2048
const CELL_STRIDE := 4096

static func _cell_key(p: Vector3) -> int:
	return (floori(p.x / GRID_CELL) + CELL_BIAS) * CELL_STRIDE + floori(p.z / GRID_CELL) + CELL_BIAS

static func _cell_key_xz(cx: int, cz: int) -> int:
	return (cx + CELL_BIAS) * CELL_STRIDE + cz + CELL_BIAS

# Reconstruit liste + grille, une seule fois par frame physique pour toutes les
# voitures. Volontairement réduit au strict minimum (une position + un rangement
# par véhicule) : cette passe court sur les 252 véhicules, y compris ceux que
# SimulationCuller a endormis, alors qu'en jeu seule une dizaine de voitures est
# active. Tout ce qui peut n'être lu que pour les quelques candidats réellement
# retenus (la demi-longueur, par exemple) est laissé aux boucles appelantes.
func _refresh_vehicle_index() -> void:
	var f := Engine.get_physics_frames()
	if f == _vehicle_cache_frame:
		return
	_vehicle_cache_frame = f
	_vehicle_cache = get_tree().get_nodes_in_group("vehicle")
	# Les paniers sont VIDÉS, pas détruits : _grid.clear() relâchait chaque frame
	# la centaine de tableaux des cellules occupées, qu'il fallait ensuite
	# réallouer un par un. Les cellules restent d'une frame à l'autre.
	for bucket in _grid.values():
		(bucket as Array).clear()
	for i in _vehicle_cache.size():
		var o := _vehicle_cache[i] as Node3D
		if o == null:
			continue
		var key := _cell_key(o.global_position)
		var bucket: Variant = _grid.get(key)
		if bucket == null:
			bucket = []
			_grid[key] = bucket
		(bucket as Array).append(i)

# Indices des véhicules des cellules autour de `center`, `rings` anneaux autour de
# la cellule centrale (1 -> bloc 3x3, 2 -> 5x5). Le bloc couvre toujours au moins
# `rings * GRID_CELL` mètres dans chaque direction depuis `center`, puisque celui-ci
# est quelque part dans la cellule centrale : 24 m avec 1 anneau, 48 m avec 2.
func _nearby_indices(center: Vector3, rings: int = 1) -> Array:
	var cx := floori(center.x / GRID_CELL)
	var cz := floori(center.z / GRID_CELL)
	var side := rings * 2 + 1
	var out: Array = []
	for dx in side:
		for dz in side:
			var bucket: Variant = _grid.get(_cell_key_xz(cx + dx - rings, cz + dz - rings))
			if bucket != null and not (bucket as Array).is_empty():
				out.append_array(bucket as Array)
	return out

# Vitesse maximale sûre compte tenu des véhicules devant soi sur la voie
# (autre voiture IA arrêtée, épave, OU la voiture du joueur qui bloque le
# passage — toutes dans le groupe "vehicle"). Ralentit progressivement en
# approche puis s'arrête à une distance de sécurité ; ne dépasse jamais.
func _obstacle_speed_limit(heading_dir: Vector3, cruise_speed: float) -> float:
	_refresh_vehicle_index()
	var right := heading_dir.cross(Vector3.UP).normalized()
	var nearest := INF
	var nearest_body: Object = null
	var my_pos := global_position
	for idx in _nearby_indices(my_pos):
		var o := _vehicle_cache[idx] as Node3D
		if o == self or o == null:
			continue
		var rel: Vector3 = o.global_position - my_pos
		rel.y = 0.0
		var fwd_dist := rel.dot(heading_dir)
		if fwd_dist <= 0.0 or fwd_dist > OBSTACLE_LOOK_AHEAD:
			continue
		if absf(rel.dot(right)) > OBSTACLE_LANE_HALF_WIDTH:
			continue
		# distance jusqu'à l'ARRIÈRE de l'obstacle (moins sa demi-longueur réelle),
		# pas jusqu'à son centre : un bus de 11 m ne s'aborde pas comme une citadine
		var other_half: float = o.get("_half_length") if "_half_length" in o else OBSTACLE_DEFAULT_HALF_LENGTH
		if fwd_dist - other_half < nearest:
			nearest = fwd_dist - other_half
			nearest_body = o
	if nearest == INF:
		return cruise_speed
	var brake_dist := nearest - (_half_length + OBSTACLE_BUMPER_GAP)
	if brake_dist <= 0.0:
		_keep_awake(nearest_body)
		return 0.0
	# Distance de freinage physique (v² = 2·a·d) plutôt qu'une réduction
	# proportionnelle arbitraire : garantit que la voiture peut TOUJOURS
	# s'arrêter pile à OBSTACLE_BUMPER_GAP de l'obstacle en freinant à AI_DECEL, quelle que
	# soit sa vitesse d'approche, au lieu de risquer de dépasser la marge de
	# sécurité si elle referme l'écart plus vite qu'elle ne peut ralentir.
	var max_safe_speed := sqrt(2.0 * AI_DECEL * brake_dist)
	if max_safe_speed < cruise_speed:
		_keep_awake(nearest_body)
	return minf(cruise_speed, max_safe_speed)

# Vitesse imposée par la signalisation à l'approche du PROCHAIN noeud sur
# l'arête courante :
#  - carrefour classique avec feu : s'arrête si le feu de cette approche
#    n'est pas vert (rouge OU orange) ;
#  - entrée du rond-point (arête d'approche, PAS déjà sur l'anneau) : cédez-
#    le-passage -> s'arrête si une voiture est déjà engagée sur l'anneau à
#    proximité de ce point d'entrée ;
#  - déjà engagé sur l'anneau (arête one_way) : prioritaire, aucun arrêt ici.
# Même formule de distance de freinage que _obstacle_speed_limit. La marge
# d'arrêt (ligne d'arrêt virtuelle) doit placer l'AVANT de la caisse à la
# limite de la zone, pas son origine : on ajoute donc la demi-longueur RÉELLE
# de la voiture (_half_length, mesurée sur le modèle) à la demi-taille réelle
# du bloc carrefour (12x12m mesuré sur RoadsCollision -> 6.0), pas juste une
# constante arbitraire.
#
# Durci après l'ajout de la ligne d'arrêt basée sur le passage piéton : le pire
# cas mesuré (crosswalk_clear_distance max réel = 13.10m + CROSSWALK_STOP_MARGIN
# 0.5 + demi-longueur max réelle observée sur les 6 modèles de voiture = 2.13m)
# donne une marge d'arrêt de ~15.73m ; à la vitesse de croisière réelle actuelle
# (CarSpawner : speed_min=speed_max=12.0, distance de freinage = 6.0m à
# AI_DECEL=12.0) le seuil de décision atteint ~21.73m, tout juste sous
# l'ancien 22.0 -- sans marge de sécurité en cas de vitesse de croisière plus
# élevée à l'avenir ou de survitesse transitoire (après un choc par ex.).
# Porté à 28.0 pour couvrir confortablement jusqu'à ~16 m/s de croisière
# (distance de freinage ~10.7m à ce même AI_DECEL) sans jamais laisser la
# zone de contrôle "sortie" (remaining > seuil) devenir plus courte que la
# vraie distance de décision -> évite un freinage tardif/brutal juste après
# l'ouverture de la zone.
const INTERSECTION_CHECK_DIST := 28.0
const INTERSECTION_HALF_SIZE := 6.0     # 12x12m réel (RoadsCollision "RoadFlat_*"), pas une estimation
const STOP_LINE_BUFFER := 0.5           # petit espace visuel entre le pare-choc et la zone
const CROSSWALK_STOP_MARGIN := 0.5      # petite marge additionnelle avant le bord du passage piéton (0.3 laissait une marge réelle mesurée de seulement ~0.08m à cause du léger dépassement inhérent au freinage discret, déjà présent sur STOP_LINE_BUFFER)
const YIELD_RING_RADIUS := 14.0
const YIELD_STOP_BUFFER := 1.0          # le rond-point n'a pas de bloc 12x12 : juste la caisse + une marge
const MERGE_CHECK_DIST := 80.0          # bretelle d'insertion : surveillance du point de convergence
const MERGE_STOP_BEFORE := 42.0         # arrêt avant le raccord à la chaussée (RoadNetwork.BLEND 40 m + marge)
const MERGE_YIELD_RADIUS := 45.0

func _intersection_speed_limit(cruise_speed: float) -> float:
	if _path == null or _cur_edge < 0:
		return cruise_speed

	# Nettoyage : une fois assez loin APRÈS être sortie du bloc dont elle
	# avait la priorité de virage, elle libère la place pour les suivantes.
	if _turn_priority_node >= 0 and _from_node == _turn_priority_node \
			and _edge_progress >= INTERSECTION_HALF_SIZE + _half_length:
		_turn_priority_node = -1

	if _path.is_ring_edge(_cur_edge):
		return cruise_speed   # déjà sur l'anneau : prioritaire, pas de cédez-le-passage à faire

	var next_node := _path.edge_other_node(_cur_edge, _from_node)
	var remaining := _path.edge_length(_cur_edge) - _edge_progress

	# bretelle d'insertion (carte 3D) : attend, avant la zone où elle rejoint la chaussée, qu'aucun véhicule de
	# l'autre branche n'arrive au point de convergence
	if _path.must_yield(_cur_edge, next_node) and remaining <= MERGE_CHECK_DIST:
		if remaining < MERGE_STOP_BEFORE + _half_length - 1.0:
			return cruise_speed   # déjà engagée dans le raccord : ne s'arrête plus au bord de la chaussée
		var merge_pos := _path.node_pos(next_node)
		_refresh_vehicle_index()
		for idx in _nearby_indices(merge_pos, 2):
			var o := _vehicle_cache[idx] as Node3D
			if o == self or o == null or not o.has_method("nears_node"):
				continue
			if o.nears_node(next_node, _cur_edge, MERGE_YIELD_RADIUS):
				_keep_awake(o)
				var brake := remaining - (MERGE_STOP_BEFORE + _half_length)
				return 0.0 if brake <= 0.0 else minf(cruise_speed, sqrt(2.0 * AI_DECEL * brake))
		return cruise_speed

	if remaining > INTERSECTION_CHECK_DIST:
		return cruise_speed

	if _path.is_roundabout_node(next_node):
		# cédez-le-passage : une voiture est-elle déjà engagée sur l'anneau
		# près de ce point d'entrée précis ?
		var stop_margin := _half_length + YIELD_STOP_BUFFER
		var must_stop := false
		var entry_pos := _path.node_pos(next_node)
		_refresh_vehicle_index()
		for idx in _nearby_indices(entry_pos):
			var o := _vehicle_cache[idx] as Node3D
			if o == self or o == null or not (o.has_method("is_on_ring") and o.is_on_ring()):
				continue
			if o.global_position.distance_to(entry_pos) <= YIELD_RING_RADIUS:
				must_stop = true
				_keep_awake(o)
				break
		if not must_stop:
			return cruise_speed
		var brake_dist := remaining - stop_margin
		if brake_dist <= 0.0:
			return 0.0
		return minf(cruise_speed, sqrt(2.0 * AI_DECEL * brake_dist))

	# --- carrefour classique avec feu ---
	# Ligne d'arrêt de base (bord du bloc 12x12), reculée en plus jusqu'au
	# bord du décalque de passage piéton (taille RÉELLE mesurée sur chaque
	# approche, cf. CircuitPath.crosswalk_stop_dist, pas une constante
	# théorique -- les décalques "_1" et "_5" n'ont pas la même distance au
	# centre) quand cette approche en a un, + une petite marge visuelle.
	var stop_margin2 := INTERSECTION_HALF_SIZE + STOP_LINE_BUFFER
	var crosswalk_edge := _path.crosswalk_clear_distance(_cur_edge, next_node)
	if crosswalk_edge > 0.0:
		stop_margin2 = maxf(stop_margin2, crosswalk_edge + CROSSWALK_STOP_MARGIN)
	stop_margin2 += _half_length

	# Planifie l'arête de sortie et détecte si c'est un vrai virage UNE SEULE
	# FOIS par traversée, dès qu'on est dans la zone de surveillance ->
	# nécessaire pour la priorité de virage ci-dessous, avant même de savoir
	# ce que dira le feu. Ceci ne freine PAS la voiture : juste préparation.
	if _planned_next_edge < 0:
		_planned_next_edge = _path.pick_next_edge(next_node, _cur_edge)
		_turn_priority_node = next_node
		_turn_priority_seq = _turn_priority_counter
		_turn_priority_counter += 1
		if _planned_next_edge >= 0:
			var incoming := _path.direction_at(_cur_edge, _from_node, _path.edge_length(_cur_edge))
			var outgoing := _path.direction_at(_planned_next_edge, next_node, 0.0)
			_turn_priority_is_turn = incoming.dot(outgoing) < TURN_DOT_THRESHOLD
		else:
			_turn_priority_is_turn = false

	# --- priorité de virage : contrainte CONTINUE (recalculée à chaque
	# recheck, comme le suivi de voiture), JAMAIS figée par une décision
	# définitive -> dès que l'autre voiture a dégagé le bloc, celle qui
	# attendait doit pouvoir repartir immédiatement, pas rester bloquée pour
	# le reste de la traversée. Ne s'active qu'à partir de SA PROPRE distance
	# de freinage (comme le feu) pour ne pas ralentir inutilement de loin.
	var turn_priority_limit := cruise_speed
	if _turn_priority_is_turn:
		var own_stop_t := (_ai_speed * _ai_speed) / (2.0 * AI_DECEL)
		if remaining <= stop_margin2 + own_stop_t:
			var must_yield_for_turn := false
			# Seules les voitures qui approchent CE carrefour peuvent avoir la
			# priorité dessus, et aucune ne le surveille au-delà de
			# INTERSECTION_CHECK_DIST (28 m) : 2 anneaux de grille (>= 48 m autour
			# du noeud) les contiennent donc toutes. Même résultat que le parcours
			# des 252 véhicules, sans le parcourir.
			_refresh_vehicle_index()
			for idx in _nearby_indices(_path.node_pos(next_node), 2):
				var o := _vehicle_cache[idx] as Node3D
				if o == self or o == null or not o.has_method("blocks_turn_at"):
					continue
				if o.blocks_turn_at(next_node, _turn_priority_seq):
					must_yield_for_turn = true
					break
			if must_yield_for_turn:
				var brake_dist_y := remaining - stop_margin2
				turn_priority_limit = 0.0 if brake_dist_y <= 0.0 else sqrt(2.0 * AI_DECEL * brake_dist_y)

	# --- feu : décision UNE FOIS "j'y vais" (n'y revient plus ensuite, pour
	# ne pas piler en plein milieu du carrefour si le feu change pendant la
	# traversée). En revanche, tant qu'on n'a PAS encore franchi ce cap, on
	# continue de revérifier le feu à CHAQUE recheck, y compris une fois déjà
	# à l'arrêt : sinon, une voiture arrêtée au rouge ne redémarre jamais,
	# `remaining` restant figé (elle n'avance plus) une fois immobilisée, ce
	# qui gelait aussi la décision "je m'arrête" pour toujours -- exactement
	# le bug de priorité de virage déjà vu, réintroduit ici côté freinage.
	var light_limit := cruise_speed
	if _committed_to_cross:
		_committed_to_stop = false
		light_limit = cruise_speed
	else:
		var own_stopping_dist := (_ai_speed * _ai_speed) / (2.0 * AI_DECEL)
		var decision_threshold := stop_margin2 + own_stopping_dist
		if remaining > decision_threshold and not _committed_to_stop:
			light_limit = cruise_speed
		elif _path.light_allows(_cur_edge, next_node):
			_committed_to_cross = true
			_committed_to_stop = false
			light_limit = cruise_speed
		else:
			_committed_to_stop = true
			var brake_dist2 := remaining - stop_margin2
			light_limit = 0.0 if brake_dist2 <= 0.0 else minf(cruise_speed, sqrt(2.0 * AI_DECEL * brake_dist2))

	return minf(light_limit, turn_priority_limit)

# Utilisé par les AUTRES voitures pour l'arbitrage de priorité de virage
# ci-dessus : renvoie le noeud de carrefour concerné, le rang d'arrivée pour
# cette traversée, et si c'est un vrai virage. Vide si aucune priorité active
# OU si la voiture est DÉFINITIVEMENT à l'arrêt à son feu (_committed_to_stop) :
# une voiture immobilisée au rouge n'occupe plus le bloc et ne doit jamais
# bloquer indéfiniment une autre voiture. En revanche une voiture encore EN
# TRAIN DE DÉCIDER (pas encore committed dans un sens ou l'autre) compte
# toujours -- sinon deux voitures qui arrivent en même temps se
# "doubleraient" l'une l'autre au lieu de respecter l'ordre d'arrivée, le
# rang le plus bas n'ayant pas encore eu la CHANCE de committed_to_cross.
# Répond directement à la seule question que l'appelant se posait ("cette
# voiture-ci me bloque-t-elle ?") au lieu de renvoyer un Dictionary que
# l'appelant décortiquait : la version précédente allouait un Dictionary par
# voiture comparée, pour chaque voiture qui tourne, à chaque revérification.
# Mêmes conditions, lues en direct : aucun décalage d'une frame sur l'arbitrage.
func blocks_turn_at(node: int, seq: int) -> bool:
	# Figée par SimulationCuller : ne bloque personne pendant la pause, garde son rang pour la reprise.
	if _turn_priority_node < 0 or _committed_to_stop or not is_physics_processing():
		return false
	return _turn_priority_node == node and _turn_priority_is_turn and _turn_priority_seq < seq

# Utilisé par les AUTRES voitures pour savoir si celle-ci est déjà engagée
# sur l'anneau du rond-point (priorité), pour le cédez-le-passage ci-dessus.
func is_on_ring() -> bool:
	return _path != null and _cur_edge >= 0 and _path.is_ring_edge(_cur_edge)

# Utilisé par les voitures d'une bretelle d'insertion : celle-ci arrive-t-elle (ou vient-elle de passer) au noeud
# `node` par une autre arête que `except_edge`, à moins de `radius` m ?
func nears_node(node: int, except_edge: int, radius: float) -> bool:
	if _path == null or _cur_edge < 0 or _cur_edge == except_edge or not is_physics_processing():
		return false
	if _path.edge_other_node(_cur_edge, _from_node) == node:
		return _path.edge_length(_cur_edge) - _edge_progress <= radius
	return _from_node == node and _edge_progress <= 10.0

# --- conduite ---------------------------------------------------

func _drive_physics(delta: float) -> void:
	var throttle := Input.get_axis("move_back", "move_forward")
	_steer_input = Input.get_axis("move_right", "move_left")

	# Feux de freinage du JOUEUR : la pédale, pas la vitesse. brake_lights_on() ne regardait que
	# _drive_speed < BRAKE_STOP_SPEED, donc les feux ne s'allumaient qu'une fois la voiture presque
	# arrêtée — appuyer sur S en roulant ne faisait rien. C'est ici, et nulle part ailleurs, que la
	# voiture du joueur décide de freiner : marche arrière demandée alors qu'on avance encore.
	_player_braking = throttle < 0.0 and _drive_speed > 0.5
	if throttle > 0.0:
		_drive_speed = move_toward(_drive_speed, DRIVE_MAX_SPEED, DRIVE_ACCEL * delta)
	elif throttle < 0.0:
		if _drive_speed > 0.5:
			_drive_speed = move_toward(_drive_speed, 0.0, DRIVE_BRAKE * delta)
		else:
			_drive_speed = move_toward(_drive_speed, -DRIVE_REVERSE_MAX, DRIVE_ACCEL * delta)
	else:
		_drive_speed = move_toward(_drive_speed, 0.0, DRIVE_FRICTION * delta)

	if absf(_drive_speed) > 0.3:
		rotate_y(_steer_input * TURN_RATE * delta * clampf(_drive_speed / DRIVE_MAX_SPEED, -1.0, 1.0))

	# Montée de trottoir : voir _try_step_up, appelée après move_and_slide.
	# (La réponse précédente était scenes/world/CurbRamp.gd, qui construisait des rampes de collision le
	# long des trottoirs. Il ne reconnaissait que des StaticBody3D nommés *Walk* portant une seule
	# BoxShape3D — la disposition du monde d'essai d'origine — alors que les trottoirs de la carte cuite
	# sont des trimesh de RoadCell et des piles de boîtes sous Sol_*, et il n'était attaché à aucun nœud
	# de World.tscn : il ne tournait plus du tout. Supprimé le 2026-09-19.)

	# recul de choc (décroît vite)
	_recoil_vel = _recoil_vel.lerp(Vector3.ZERO, clampf(delta * 6.0, 0.0, 1.0))

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	var fwd := -global_transform.basis.z
	velocity.x = fwd.x * _drive_speed + _recoil_vel.x
	velocity.z = fwd.z * _drive_speed + _recoil_vel.z
	move_and_slide()
	_try_step_up(fwd)
	_resolve_drive_collisions(fwd)

# Franchissement de bordure. move_and_slide() ne monte AUCUNE marche verticale, si basse soit-elle : mesuré, la
# voiture arcade s'arrête net devant les bordures de 0,150 m, à 3, 6, 10 et 15 m/s, aussi bien sur le trimesh
# d'une artère que sur les boîtes du centre-ville. On relève donc la caisse à la main quand elle bute sur une
# face verticale basse ayant du sol juste derrière.
#
# Réservé au joueur : `driven_by_player` est faux pour les 252 voitures de la circulation, qui gardent donc
# exactement le comportement d'avant et restent arrêtées par les bordures. Les PNJ ne passent pas par ici.
func _try_step_up(fwd: Vector3) -> void:
	if not driven_by_player or not is_on_floor() or absf(_drive_speed) < 0.5:
		return
	# sens de MARCHE, pas d'orientation : en marche arrière la bordure est derrière la voiture
	var dir := fwd * signf(_drive_speed)
	var bute := false
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		# face quasi verticale, prise de face : une pente reste gérée par move_and_slide
		if absf(n.y) <= 0.35 and dir.dot(-n) > 0.3:
			bute = true
			break
	if not bute:
		return
	var lift := Vector3.UP * STEP_UP_MAX
	if test_move(global_transform, lift):
		return                                   # pas la place de se relever : tunnel, pont, autre voiture
	var releve := global_transform.translated(lift)
	var devant := dir * STEP_UP_AHEAD
	if test_move(releve, devant):
		return                                   # vrai mur : la caisse ne passe pas non plus au-dessus
	var contact := KinematicCollision3D.new()
	if not test_move(releve.translated(devant), Vector3.DOWN * (STEP_UP_MAX + 0.05), contact):
		return                                   # rien sur quoi se reposer : un trou, pas une marche
	# On pose la caisse exactement là où l'essai vient de la faire atterrir : relevée, avancée, puis redescendue
	# jusqu'au contact. Se contenter de la relever sur place ne suffit pas — mesuré : à 3 m/s la voiture se
	# relevait 14 fois de suite et retombait à chaque fois sur la chaussée, parce qu'avec 0,05 m parcourus par
	# frame sa caisse restait presque entièrement au-dessus de la route et que l'accrochage au sol
	# (floor_snap_length) la ramenait aussitôt contre la face de la bordure.
	global_position += lift + devant + contact.get_travel()

func _resolve_drive_collisions(fwd: Vector3) -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		if absf(n.y) > 0.7:
			continue   # sol / marche, pas un mur
		var other := c.get_collider()
		var frontality := clampf(-fwd.dot(n), -1.0, 1.0)   # 1 = choc pile de face

		if other != null and other.is_in_group("vehicle") and other.has_method("knock"):
			other.knock(-n, absf(_drive_speed) * 0.6 + 4.0)
			_drive_speed *= 0.35
			_recoil_vel = n * (absf(_drive_speed) * 0.4 + 4.0)
			_tilt_pitch = -0.12 * maxf(frontality, 0.3)
		else:
			# mur / obstacle statique : on tue la vitesse selon la frontalité
			_drive_speed *= clampf(1.0 - 0.95 * maxf(frontality, 0.0), 0.0, 1.0)
			_recoil_vel = n * (3.0 + 3.0 * maxf(frontality, 0.0))
			_tilt_pitch = -0.10 * maxf(frontality, 0.2)
		_tilt_roll = clampf(n.dot(global_transform.basis.x), -1.0, 1.0) * 0.08

func knock(dir: Vector3, strength: float) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length() < 0.01:
		return
	_knock_vel = d.normalized() * strength
	_knock_time = KNOCK_TIME
	_tilt_roll = 0.1
	_tilt_pitch = -0.06

func get_drive_speed() -> float:
	return _drive_speed

# --- visuel (roues + tilt) -----------------------------------

func _update_visuals(delta: float, fwd_speed: float, steer_target: float) -> void:
	if not _wheels.is_empty():
		_wheel_spin = fmod(_wheel_spin + (fwd_speed / WHEEL_RADIUS) * delta, TAU)
		_steer_visual = lerpf(_steer_visual, steer_target * MAX_STEER_RAD, clampf(delta * 10.0, 0.0, 1.0))
		var spin_b := Basis(wheel_spin_axis.normalized(), _wheel_spin)
		# spin_b : dans le repère roue (post-multiplié via rest).
		# steer_b : dans le repère caisse (pré-multiplié) -> rotation garantie
		#           autour de la verticale, la roue pivote gauche/droite.
		var steer_b := Basis(wheel_steer_axis.normalized(), _steer_visual)
		for w in _wheels:
			var rest: Basis = _wheel_rest[w]
			if w in _wheels_front:
				w.transform.basis = steer_b * rest * spin_b
			else:
				w.transform.basis = rest * spin_b

	# tilt de carrosserie : revient à zéro
	_tilt_pitch = lerpf(_tilt_pitch, 0.0, clampf(delta * 6.0, 0.0, 1.0))
	_tilt_roll = lerpf(_tilt_roll, 0.0, clampf(delta * 6.0, 0.0, 1.0))
	if _model != null:
		_model.rotation.x = _tilt_pitch
		_model.rotation.z = _tilt_roll
		_model.rotation.y = deg_to_rad(model_yaw_deg)

func start_drive() -> void:
	driven_by_player = true
	_abandoned = false
	_player_near = false
	_drive_speed = 0.0
	_prompt.visible = false

func stop_drive() -> void:
	driven_by_player = false
	_abandoned = true
	_drive_speed = 0.0
	velocity = Vector3.ZERO
	if not is_player_owned:
		get_tree().create_timer(ABANDON_DESPAWN).timeout.connect(queue_free)

# Voiture EN STATIONNEMENT (ParkedVehicles) : aucun trajet, aucune IA, elle se pose au sol et
# attend qu'on la prenne. `_abandoned` est exactement l'état qui convient — c'est celui d'une voiture
# laissée là — et c'est le seul qui laisse la gravité agir quand `_path` est nul : sans lui,
# _physics_process sort immédiatement et la voiture reste en l'air. Aucun compte à rebours de
# disparition n'est armé ici ; il n'est créé que dans stop_drive(), quand le joueur la quitte.
func park() -> void:
	_abandoned = true
	_drive_speed = 0.0
	velocity = Vector3.ZERO


# Voiture à l'arrêt que personne ne conduit : garée par ParkedVehicles, ou abandonnée par le joueur.
func is_parked() -> bool:
	return _abandoned and not driven_by_player


func is_occupied() -> bool:
	return driven_by_player

# Coupure de calcul hors champ et loin du joueur (SimulationCuller) : l'état reste figé tel quel, sans
# suppression ni déplacement. À la reprise, relecture immédiate du feu et des obstacles au lieu de repartir
# sur la limite de vitesse mise en cache avant la pause.
func set_simulation_active(active: bool) -> void:
	set_physics_process(active)
	if active:
		_obstacle_recheck_timer = 0.0

# Garde éveillée (SimulationCuller) la voiture qui retient celle-ci.
static func _keep_awake(o: Object) -> void:
	o.set_meta(SIM_KEEP_AWAKE_META, Engine.get_physics_frames() + SIM_KEEP_AWAKE_FRAMES)

# --- zone d'interaction + éjection PNJ -------------------------

func _on_zone_entered(body: Node3D) -> void:
	if body.is_in_group("player") and body.has_method("notify_car_in_range"):
		_player_near = true
		body.notify_car_in_range(self)
		_refresh_prompt()

func _on_zone_exited(body: Node3D) -> void:
	if body.is_in_group("player") and body.has_method("notify_car_out_of_range"):
		_player_near = false
		body.notify_car_out_of_range(self)
		_prompt.visible = false

func _refresh_prompt() -> void:
	_prompt.visible = _player_near and not driven_by_player

func eject_driver() -> void:
	if not has_npc_driver:
		return
	has_npc_driver = false
	var npc_scene := load("res://scenes/npc/NPC.tscn") as PackedScene
	if npc_scene == null:
		return
	var npc := npc_scene.instantiate()
	get_tree().current_scene.add_child(npc)
	if npc.has_method("setup_ejected"):
		var eject_point := get_node_or_null("EjectPoint") as Node3D
		var spawn_pos: Vector3 = eject_point.global_position if eject_point != null else global_position
		var pedgraph := get_tree().current_scene.get_node_or_null("PedGraph") as PathGraph
		npc.setup_ejected(spawn_pos, pedgraph)

# --- écrasement PNJ ------------------------------------------

func _on_crush_zone_entered(body: Node3D) -> void:
	if not driven_by_player or absf(_drive_speed) < CRUSH_MIN_SPEED:
		return
	if body.is_in_group("npc") and body.has_method("take_damage"):
		body.take_damage(999, body.global_position, Vector3.UP)   # réutilise la mort PNJ + sang au sol
		_add_body_stain()

func _add_body_stain() -> void:
	if _stains >= MAX_STAINS:
		return
	_stains += 1
	var q := QuadMesh.new()
	q.size = Vector2(randf_range(0.25, 0.5), randf_range(0.25, 0.5))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.22, 0.0, 0.0, randf_range(0.55, 0.85))
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	# collé juste devant le pare-choc (la voiture faisant face à -Z)
	mi.position = Vector3(randf_range(-0.7, 0.7), randf_range(0.1, 0.9), -2.02)
	mi.rotation_degrees = Vector3(0, 180, randf_range(0.0, 360.0))
	add_child(mi)


# Feux de freinage allumés : la voiture décélère, ou elle est à l'arrêt. Lu par VehicleLights.
# Quand c'est le joueur qui conduit cette Car (modèle arcade), c'est _drive_speed qui fait foi.
func brake_lights_on() -> bool:
	# Une voiture laissée là n'a personne au volant : ses feux doivent être ÉTEINTS. Sans cette
	# sortie, les véhicules en stationnement des lieux (ParkedVehicles) auraient leurs feux de
	# freinage allumés en permanence, puisque _ai_speed y vaut zéro.
	if is_parked():
		return false
	if driven_by_player:
		return _player_braking or absf(_drive_speed) < BRAKE_STOP_SPEED
	return _braking or _ai_speed < BRAKE_STOP_SPEED
