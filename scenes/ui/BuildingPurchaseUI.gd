extends Control

@onready var name_label: Label = $Panel/VBoxContainer/NameLabel
@onready var price_label: Label = $Panel/VBoxContainer/PriceLabel
@onready var income_label: Label = $Panel/VBoxContainer/IncomeLabel
@onready var buy_button: Button = $Panel/VBoxContainer/BuyButton
@onready var status_label: Label = $Panel/VBoxContainer/StatusLabel
@onready var close_button: Button = $Panel/VBoxContainer/CloseButton
@onready var manage_button: Button = $Panel/VBoxContainer/ManageButton

var current_building: BuildingData

func _ready() -> void:
	add_to_group("building_purchase_ui")
	visible = false
	buy_button.pressed.connect(_on_buy_pressed)
	close_button.pressed.connect(_on_close_pressed)
	manage_button.pressed.connect(_on_manage_pressed)

func show_for_building(building_data: BuildingData) -> void:
	current_building = building_data
	name_label.text = building_data.display_name
	price_label.text = "Prix : %d $" % building_data.price
	income_label.text = "Revenu passif : %d $ / cycle" % building_data.passive_income
	_update_status()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func hide_ui() -> void:
	visible = false
	current_building = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_close_pressed() -> void:
	hide_ui()

func _update_status() -> void:
	if current_building == null:
		return
	var owned := GameManager.owns_building(current_building.id)
	if owned:
		status_label.text = "Déjà possédé"
		buy_button.disabled = true
	else:
		status_label.text = ""
		buy_button.disabled = false
	# Le bouton de gestion n'apparaît qu'une fois le bâtiment possédé
	# et seulement s'il existe un business rattaché à ce bâtiment.
	var has_business := EconomyManager.get_business_for_building(current_building.id) != null
	manage_button.visible = owned and has_business

func _on_buy_pressed() -> void:
	if current_building == null:
		return
	if GameManager.remove_money(current_building.price):
		GameManager.own_building(current_building.id)
		_update_status()
	else:
		status_label.text = "Pas assez d'argent"

func _on_manage_pressed() -> void:
	if current_building == null:
		return
	var business := EconomyManager.get_business_for_building(current_building.id)
	if business == null:
		return
	visible = false
	current_building = null
	get_tree().call_group("business_panel", "show_for_business", business)
