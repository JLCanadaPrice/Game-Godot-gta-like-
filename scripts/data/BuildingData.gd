class_name BuildingData
extends Resource

@export var id: String
@export var display_name: String
@export var district: String
@export var price: int
@export var passive_income: int  # par cycle (heure de jeu, jour, etc.)
@export var upgrade_level: int = 0
@export var max_upgrade_level: int = 3
@export var risk_factor: float = 0.1  # 0.0 à 1.0, influence les descentes de police
@export var map_icon: Texture2D
@export var world_position: Vector3 = Vector3.ZERO  # pour le fast travel
