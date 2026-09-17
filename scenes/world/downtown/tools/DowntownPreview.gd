extends SceneTree

# Aperçu du plan de masse du centre-ville (DowntownSpec / DowntownLayout) : image vue de dessus, nord en haut, avec
# chaussées par classe, terre-pleins, trottoirs, passages piétons, carrefours à feux, ruelles, îlots colorés par zone,
# raccords avec les routes de la carte, boutiques et emprises des lieux (places.json). Imprime le bilan de la trame et
# contrôle les raccords (chaque nœud "grid" de MapSpec doit être un carrefour du plan) et les empiètements sur les
# boutiques et les lieux.
#
# Lancer : Godot --headless --path <projet> --script res://scenes/world/downtown/tools/DowntownPreview.gd -- --out=<png>

const Layout := preload("res://scenes/world/downtown/DowntownLayout.gd")
const Spec := preload("res://scenes/world/downtown/DowntownSpec.gd")
const MapSpec := preload("res://scenes/world/map/MapSpec.gd")
const PLACES_JSON := "res://scenes/world/map/generated/places/places.json"

const ORIGIN := Vector2(-965.0, -520.0)
const SIZE := Vector2(1020.0, 745.0)
const SCALE := 1.5

const COLORS := {
	"ground": Color8(214, 205, 180), "water": Color8(92, 137, 176), "quay": Color8(182, 176, 168),
	"boulevard": Color8(52, 52, 58), "avenue": Color8(66, 66, 72), "perimeter": Color8(66, 66, 72),
	"street": Color8(92, 92, 98), "one_way": Color8(104, 96, 112), "box": Color8(60, 60, 66),
	"median": Color8(92, 140, 80), "sidewalk": Color8(196, 196, 190), "crosswalk": Color8(250, 250, 250),
	"alley": Color8(140, 124, 104), "lit": Color8(255, 210, 40), "grid": Color8(230, 40, 200),
	"core": Color8(70, 96, 150), "midrise": Color8(130, 150, 178), "lowrise": Color8(200, 186, 150),
	"plaza": Color8(132, 178, 110), "casino": Color8(196, 60, 60), "shops": Color8(230, 150, 50),
	"civic": Color8(160, 120, 180), "place": Color8(200, 30, 30), "shop": Color8(255, 120, 0),
}


func _initialize() -> void:
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	var layout := Layout.new()
	var img := Image.create(int(SIZE.x * SCALE), int(SIZE.y * SCALE), false, Image.FORMAT_RGBA8)
	img.fill(COLORS["ground"])
	_rect(img, Rect2(-500, -650, 500, 150), COLORS["water"])
	_rect(img, Rect2(-524, -500, 496, 40), COLORS["quay"])
	for block: Dictionary in layout.blocks:
		var color: Color = COLORS[block["zone"]]
		if block["plaza"]:
			color = color.lerp(COLORS["plaza"], 0.45)
		_rect(img, block["interior"], color)
	for i in layout.segments.size():
		var s: Dictionary = layout.segments[i]
		for side in [-1, 1]:
			_rect(img, layout.sidewalk_rect(i, side), COLORS["sidewalk"])
	for n in layout.nodes.size():
		var node: Dictionary = layout.nodes[n]
		var p: Vector2 = node["pos"]
		var hx := float(node["hx"])
		var hz := float(node["hz"])
		_rect(img, Rect2(p.x - node["ped_x_neg"] - 1.0, p.y - node["ped_z_neg"] - 1.0, node["ped_x_neg"] + node["ped_x_pos"] + 2.0, node["ped_z_neg"] + node["ped_z_pos"] + 2.0), COLORS["sidewalk"])
		_rect(img, Rect2(p.x - hx, p.y - hz, hx * 2.0, hz * 2.0), COLORS["box"])
	for alley: Dictionary in layout.alleys:
		_rect(img, alley["curb_rect"], COLORS["alley"])
	for i in layout.segments.size():
		var s: Dictionary = layout.segments[i]
		var road := layout.carriageway_rect(i)
		_rect(img, road, COLORS[s["profile"]])
		if float(s["median"]) > 0.0:
			var m := float(s["median"]) * 0.5
			_rect(img, Rect2(road.position.x + road.size.x * 0.5 - m, road.position.y + 4.0, m * 2.0, road.size.y - 8.0) if s["axis"] == "x"
					else Rect2(road.position.x + 4.0, road.position.y + road.size.y * 0.5 - m, road.size.x - 8.0, m * 2.0), COLORS["median"])
	var crosswalks := 0
	var stops: Array[float] = []
	for n in layout.nodes.size():
		var node: Dictionary = layout.nodes[n]
		if not node["lit"]:
			continue
		for arm: String in node["arms"]:
			var cw := layout.crosswalk(n, arm)
			var r: Rect2 = cw["rect"]
			var across_x := arm == "N" or arm == "S"
			var k := 0.0
			var length := r.size.x if across_x else r.size.y
			while k < length:
				_rect(img, Rect2(r.position.x + k, r.position.y, 0.9, r.size.y) if across_x else Rect2(r.position.x, r.position.y + k, r.size.x, 0.9), COLORS["crosswalk"])
				k += 1.8
			crosswalks += 1
			stops.append(float(cw["stop"]))
		_dot(img, node["pos"], 2.5, COLORS["lit"])
	# raccords de la carte
	var grid_ok := 0
	var grid_missing: Array[String] = []
	for id: String in MapSpec.NODES:
		var spec_node: Dictionary = MapSpec.NODES[id]
		if spec_node["kind"] != "grid":
			continue
		_ring(img, spec_node["pos"], 7.0, COLORS["grid"])
		if layout.node_index(spec_node["pos"]) >= 0:
			grid_ok += 1
		else:
			grid_missing.append(id)
	# boutiques et lieux
	var clashes: Array[String] = []
	for shop: Dictionary in Spec.SHOPS:
		_rect(img, shop["rect"], COLORS["shop"])
		_check_clash(layout, shop["rect"], shop["name"], clashes)
	var places: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PLACES_JSON))
	for fp: Dictionary in places["footprints"]:
		var r := _poly_rect(fp["poly"])
		if not Rect2(-972, -489, 1032, 716).intersects(r):
			continue
		_outline(img, r, COLORS["place"])
		_check_clash(layout, r, "lieu %s (%.0f, %.0f)" % [fp["kind"], r.get_center().x, r.get_center().y], clashes)
	for poi: Dictionary in MapSpec.POIS:
		if poi["id"] == "casino":
			var half: Vector2 = poi["size"] * 0.5
			var casino := Rect2(poi["pos"] - half, poi["size"])
			_outline(img, casino, COLORS["place"])
			_check_clash(layout, casino, "casino (MapSpec.POIS)", clashes)
	if out != "":
		img.save_png(out)
	var st := layout.stats()
	stops.sort()
	print("DOWNTOWN_PLAN tronçons %s | longueurs km %s" % [st["segments"], _round(st["km"])])
	print("DOWNTOWN_PLAN %d carrefours (%d à feux, dont %d en T), %d passages piétons (arrêt à %.1f–%.1f m du centre), %d îlots %s, %d ruelles"
			% [st["nodes"], st["lit"], st["tees"], crosswalks, stops[0], stops[stops.size() - 1], st["blocks"], st["zones"], st["alleys"]])
	print("DOWNTOWN_PLAN raccords de la carte : %d/8 sur un carrefour %s | empiètements : %s" % [grid_ok, grid_missing, clashes if not clashes.is_empty() else "aucun"])
	var small := []
	var shapes := []
	for block: Dictionary in layout.blocks:
		var inner: Rect2 = block["interior"]
		if inner.size.x < 40.0 or inner.size.y < 40.0:
			small.append("%s %s" % [block["zone"], inner])
		var cells: Rect2i = block["cells"]
		if cells.get_area() != int(block["cell_count"]):
			shapes.append("%s %s" % [block["zone"], block["outer"]])
	var dead := []
	for node: Dictionary in layout.nodes:
		var arms: Dictionary = node["arms"]
		if arms.size() < 2 or (arms.size() == 2 and ((arms.has("N") and arms.has("S")) or (arms.has("W") and arms.has("E")))):
			dead.append("%s %s" % [node["pos"], arms.keys()])
	print("DOWNTOWN_PLAN îlots de moins de 40 m : %s | îlots non rectangulaires : %s | impasses ou nœuds de passage : %s" % [small, shapes, dead])
	quit()


