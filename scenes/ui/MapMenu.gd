extends Control

# Carte plein écran : fond de toute la carte 3D (WorldMapTexture : zones, rivière,
# autoroutes, artères) affiché en gardant ses proportions, détail des rues et
# bâtiments du centre-ville par-dessus (même génération de texture que
# Minimap.gd, voir DistrictMapTexture.gd) et flèche du joueur. Le détail et la
# flèche sont replacés sur le fond tant que la carte est ouverte (l'écran peut
# être redimensionné). Sans fond généré : le centre-ville seul, comme avant.
const MAP_PIXELS_PER_METER := 1.0

@onready var map_container: Control = $MapContainer
@onready var map_background: TextureRect = $MapContainer/MapBackground
@onready var building_icons_layer: Control = $MapContainer/BuildingIcons

var building_icon_scene := preload("res://scenes/ui/BuildingMapIcon.tscn")
var _district: TextureRect
var _arrow: Polygon2D

func _ready() -> void:
	add_to_group("map_menu")
	visible = false
	var district_texture := DistrictMapTexture.build(get_tree().current_scene, MAP_PIXELS_PER_METER)
	var world_texture := WorldMapTexture.load_texture()
	if world_texture == null:
		map_background.texture = district_texture
	else:
		map_background.texture = world_texture
		_district = TextureRect.new()
		_district.name = "DistrictDetail"
		_district.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_district.texture = district_texture
		_district.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_district.stretch_mode = TextureRect.STRETCH_SCALE
		map_container.add_child(_district)
		map_container.move_child(_district, map_background.get_index() + 1)
		_arrow = Polygon2D.new()
		_arrow.name = "PlayerArrow"
		_arrow.polygon = PackedVector2Array([Vector2(0, -9), Vector2(6, 7), Vector2(-6, 7)])
		_arrow.color = Color(1, 0.9, 0.2, 1)
		map_container.add_child(_arrow)
	# L'ancien système d'icônes de bâtiments (BuildingMapIcon) n'a jamais eu
	# de calcul de position à l'écran -- les icônes s'empilaient toutes au
	# même endroit. Désactivé pour l'instant plutôt que réparé (hors
	# périmètre de ce chantier) : le code reste prêt à être repris plus tard
	# avec un vrai positionnement via DistrictMapTexture.world_to_pixel().
	# _populate_building_icons()

func _process(_delta: float) -> void:
	if not visible or _district == null:
		return
	# rectangle réellement dessiné par MapBackground (STRETCH_KEEP_ASPECT_CENTERED)
	var tex_size := map_background.texture.get_size()
	var fit := minf(map_background.size.x / tex_size.x, map_background.size.y / tex_size.y)
	var origin := map_background.position + (map_background.size - tex_size * fit) * 0.5
	var px_per_m := WorldMapTexture.PIXELS_PER_METER * fit
	var district_min := Vector3(DistrictMapTexture.WORLD_MIN.x, 0.0, DistrictMapTexture.WORLD_MIN.y)
	_district.position = origin + WorldMapTexture.world_to_pixel(district_min, px_per_m)
	_district.size = _district.texture.get_size() * (px_per_m / MAP_PIXELS_PER_METER)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	_arrow.visible = player != null
	if player != null:
		_arrow.position = origin + WorldMapTexture.world_to_pixel(player.global_position, px_per_m)
		var forward := -player.global_transform.basis.z
		if Vector2(forward.x, forward.z).length_squared() > 0.0001:
			_arrow.rotation = Vector2(forward.x, forward.z).angle() + PI / 2.0

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
