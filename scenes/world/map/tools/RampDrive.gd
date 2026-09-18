extends SceneTree

# Essai roulé des raccords de bretelle (chantier des routes, 2026-09-18), lecture seule : une voiture est conduite sur
# le trajet d'une bretelle, du museau jusqu'au-delà du raccord, et à chaque tick on relève
#  - l'appui sous les 4 coins de la caisse : un rayon descendant doit trouver du solide à ±SUPPORT m du coin ;
#  - le saut vertical de la caisse d'un tick à l'autre (marche franchie) ;
#  - la hauteur de roulement par rapport au trajet théorique.
# La voiture est posée sur le trajet et avancée à vitesse constante (pas de pilote IA) : on teste la surface, pas la
# conduite. Rien n'est écrit sur la carte.
#
# Lancer : Godot --headless --path <projet> --script res://scenes/world/map/tools/RampDrive.gd -- <id> [<id> ...]

const Network := preload("res://scenes/world/map/tools/RoadNetwork.gd")
const MAP := preload("res://scenes/world/map/Map.tscn")
const HALF_W := 0.9                 # demi-largeur de la caisse de Car.tscn (BoxShape3D 1,8 x 1,2 x 4)
const HALF_L := 2.0
const SUPPORT := 0.25               # m : tolérance d'appui sous un coin
const JUMP := 0.08                  # m : saut vertical d'un tick à l'autre au-delà duquel on signale
const SPEED := 14.0                 # m/s (50 km/h, vitesse d'insertion)
const TICK := 0.05                  # s entre deux relevés
const RANGE := 130.0                # m parcourus depuis le museau


func _init() -> void:
	var wanted := PackedStringArray(OS.get_cmdline_user_args())
	var map: Node3D = MAP.instantiate()
	root.add_child(map)
	await process_frame
	await physics_frame
	var space := root.get_world_3d().direct_space_state
	var net := Network.new()
	net.build()
	var worst_gap := 0.0
	var worst_jump := 0.0
	var failures := 0
	var driven := 0
	for rb in net.ribbons:
		if rb.kind != "ramp" or (wanted.size() > 0 and not wanted.has(rb.id)):
			continue
		driven += 1
		var arcs := PackedFloat32Array([0.0])
		for k in range(1, rb.path.size()):
			arcs.append(arcs[k - 1] + Vector2(rb.path[k].x - rb.path[k - 1].x, rb.path[k].z - rb.path[k - 1].z).length())
		var total: float = arcs[arcs.size() - 1]
		var gap_max := 0.0
		var gap_at := 0.0
		var jump_max := 0.0
		var jump_at := 0.0
		var last_y := INF
		var steps := int(RANGE / (SPEED * TICK))
		for i in steps:
			var d: float = float(i) * SPEED * TICK
			if d > total:
				break
			var a: float = (total - d) if rb.taper_at_end else d
			var p := _at(rb.path, arcs, a)
			var f := _dir(rb.path, arcs, a, rb.taper_at_end)
			var r := Vector3(f.z, 0.0, -f.x)
			var ground := _drop(space, p + Vector3.UP * 1.0)
			if ground.is_empty():
				failures += 1
				print("DRIVE_HOLE %s a %.0f m du museau : rien sous le trajet" % [rb.id, d])
				continue
			var y: float = ground["position"].y
			if last_y < INF and absf(y - last_y) > JUMP:
				if absf(y - last_y) > jump_max:
					jump_max = absf(y - last_y)
					jump_at = d
			last_y = y
			for corner: Vector3 in [p + f * HALF_L + r * HALF_W, p + f * HALF_L - r * HALF_W, p - f * HALF_L + r * HALF_W, p - f * HALF_L - r * HALF_W]:
				var c := _drop(space, corner + Vector3.UP * 1.0)
				if c.is_empty():
					failures += 1
					print("DRIVE_CORNER %s a %.0f m du museau : coin sans appui (%.1f,%.1f)" % [rb.id, d, corner.x, corner.z])
					continue
				var gap: float = absf(float(c["position"].y) - y)
				if gap > gap_max:
					gap_max = gap
					gap_at = d
		if gap_max > SUPPORT:
			failures += 1
		if jump_max > JUMP:
			failures += 1
		worst_gap = maxf(worst_gap, gap_max)
		worst_jump = maxf(worst_jump, jump_max)
		print("DRIVE %s appui des coins : ecart max %.3f m @%.0f m (limite %.2f) | saut vertical max %.3f m @%.0f m (limite %.2f)"
				% [rb.id, gap_max, gap_at, SUPPORT, jump_max, jump_at, JUMP])
	print("DRIVE_RESULT %s | %d bretelles roulees, ecart d'appui max %.3f m, saut max %.3f m, %d anomalies"
			% ["OK" if failures == 0 else "ECHEC", driven, worst_gap, worst_jump, failures])
	quit(0 if failures == 0 else 1)


func _drop(space: PhysicsDirectSpaceState3D, from: Vector3) -> Dictionary:
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0))


func _at(pts: PackedVector3Array, arcs: PackedFloat32Array, a: float) -> Vector3:
	for k in range(1, pts.size()):
		if arcs[k] >= a:
			var t: float = (a - arcs[k - 1]) / maxf(arcs[k] - arcs[k - 1], 0.0001)
			return pts[k - 1].lerp(pts[k], t)
	return pts[pts.size() - 1]


func _dir(pts: PackedVector3Array, arcs: PackedFloat32Array, a: float, reversed: bool) -> Vector3:
	var p0 := _at(pts, arcs, maxf(a - 1.0, 0.0))
	var p1 := _at(pts, arcs, minf(a + 1.0, arcs[arcs.size() - 1]))
	var d := (p1 - p0)
	d.y = 0.0
	if d.length() < 0.001:
		d = Vector3.FORWARD
	return (-d if reversed else d).normalized()
