extends Node3D

# Franchissement des bordures de trottoir par la voiture arcade (Car.gd, CharacterBody3D) — le modèle des
# 252 voitures de la circulation ET celui que le joueur conduit quand il prend une voiture dans la rue.
#
# Le test se joue sur une maquette et non sur la carte : une dalle de chaussée, une dalle de trottoir 0,15 m plus
# haut (la hauteur mesurée sur la collision cuite, identique sur les artères et au centre-ville), une marche
# verticale entre les deux. Ça tient en une seconde et ça ne dépend d'aucune cuisson.
#
# Trois exigences, dans cet ordre d'importance :
#  1. au volant, la voiture MONTE sur le trottoir, à toutes les vitesses d'approche ;
#  2. elle en REDESCEND sans rester coincée et sans décoller ;
#  3. sans personne au volant, elle NE monte PAS : les 252 voitures de l'IA doivent continuer d'être arrêtées
#     par les bordures. C'est la contrainte qui a décidé de la forme du correctif — un relevé de caisse réservé
#     au joueur (Car._try_step_up) plutôt qu'une rampe de collision posée le long des trottoirs, qui aurait
#     ouvert les trottoirs à tout le monde.
#
# Lancer : Godot --headless res://scenes/tests/CarKerbTest.tscn

const ARCADE := preload("res://scenes/vehicles/Car.tscn")
const MARCHE := 0.15
const BORDURE_Z := 0.0        # z de la face verticale
const VITESSES := [3.0, 6.0, 10.0, 15.0]

var _errors: Array[String] = []


func _ready() -> void:
	print("CAR_KERB_BEGIN")
	_slab(Vector3(60, 2, 60), Vector3(0, -1.0, BORDURE_Z - 30.0))              # chaussée, dessus à 0
	_slab(Vector3(60, 2, 60), Vector3(0, -1.0 + MARCHE, BORDURE_Z + 30.0))     # trottoir, dessus à 0,15
	_run.call_deferred()


func _slab(size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	add_child(body)
	body.position = at


func _run() -> void:
	for v: float in VITESSES:
		await _montee(v)
	await _sans_personne()
	if _errors.is_empty():
		print("CAR_KERB_RESULT OK")
	else:
		print("CAR_KERB_RESULT FAIL " + " | ".join(_errors))
	get_tree().quit(0 if _errors.is_empty() else 1)


func _montee(v: float) -> void:
	var car := _car(-8.0)
	car.driven_by_player = true
	var haut := -INF
	var arret := 0
	Input.action_press("move_forward")
	for i in 210:
		car.set("_drive_speed", v)
		await get_tree().physics_frame
		haut = maxf(haut, car.global_position.y)
		if i > 60 and car.velocity.length() < 0.5:
			arret += 1
		if car.global_position.z > BORDURE_Z + 3.0:
			break
	Input.action_release("move_forward")
	var monte := car.global_position.z
	# redescente en marche arrière par le même chemin
	var haut_bas := -INF
	Input.action_press("move_back")
	for i in 180:
		car.set("_drive_speed", -v)
		await get_tree().physics_frame
		haut_bas = maxf(haut_bas, car.global_position.y)
		if car.global_position.z < BORDURE_Z - 3.0:
			break
	Input.action_release("move_back")
	var bas := car.global_position.z
	print("CAR_KERB_MONTEE v %.0f m/s : monte jusqu'a z %+.2f (haut %.3f m, %d frames a l'arret), redescend a z %+.2f (haut %.3f m)"
			% [v, monte, haut, arret, bas, haut_bas])
	if monte < BORDURE_Z + 2.0:
		_fail("a %.0f m/s la voiture du joueur ne monte pas sur le trottoir (z %+.2f)" % [v, monte])
	if bas > BORDURE_Z - 2.0:
		_fail("a %.0f m/s la voiture du joueur ne redescend pas du trottoir (z %+.2f)" % [v, bas])
	# décollage : la caisse ne doit jamais dépasser le dessus du trottoir de plus d'une demi-marche
	if haut > MARCHE + 1.2 or haut_bas > MARCHE + 1.2:
		_fail("a %.0f m/s la voiture decolle (%.3f m en montant, %.3f m en descendant)" % [v, haut, haut_bas])
	car.queue_free()
	await get_tree().physics_frame


# Sans personne au volant, le relevé de caisse ne doit RIEN faire : on conduit la voiture à la main, on appelle
# _try_step_up nous-mêmes, et on vérifie qu'elle reste arrêtée devant la marche.
func _sans_personne() -> void:
	var car := _car(-8.0)
	car.driven_by_player = false
	car.set_physics_process(false)
	var fwd := -car.global_transform.basis.z
	for i in 300:
		car.set("_drive_speed", 8.0)
		car.velocity = fwd * 8.0 + Vector3.DOWN * (0.0 if car.is_on_floor() else 6.0)
		car.move_and_slide()
		car.call("_try_step_up", fwd)
		await get_tree().physics_frame
	var z := car.global_position.z
	print("CAR_KERB_SANS_PERSONNE voiture sans conducteur poussee contre la marche pendant 5 s : arretee a z %+.2f" % z)
	if z > BORDURE_Z - 1.0:
		_fail("une voiture sans conducteur franchit la bordure (z %+.2f) : l'IA monterait sur les trottoirs" % z)
	car.queue_free()
	await get_tree().physics_frame


func _car(z: float) -> CharacterBody3D:
	var car: CharacterBody3D = ARCADE.instantiate()
	add_child(car)
	car.remove_from_group("vehicle")
	# l'avant de la voiture arcade est son -Z : pour rouler vers +Z il faut un demi-tour
	car.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.6, z))
	return car


func _fail(line: String) -> void:
	if _errors.size() < 8 and not _errors.has(line):
		_errors.append(line)
