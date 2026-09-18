extends SceneTree

# Audit temporaire des bretelles (2026-09-18), lecture seule :
#  - largeur réelle de la chaussée relevée sur les triangles du maillage cuit (enrobé), et position du trajet de
#    circulation dedans, sur les 90 premiers mètres depuis le museau ;
#  - profil en travers (enrobé + béton + terrain) à la station la plus serrée : hauteur de ce sur quoi roule la roue ;
#  - écart de hauteur entre la bretelle et la chaussée voisine, au mètre, et « genou » du raccord.
#
# Lancer : Godot --headless --path <projet> --script res://scenes/world/map/tools/RampAudit.gd

const Network := preload("res://scenes/world/map/tools/RoadNetwork.gd")
const ROADS := "res://scenes/world/map/generated/Roads.tscn"
const TERRAIN := "res://scenes/world/map/generated/Terrain.tscn"
const CELL := 8.0
const ROI := 48.0            # rayon autour d'une station : triangles chargés
const REACH := 40.0
const SURFACE_BAND := 0.45
const STATIONS := 90
const CAR_HALF := 0.9        # demi-largeur du collider de Car.tscn (BoxShape3D 1,8 x 1,2 x 4)

var asphalt := PackedVector3Array()
var solid := PackedVector3Array()
var a_buckets := {}
var s_buckets := {}
var roi := {}


