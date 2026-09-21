extends Node3D

# Feux de véhicules et véhicules en stationnement, vérifiés dans le MONDE CUIT.
#
# Ce que le test couvre, et pourquoi :
#  - FREINS DU JOUEUR : appuyer sur S en roulant doit allumer les feux. C'est le défaut corrigé le
#    2026-09-20 : brake_lights_on() ne regardait que la vitesse quand le joueur conduisait, donc les
#    feux ne s'allumaient qu'une fois la voiture presque arrêtée, et jamais en roulant ;
#  - VOITURE GARÉE : feux éteints. Sans cette règle, un véhicule à l'arrêt (vitesse nulle) allumerait
#    ses feux de freinage en permanence — ce que la section « véhicules garés » aurait introduit sur
#    les quatorze véhicules des lieux ;
#  - GYROPHARES : éteints par défaut, bascule par l'API, deux moitiés de rampe qui ALTERNENT (jamais
#    allumées ensemble), double éclat par phase, et les couleurs du vrai : rouge/bleu pour la police,
#    rouge/blanc pour les urgences, ambre réservé à l'arrière des camions de pompiers ;
#  - STATIONNEMENT : les véhicules des lieux sont de VRAIES voitures du groupe `vehicle`, avec leur
#    collision, à l'endroit que la cuisson a écrit dans sa fiche.

const WORLD := preload("res://scenes/world/World.tscn")
const CAR := preload("res://scenes/vehicles/Car.tscn")
const PLACES_JSON := "res://scenes/world/map/generated/places/places.json"
const DOWNTOWN_JSON := "res://scenes/world/downtown/generated/parked.json"
# Chemins RÉELS du catalogue : _couleurs_gyro lit le rôle dans resources/vehicle_models, un chemin
# inventé n'y est pas et retomberait sur le rôle vide.
const VEH := "res://assets/vehicle_models_extra/city_vehicles_UNVERIFIED_LICENSE/"
const POLICE := VEH + "Police/Veh_Police_Sedan.glb"
const POMPIER := VEH + "Emergency/Veh_Firetruck.glb"
const AMBULANCE := VEH + "Emergency/Veh_Ambulance.glb"
const BERLINE := "res://assets/vehicle_models_extra/city_vehicles_UNVERIFIED_LICENSE/Sedans/Veh_Sedan_01_Blue.glb"

var _fautes: Array[String] = []
var _monde: Node = null


func _ready() -> void:
	_monde = WORLD.instantiate()
	add_child(_monde)
	for s in ["CarSpawner", "NpcSpawner"]:
		var n := _monde.get_node_or_null(s)
		if n != null:
			n.set_process(false)
	for k in 8:
		await get_tree().physics_frame
	await _freins_joueur()
	await _flaque_de_frein()
	_stationnement()
	_gyro_motif()
	_gyro_api()
	_verdict()


# --- freins du joueur -----------------------------------------------------------------------------

func _freins_joueur() -> void:
	var car := CAR.instantiate()
	car.forced_model_path = BERLINE
	add_child(car)
	car.global_position = Vector3(0, 400, 0)
	car.driven_by_player = true
	car.set("_drive_speed", 10.0)
	# pas de pédale : en roulant, les feux doivent être ÉTEINTS
	Input.action_release("move_back")
	for k in 3:
		await get_tree().physics_frame
	var au_repos: bool = car.call("brake_lights_on")
	# pédale enfoncée en roulant : les feux doivent être ALLUMÉS, de jour comme de nuit
	car.set("_drive_speed", 10.0)
	Input.action_press("move_back")
	for k in 3:
		await get_tree().physics_frame
	var en_freinant: bool = car.call("brake_lights_on")
	Input.action_release("move_back")
	if au_repos:
		_fautes.append("feux de freinage allumés alors que le joueur roule sans freiner")
	if not en_freinant:
		_fautes.append("feux de freinage ÉTEINTS alors que le joueur appuie sur le frein en roulant")
	# voiture garée : personne au volant, feux éteints
	car.driven_by_player = false
	car.call("park")
	for k in 2:
		await get_tree().physics_frame
	var garee: bool = car.call("brake_lights_on")
	if garee:
		_fautes.append("feux de freinage allumés sur une voiture garée")
	print("VEHICLE_LIGHTS_FREINS roule %s / freine %s / garee %s" % [str(au_repos), str(en_freinant), str(garee)])
	car.queue_free()


