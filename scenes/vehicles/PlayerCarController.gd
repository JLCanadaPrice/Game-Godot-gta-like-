extends "res://assets/car_physics/MAIN/car.gd"

# Adapte le coeur physique du pack (car.gd, RigidBody3D + suspension par
# roue par raycast) au contrat d'interaction déjà utilisé par Player.gd
# pour TOUTE voiture "montable" (cf. Car.gd, l'ancien modèle arcade) :
# is_occupied() / eject_driver() (optionnel) / start_drive() / stop_drive()
# / get_drive_speed() (optionnel) / noeuds DriverSeat + ExitPoint.
#
# Étape 2 du chantier "physique de conduite réaliste" : véhicule du JOUEUR
# uniquement, coeur physique seul (car.gd + wheel.gd), sans les scripts
# misc/ (son, fumée, traces de pneus, debug forces) pour l'instant -- cf.
# rapport étape 1. `Controlled` (déjà présent sur car.gd) gate déjà la
# lecture des pédales gaz/frein/embrayage -> le laisser à false pendant
# qu'il n'y a personne dedans reproduit le comportement "voiture à l'arrêt,
# personne au volant" sans avoir à toucher au coeur physique lui-même.

var _occupied := false

func _ready() -> void:
	super._ready()
	Controlled = false   # personne au volant au démarrage

	# Cause du "impossible de monter avec E" (trouvée) : les callbacks
	# existaient déjà plus bas dans ce fichier mais n'étaient jamais
	# connectés aux signaux de InteractZone -> notify_car_in_range() n'était
	# donc jamais appelée, le joueur n'entrait jamais dans _cars_in_range
	# (cf. Player.gd), et _try_enter_vehicle() ne trouvait rien. Même
	# principe de câblage que Car.gd (ancien modèle arcade), qui connecte
	# ses propres callbacks en code dans _ready() plutôt que via l'éditeur.
	var zone := get_node_or_null("InteractZone") as Area3D
	if zone != null:
		zone.body_entered.connect(_on_interact_zone_body_entered)
		zone.body_exited.connect(_on_interact_zone_body_exited)
	else:
		push_warning("PlayerCarController: InteractZone introuvable -> impossible de monter dans la voiture")

func is_occupied() -> bool:
	return _occupied

func start_drive() -> void:
	_occupied = true
	Controlled = true

func stop_drive() -> void:
	_occupied = false
	Controlled = false

func get_drive_speed() -> float:
	return linear_velocity.length()

func _on_interact_zone_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and body.has_method("notify_car_in_range"):
		body.notify_car_in_range(self)

func _on_interact_zone_body_exited(body: Node3D) -> void:
	if body.is_in_group("player") and body.has_method("notify_car_out_of_range"):
		body.notify_car_out_of_range(self)