func _init() -> void:
	var net := Network.new()
	net.build()
	var ramps: Array = []
	for rb in net.ribbons:
		if rb.kind == "ramp":
			ramps.append(rb)
	print("AUDIT_BUILD erreurs=%d rubans=%d bretelles=%d" % [net.errors.size(), net.ribbons.size(), ramps.size()])

	for rb in ramps:
		var arcs := _arcs(rb.points)
		var total: float = arcs[arcs.size() - 1]
		for d in range(0, STATIONS + 1, 4):
			var a: float = (total - float(d)) if rb.taper_at_end else float(d)
			if a < 0.0:
				continue
			var p := _at(rb.path, arcs, a)
			for x in range(floori((p.x - ROI) / CELL), floori((p.x + ROI) / CELL) + 1):
				for z in range(floori((p.z - ROI) / CELL), floori((p.z + ROI) / CELL) + 1):
					roi[Vector2i(x, z)] = true
	_load(ROADS, ["Asphalt"], asphalt, a_buckets)
	_load(ROADS, ["Asphalt", "Concrete"], solid, s_buckets)
	_load(TERRAIN, ["Mesh"], solid, s_buckets)
	print("AUDIT_MESH enrobe=%d tri, solide=%d tri" % [asphalt.size() / 3, solid.size() / 3])

	# --- largeur de chaussée sous le trajet -------------------------------------------------------------------------
	print("AUDIT_W_HEAD id;d_m;cote_biseau_m;autre_cote_m;largeur_continue_m;theorique_ruban_m")
	var worst_all := INF
	var worst_id := ""
	var worst_d := 0.0
	var worst_rb = null
	for rb in ramps:
		var arcs := _arcs(rb.points)
		var total: float = arcs[arcs.size() - 1]
		var mn := INF
		var mn_d := 0.0
		var lack_from := -1.0
		var lack_to := -1.0
		for d in range(0, STATIONS + 1):
			var dd := float(d)
			if dd > total - 1.0:
				break
			var a: float = (total - dd) if rb.taper_at_end else dd
			var p := _at(rb.path, arcs, a)
			var f := _dir_at(rb.path, arcs, a, rb.taper_at_end)
			var span := _cross_section(p, f)
			if span.is_empty():
				continue
			var lo: float = -float(span[0])
			var hi: float = float(span[1])
			var near: float = minf(lo, hi)
			var far: float = maxf(lo, hi)
			if near < mn:
				mn = near
				mn_d = dd
			if near < CAR_HALF:
				if lack_from < 0.0:
					lack_from = dd
				lack_to = dd
			if d <= 60 and d % 2 == 0:
				var factor := 1.0
				if rb.taper > 0.0:
					factor = clampf(dd / rb.taper, 0.06, 1.0)
				print("AUDIT_W %s;%.0f;%.2f;%.2f;%.2f;%.2f" % [rb.id, dd, near, far, lo + hi, rb.width * factor])
		var tip: Vector3 = rb.points[rb.points.size() - 1] if rb.taper_at_end else rb.points[0]
		print("AUDIT_WORST %s museau=(%.0f,%.1f,%.0f) mini=%.2f@%.0fm manque_de=%.0f_a=%.0fm (%.0f m)"
				% [rb.id, tip.x, tip.y, tip.z, mn, mn_d, lack_from, lack_to, maxf(0.0, lack_to - lack_from)])
		if mn < worst_all:
			worst_all = mn
			worst_id = rb.id
			worst_d = mn_d
			worst_rb = rb
	print("AUDIT_WORST_ALL %s %.2f m @ %.0f m du museau (demi-voiture %.2f m)" % [worst_id, worst_all, worst_d, CAR_HALF])

	# --- profil en travers à la station la plus serrée ---------------------------------------------------------------
	if worst_rb != null:
		var arcs := _arcs(worst_rb.points)
		var total: float = arcs[arcs.size() - 1]
		for st: float in [worst_d - 8.0, worst_d, worst_d + 8.0]:
			var a: float = (total - st) if worst_rb.taper_at_end else st
			var p := _at(worst_rb.path, arcs, a)
			var f := _dir_at(worst_rb.path, arcs, a, worst_rb.taper_at_end)
			var side := Vector3(-f.z, 0.0, f.x).normalized()
			var flip := 1.0
			var span := _cross_section(p, f)
			if not span.is_empty() and -float(span[0]) > float(span[1]):
				flip = 1.0
			else:
				flip = -1.0
			var row: Array = []
			for i in range(0, 25):
				var u := -2.0 + float(i) * 0.25
				var q := p + side * (u * flip)
				row.append("%.2f:%.2f" % [u, _top(q) - (p.y + Network.ROAD_TOP)])
			print("AUDIT_PROFIL %s @%.0fm (u = m vers le biseau, valeur = hauteur - surface) %s" % [worst_rb.id, st, " ".join(row)])

	# --- hauteurs ---------------------------------------------------------------------------------------------------
	print("AUDIT_H_HEAD id;dh_raccord;dh_max_accole;genou_m_par_m;profil")
	var worst_join := 0.0
	var worst_join_id := ""
	var worst_knee := 0.0
	var worst_knee_id := ""
	var worst_att := 0.0
	var worst_att_id := ""
	for rb in ramps:
		var arcs := _arcs(rb.points)
		var total: float = arcs[arcs.size() - 1]
		var cw = _nearest_carriageway(net, rb)
		if cw == null:
			print("AUDIT_H %s aucune chaussee voisine" % rb.id)
			continue
		var dh := PackedFloat32Array()
		for d in range(0, 61):
			var a: float = (total - float(d)) if rb.taper_at_end else float(d)
			if a < 0.0:
				dh.append(dh[dh.size() - 1])
				continue
			var p := _at(rb.points, arcs, a)
			var q := _nearest_point(cw.points, p)
			dh.append(p.y - q.y)
		# fin de la zone accolée : dernière station où l'enrobé est encore continu avec la chaussée
		var attached := 0
		for d in range(0, 61):
			var a: float = (total - float(d)) if rb.taper_at_end else float(d)
			if a < 0.0:
				break
			var p := _at(rb.path, arcs, a)
			var f := _dir_at(rb.path, arcs, a, rb.taper_at_end)
			var span := _cross_section(p, f)
			if not span.is_empty() and (float(span[1]) - float(span[0])) > 12.0:
				attached = d
		var knee := 0.0
		var knee_at := 0
		for d in range(1, mini(attached + 1, dh.size())):
			var step: float = absf(dh[d] - dh[d - 1])
			if step > knee:
				knee = step
				knee_at = d
		var line: Array = []
		for d in [0, 4, 8, 12, 16, 20, 24, 26, 28, 30, 34, 40, 48, 60]:
			if d < dh.size():
				line.append("%d:%.2f" % [d, dh[d]])
		print("AUDIT_H %s accole_jusqu_a=%dm dh_museau=%.3f dh_fin_accole=%.2f genou=%.2f m/m @%dm | %s"
				% [rb.id, attached, dh[0], dh[mini(attached, dh.size() - 1)], knee, knee_at, " ".join(line)])
		if absf(dh[0]) > absf(worst_join):
			worst_join = dh[0]
			worst_join_id = rb.id
		if absf(dh[mini(attached, dh.size() - 1)]) > absf(worst_att):
			worst_att = dh[mini(attached, dh.size() - 1)]
			worst_att_id = rb.id
		if knee > worst_knee:
			worst_knee = knee
			worst_knee_id = rb.id
	print("AUDIT_H_WORST museau %.3f m (%s) | fin de zone accolee %.2f m (%s) | genou %.2f m/m (%s)"
			% [worst_join, worst_join_id, worst_att, worst_att_id, worst_knee, worst_knee_id])
	quit()