# --- la flaque de freinage tombe DERRIERE la voiture ----------------------------------------------
# Elle etait posee a 0,25 m de l'ORIGINE du vehicule, c'est-a-dire de son centre : la lumiere se
# trouvait donc SOUS la caisse. On exige maintenant qu'elle soit au-dela de la poupe.

func _flaque_de_frein() -> void:
	var vl := _monde.get_node_or_null("VehicleLights")
	if vl == null:
		return
	var car := CAR.instantiate()
	car.forced_model_path = BERLINE
	add_child(car)
	car.global_position = Vector3(0, 300, 0)
	car.driven_by_player = true
	car.set("_drive_speed", 10.0)
	Input.action_press("move_back")
	# la camera doit voir la voiture : VehicleLights ne pose que ce qui est a portee
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.global_position = Vector3(0, 302, 12)
	cam.look_at(Vector3(0, 300, 0), Vector3.UP)
	var cycle := _monde.get_node_or_null("DayNight")
	if cycle != null:
		cycle.set("paused", true)
		cycle.call("set_hour", 1.0)
	for k in 10:
		await get_tree().process_frame
	Input.action_release("move_back")
	var spots: Array = []
	for n in vl.get_children():
		if n is SpotLight3D and String(n.name).begins_with("Frein_") and (n as SpotLight3D).visible:
			spots.append(n)
	if spots.is_empty():
		_fautes.append("aucune flaque de freinage posee la nuit sur une voiture qui freine")
		car.queue_free()
		cam.queue_free()
		return
	var l: SpotLight3D = spots[0]
	# distance derriere l'origine, le long de l'axe de la voiture
	# CONVENTION, verifiee dans Car.gd : l'AVANT d'une voiture est -basis.z (var fwd := -basis.z), donc
	# sa POUPE est +basis.z. Le modele, lui, porte un lacet de 180° (model_yaw_deg), si bien que son
	# propre +Z est l'avant : les deux reperes sont opposes. Mesurer le recul sur le mauvais des deux
	# donne un resultat de signe inverse, ce qui est arrive une fois ici.
	var xf: Transform3D = car.global_transform
	var arriere: Vector3 = xf.basis.z.normalized()
	var recul: float = (l.global_position - xf.origin).dot(arriere)
	var demi := 2.08   # demi-longueur mesuree d'une berline du pack a l'echelle 1,65
	if recul < demi:
		_fautes.append("la flaque de freinage est a %.2f m de l'origine, soit SOUS la voiture (poupe a %.2f m)" % [recul, demi])
	if l.light_cull_mask & 4 != 0:
		_fautes.append("la flaque de freinage eclaire la carrosserie : le calque 3 doit etre exclu")
	print("VEHICLE_LIGHTS_FLAQUE %d flaque(s), recul %.2f m (poupe a %.2f m), masque %d" % [spots.size(), recul, demi, l.light_cull_mask])
	car.queue_free()
	cam.queue_free()


# --- véhicules en stationnement -------------------------------------------------------------------

func _stationnement() -> void:
	var fiches: Array = []
	for chemin in [PLACES_JSON, DOWNTOWN_JSON]:
		if not FileAccess.file_exists(chemin):
			_fautes.append("%s absent : la cuisson n'a pas écrit les véhicules garés" % chemin)
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(chemin))
		if typeof(data) == TYPE_DICTIONARY and data.has("parked"):
			fiches.append_array(data["parked"])
	var attendus := fiches.size()
	var noeud := _monde.get_node_or_null("ParkedVehicles")
	if noeud == null:
		_fautes.append("ParkedVehicles absent de World.tscn")
		return
	var poses: Array[Node3D] = []
	for c in noeud.get_children():
		if c is Node3D and (c as Node3D).is_in_group("vehicle"):
			poses.append(c as Node3D)
	if poses.size() != attendus:
		_fautes.append("%d vehicule(s) gare(s) pose(s) pour %d fiche(s)" % [poses.size(), attendus])
	var sans_collision := 0
	var loin := 0
	var pire := 0.0
	for c in poses:
		if c.find_children("*", "CollisionShape3D", true, false).is_empty():
			sans_collision += 1
		var meilleur := 1e9
		for f: Dictionary in fiches:
			var p: Array = f["pos"]
			meilleur = minf(meilleur, Vector2(c.global_position.x - float(p[0]), c.global_position.z - float(p[2])).length())
		pire = maxf(pire, meilleur)
		if meilleur > 1.5:
			loin += 1
	if sans_collision > 0:
		_fautes.append("%d vehicule(s) gare(s) sans collision : impossible a heurter ni a voler" % sans_collision)
	if loin > 0:
		_fautes.append("%d vehicule(s) gare(s) a plus de 1,5 m de leur fiche (pire %.2f m)" % [loin, pire])
	print("VEHICLE_LIGHTS_GARES %d vehicules poses sur %d fiches, ecart maxi %.2f m, %d sans collision"
			% [poses.size(), attendus, pire, sans_collision])


