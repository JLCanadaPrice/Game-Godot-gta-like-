class_name CarData
extends Resource

# Définition statique d'un modèle de voiture achetable au concessionnaire
# (un .tres par modèle, sous resources/cars/), même convention que
# BuildingData/resources/buildings/. Pas de passive_income : une voiture ne
# rapporte rien, contrairement à un bâtiment -- c'est un achat personnel.

@export var id: String
@export var display_name: String
@export var model_path: String    # un des CAR_MODELS de Car.gd (Cop.fbx exclu, réservé police)
@export var category: String      # "économique", "sport", "utilitaire", "taxi" -- affichage seulement
@export var price: int
