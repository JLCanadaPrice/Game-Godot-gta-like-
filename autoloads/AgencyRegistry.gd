extends Node

# Charge automatiquement tous les ApartmentData (.tres) présents dans
# resources/apartments/ au démarrage du jeu -- même convention que
# BuildingRegistry/CarRegistry.

var all_apartments: Array[ApartmentData] = []

func _ready() -> void:
	_load_all_apartments()

func _load_all_apartments() -> void:
	var dir := DirAccess.open("res://resources/apartments/")
	if dir == null:
		push_warning("Dossier resources/apartments/ introuvable")
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var data: ApartmentData = load("res://resources/apartments/" + file_name)
			all_apartments.append(data)
		file_name = dir.get_next()
	dir.list_dir_end()

func get_apartment(id: String) -> ApartmentData:
	for a in all_apartments:
		if a.id == id:
			return a
	return null
