extends Control

# Mini-carte abstraite : joueur au centre fixe, oriente nord toujours vers
# le haut. Convention du monde confirmée dans DistrictBaker.gd : Nord=-Z,
# Sud=+Z, Est=+X, Ouest=-X. Comme +Z (sud) et l'écran +Y (bas) pointent déjà
# dans le même sens, la projection est directe (dx, dz) -> (x, y) écran,
# sans inversion.
#
# Fond routes/bâtiments : pré-rendu UNE SEULE FOIS au démarrage (voir
# DistrictMapTexture.gd, logique partagée avec MapMenu.gd). Zéro recalcul
# par frame ensuite : seule la position de ce gros TextureRect est décalée
# chaque frame pour suivre le joueur (fond fixe = pas de nouveau dessin).
# Sous ce détail du centre-ville, le fond de toute la carte 3D (WorldMapTexture :
# zones, rivière, autoroutes et artères), agrandi à la même échelle et décalé de même.

const RADIUS_METERS := 75.0
const WIDGET_RADIUS_PX := 80.0
const BG_SCALE: float = WIDGET_RADIUS_PX / RADIUS_METERS  # px/m, même échelle que l'affichage

@onready var player_arrow: Polygon2D = $PlayerArrow
@onready var background_map: TextureRect = $BackgroundMap

var _player: Node3D
var _world_map: TextureRect

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	player_arrow.position = size * 0.5
	background_map.texture = DistrictMapTexture.build(get_tree().current_scene, BG_SCALE)
	background_map.size = background_map.texture.get_size()
	var world_texture := WorldMapTexture.load_texture()
	if world_texture != null:
		_world_map = TextureRect.new()
		_world_map.name = "WorldMap"
		_world_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_world_map.texture = world_texture
		_world_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_world_map.stretch_mode = TextureRect.STRETCH_SCALE
		_world_map.size = world_texture.get_size() * (BG_SCALE / WorldMapTexture.PIXELS_PER_METER)
		add_child(_world_map)
		move_child(_world_map, background_map.get_index())   # sous le détail du centre-ville

func _process(_delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return

	var forward: Vector3 = -_player.global_transform.basis.z
	var screen_dir := Vector2(forward.x, forward.z)
	if screen_dir.length_squared() > 0.0001:
		player_arrow.rotation = screen_dir.angle() + PI / 2.0

	var player_px := DistrictMapTexture.world_to_pixel(_player.global_position, BG_SCALE)
	background_map.position = size * 0.5 - player_px
	if _world_map != null:
		_world_map.position = size * 0.5 - WorldMapTexture.world_to_pixel(_player.global_position, BG_SCALE)
