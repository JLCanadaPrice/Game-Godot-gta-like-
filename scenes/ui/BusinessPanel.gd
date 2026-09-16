extends Control

# Interface de gestion d'un business : stock, revenu estimé par cycle,
# bouton de réapprovisionnement. Ouverte depuis BuildingPurchaseUI quand
# le joueur possède le bâtiment lié.

@onready var name_label: Label = $Panel/VBoxContainer/NameLabel
@onready var stock_label: Label = $Panel/VBoxContainer/StockLabel
@onready var income_label: Label = $Panel/VBoxContainer/IncomeLabel
@onready var restock_button: Button = $Panel/VBoxContainer/RestockButton
@onready var status_label: Label = $Panel/VBoxContainer/StatusLabel
@onready var close_button: Button = $Panel/VBoxContainer/CloseButton

var current_business: BusinessData

func _ready() -> void:
	add_to_group("business_panel")
	visible = false
	restock_button.pressed.connect(_on_restock_pressed)
	close_button.pressed.connect(_on_close_pressed)
	EconomyManager.business_stock_changed.connect(_on_business_event)
	EconomyManager.business_income_generated.connect(_on_business_event)
	GameManager.money_changed.connect(_on_money_changed)

func show_for_business(business: BusinessData) -> void:
	current_business = business
	visible = true
	status_label.text = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()

func hide_ui() -> void:
	visible = false
	current_business = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_close_pressed() -> void:
	hide_ui()

func _on_business_event(business_id: String, _value: int) -> void:
	if current_business != null and business_id == current_business.id:
		_refresh()

func _on_money_changed(_amount: int) -> void:
	if visible:
		_refresh()  # garde le coût / la disponibilité du bouton à jour

func _on_restock_pressed() -> void:
	if current_business == null:
		return
	if EconomyManager.restock(current_business.id):
		status_label.text = "Réapprovisionné"
	else:
		status_label.text = "Pas assez d'argent"
	_refresh()

func _refresh() -> void:
	if current_business == null:
		return
	var b := current_business
	name_label.text = b.display_name
	stock_label.text = "Stock : %d / %d" % [b.current_stock, b.max_stock]
	income_label.text = "Revenu estimé : %d $ / cycle" % EconomyManager.get_cycle_income(b)

	if b.current_stock >= b.max_stock:
		restock_button.disabled = true
		restock_button.text = "Stock plein"
	else:
		restock_button.disabled = false
		restock_button.text = "Réapprovisionner (%d $)" % EconomyManager.get_restock_cost(b)
