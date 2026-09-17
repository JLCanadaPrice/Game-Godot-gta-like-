class_name DistrictMapTexture
extends RefCounted

# Génère une ImageTexture des routes/bâtiments du centre-ville -- logique partagée entre Minimap.gd (petit widget HUD)
# et MapMenu.gd (carte plein écran, plus grande résolution), seule l'échelle (pixels_per_meter) diffère entre les deux.
#
# Centre-ville reconstruit : chaussées, carrefours et ruelles tirés du plan (DowntownLayout, mêmes rectangles que les
# rues générées) ; bâtiments : rectangles, taille réelle prise sur StaticBody3D/CollisionShape3D (boîte) de chaque
# bâtiment de Downtown/Buildings et des boutiques (Downtown/Shops), projetée en espace monde pour rester correcte
# quelle que soit la rotation.

const Layout := preload("res://scenes/world/downtown/DowntownLayout.gd")

# Bbox monde couvrant tout le centre-ville (rues du pourtour et bâtiments).
const WORLD_MIN := Vector2(-952.0, -460.0)
const WORLD_MAX := Vector2(20.0, 208.0)

const ROAD_COLOR := Color(0.55, 0.55, 0.58, 1.0)
const BUILDING_COLOR := Color(0.3, 0.26, 0.22, 1.0)
const BUILDING_HOLDERS := ["Downtown/Buildings", "Downtown/Shops"]

static func world_to_pixel(world_pos: Vector3, pixels_per_meter: float) -> Vector2:
	return Vector2(
		(world_pos.x - WORLD_MIN.x) * pixels_per_meter,
		(world_pos.z - WORLD_MIN.y) * pixels_per_meter)

static func build(scene_root: Node, pixels_per_meter: float) -> ImageTexture:
	var tex_w := int(ceil((WORLD_MAX.x - WORLD_MIN.x) * pixels_per_meter))
	var tex_h := int(ceil((WORLD_MAX.y - WORLD_MIN.y) * pixels_per_meter))
	var img := Image.create(tex_w, tex_h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))  # vide/transparent -> le fond du panneau appelant reste visible

	if scene_root == null:
		return ImageTexture.create_from_image(img)

	var layout := Layout.new()
	for i in layout.segments.size():
		_draw_rect2(img, layout.carriageway_rect(i), ROAD_COLOR, pixels_per_meter)
	for node: Dictionary in layout.nodes:
		var p: Vector2 = node["pos"]
		var hx := float(node["hx"])
		var hz := float(node["hz"])
		_draw_rect2(img, Rect2(p.x - hx, p.y - hz, hx * 2.0, hz * 2.0), ROAD_COLOR, pixels_per_meter)
	for alley: Dictionary in layout.alleys:
		_draw_rect2(img, alley["curb_rect"], ROAD_COLOR, pixels_per_meter)

	for holder_path in BUILDING_HOLDERS:
		var holder := scene_root.get_node_or_null(holder_path)
		if holder == null:
			continue
		for building in holder.get_children():
			var footprint := _get_building_footprint(building)
			if not footprint.is_empty():
				_draw_world_rect(img, footprint["position"],
					footprint["width"], footprint["depth"], BUILDING_COLOR, pixels_per_meter)

	return ImageTexture.create_from_image(img)

static func _get_building_footprint(building: Node) -> Dictionary:
	var body := building.get_node_or_null("StaticBody3D")
	if body == null:
		return {}
	var cs := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs == null or not (cs.shape is BoxShape3D):
		return {}
	var box := cs.shape as BoxShape3D
	var half: Vector3 = box.size * 0.5
	var basis: Basis = cs.global_transform.basis
	# Projection des demi-étendues locales sur les axes monde X/Z (correcte
	# pour n'importe quelle rotation, pas seulement les multiples de 90°).
	var world_hx: float = absf(basis.x.x) * half.x + absf(basis.y.x) * half.y + absf(basis.z.x) * half.z
	var world_hz: float = absf(basis.x.z) * half.x + absf(basis.y.z) * half.y + absf(basis.z.z) * half.z
	return {
		"position": cs.global_position,
		"width": world_hx * 2.0,
		"depth": world_hz * 2.0,
	}

static func _draw_rect2(img: Image, r: Rect2, color: Color, pixels_per_meter: float) -> void:
	_draw_world_rect(img, Vector3(r.get_center().x, 0.0, r.get_center().y), r.size.x, r.size.y, color, pixels_per_meter)

static func _draw_world_rect(img: Image, world_center: Vector3, width_m: float, depth_m: float, color: Color, pixels_per_meter: float) -> void:
	var px := (world_center.x - WORLD_MIN.x) * pixels_per_meter
	var py := (world_center.z - WORLD_MIN.y) * pixels_per_meter
	var hw := (width_m * 0.5) * pixels_per_meter
	var hh := (depth_m * 0.5) * pixels_per_meter
	var rect := Rect2i(int(px - hw), int(py - hh), int(hw * 2.0), int(hh * 2.0))
	rect = rect.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if rect.size.x > 0 and rect.size.y > 0:
		img.fill_rect(rect, color)
