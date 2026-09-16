extends Node

# Inventaire du joueur : registre des types d'objets (ItemData, un .tres par
# objet dans resources/items/, même convention que BuildingRegistry) +
# contenu runtime (quantités possédées). Vide pour l'instant, prêt à
# recevoir des objets plus tard (dealer, fabrication de drogue, etc.).

signal inventory_changed

var item_registry: Dictionary = {}  # id (String) -> ItemData
var contents: Dictionary = {}       # id (String) -> quantité (int)

func _ready() -> void:
	_load_item_registry()

func _load_item_registry() -> void:
	var dir := DirAccess.open("res://resources/items/")
	if dir == null:
		return  # dossier pas encore créé / vide, rien à charger
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var data: ItemData = load("res://resources/items/" + file_name)
			item_registry[data.id] = data
		file_name = dir.get_next()
	dir.list_dir_end()

func add_item(id: String, qty: int) -> void:
	if qty <= 0:
		return
	contents[id] = get_quantity(id) + qty
	inventory_changed.emit()

func remove_item(id: String, qty: int) -> void:
	if qty <= 0 or not contents.has(id):
		return
	var remaining: int = contents[id] - qty
	if remaining <= 0:
		contents.erase(id)
	else:
		contents[id] = remaining
	inventory_changed.emit()

func get_quantity(id: String) -> int:
	return contents.get(id, 0)

func get_owned_ids() -> Array:
	return contents.keys()
