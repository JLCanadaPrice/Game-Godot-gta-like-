extends SceneTree

# Outil temporaire (2026-09-18) : coordonnées du trajet des bretelles, pour placer les caméras au sol et les essais
# roulés. Lecture seule.
#
# Lancer : Godot --headless --path <projet> --script res://scenes/world/map/tools/RampPoints.gd -- <id> [<id> ...]

const Network := preload("res://scenes/world/map/tools/RoadNetwork.gd")


func _init() -> void:
	var wanted := PackedStringArray(OS.get_cmdline_user_args())
	var net := Network.new()
	net.build()
	var seen := {}
	for rb in net.ribbons:
		if rb.kind != "ramp":
			continue
		if wanted.size() > 0 and not wanted.has(rb.id):
			continue
		var n := 0
		if seen.has(rb.id):
			n = int(seen[rb.id]) + 1
		seen[rb.id] = n
		var arcs := PackedFloat32Array([0.0])
		for k in range(1, rb.points.size()):
			arcs.append(arcs[k - 1] + Vector2(rb.points[k].x - rb.points[k - 1].x, rb.points[k].z - rb.points[k - 1].z).length())
		var total: float = arcs[arcs.size() - 1]
		var row: Array = []
		for d: float in [0.0, 10.0, 20.0, 30.0, 36.0, 45.0, 60.0, 80.0, 110.0]:
			if d > total:
				continue
			var a: float = (total - d) if rb.taper_at_end else d
			var p := _at(rb.path, arcs, a)
			row.append("d%.0f=(%.1f,%.2f,%.1f)" % [d, p.x, p.y, p.z])
		print("RAMP %s#%d long=%.0f biseau_a_la_fin=%s | %s" % [rb.id, n, total, rb.taper_at_end, " ".join(row)])
	quit()


func _at(pts: PackedVector3Array, arcs: PackedFloat32Array, a: float) -> Vector3:
	for k in range(1, pts.size()):
		if arcs[k] >= a:
			var t: float = (a - arcs[k - 1]) / maxf(arcs[k] - arcs[k - 1], 0.0001)
			return pts[k - 1].lerp(pts[k], t)
	return pts[pts.size() - 1]
