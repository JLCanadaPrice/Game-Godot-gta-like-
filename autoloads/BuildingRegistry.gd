extends Node

# Charge automatiquement tous les BuildingData (.tres) présents
# dans resources/buildings/ au démarrage du jeu.

var all_buildings: Array[BuildingData] = []

func _ready() -> void:
	_load_all_buildings()

func _load_all_buildings() -> void:
	var dir := DirAccess.open("res://resources/buildings/")
	if dir == null:
		push_warning("Dossier resources/buildings/ introuvable")
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var data: BuildingData = load("res://resources/buildings/" + file_name)
			all_buildings.append(data)
		file_name = dir.get_next()
	dir.list_dir_end()

func get_building(id: String) -> BuildingData:
	for b in all_buildings:
		if b.id == id:
			return b
	return null
