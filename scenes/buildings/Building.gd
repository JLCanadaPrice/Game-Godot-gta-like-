extends Area3D

const Facade := preload("res://scripts/facade_factory.gd")

@export var building_data: BuildingData

@onready var interact_prompt: Node3D = $InteractPrompt
@onready var prompt_label: Label3D = $InteractPrompt/Label

var _player_in_range := false

func _ready() -> void:
	_apply_facade()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	GameManager.building_purchased.connect(_on_building_purchased)
	interact_prompt.visible = false
	_refresh_prompt()

func _apply_facade() -> void:
	var mi := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	var world_scale := mi.global_transform.basis.get_scale()
	mi.material_override = Facade.build(mi.get_aabb().size, world_scale)

func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range:
		return
	if event.is_action_pressed("interact"):
		# Ouvre le panneau dans les deux cas : achat si non possédé,
		# accès à la gestion du business si déjà possédé.
		get_tree().call_group("building_purchase_ui", "show_for_building", building_data)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		interact_prompt.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		interact_prompt.visible = false
		get_tree().call_group("building_purchase_ui", "hide_ui")
		get_tree().call_group("business_panel", "hide_ui")

func _on_building_purchased(building_id: String) -> void:
	if building_data != null and building_id == building_data.id:
		_refresh_prompt()

func _is_owned() -> bool:
	return building_data != null and GameManager.owns_building(building_data.id)

func _refresh_prompt() -> void:
	if _is_owned():
		prompt_label.text = "Acheté  -  [ E ] gérer"
	else:
		prompt_label.text = "[ E ]  Acheter le bâtiment"