# --- motif du gyrophare ---------------------------------------------------------------------------

func _gyro_motif() -> void:
	var vl := _monde.get_node_or_null("VehicleLights")
	if vl == null:
		_fautes.append("VehicleLights absent de World.tscn")
		return
	var g: Array = vl.get("GYRO_GAUCHE")
	var d: Array = vl.get("GYRO_DROITE")
	var ensemble := 0
	var ng := 0
	var nd := 0
	for k in g.size():
		if bool(g[k]) and bool(d[k]):
			ensemble += 1
		if bool(g[k]):
			ng += 1
		if bool(d[k]):
			nd += 1
	if ensemble > 0:
		_fautes.append("les deux moities de rampe sont allumees ensemble sur %d temps : elles doivent ALTERNER" % ensemble)
	if ng != 2 or nd != 2:
		_fautes.append("double eclat attendu par moitie : %d a gauche, %d a droite" % [ng, nd])
	var police: Dictionary = vl.call("_couleurs_gyro", POLICE)
	var pompier: Dictionary = vl.call("_couleurs_gyro", POMPIER)
	var ambu: Dictionary = vl.call("_couleurs_gyro", AMBULANCE)
	if int(police["gyro_g"]) != 0 or int(police["gyro_d"]) != 1:
		_fautes.append("police : rampe attendue rouge a gauche et bleue a droite, obtenu %s" % str(police))
	if int(ambu["gyro_d"]) != 3:
		_fautes.append("ambulance : moitie droite attendue BLANCHE, obtenu %s" % str(ambu))
	if int(pompier["gyro_ar"]) != 4:
		_fautes.append("camion de pompiers : ambre attendu a l'ARRIERE, obtenu %s" % str(pompier))
	if int(police["gyro_ar"]) == 4:
		_fautes.append("une voiture de police porte de l'ambre : reserve aux camions")
	print("VEHICLE_LIGHTS_GYRO motif %d/%d eclats, %d chevauchement ; police %s, ambulance %s, pompiers %s"
			% [ng, nd, ensemble, str(police), str(ambu), str(pompier)])


# --- allumage des gyrophares ----------------------------------------------------------------------

func _gyro_api() -> void:
	var vl := _monde.get_node_or_null("VehicleLights")
	if vl == null:
		return
	var urgence: Node3D = null
	for v in get_tree().get_nodes_in_group(&"vehicle"):
		var body := v as Node3D
		if body == null or not body.is_inside_tree():
			continue
		if bool(vl.call("_urgence", vl.call("_cle", body))):
			urgence = body
			break
	if urgence == null:
		_fautes.append("aucun vehicule d'urgence dans la scene : le gyrophare ne peut pas etre verifie")
		return
	if bool(vl.call("gyro_on", urgence)):
		_fautes.append("gyrophare ALLUME par defaut : il doit etre eteint tant qu'aucun evenement ne l'allume")
	var apres: bool = vl.call("toggle_gyro", urgence)
	if not apres or not bool(vl.call("gyro_on", urgence)):
		_fautes.append("toggle_gyro n'allume pas la rampe")
	var n: int = vl.call("allumer_urgences", false)
	if bool(vl.call("gyro_on", urgence)):
		_fautes.append("allumer_urgences(false) n'eteint pas la rampe")
	print("VEHICLE_LIGHTS_GYRO_API eteint par defaut, bascule OK, %d vehicule(s) d'urgence adressable(s)" % n)


func _verdict() -> void:
	if _fautes.is_empty():
		print("VEHICLE_LIGHTS_RESULT OK")
	else:
		for f in _fautes:
			print("VEHICLE_LIGHTS_FAUTE %s" % f)
		print("VEHICLE_LIGHTS_RESULT FAIL %d faute(s)" % _fautes.size())
	get_tree().quit(0)
