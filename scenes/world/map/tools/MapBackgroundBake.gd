extends SceneTree

# Étape 2b : fond de la mini-carte et de la carte plein écran pour toute la zone explorable (WorldMapTexture) : couleurs
# des zones (quartiers, zone industrielle, aéroport, campagne en parcelles, forêts), rivière et lacs, voie ferrée,
# routes du modèle RoadNetwork (autoroutes, bretelles, artères, plateaux). Réglages d'import écrits avec : lancer avant
# l'import.
#
# Lancer : Godot --headless --path <projet> --script res://scenes/world/map/tools/MapBackgroundBake.gd

const Spec := preload("res://scenes/world/map/MapSpec.gd")
const Network := preload("res://scenes/world/map/tools/RoadNetwork.gd")
const PATH := "res://scenes/world/map/generated/map_background.png"
const PPM := 0.5
const LAND := Color("3f4a36")
const ZONE_COLORS := {"downtown": Color("4b4d4f"), "suburb": Color("4a5140"), "residential": Color("4d5242"), "mixed": Color("4e5046"),
		"industrial": Color("55544e"), "airport": Color("5a5c55"), "farmland": Color("56603f"), "forest": Color("2f4029")}
const WATER := Color("3d6f8e")
const HIGHWAY := Color("d9a23a")
const RAMP := Color("c98f33")
const ARTERIAL := Color("c9c9c4")
const DIRT := Color("8a7458")
const RAIL := Color("2a2622")
const IMPORT_TEMPLATE := """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="%s"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""

var img: Image


func _initialize() -> void:
	var r := Spec.PLAYABLE
	img = Image.create(ceili(r.size.x * PPM), ceili(r.size.y * PPM), false, Image.FORMAT_RGB8)
	img.fill(LAND)
	var net := Network.new()
	net.build()
	# zones : forêts et campagne d'abord, quartiers par-dessus
	for pass_type in ["forest", "farmland", "other"]:
		for zone: Dictionary in Spec.ZONES:
			var t: String = zone["type"]
			if (pass_type == "other") == (t == "forest" or t == "farmland") or (pass_type != "other" and t != pass_type):
				continue
			_fill_zone(Spec.zone_polygon(zone), t)
	for entry: Array in net.terrain.river_curve(6.0):
		_disc(entry[0], float(entry[1]) * 0.5, WATER)
	for lake: Dictionary in Spec.LAKES:
		_ellipse(lake["center"], lake["radii"], WATER)
	var rail := PackedVector2Array(Spec.RAIL)
	for k in rail.size() - 1:
		_line(rail[k], rail[k + 1], 2.5, RAIL)
	for pad: Dictionary in net.pads:
		var poly := PackedVector2Array()
		for p: Vector3 in pad["rim"]:
			poly.append(Vector2(p.x, p.z))
		_polygon(poly, ARTERIAL)
	for kind in ["arterial", "sidewalk", "ramp", "ring", "carriageway", "median"]:
		for rb in net.ribbons:
			if rb.kind != kind or not rb.mesh or kind == "sidewalk":
				continue
			var color := HIGHWAY
			match kind:
				"ramp", "ring":
					color = RAMP
				"arterial":
					color = DIRT if rb.style == "dirt" else ARTERIAL
			var pts: PackedVector3Array = rb.points
			for k in pts.size() - 1:
				_line(Vector2(pts[k].x, pts[k].z), Vector2(pts[k + 1].x, pts[k + 1].z), maxf(rb.width * 0.5, 3.0), color)
	# image inchangée : rien n'est réécrit (évite un réimport inutile du fond de carte)
	var previous := Image.load_from_file(ProjectSettings.globalize_path(PATH)) if FileAccess.file_exists(PATH) else null
	if previous != null and previous.get_size() == img.get_size():
		previous.convert(Image.FORMAT_RGB8)
		if previous.get_data() == img.get_data():
			print("MAP_BACKGROUND %s : inchangé" % PATH)
			quit(0)
			return
	img.save_png(PATH)
	var f := FileAccess.open(PATH + ".import", FileAccess.WRITE)
	f.store_string(IMPORT_TEMPLATE % PATH)
	f.close()
	print("MAP_BACKGROUND %s : %dx%d px" % [PATH, img.get_width(), img.get_height()])
	quit(0)


func _px(p: Vector2) -> Vector2:
	return (p - Spec.PLAYABLE.position) * PPM


func _fill_zone(poly: PackedVector2Array, type: String) -> void:
	var px := PackedVector2Array()
	for p in poly:
		px.append(_px(p))
	var box := Rect2(px[0], Vector2.ZERO)
	for p in px:
		box = box.expand(p)
	for y in range(maxi(0, floori(box.position.y)), mini(img.get_height(), ceili(box.end.y))):
		for x in range(maxi(0, floori(box.position.x)), mini(img.get_width(), ceili(box.end.x))):
			if not Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), px):
				continue
			var c: Color = ZONE_COLORS[type]
			if type == "farmland":
				var world := Vector2(x, y) / PPM + Spec.PLAYABLE.position
				var cell := Vector2i(floori(world.x / 150.0), floori(world.y / 110.0))
				c = c.lightened([0.0, 0.08, 0.16, 0.04][absi((cell.x * 73856093) ^ (cell.y * 19349663)) % 4])
			img.set_pixel(x, y, c)


func _polygon(poly: PackedVector2Array, color: Color) -> void:
	if poly.size() < 3:
		return
	var px := PackedVector2Array()
	for p in poly:
		px.append(_px(p))
	var box := Rect2(px[0], Vector2.ZERO)
	for p in px:
		box = box.expand(p)
	for y in range(maxi(0, floori(box.position.y)), mini(img.get_height(), ceili(box.end.y) + 1)):
		for x in range(maxi(0, floori(box.position.x)), mini(img.get_width(), ceili(box.end.x) + 1)):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), px):
				img.set_pixel(x, y, color)


func _line(a: Vector2, b: Vector2, half_width_m: float, color: Color) -> void:
	var steps := maxi(1, ceili(a.distance_to(b) * PPM))
	for s in steps + 1:
		_disc(a.lerp(b, float(s) / steps), half_width_m, color)


func _disc(p: Vector2, radius_m: float, color: Color) -> void:
	var c := _px(p)
	var r := maxf(radius_m * PPM, 0.6)
	for y in range(floori(c.y - r), ceili(c.y + r) + 1):
		for x in range(floori(c.x - r), ceili(c.x + r) + 1):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and Vector2(x + 0.5, y + 0.5).distance_squared_to(c) <= r * r:
				img.set_pixel(x, y, color)


func _ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var c := _px(center)
	var rr := radii * PPM
	for y in range(floori(c.y - rr.y), ceili(c.y + rr.y) + 1):
		for x in range(floori(c.x - rr.x), ceili(c.x + rr.x) + 1):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and ((Vector2(x + 0.5, y + 0.5) - c) / rr).length() <= 1.0:
				img.set_pixel(x, y, color)
