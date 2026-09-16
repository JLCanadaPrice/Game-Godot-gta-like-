extends Control

signal fast_travel_requested(building_data: BuildingData)

@onready var texture_rect: TextureRect = $TextureRect
@onready var button: Button = $Button

var data: BuildingData

func setup(building_data: BuildingData) -> void:
	data = building_data
	if building_data.map_icon:
		texture_rect.texture = building_data.map_icon
	_update_state()

func _update_state() -> void:
	if GameManager.owns_building(data.id):
		modulate = Color.GREEN
	else:
		modulate = Color.YELLOW

func _on_button_pressed() -> void:
	fast_travel_requested.emit(data)
