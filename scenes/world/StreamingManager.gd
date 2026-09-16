extends Node
class_name StreamingManager

# ÉTAPE 1 — fondation du streaming par chunks pour la carte 1km x 1km.
# Ce script calcule et valide (via prints) la grille de chunks ; il ne charge/
# décharge encore AUCUN contenu — ça viendra dans une étape suivante, une fois
# la route de base et cette grille validées ensemble.

const CHUNK_SIZE := 250.0                  # taille d'un chunk, en mètres (carré)
const MAP_SIZE := Vector2(1000.0, 1000.0)  # carte totale : 1km x 1km

# Grille centrée sur l'origine (0,0,0) : couvre de -MAP_SIZE/2 à +MAP_SIZE/2
# sur les axes X (largeur) et Z (profondeur).
var grid_dims: Vector2i
var origin_offset: Vector2   # coin (-x,-z) de la grille, en coordonnées monde

func _ready() -> void:
	grid_dims = Vector2i(
		ceili(MAP_SIZE.x / CHUNK_SIZE),
		ceili(MAP_SIZE.y / CHUNK_SIZE))
	origin_offset = Vector2(-MAP_SIZE.x * 0.5, -MAP_SIZE.y * 0.5)

	print("[StreamingManager] CHUNK_SIZE=%.1f | carte=%.0fx%.0fm | grille=%dx%d chunks (%d au total)" % [
		CHUNK_SIZE, MAP_SIZE.x, MAP_SIZE.y, grid_dims.x, grid_dims.y, grid_dims.x * grid_dims.y])
	_debug_print_grid()

# Coordonnée de chunk (colonne, ligne) contenant la position monde donnée.
func world_to_chunk(pos: Vector3) -> Vector2i:
	var local := Vector2(pos.x, pos.z) - origin_offset
	return Vector2i(floori(local.x / CHUNK_SIZE), floori(local.y / CHUNK_SIZE))

# Centre du chunk, en coordonnées monde (y=0).
func chunk_to_world_center(chunk: Vector2i) -> Vector3:
	return Vector3(
		origin_offset.x + (chunk.x + 0.5) * CHUNK_SIZE,
		0.0,
		origin_offset.y + (chunk.y + 0.5) * CHUNK_SIZE)

# Empreinte (x, z, largeur, profondeur) du chunk, en coordonnées monde.
func chunk_to_world_bounds(chunk: Vector2i) -> Rect2:
	return Rect2(
		origin_offset.x + chunk.x * CHUNK_SIZE,
		origin_offset.y + chunk.y * CHUNK_SIZE,
		CHUNK_SIZE, CHUNK_SIZE)

func _debug_print_grid() -> void:
	print("[StreamingManager] Détail de la grille (chunk -> centre monde -> bounds X/Z) :")
	for cz in grid_dims.y:
		for cx in grid_dims.x:
			var c := Vector2i(cx, cz)
			var center := chunk_to_world_center(c)
			var b := chunk_to_world_bounds(c)
			print("  chunk(%d,%d) -> centre=(%.1f, %.1f) | x:[%.1f .. %.1f] z:[%.1f .. %.1f]" % [
				c.x, c.y, center.x, center.z, b.position.x, b.end.x, b.position.y, b.end.y])
