extends Control

# Carte plein écran : réutilise la même génération de texture
# routes/bâtiments que Minimap.gd (voir DistrictMapTexture.gd), juste à une
# résolution plus élevée puisque affichée en plein écran. Le TextureRect
# MapBackground garde le ratio d'aspect réel du quartier (STRETCH_KEEP_ASPECT_CENTERED)
# et se redimensionne tout seul avec l'écran.
const MAP_PIXELS_PER_METER := 3.0

@onready var map_container: Control = $MapContainer
@onready var map_background: TextureRect = $MapContainer/MapBackground
@onready var building_icons_layer: Control = $MapContainer/BuildingIcons

var building_icon_scene := preload("res://scenes/ui/BuildingMapIcon.tscn")

func _ready() -> void:
	add_to_group("map_menu")
	visible = false
	map_background.texture = DistrictMapTexture.build(get_tree().current_scene, MAP_PIXELS_PER_METER)
	# L'ancien système d'icônes de bâtiments (BuildingMapIcon) n'a jamais eu
	# de calcul de position à l'écran -- les icônes s'empilaient toutes au
	# même endroit. Désactivé pour l'instant plutôt que réparé (hors
	# périmètre de ce chantier) : le code reste prêt à être repris plus tard
	# avec un vrai positionnement via DistrictMapTexture.world_to_pixel().
	# _populate_building_icons()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_map"):
		toggle_map()

func toggle_map() -> void:
	visible = not visible
	# Ne met plus le jeu en pause (cohérent avec I/C) -> comme eux, c'est ce
	# panneau qui pilote Input.mouse_mode le temps qu'il est ouvert, sinon le
	# clic de recapture souris de Player.gd (qui ne tournait pas pendant la
	# pause) reprendrait la main sur la carte.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED

func _populate_building_icons() -> void:
	for building_data: BuildingData in BuildingRegistry.all_buildings:
		var icon := building_icon_scene.instantiate()
		building_icons_layer.add_child(icon)
		icon.setup(building_data)
		icon.fast_travel_requested.connect(_on_fast_travel_requested)

func _on_fast_travel_requested(building_data: BuildingData) -> void:
	if not GameManager.owns_building(building_data.id):
		return  # pas de fast travel vers un bâtiment pas encore acheté
	visible = false
	# TODO: téléporter le joueur à building_data.world_position
