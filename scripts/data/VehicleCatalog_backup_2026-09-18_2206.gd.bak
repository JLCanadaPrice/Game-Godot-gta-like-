extends RefCounted

# Catalogue des réglages par modèle de véhicule (resources/vehicle_models/*.tres, un VehicleModelData par
# modèle), chargé une seule fois à la première demande. Sert à Car.gd : réglages d'un modèle à partir du
# chemin de son fichier, et tirage pondéré des modèles de la circulation. Pas d'autoload : Car.gd le
# précharge en constante et l'appelle en statique.

const ModelData := preload("res://scripts/data/VehicleModelData.gd")
const MODELS_DIR := "res://resources/vehicle_models/"

static var _models: Array[ModelData] = []
static var _by_path: Dictionary = {}     # chemin d'une variante -> ModelData
static var _loaded := false


static func models() -> Array[ModelData]:
	if not _loaded:
		_load()
	return _models


static func find_by_path(path: String) -> ModelData:
	if not _loaded:
		_load()
	return _by_path.get(path) as ModelData


# Tirage pondéré (traffic_weight) parmi les modèles du rôle demandé, puis variante de couleur au hasard.
# Renvoie "" si aucun modèle n'est éligible : l'appelant garde alors son propre repli.
static func pick_traffic_path(role: String = "civil") -> String:
	var eligible: Array[ModelData] = []
	var total := 0.0
	for m in models():
		if m.role == role and m.traffic_weight > 0.0 and not m.model_paths.is_empty():
			eligible.append(m)
			total += m.traffic_weight
	if eligible.is_empty():
		return ""
	var roll := randf() * total
	var chosen: ModelData = eligible.back()
	for m in eligible:
		roll -= m.traffic_weight
		if roll < 0.0:
			chosen = m
			break
	return chosen.model_paths[randi() % chosen.model_paths.size()]


static func _load() -> void:
	_loaded = true
	var dir := DirAccess.open(MODELS_DIR)
	if dir == null:
		push_warning("Dossier %s introuvable : réglages par modèle indisponibles" % MODELS_DIR)
		return
	for file_name in dir.get_files():
		var res_name := file_name.trim_suffix(".remap")   # jeu exporté : .tres convertis, listés en .remap
		if not res_name.ends_with(".tres"):
			continue
		var data := load(MODELS_DIR + res_name) as ModelData
		if data == null or _models.has(data):
			continue
		_models.append(data)
		for p in data.model_paths:
			_by_path[p] = data
