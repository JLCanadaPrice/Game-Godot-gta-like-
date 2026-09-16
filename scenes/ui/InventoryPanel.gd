extends Control

# Panneau d'inventaire : ouvert/fermé par la touche I (toggle_inventory).
# Ne met pas le jeu en pause (comme BusinessPanel/BuildingPurchaseUI), pour
# rester utilisable pendant que le monde continue de tourner. Vide pour
# l'instant -- la structure de données (InventoryManager) est prête à
# recevoir des objets plus tard.

@onready var panel: Panel = $Panel
@onready var items_list: VBoxContainer = $Panel/VBoxContainer/ScrollContainer/ItemsList
@onready var empty_label: Label = $Panel/VBoxContainer/EmptyLabel
@onready var close_button: Button = $Panel/VBoxContainer/CloseButton

func _ready() -> void:
	add_to_group("inventory_panel")
	visible = false
	close_button.pressed.connect(_on_close_pressed)
	InventoryManager.inventory_changed.connect(_refresh)
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		toggle()

func toggle() -> void:
	if visible:
		hide_ui()
	else:
		show_ui()

func show_ui() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()

func hide_ui() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_close_pressed() -> void:
	hide_ui()

func _refresh() -> void:
	for child in items_list.get_children():
		child.queue_free()
	var owned_ids: Array = InventoryManager.get_owned_ids()
	empty_label.visible = owned_ids.is_empty()
	for id in owned_ids:
		var data: ItemData = InventoryManager.item_registry.get(id)
		var qty: int = InventoryManager.get_quantity(id)
		var display: String = data.display_name if data != null else String(id)
		var label := Label.new()
		label.text = "%s  x%d" % [display, qty]
		items_list.add_child(label)
