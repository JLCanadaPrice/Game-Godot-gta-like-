extends Node3D

# PARKING À ÉTAGES (Business_ParkingStructure) : ce qui le rend praticable, vérifié sur les exemplaires CUITS.
#
#  1. COLLISION PAR DALLE : sur chaque plateau de chaque exemplaire, un piéton (la capsule du joueur, rayon 0,4 m,
#     hauteur 1,8 m) et une voiture (Car.tscn, laissée là) lâchés à 1 m au-dessus du plancher s'y posent et y
#     restent. Avec l'ancienne boîte pleine, ils se posaient sur le TOIT de la boîte, 18 m plus haut.
#
# Les plateaux sont relevés sur le maillage cuit (ParkingStructureKit.planchers), pas recopiés d'une constante.
#
# Lancer : Godot --headless --path <projet> res://scenes/tests/ParkingStructureTest.tscn

const Kit := preload("res://scenes/world/map/tools/ParkingStructureKit.gd")
const CENTRE_VILLE := "res://scenes/world/downtown/generated/Buildings.tscn"
const CAR := preload("res://scenes/vehicles/Car.tscn")
const BERLINE := "res://assets/vehicle_models_extra/city_vehicles_UNVERIFIED_LICENSE/Sedans/Veh_Sedan_01_Blue.glb"
const GRAVITE := 9.8
const DUREE := 2.0
# Points de lâcher, repère du modèle : bande sud (z -5), loin des poteaux (z ~0) et des tours.
const PIETON := Vector3(-4.0, 0.0, -5.0)
const VOITURE := Vector3(6.0, 0.0, -5.5)

var _fautes: Array[String] = []
var _pietons: Array = []     # [CharacterBody3D, altitude attendue du pied, libellé]
var _voitures: Array = []    # [Car, plancher, libellé]
var _t := 0.0
var _repos_voiture := 0.0    # hauteur de l'origine d'une voiture posée sur un sol plat (relevée sur le sol témoin)
var _temoin: Node3D


func _ready() -> void:
	# sol témoin : une dalle plate à y = 0, loin de tout, pour relever la hauteur de repos d'une voiture
	var sol := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var boite := BoxShape3D.new()
	boite.size = Vector3(40, 1, 40)
	cs.shape = boite
	cs.position.y = -0.5
	sol.add_child(cs)
	sol.position = Vector3(0, 0, 3000)
	add_child(sol)
	_temoin = _voiture(Vector3(0, 1.0, 3000), "temoin")
	var ville: Node3D = (load(CENTRE_VILLE) as PackedScene).instantiate()
	add_child(ville)
	var parkings: Array = []
	for b in ville.get_children():
		if String(b.get_meta("model", "")) == Kit.CLE:
			parkings.append(b)
	if parkings.size() != 3:
		_fautes.append("%d parking(s) a etages au centre-ville au lieu de 3" % parkings.size())
	for b: Node3D in parkings:
		var mi := b.get_node("Mesh") as MeshInstance3D
		var cs2 := b.get_node_or_null("StaticBody3D/CollisionShape3D") as CollisionShape3D
		if cs2 == null or not (cs2.shape is ConcavePolygonShape3D):
			_fautes.append("%s : collision %s, pas les triangles du modele" % [b.name, "absente" if cs2 == null else cs2.shape.get_class()])
		var planchers := Kit.planchers(mi.mesh)
		print("PARKING %s en %s : planchers %s" % [b.name, str(b.global_position.snapped(Vector3.ONE * 0.01)), str(planchers)])
		if planchers.size() != 5:
			_fautes.append("%s : %d plateaux releves au lieu de 5" % [b.name, planchers.size()])
		for k in planchers.size():
			var y: float = planchers[k]
			var p := b.global_transform * (PIETON + Vector3(0, y + 1.0, 0))
			_pietons.append([_pieton(p), (b.global_transform * Vector3(0, y, 0)).y, "%s niveau %d" % [b.name, k]])
			var c := b.global_transform * (VOITURE + Vector3(0, y + 1.0, 0))
			_voitures.append([_voiture(c, "%s niveau %d" % [b.name, k]), (b.global_transform * Vector3(0, y, 0)).y, "%s niveau %d" % [b.name, k]])


func _pieton(p: Vector3) -> CharacterBody3D:
	var corps := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	cs.shape = capsule
	corps.add_child(cs)
	corps.floor_snap_length = 0.4
	add_child(corps)
	corps.global_position = p
	return corps


func _voiture(p: Vector3, nom: String) -> Node3D:
	var car := CAR.instantiate() as Node3D
	car.set("forced_model_path", BERLINE)
	car.name = "Voiture_" + nom.validate_node_name()
	add_child(car)
	car.global_position = p
	car.call("park")
	return car


func _physics_process(delta: float) -> void:
	_t += delta
	for e: Array in _pietons:
		var corps: CharacterBody3D = e[0]
		corps.velocity.y = 0.0 if corps.is_on_floor() else corps.velocity.y - GRAVITE * delta
		corps.move_and_slide()
	if _t < DUREE:
		return
	set_physics_process(false)
	_repos_voiture = _temoin.global_position.y
	var pire_pieton := 0.0
	for e: Array in _pietons:
		var corps: CharacterBody3D = e[0]
		var pied := corps.global_position.y - 0.9
		var ecart := absf(pied - float(e[1]))
		pire_pieton = maxf(pire_pieton, ecart)
		if not corps.is_on_floor() or ecart > 0.05:
			_fautes.append("pieton %s : pied a %.2f m pour un plancher a %.2f (%s)" % [e[2], pied, e[1], "au sol" if corps.is_on_floor() else "EN L'AIR"])
	var pire_voiture := 0.0
	for e: Array in _voitures:
		var car: Node3D = e[0]
		var ecart := absf(car.global_position.y - float(e[1]) - _repos_voiture)
		pire_voiture = maxf(pire_voiture, ecart)
		if ecart > 0.05:
			_fautes.append("voiture %s : origine a %.2f m pour un plancher a %.2f (repos %.2f)" % [e[2], car.global_position.y, e[1], _repos_voiture])
	print("PARKING_DALLES %d pietons et %d voitures poses sur les plateaux : ecart au plancher %.3f m au pire (pietons), %.3f m (voitures)"
			% [_pietons.size(), _voitures.size(), pire_pieton, pire_voiture])
	if _fautes.is_empty():
		print("PARKING_STRUCTURE_RESULT OK")
	else:
		for f in _fautes.slice(0, 30):
			print("PARKING_STRUCTURE_FAUTE %s" % f)
		print("PARKING_STRUCTURE_RESULT FAIL %d faute(s)" % _fautes.size())
	get_tree().quit()