func _load(path: String, names: Array, into: PackedVector3Array, buckets: Dictionary) -> void:
	var scene: PackedScene = load(path)
	var root := scene.instantiate()
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for c in node.get_children():
			stack.append(c)
		if not (node is MeshInstance3D) or not names.has(String(node.name)):
			continue
		var mi := node as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var walk: Node = mi
		while walk != null and walk != root:
			if walk is Node3D:
				xf = (walk as Node3D).transform * xf
			walk = walk.get_parent()
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var arr: Array = mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for i in range(0, idx.size(), 3):
				var a := xf * verts[idx[i]]
				var b := xf * verts[idx[i + 1]]
				var c := xf * verts[idx[i + 2]]
				var mid := (a + b + c) / 3.0
				if not roi.has(Vector2i(floori(mid.x / CELL), floori(mid.z / CELL))):
					continue
				var t := into.size() / 3
				into.append(a)
				into.append(b)
				into.append(c)
				var x0 := floori(minf(a.x, minf(b.x, c.x)) / CELL)
				var x1 := floori(maxf(a.x, maxf(b.x, c.x)) / CELL)
				var z0 := floori(minf(a.z, minf(b.z, c.z)) / CELL)
				var z1 := floori(maxf(a.z, maxf(b.z, c.z)) / CELL)
				for x in range(x0, x1 + 1):
					for z in range(z0, z1 + 1):
						var k := Vector2i(x, z)
						if not buckets.has(k):
							buckets[k] = PackedInt32Array()
						var lst: PackedInt32Array = buckets[k]
						lst.append(t)
						buckets[k] = lst
	root.free()


# Hauteur de la face solide la plus haute sous / au niveau de q (enrobé, béton, terrain).
func _top(q: Vector3) -> float:
	var best := -1e9
	for t: int in s_buckets.get(Vector2i(floori(q.x / CELL), floori(q.z / CELL)), PackedInt32Array()):
		var a := solid[t * 3]
		var b := solid[t * 3 + 1]
		var c := solid[t * 3 + 2]
		var y := _bary_y(a, b, c, q)
		if y != -1e9 and y > best and y <= q.y + 1.0:
			best = y
	return best


func _bary_y(a: Vector3, b: Vector3, c: Vector3, q: Vector3) -> float:
	var v0 := Vector2(c.x - a.x, c.z - a.z)
	var v1 := Vector2(b.x - a.x, b.z - a.z)
	var v2 := Vector2(q.x - a.x, q.z - a.z)
	var d00 := v0.dot(v0)
	var d01 := v0.dot(v1)
	var d11 := v1.dot(v1)
	var den := d00 * d11 - d01 * d01
	if absf(den) < 1e-9:
		return -1e9
	var d20 := v2.dot(v0)
	var d21 := v2.dot(v1)
	var u := (d11 * d20 - d01 * d21) / den
	var v := (d00 * d21 - d01 * d20) / den
	if u < -0.001 or v < -0.001 or u + v > 1.001:
		return -1e9
	return a.y + u * (c.y - a.y) + v * (b.y - a.y)


