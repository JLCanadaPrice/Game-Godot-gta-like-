extends Node3D

# Franchissement des bordures de trottoir.
#
# Le test se joue sur une maquette et non sur la carte : une dalle de chaussée, une dalle de trottoir 0,15 m plus
# haut (la hauteur mesurée sur la collision cuite, identique sur les artères et au centre-ville), une marche
# verticale entre les deux. Ça tient en quelques secondes et ça ne dépend d'aucune cuisson.
#
# Deux voitures, deux exigences :
#  1. la voiture du JOUEUR roule sur son châssis réel (CLAUDE.md §14) : ses roues à rayon montent une bordure comme de
#     vraies roues. Au volant, elle MONTE sur le trottoir à toutes les vitesses d'approche, sans que sa coque touche la
#     bordure, puis en REDESCEND en marche arrière (S tenu à l'arrêt, comme au clavier), sans rester coincée ni
#     décoller ;
#  2. une voiture de la CIRCULATION, sans personne au volant (Car.gd, conduite cinématique), NE monte PAS : les 252
#     voitures de l'IA doivent continuer d'être arrêtées par les bordures. C'est la face verticale de leur enveloppe,
#     sous les pare-chocs, qui les arrête (CLAUDE.md §12).
# Jusqu'au 2026-09-24, la voiture du joueur était arcade et montait par un relevé de caisse réservé au joueur
# (Car._try_step_up), supprimé avec l'arcade.
#
# La séquence est jouée sur le modèle tiré au sort par la circulation, PUIS sur un pick-up, un camion et un bus, dont les
# enveloppes et les coques sont faites par pièce.
#
# Lancer : Godot --headless --fixed-fps 60 res://scenes/tests/CarKerbTest.tscn

const ARCADE := preload("res://scenes/vehicles/Car.tscn")
const VehicleCatalog := preload("res://scripts/data/VehicleCatalog.gd")
const MARCHE := 0.15
const BORDURE_Z := 0.0        # z de la face verticale
const VITESSES := [3.0, 6.0, 10.0, 15.0]
const V_RECUL := 3.0          # m/s : vitesse de la redescente en marche arrière
const MODELES := ["", "city_pickup_01", "city_truck_01", "city_bus_01"]   # "" : tiré au sort par la circulation

var _errors: Array[String] = []
var _chemin := ""             # modèle imposé à la voiture de la séquence en cours ("" : tirage)
var _trottoir: StaticBody3D


func _ready() -> void:
	print("CAR_KERB_BEGIN")
	_slab(Vector3(60, 2, 60), Vector3(0, -1.0, BORDURE_Z - 30.0))                    # chaussée, dessus à 0
	_trottoir = _slab(Vector3(60, 2, 60), Vector3(0, -1.0 + MARCHE, BORDURE_Z + 30.0))  # trottoir, dessus à 0,15
	_run.call_deferred()


