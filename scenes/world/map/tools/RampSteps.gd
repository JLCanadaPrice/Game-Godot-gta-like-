extends SceneTree

# Outil temporaire (2026-09-18) : marches verticales sur les trajets de bretelle. Pour chaque ruban "ramp" et pour
# chaque arête du graphe qui en vient, pente locale de chaque segment, écart entre les deux bouts du ruban et la
# surface qu'il rejoint (chaussée d'autoroute côté museau, anneau / plateau côté échangeur). Lecture seule.
#
# Lancer : Godot --headless --path <projet> --script res://scenes/world/map/tools/RampSteps.gd

const Network := preload("res://scenes/world/map/tools/RoadNetwork.gd")


func _init() -> void:
	var net := Network.new()
	net.build()
	var ramps: Array = []
	for rb in net.ribbons:
		if rb.kind == "ramp":
			ramps.append(rb)
	print("STEPS_BUILD bretelles=%d aretes=%d" % [ramps.size(), net.g_edges.size()])

	# --- pente locale le long du trajet de chaque bretelle --------------------------------------------------------
	var worst := 0.0
	var worst_id := ""
	var worst_at := ""
	var over := 0
	for rb in ramps:
		var mx := 0.0
		var mx_at := 0.0
		var run := 0.0
		for k in range(rb.path.size() - 1):
			var a: Vector3 = rb.path[k]
			var b: Vector3 = rb.path[k + 1]
			var l: float = Vector2(b.x - a.x, b.z - a.z).length()
			run += l
			if l < 0.05:
				continue
			var slope: float = absf(b.y - a.y) / l
			if slope > mx:
				mx = slope
				mx_at = run
		if mx > 0.12:
			over += 1
		if mx > worst:
			worst = mx
			worst_id = rb.id
			worst_at = "%.0f m du depart du ruban" % mx_at
		print("STEPS_RAMP %s pente_locale_max=%.1f%% @%.0fm (limite modele %.1f%%)" % [rb.id, mx * 100.0, mx_at, Network.GRADE_LIMIT["ramp"] * 100.0])
	print("STEPS_SLOPE_WORST %s %.1f%% (%s) | %d bretelles au-dessus de 12%%" % [worst_id, worst * 100.0, worst_at, over])

	# --- bouts : écart avec la surface rejointe --------------------------------------------------------------------
	var worst_end := 0.0
	var worst_end_id := ""
	for rb in ramps:
		var a0: Vector3 = rb.path[0]
		var a1: Vector3 = rb.path[rb.path.size() - 1]
		var best0 := _closest_other(net, rb, a0)
		var best1 := _closest_other(net, rb, a1)
		print("STEPS_ENDS %s bout0 %s | bout1 %s" % [rb.id, best0, best1])
		for s: String in [best0, best1]:
			var parts := s.split("dy=")
			if parts.size() > 1:
				var v := absf(float(parts[1].split(" ")[0]))
				if v > worst_end:
					worst_end = v
					worst_end_id = rb.id
	print("STEPS_ENDS_WORST %s %.3f m" % [worst_end_id, worst_end])

	# --- arêtes du graphe issues d'une bretelle : marche entre deux points consécutifs ------------------------------
	var gw := 0.0
	var gw_txt := ""
	for e: Dictionary in net.g_edges:
		var pts: PackedVector3Array = e["points"]
		for k in range(pts.size() - 1):
			var l: float = Vector2(pts[k + 1].x - pts[k].x, pts[k + 1].z - pts[k].z).length()
			var dy: float = absf(pts[k + 1].y - pts[k].y)
			if l < 0.6 and dy > gw:
				gw = dy
				gw_txt = "(%.1f,%.2f,%.1f) -> (%.1f,%.2f,%.1f) sur %.2f m" % [pts[k].x, pts[k].y, pts[k].z, pts[k + 1].x, pts[k + 1].y, pts[k + 1].z, l]
	print("STEPS_GRAPH_SHORTSEG marche max sur un segment de moins de 0,6 m : %.3f m %s" % [gw, gw_txt])
	quit()


func _closest_other(net, rb, p: Vector3) -> String:
	var best := ""
	var bd := INF
	for other in net.ribbons:
		if other == rb or other.path.is_empty():
			continue
		for k in range(other.path.size() - 1):
			var q := Geometry3D.get_closest_point_to_segment(Vector3(p.x, other.path[k].y, p.z), other.path[k], other.path[k + 1])
			var d := Vector2(q.x - p.x, q.z - p.z).length()
			if d < bd:
				bd = d
				best = "%s a %.2f m, dy=%.3f m" % [other.id, d, p.y - q.y]
	return best if bd < 6.0 else "rien a moins de 6 m"