func _cross_section(p: Vector3, f: Vector3) -> Array:
	var side := Vector3(-f.z, 0.0, f.x).normalized()
	var level: float = p.y + Network.ROAD_TOP
	var seen := {}
	var pieces: Array = []
	var cells := {}
	for m in range(-int(REACH), int(REACH) + 1, 4):
		var q := p + side * float(m)
		cells[Vector2i(floori(q.x / CELL), floori(q.z / CELL))] = true
	for k in cells:
		for t: int in a_buckets.get(k, PackedInt32Array()):
			if seen.has(t):
				continue
			seen[t] = true
			var seg := _cut(asphalt[t * 3], asphalt[t * 3 + 1], asphalt[t * 3 + 2], p, f)
			if seg.is_empty():
				continue
			var p0: Vector3 = seg[0]
			var p1: Vector3 = seg[1]
			if absf(p0.y - level) > SURFACE_BAND or absf(p1.y - level) > SURFACE_BAND:
				continue
			var u0: float = (p0 - p).dot(side)
			var u1: float = (p1 - p).dot(side)
			pieces.append([minf(u0, u1), maxf(u0, u1)])
	if pieces.is_empty():
		return []
	pieces.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var lo := INF
	var hi := -INF
	var cur_lo: float = pieces[0][0]
	var cur_hi: float = pieces[0][1]
	for i in range(1, pieces.size()):
		if float(pieces[i][0]) <= cur_hi + 0.05:
			cur_hi = maxf(cur_hi, float(pieces[i][1]))
		else:
			if cur_lo <= 0.0 and cur_hi >= 0.0:
				lo = cur_lo
				hi = cur_hi
			cur_lo = pieces[i][0]
			cur_hi = pieces[i][1]
	if cur_lo <= 0.0 and cur_hi >= 0.0:
		lo = cur_lo
		hi = cur_hi
	if lo == INF:
		return []
	return [lo, hi]


func _cut(a: Vector3, b: Vector3, c: Vector3, p: Vector3, f: Vector3) -> Array:
	var da := (a - p).dot(f)
	var db := (b - p).dot(f)
	var dc := (c - p).dot(f)
	var out: Array = []
	for pair in [[a, da, b, db], [b, db, c, dc], [c, dc, a, da]]:
		var d0: float = pair[1]
		var d1: float = pair[3]
		if (d0 < 0.0) == (d1 < 0.0):
			continue
		var t: float = d0 / (d0 - d1)
		out.append((pair[0] as Vector3).lerp(pair[2] as Vector3, t))
	if out.size() < 2:
		return []
	return [out[0], out[1]]


func _arcs(pts: PackedVector3Array) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.0])
	for k in range(1, pts.size()):
		out.append(out[k - 1] + Vector2(pts[k].x - pts[k - 1].x, pts[k].z - pts[k - 1].z).length())
	return out


func _at(pts: PackedVector3Array, arcs: PackedFloat32Array, a: float) -> Vector3:
	for k in range(1, pts.size()):
		if arcs[k] >= a:
			var t: float = (a - arcs[k - 1]) / maxf(arcs[k] - arcs[k - 1], 0.0001)
			return pts[k - 1].lerp(pts[k], t)
	return pts[pts.size() - 1]


func _dir_at(pts: PackedVector3Array, arcs: PackedFloat32Array, a: float, at_end: bool) -> Vector3:
	var p0 := _at(pts, arcs, maxf(0.0, a - 2.0))
	var p1 := _at(pts, arcs, minf(arcs[arcs.size() - 1], a + 2.0))
	var d := Vector3(p1.x - p0.x, 0.0, p1.z - p0.z).normalized()
	return -d if at_end else d


func _nearest_point(pts: PackedVector3Array, p: Vector3) -> Vector3:
	var best := pts[0]
	var bd := INF
	for k in range(pts.size() - 1):
		var q := Geometry3D.get_closest_point_to_segment(Vector3(p.x, pts[k].y, p.z), pts[k], pts[k + 1])
		var d := Vector2(q.x - p.x, q.z - p.z).length_squared()
		if d < bd:
			bd = d
			best = q
	return best


func _nearest_carriageway(net, rb):
	var tip: Vector3 = rb.points[rb.points.size() - 1] if rb.taper_at_end else rb.points[0]
	var best = null
	var bd := INF
	for other in net.ribbons:
		if other.kind != "carriageway" or other.chain != rb.chain:
			continue
		var q := _nearest_point(other.points, tip)
		var d := Vector2(q.x - tip.x, q.z - tip.z).length()
		if d < bd:
			bd = d
			best = other
	return best if bd < 30.0 else null
