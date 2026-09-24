extends RefCounted

# LE JOUEUR AU CLAVIER, pour les tests et les vidéos de la conduite (2026-09-24, CLAUDE.md §15). Depuis que le châssis ne
# braque plus jamais les roues à la place du joueur (« c'est MOI qui contre-braque »), c'est à lui de rattraper une glisse
# et de suivre sa voie : un test qui le prouve doit le faire comme un joueur, en pressant les touches du jeu.
#
# Il ne rend QUE des touches (gauche, droite) ; l'appelant les presse (Input.action_press), avec les gaz, le frein et le
# frein à main qu'il décide. Il voit la voiture avec un temps de réaction (DELAI), anticipe à moitié ce qu'il voit bouger
# (ANTICIPE), et tapote la touche qui rapproche le volant de ce qu'il vise ; dans une bande de tolérance (BANDE), il lâche,
# et le volant revient vers le centre, comme au clavier. Pour CONTRE-BRAQUER (contre_braquer), il vise les roues avant dans
# la direction où va l'avant de la voiture (le pneu avant ne glisse plus), moins un peu du lacet qu'il voit (K_LACET) : il
# relâche le contre-braquage quand la voiture revient.
# Réglé sur une sonde des 72 modèles (hors dépôt, 2026-09-24) : avec ce joueur, chaque dérapage au frein à main à 50, 80 et
# 110 km/h (Espace lâché à 15° de dérive) se rattrape en 2,4 s au plus.

const DELAI := 0.15        # s : temps de réaction
const ANTICIPE := 0.5      # part du mouvement vu qu'il prolonge sur son temps de réaction
const K_LACET := 0.2       # s : contre-braquage retiré par rad/s de lacet (il relâche quand la voiture revient)
const BANDE := 0.15        # volant : écart toléré avant de retoucher une touche
const PAS_MEMOIRE := 60    # pas physiques gardés en mémoire (1 s)

var _hist: Array = []      # [t, trajectoire de l'avant (rad, + à gauche), lacet (rad/s, + à gauche)]


# À appeler une fois par pas physique : ce que le joueur voit.
func observer(ch: RigidBody3D, t: float) -> void:
	var xf := ch.global_transform
	var inv := xf.basis.inverse()
	var cdg := xf * ch.center_of_mass
	var p_av: Vector3 = xf * Vector3(0.0, 0.3, float(ch.get("AckermannPoint")) + float(ch.get("empattement")))
	var v_av: Vector3 = ch.linear_velocity + ch.angular_velocity.cross(p_av - cdg)
	var l: Vector3 = inv * v_av
	_hist.append([t, atan2(l.x, maxf(absf(l.z), 0.5)), (inv * ch.angular_velocity).y])
	while _hist.size() > PAS_MEMOIRE:
		_hist.pop_front()


func oublier() -> void:
	_hist.clear()


# Dérive au centre de gravité, en degrés (+ : la vitesse file à gauche de l'axe) : l'angle entre où va la voiture et où
# elle pointe. Au-dessous de 3 m/s, 0 (une voiture presque arrêtée qui pivote a une vitesse de n'importe quel sens).
static func derive(ch: RigidBody3D) -> float:
	var vh := ch.linear_velocity
	vh.y = 0.0
	if vh.length() < 3.0:
		return 0.0
	var lv: Vector3 = ch.global_transform.basis.inverse() * ch.linear_velocity
	return rad_to_deg(atan2(lv.x, maxf(absf(lv.z), 0.5)))


# CONTRE-BRAQUER : la touche à presser (-1 gauche, 1 droite, 0 aucune).
func contre_braquer(ch: RigidBody3D, t: float) -> int:
	var vu := _vu(t)
	var avant := _vu(t - 0.05)
	var dt := maxf(float(vu[0]) - float(avant[0]), 0.001)
	var traj := float(vu[1]) + (float(vu[1]) - float(avant[1])) / dt * DELAI * ANTICIPE
	var lacet := float(vu[2]) + (float(vu[2]) - float(avant[2])) / dt * DELAI * ANTICIPE
	return viser(ch, traj - K_LACET * lacet)


# La touche qui rapproche le volant de l'angle de braquage visé (rad, + à gauche), hors d'une bande de tolérance.
func viser(ch: RigidBody3D, braquage: float) -> int:
	var s_vise := clampf(-braquage / maxf(float(ch.get("braquage_max")), 0.01), -1.0, 1.0)     # volant visé (+ à droite)
	var s := float(ch.get("steer2"))
	if s < s_vise - BANDE:
		return 1
	if s > s_vise + BANDE:
		return -1
	# dans la bande : il garde la touche tant que le volant n'est pas encore allé aussi loin que visé
	if absf(s_vise) > 0.3 and signf(s_vise) == signf(s) and absf(s) < absf(s_vise):
		return int(signf(s_vise))
	return 0


func _vu(t: float) -> Array:
	if _hist.is_empty():
		return [t, 0.0, 0.0]
	var vu: Array = _hist[0]
	for h: Array in _hist:
		if float(h[0]) <= t - DELAI:
			vu = h
	return vu