func _slab(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	add_child(body)
	body.position = at
	return body


func _run() -> void:
	for id: String in MODELES:
		_chemin = ""
		if id != "":
			for m in VehicleCatalog.models():
				if m.id == id:
					_chemin = m.model_paths[0]
			if _chemin == "":
				_fail("modele %s introuvable au catalogue" % id)
				continue
		print("CAR_KERB_MODELE %s" % (id if id != "" else "tire au sort"))
		for v: float in VITESSES:
			await _montee(v)
		await _sans_personne()
	_pedales()
	if _errors.is_empty():
		print("CAR_KERB_RESULT OK")
	else:
		print("CAR_KERB_RESULT FAIL " + " | ".join(_errors))
	get_tree().quit(0 if _errors.is_empty() else 1)


func _pedales(gaz := false, frein := false) -> void:
	Input.action_release("gas")
	Input.action_release("brake")
	if gaz:
		Input.action_press("gas")
	if frein:
		Input.action_press("brake")


func _montee(v: float) -> void:
	var car := _car(-10.0)
	await get_tree().physics_frame
	car.call("start_drive")
	var ch: RigidBody3D = car.call("chassis")
	if ch == null:
		_fail("pas de chassis reel pour la voiture du joueur (%s)" % car.get("model_path"))
		car.queue_free()
		return
	ch.call("repartir", -car.global_transform.basis.z * v)
	var haut := -INF
	var contact := 0
	# montée, vitesse tenue à l'accélérateur
	for i in 480:
		var vit: float = ch.call("vitesse_avant")
		_pedales(vit < v, vit > v + 1.5)
		await get_tree().physics_frame
		haut = maxf(haut, car.global_position.y)
		if _trottoir in ch.get_colliding_bodies():
			contact += 1
		if car.global_position.z > BORDURE_Z + 3.0:
			break
	var monte := car.global_position.z
	# arrêt, puis redescente en marche arrière : S tenu (à l'arrêt, la boîte passe la marche arrière), vitesse tenue
	var bas := monte
	var haut_bas := -INF
	for i in 1500:
		var vit: float = ch.call("vitesse_avant")
		var recule: bool = int(ch.get("gear")) == -1
		_pedales(recule and vit < -V_RECUL - 1.0, not recule or vit > -V_RECUL)
		await get_tree().physics_frame
		haut_bas = maxf(haut_bas, car.global_position.y)
		if _trottoir in ch.get_colliding_bodies() and car.global_position.z < BORDURE_Z + 6.0:
			contact += 1
		bas = car.global_position.z
		if bas < BORDURE_Z - 3.0:
			break
	_pedales()
	print("CAR_KERB_MONTEE v %.0f m/s : monte jusqu'a z %+.2f (haut %.3f m), redescend a z %+.2f (haut %.3f m), coque contre la bordure %d pas"
			% [v, monte, haut, bas, haut_bas, contact])
	if monte < BORDURE_Z + 2.0:
		_fail("a %.0f m/s la voiture du joueur ne monte pas sur le trottoir (z %+.2f)" % [v, monte])
	if bas > BORDURE_Z - 2.0:
		_fail("a %.0f m/s la voiture du joueur ne redescend pas du trottoir en marche arriere (z %+.2f)" % [v, bas])
	# décollage : la caisse ne doit jamais dépasser le dessus du trottoir de plus d'une demi-marche
	if haut > MARCHE + 1.2 or haut_bas > MARCHE + 1.2:
		_fail("a %.0f m/s la voiture decolle (%.3f m en montant, %.3f m en descendant)" % [v, haut, haut_bas])
	if contact > 0:
		_fail("a %.0f m/s la coque de %s touche la bordure (%d pas)" % [v, String(car.get("model_path")).get_file(), contact])
	remove_child(car)
	car.queue_free()
	await get_tree().physics_frame


# Une voiture de la circulation, sans personne au volant, poussée à la main contre la marche : elle doit rester
# arrêtée devant.
func _sans_personne() -> void:
	var car := _car(-8.0)
	car.driven_by_player = false
	car.set_physics_process(false)
	var fwd := -car.global_transform.basis.z
	for i in 300:
		car.velocity = fwd * 8.0 + Vector3.DOWN * (0.0 if car.is_on_floor() else 6.0)
		car.move_and_slide()
		await get_tree().physics_frame
	var z := car.global_position.z
	print("CAR_KERB_SANS_PERSONNE voiture sans conducteur poussee contre la marche pendant 5 s : arretee a z %+.2f" % z)
	if z > BORDURE_Z - 1.0:
		_fail("une voiture sans conducteur franchit la bordure (z %+.2f) : l'IA monterait sur les trottoirs" % z)
	car.queue_free()
	await get_tree().physics_frame


func _car(z: float) -> CharacterBody3D:
	var car: CharacterBody3D = ARCADE.instantiate()
	if _chemin != "":
		car.set("forced_model_path", _chemin)
	add_child(car)
	car.remove_from_group("vehicle")
	# l'avant de la voiture est son -Z : pour rouler vers +Z il faut un demi-tour
	car.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.6, z))
	return car


func _fail(line: String) -> void:
	if _errors.size() < 8 and not _errors.has(line):
		_errors.append(line)