# Emprise des chaussées, trottoirs et ruelles qui chevauche `r` (hors trottoir extérieur longé).
func _check_clash(layout: Layout, r: Rect2, label: String, clashes: Array[String]) -> void:
	var inner := r.grow(-0.05)
	for i in layout.segments.size():
		for side in [-1, 1]:
			if layout.sidewalk_rect(i, side).intersects(inner):
				clashes.append("%s / trottoir de %s" % [label, layout.segments[i]["name"]])
				return
		if layout.carriageway_rect(i).intersects(inner):
			clashes.append("%s / chaussée de %s" % [label, layout.segments[i]["name"]])
			return
	for alley: Dictionary in layout.alleys:
		if (alley["curb_rect"] as Rect2).intersects(inner):
			clashes.append("%s / ruelle" % label)
			return


func _poly_rect(poly: Array) -> Rect2:
	var r := Rect2(Vector2(poly[0][0], poly[0][1]), Vector2.ZERO)
	for q: Array in poly:
		r = r.expand(Vector2(q[0], q[1]))
	return r


func _px(p: Vector2) -> Vector2:
	return (p - ORIGIN) * SCALE


func _rect(img: Image, r: Rect2, color: Color) -> void:
	var a := _px(r.position)
	var b := _px(r.end)
	var ri := Rect2i(Vector2i(floori(a.x), floori(a.y)), Vector2i(maxi(1, roundi(b.x - a.x)), maxi(1, roundi(b.y - a.y))))
	ri = ri.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if ri.size.x > 0 and ri.size.y > 0:
		img.fill_rect(ri, color)


func _outline(img: Image, r: Rect2, color: Color) -> void:
	var t := 1.0 / SCALE * 2.0
	_rect(img, Rect2(r.position, Vector2(r.size.x, t)), color)
	_rect(img, Rect2(Vector2(r.position.x, r.end.y - t), Vector2(r.size.x, t)), color)
	_rect(img, Rect2(r.position, Vector2(t, r.size.y)), color)
	_rect(img, Rect2(Vector2(r.end.x - t, r.position.y), Vector2(t, r.size.y)), color)


func _dot(img: Image, p: Vector2, radius: float, color: Color) -> void:
	_rect(img, Rect2(p - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), color)


func _ring(img: Image, p: Vector2, radius: float, color: Color) -> void:
	_outline(img, Rect2(p - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), color)


func _round(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = snappedf(float(d[k]), 0.01)
	return out
