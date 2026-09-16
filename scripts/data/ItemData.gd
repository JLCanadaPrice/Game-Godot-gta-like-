class_name ItemData
extends Resource

# Définition statique d'un TYPE d'objet d'inventaire (un .tres par objet,
# sous resources/items/), même convention que BuildingData/BusinessData.
# Ne contient pas la quantité possédée par le joueur : ça, c'est l'état
# runtime géré par InventoryManager.contents.

@export var id: String
@export var display_name: String
@export var description: String
@export var icon: Texture2D
@export var category: String = "divers"  # "arme", "drogue", "outil", "document", "divers"
@export var stackable: bool = true
@export var max_stack: int = 99
