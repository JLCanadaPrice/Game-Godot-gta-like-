class_name VehicleModelData
extends Resource

# Réglages d'un modèle de véhicule (un .tres par modèle, sous resources/vehicle_models/), lus par
# Car._setup_model() via scripts/data/VehicleCatalog.gd -- même convention que CarData/resources/cars/.

@export var id: String
# Variantes de couleur du même modèle (même géométrie, mêmes réglages) : une est tirée au hasard.
@export var model_paths: PackedStringArray
@export var model_scale := 1.0
@export var model_yaw_deg := 180.0      # orientation native : 180 pour un modèle dont l'avant est en +Z
@export var model_y_offset := -0.45     # décalage vertical du modèle visuel (cf. Car.gd), origine au sol
# "civil" = circulation normale. Les autres rôles sont réservés (futurs systèmes police / urgences / SWAT,
# aéronefs) et ne sont jamais tirés par la circulation civile.
@export_enum("civil", "police", "emergency", "swat", "aircraft") var role: String = "civil"
@export_range(0.0, 10.0, 0.05) var traffic_weight := 1.0   # poids relatif dans la circulation (0 = jamais)
