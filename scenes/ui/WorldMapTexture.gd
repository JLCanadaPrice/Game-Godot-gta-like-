class_name WorldMapTexture
extends RefCounted

# Fond de carte de toute la zone explorable (MapBackgroundBake : zones, forêts, rivière et lacs, routes, voie ferrée),
# 0,5 px par mètre, nord en haut. Le détail des rues et bâtiments du centre-ville reste dessiné par DistrictMapTexture
# par-dessus (Minimap, MapMenu).

const TEXTURE_PATH := "res://scenes/world/map/generated/map_background.png"
const WORLD_MIN := Vector2(-2174.0, -1480.0)     # MapSpec.PLAYABLE.position
const WORLD_SIZE := Vector2(4347.0, 2447.0)      # MapSpec.PLAYABLE.size
const PIXELS_PER_METER := 0.5


static func load_texture() -> Texture2D:
	return load(TEXTURE_PATH) as Texture2D if ResourceLoader.exists(TEXTURE_PATH) else null


static func world_to_pixel(world_pos: Vector3, pixels_per_meter: float) -> Vector2:
	return Vector2(world_pos.x - WORLD_MIN.x, world_pos.z - WORLD_MIN.y) * pixels_per_meter
