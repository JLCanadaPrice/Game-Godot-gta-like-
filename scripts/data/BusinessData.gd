class_name BusinessData
extends Resource

# Données d'un "business" criminel stylisé, lié à un bâtiment possédé.
# Reste volontairement abstrait (pas de détails réalistes) : stock, prix, demande, risque.

@export var id: String
@export var display_name: String
@export var linked_building_id: String  # doit correspondre à un BuildingData.id
@export var base_price: int
@export var current_stock: int = 0
@export var max_stock: int = 100
@export var demand_factor: float = 1.0  # multiplie le revenu selon la demande du quartier
@export var risk_factor: float = 0.1    # 0.0 à 1.0, influence le wanted level via PoliceManager
