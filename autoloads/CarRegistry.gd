extends Node

# Charge automatiquement tous les CarData (.tres) présents dans
# resources/cars/ au démarrage du jeu -- même convention que BuildingRegistry.

var all_cars: Array[CarData] = []

func _ready() -> void:
	_load_all_cars()

func _load_all_cars() -> void:
	var dir := DirAccess.open("res://resources/cars/")
	if dir == null:
		push_warning("Dossier resources/cars/ introuvable")
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var data: CarData = load("res://resources/cars/" + file_name)
			all_cars.append(data)
		file_name = dir.get_next()
	dir.list_dir_end()

func get_car(id: String) -> CarData:
	for c in all_cars:
		if c.id == id:
			return c
	return null
