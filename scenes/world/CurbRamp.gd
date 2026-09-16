extends Node3D

# Rampe de bordure.
#
# Les trottoirs de route (Roads/*Walk*) ont un dessus surélevé (~0.12 m au-dessus
# de la chaussée). Une BoxShape3D de CharacterBody3D (la voiture) ne franchit
# JAMAIS une face verticale via move_and_slide, aussi basse soit-elle -> d'où
# l'échec des deux tentatives raycast+nudge. On règle ça par la géométrie : le
# long de chaque bord long des trottoirs on ajoute un coin de collision en pente
# douce (ConvexPolygonShape3D). move_and_slide gère nativement les pentes sous
# floor_max_angle (45° par défaut), donc voiture ET joueur montent tout seuls,
# sans aucun code de détection.
#
# Généré au chargement à partir des dimensions réelles des trottoirs -> rien à
# maintenir à la main si la scène change. Collision uniquement : la pente est
# douce et masquée par le mesh de bordure existant, invisible en jeu.

const RAMP_RUN := 0.55        # avancée horizontale de la pente vers la chaussée (m)
const ROAD_TOP_Y := 0.05      # dessus des chaussées (toutes à y=-0.1, hauteur 0.3) dans World.tscn
const LIP := 0.02             # léger recouvrement haut/bas pour supprimer tout ressaut

func _ready() -> void:
	for child in get_parent().get_children():
		var body := child as StaticBody3D
		if body == null or not String(body.name).contains("Walk"):
			continue
		var cs := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		_build_ramps(body, (cs.shape as BoxShape3D).size)

func _build_ramps(body: StaticBody3D, size: Vector3) -> void:
	var along_x := size.x >= size.z                     # trottoir orienté selon X ?
	var half_long: float = (size.x if along_x else size.z) * 0.5
	var half_short: float = (size.z if along_x else size.x) * 0.5
	var top_local := size.y * 0.5                       # dessus du trottoir, repère du body
	var road_local := ROAD_TOP_Y - body.position.y      # niveau chaussée, repère du body

	var sides: Array[float] = [-1.0, 1.0]
	var ends: Array[float] = [-half_long, half_long]
	for s in sides:                                     # un coin par bord long
		var edge: float = s * half_short
		var pts := PackedVector3Array()
		for l in ends:
			# triangle : sommet au ras du dessus de trottoir, base au niveau
			# chaussée, pied avancé de RAMP_RUN dans la chaussée. Hypoténuse
			# sommet<->pied = surface de la rampe (~12°).
			if along_x:
				pts.push_back(Vector3(l, top_local + LIP, edge - s * LIP))
				pts.push_back(Vector3(l, road_local - LIP, edge))
				pts.push_back(Vector3(l, road_local - LIP, edge + s * RAMP_RUN))
			else:
				pts.push_back(Vector3(edge - s * LIP, top_local + LIP, l))
				pts.push_back(Vector3(edge, road_local - LIP, l))
				pts.push_back(Vector3(edge + s * RAMP_RUN, road_local - LIP, l))
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		var col := CollisionShape3D.new()
		col.name = "CurbRamp%s" % ("Pos" if s > 0.0 else "Neg")
		col.shape = shape
		body.add_child(col)
