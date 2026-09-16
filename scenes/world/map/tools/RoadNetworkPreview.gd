extends SceneTree

# Contrôle du modèle de réseau routier (RoadNetwork) avant la cuisson : rapport (pentes, dégagements, graphe) et
# aperçus vus du dessus : carte entière et gros plans des échangeurs, rubans colorés par type, noeuds du graphe.
#
# Lancer : Godot --headless --path <projet> --script res://scenes/world/map/tools/RoadNetworkPreview.gd -- --out=<dossier>

const Spec := preload("res://scenes/world/map/MapSpec.gd")
const Network := preload("res://scenes/world/map/tools/RoadNetwork.gd")
const COLORS := {"carriageway": Color("d89b1d"), "median": Color("7a7a7a"), "ramp": Color("e06a2c"), "ring": Color("c0392b")}
const WIDTHS := {"carriageway": 10.7, "median": 3.0, "ramp": 7.0, "ring": 10.0}


func _initialize() -> void:
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	var t0 := Time.get_ticks_msec()
	var net := Network.new()
	net.build()
	print("ROADNET construit en %.1f s : %d chaînes, %d rubans, %d tunnels, %d brèches de limite, %d passages sur la voie ferrée"
			% [(Time.get_ticks_msec() - t0) / 1000.0, net.chains.size(), net.ribbons.size(), net.tunnels.size(), net.boundary_gaps.size(), net.rail_crossings.size()])
	for line in net.report:
		print("ROADNET " + line)
	for line in net.errors:
		print("ROADNET ERREUR " + line)
	print("ROADNET fortement connexe : %s | anneaux %d noeuds | cédez-le-passage %d | %d erreur(s)" % [net.strongly_connected(), net.g_roundabout.size(), net.g_yield.size(), net.errors.size()])
	for chain in net.chains:
		var h: PackedFloat32Array = chain["heights"]
		var lo := INF
		var hi := -INF
		for v in h:
			lo = minf(lo, v)
			hi = maxf(hi, v)
		print("ROADNET chaîne %s : %d noeuds %s, %.1f km, hauteur %.1f à %.1f m" % [chain["id"], (chain["nodes"] as Array).size(), chain["nodes"], Network.polyline_length(chain["points"]) / 1000.0, lo, hi])
	if out != "":
		_render(net, Rect2(Spec.TERRAIN.position, Spec.TERRAIN.size), 0.25, out.path_join("reseau_autoroutes.png"))
		for node_id in ["x_no", "x_ne", "x_st", "x_se"]:
			var c := Spec.node_pos(node_id)
			_render(net, Rect2(c - Vector2(450, 450), Vector2(900, 900)), 1.0, out.path_join("echangeur_%s.png" % node_id))
	quit(0)


func _render(net, rect: Rect2, scale: float, path: String) -> void:
	var img := Image.create(int(rect.size.x * scale), int(rect.size.y * scale), false, Image.FORMAT_RGB8)
	img.fill(Color("dfe5d0"))
	var river := net.terrain.river_curve(8.0) as Array
	for entry: Array in river:
		_disc(img, rect, scale, entry[0], entry[1] * 0.5, Color("6ea5c3"))
	for kind in ["median", "carriageway", "ring", "ramp"]:
		for rb in net.ribbons:
			if rb.kind != kind:
				continue
			for p: Vector3 in rb.points:
				_disc(img, rect, scale, Vector2(p.x, p.z), WIDTHS[kind] * 0.5, COLORS[kind])
	for p in net.g_nodes:
		_disc(img, rect, scale, Vector2(p.x, p.z), 3.0 / scale, Color.BLACK)
	for e in net.g_edges:
		var pts: PackedVector3Array = e["points"]
		for k in range(0, pts.size(), 3):
			_dot(img, rect, scale, Vector2(pts[k].x, pts[k].z), Color("1f4e8c"))
	for c: Vector3 in net.conflicts:
		_disc(img, rect, scale, Vector2(c.x, c.z), 9.0 / scale, Color.MAGENTA)
	for rc: Dictionary in net.rail_crossings:
		_disc(img, rect, scale, rc["pos"], 5.0 / scale, Color("5a3a1a"))
	img.save_png(path)
	print("ROADNET_PREVIEW " + path)


func _disc(img: Image, rect: Rect2, scale: float, p: Vector2, radius_m: float, color: Color) -> void:
	var c := Vector2i((p - rect.position) * scale)
	var r := maxi(0, int(radius_m * scale))
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
