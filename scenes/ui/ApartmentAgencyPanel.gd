extends Control

# Catalogue de l'agence immobilière : ouvert depuis l'onglet "Services" du
# téléphone (PhonePanel), même patron que CarDealershipPanel. Ne met pas le
# jeu en pause. V1 : achat = propriété possédée (GameManager.owned_apartments),
# pas encore de lieu visitable -- pas de spawn/téléportation ici,
# contrairement au concessionnaire (ApartmentData.world_position est prêt
# pour ça mais inutilisé pour l'instant).

@onready var items_list: VBoxContainer = $Panel/VBoxContainer/ScrollContainer/ItemsList
@onready var status_label: Label = $Panel/VBoxContainer/StatusLabel
@onready var close_button: Button = $Panel/VBoxContainer/CloseButton

func _ready() -> void:
	add_to_group("apartment_agency_panel")
	visible = false
	close_button.pressed.connect(_on_close_pressed)
	GameManager.money_changed.connect(_on_money_changed)
	GameManager.apartment_purchased.connect(_on_apartment_purchased)
	_refresh()

func show_ui() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	status_label.text = ""
	_refresh()

func hide_ui() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_close_pressed() -> void:
	hide_ui()

func _on_money_changed(_amount: int) -> void:
	if visible:
		_refresh()   # garde la disponibilité des boutons "Acheter" à jour

func _on_apartment_purchased(_apartment_id: String) -> void:
	if visible:
		_refresh()

func _refresh() -> void:
	for child in items_list.get_children():
		child.queue_free()
	for apt_data: ApartmentData in AgencyRegistry.all_apartments:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s (%s) -- %d $" % [apt_data.display_name, apt_data.neighborhood, apt_data.price]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		if GameManager.owns_apartment(apt_data.id):
			var owned_label := Label.new()
			owned_label.text = "Possédé"
			row.add_child(owned_label)
		else:
			var buy_button := Button.new()
			buy_button.text = "Acheter"
			buy_button.disabled = GameManager.money < apt_data.price
			var data := apt_data
			buy_button.pressed.connect(func(): _on_buy_pressed(data))
			row.add_child(buy_button)

		items_list.add_child(row)

func _on_buy_pressed(apt_data: ApartmentData) -> void:
	if GameManager.owns_apartment(apt_data.id):
		return
	if not GameManager.remove_money(apt_data.price):
		status_label.text = "Pas assez d'argent"
		return
	GameManager.own_apartment(apt_data.id)
	status_label.text = "%s acheté !" % apt_data.display_name
