extends Control

@onready var money_label: Label = $MarginContainer/VBoxContainer/MoneyLabel
@onready var reputation_label: Label = $MarginContainer/VBoxContainer/ReputationLabel
@onready var wanted_label: Label = $MarginContainer/VBoxContainer/WantedLabel
@onready var ammo_label: Label = $MarginContainer/VBoxContainer/AmmoLabel
@onready var crosshair: Control = $Crosshair

func _ready() -> void:
	GameManager.money_changed.connect(_on_money_changed)
	GameManager.reputation_changed.connect(_on_reputation_changed)
	PoliceManager.wanted_level_changed.connect(_on_wanted_changed)
	# Valeurs initiales (les signaux ne sont émis que lors d'un changement)
	_on_money_changed(GameManager.money)
	_on_reputation_changed(GameManager.reputation)
	_on_wanted_changed(PoliceManager.wanted_level)

	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_signal("ammo_changed"):
		player.connect("ammo_changed", _on_ammo_changed)
	if player != null and player.has_signal("weapon_equipped_changed"):
		player.connect("weapon_equipped_changed", _on_weapon_equipped_changed)

func _on_ammo_changed(current_ammo: int, reserve_ammo: int) -> void:
	ammo_label.text = "Munitions : %d / %d" % [current_ammo, reserve_ammo]

func _on_weapon_equipped_changed(equipped: bool) -> void:
	crosshair.visible = equipped

func _on_money_changed(new_amount: int) -> void:
	money_label.text = "Argent : %d $" % new_amount

func _on_reputation_changed(new_amount: int) -> void:
	reputation_label.text = "Réputation : %d" % new_amount

func _on_wanted_changed(new_level: int) -> void:
	var filled := "★".repeat(new_level)
	var empty := "☆".repeat(PoliceManager.MAX_WANTED - new_level)
	wanted_label.text = "Recherché : %s%s" % [filled, empty]
