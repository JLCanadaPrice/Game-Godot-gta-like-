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

const RADIUS_METERS := 75.0
const WIDGET_RADIUS_PX := 80.0
const BG_SCALE: float = WIDGET_RADIUS_PX / RADIUS_METERS  # px/m, même échelle que l'affichage

@onready var player_arrow: Polygon2D = $PlayerArrow
@onready var background_map: TextureRect = $BackgroundMap

var _player: Node3D

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	player_arrow.position = size * 0.5
	background_map.texture = DistrictMapTexture.build(get_tree().current_scene, BG_SCALE)
	background_map.size = background_map.texture.get_size()

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
