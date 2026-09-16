extends SceneTree

# Contrôle du modèle de réseau routier (RoadNetwork) avant la cuisson : rapport (pentes, dégagements, graphe) et
# aperçus vus du dessus : carte entière et gros plans des échangeurs, losanges et carrefours, rubans colorés par type,
# plateaux, graphe, conflits (magenta), passages de la voie ferrée (brun).
#
# Lancer : Godot --headless --path <projet> --script res://scenes/world/map/tools/RoadNetworkPreview.gd -- --out=<dossier>

const Spec := preload("res://scenes/world/map/MapSpec.gd")
const Network := preload("res://scenes/world/map/tools/RoadNetwork.gd")
const COLORS := {"carriageway": Color("d89b1d"), "median": Color("7a7a7a"), "ramp": Color("e06a2c"), "ring": Color("c0392b"),
		"urban": Color("5d6d7e"), "arterial": Color("8e44ad"), "access": Color("16a085"), "dirt": Color("a0522d"), "sidewalk": Color("bdc3c7"), "pad": Color("34495e")}
const CLOSE_UPS := ["x_no", "x_ne", "x_st", "x_se", "d_n9", "d_o172", "d_no13", "d_so13", "d_e8", "d_s7", "j_lake", "r_echo", "g_o172", "j_hollow"]


func _initialize() -> void:
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	var t0 := Time.get_ticks_msec()
	var net := Network.new()
	net.build()
	print("ROADNET construit en %.1f s : %d chaînes, %d chaînes d'artères, %d rubans, %d plateaux, %d raccords, %d tunnels, %d brèches de limite"
			% [(Time.get_ticks_msec() - t0) / 1000.0, net.chains.size(), net.arterial_chains.size(), net.ribbons.size(), net.pads.size(), net.connectors.size(), net.tunnels.size(), net.boundary_gaps.size()])
	for line in net.report:
		print("ROADNET " + line)
	for line in net.errors:
		print("ROADNET ERREUR " + line)
	print("ROADNET fortement connexe : %s | anneaux %d noeuds | cédez-le-passage %d | feux %d | grille %d | %d erreur(s)"
			% [net.strongly_connected(), net.g_roundabout.size(), net.g_yield.size(), net.g_lit.size(), net.g_grid.size(), net.errors.size()])
	for chain in net.chains:
		var h: PackedFloat32Array = chain["heights"]
		var lo := INF
		var hi := -INF
		for v in h:
			lo = minf(lo, v)
			hi = maxf(hi, v)
		print("ROADNET chaîne %s : %d noeuds %s, %.1f km, hauteur %.1f à %.1f m" % [chain["id"], (chain["nodes"] as Array).size(), chain["nodes"], Network.polyline_length(chain["points"]) / 1000.0, lo, hi])
	if out != "":
		_render(net, Rect2(Spec.TERRAIN.position, Spec.TERRAIN.size), 0.25, out.path_join("reseau_routes.png"))
		for node_id: String in CLOSE_UPS:
			var c := Spec.node_pos(node_id)
			var half := 450.0 if node_id.begins_with("x_") else 160.0
			_render(net, Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0), 900.0 / (half * 2.0), out.path_join("zoom_%s.png" % node_id))
	quit(0)


func _render(net, rect: Rect2, scale: float, path: String) -> void:
	var img := Image.create(int(rect.size.x * scale), int(rect.size.y * scale), false, Image.FORMAT_RGB8)
	img.fill(Color("dfe5d0"))
	var river := net.terrain.river_curve(8.0) as Array
	for entry: Array in river:
		_disc(img, rect, scale, entry[0], entry[1] * 0.5, Color("6ea5c3"))
	for pad: Dictionary in net.pads:
		var rim: PackedVector3Array = pad["rim"]
		var poly := PackedVector2Array()
		for p in rim:
			poly.append((Vector2(p.x, p.z) - rect.position) * scale)
		_fill_polygon(img, poly, COLORS["pad"])
	for kind in ["median", "sidewalk", "carriageway", "arterial", "ring", "ramp"]:
		for rb in net.ribbons:
			if rb.kind != kind or not rb.mesh:
				continue
			var color: Color = COLORS[rb.style] if kind == "arterial" else COLORS[kind]
			for p: Vector3 in rb.points:
				_disc(img, rect, scale, Vector2(p.x, p.z), rb.width * 0.5, color)
	for e in net.g_edges:
		var pts: PackedVector3Array = e["points"]
		for k in pts.size() - 1:
			var a := Vector2(pts[k].x, pts[k].z)
			var b := Vector2(pts[k + 1].x, pts[k + 1].z)
			var n := maxi(1, int(a.distance_to(b) * scale / 3.0))
			for s in n:
				_dot(img, rect, scale, a.lerp(b, float(s) / n), Color("1f4e8c") if e["one_way"] else Color("f1c40f"))
	for i in net.g_nodes.size():
		var p: Vector3 = net.g_nodes[i]
		var color := Color.BLACK
		if net.g_lit.has(i):
			color = Color.RED
		elif net.g_grid.has(i):
			color = Color.WHITE
		_disc(img, rect, scale, Vector2(p.x, p.z), 2.5 / scale, color)
	for c: Vector3 in net.conflicts:
		_disc(img, rect, scale, Vector2(c.x, c.z), 9.0 / scale, Color.MAGENTA)
	for rc: Dictionary in net.rail_crossings:
		_disc(img, rect, scale, rc["pos"], 5.0 / scale, Color("5a3a1a"))
	img.save_png(path)
	print("ROADNET_PREVIEW " + path)


func _fill_polygon(img: Image, poly: PackedVector2Array, color: Color) -> void:
	if poly.size() < 3:
		return
	var box := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		box = box.expand(p)
	for y in range(maxi(0, int(box.position.y)), mini(img.get_height(), int(box.end.y) + 1)):
		for x in range(maxi(0, int(box.position.x)), mini(img.get_width(), int(box.end.x) + 1)):
			if Geometry2D.is_point_in_polygon(Vector2(x, y), poly):
				img.set_pixel(x, y, color)


func _disc(img: Image, rect: Rect2, scale: float, p: Vector2, radius_m: float, color: Color) -> void:
	var c := Vector2i((p - rect.position) * scale)
	var r := maxi(0, int(radius_m * scale))
	if c.x + r < 0 or c.y + r < 0 or c.x - r >= img.get_width() or c.y - r >= img.get_height():
		return
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if x * x + y * y <= r * r:
				_dot_px(img, c.x + x, c.y + y, color)


func _dot(img: Image, rect: Rect2, scale: float, p: Vector2, color: Color) -> void:
	var c := Vector2i((p - rect.position) * scale)
	_dot_px(img, c.x, c.y, color)


func _dot_px(img: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, color)
