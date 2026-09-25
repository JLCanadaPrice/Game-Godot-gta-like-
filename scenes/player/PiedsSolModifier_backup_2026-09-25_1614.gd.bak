extends SkeletonModifier3D
class_name PiedsSolModifier

# LES PIEDS SUIVENT LE SOL (2026-09-25, CLAUDE.md §16). Les animations sont faites pour un sol plat : sur une pente, un
# trottoir ou une rampe, le pied posé en avant s'enfonçait et celui de derrière flottait — mesuré sur le vrai joueur,
# semelle pendant l'appui de -3 à +10 cm sur une pente de 10°, de -6 à +20 cm sur 20°. Le joueur (Player) mesure le sol
# sous chaque pied (un rayon vertical par image physique) et donne ici, pour chaque pied, de combien le sol y est
# plus haut (+) ou plus bas (-) que sous le corps. Le modificateur, après l'animation :
#  1. descend le BASSIN du plus grand creux (la jambe du côté bas ne pourrait pas s'allonger jusqu'au sol) ;
#  2. déplace chaque PIED de son écart, en gardant sa levée d'animation (le pied en l'air suit aussi le terrain), et
#     l'incline sur la pente quand il est posé ;
#  3. replie la JAMBE sur ce pied (IK analytique à deux os : cuisse 0,43 m, tibia 0,51 m, genou gardé dans le plan de
#     l'animation, donc vers l'avant). Dans ce squelette Quaternius, le pied est enfant de Root, pas du tibia : sans ce
#     troisième temps, la chaussure se détacherait du tibia.
# Sur sol plat les écarts sont nuls et la pose de l'animation ressort telle quelle.
# Même garde qu'ailleurs contre les passages multiples dans une image (cf. JumpPoseModifier, PoseTirModifier) : on
# repart de la pose de l'animation relevée au premier passage.

@export_range(0.0, 1.0) var poids := 0.0        # 0 : l'animation seule (en l'air, en voiture...) ; 1 : pieds au sol
var ecarts := [0.0, 0.0]                        # m, dans le monde : sol sous le pied gauche, droit, moins sol sous le corps
var normales := [Vector3.UP, Vector3.UP]        # normale du sol sous chaque pied, dans le monde
var sols_pointe := [-INF, -INF]                # m, dans le monde : hauteur du sol sous la pointe de chaque chaussure (-INF : rien)
var pieds_monde := [Vector3.ZERO, Vector3.ZERO] # sortie : pieds de l'ANIMATION dans le monde, où le joueur mesure le sol
var pointes_monde := [Vector3.ZERO, Vector3.ZERO] # sortie : pointes des chaussures de l'ANIMATION, dans le monde

const LEVEE_POSE := 0.05      # m : jusque-là au-dessus du sol d'animation, le pied est posé (incliné sur la pente)
const LEVEE_LIBRE := 0.20     # m : au-delà, il est en l'air (plus incliné)
const POINTE_ANGLE_MAX := 0.7 # rad (40°) : pied relevé au plus de ça pour sortir la pointe d'une marche

var _bassin := -1
var _cuisses := PackedInt32Array()
var _tibias := PackedInt32Array()
var _pieds := PackedInt32Array()
var _rot_base := {}           # os -> rotation locale de l'ANIMATION (premier passage de l'image)
var _pos_base := {}           # os -> position locale de l'ANIMATION
var _rot_ecrite := {}
var _pos_ecrite := {}
var _image := -1
var _pointe_locale := [Vector3.ZERO, Vector3.ZERO]   # bout de la chaussure dans le repère de l'os du pied (preparer_pointes)


func _ready() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	_bassin = sk.find_bone("Hips")
	for cote: String in ["Left", "Right"]:
		_cuisses.append(sk.find_bone(cote + "UpperLeg"))
		_tibias.append(sk.find_bone(cote + "LowerLeg"))
		_pieds.append(sk.find_bone(cote + "Foot"))


# Bout de chaque chaussure, relevé sur le maillage des chaussures (`chaussures`, peau du squelette) : parmi les sommets
# portés par l'os du pied et à 3 cm de la semelle au repos, le plus loin de l'os — à 0,226 m, pour les deux pieds.
# Pas « 15 cm devant » : au repos, le pied gauche de ce squelette pointe presque sur le côté (+X), le droit vers +Z.
func preparer_pointes(chaussures: MeshInstance3D) -> void:
	var sk := get_skeleton()
	if sk == null or chaussures == null or chaussures.skin == null or _pieds.has(-1):
		return
	var arr := chaussures.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var we: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	if bo.is_empty():
		return
	var par := bo.size() / v.size()
	for i in 2:
		var repos := sk.get_bone_global_rest(_pieds[i])
		var locaux := PackedVector3Array()
		for s in v.size():
			var best := 0
			for k in par:
				if we[s * par + k] > we[s * par + best]:
					best = k
			var bind := bo[s * par + best]
			if sk.find_bone(String(chaussures.skin.get_bind_name(bind))) == _pieds[i]:
				locaux.append(chaussures.skin.get_bind_pose(bind) * v[s])
		var bas := INF
		for l in locaux:
			bas = minf(bas, (repos * l).y)
		for l in locaux:
			if (repos * l).y <= bas + 0.03 and l.length() > (_pointe_locale[i] as Vector3).length():
				_pointe_locale[i] = l


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or _bassin < 0 or _pieds.has(-1) or _tibias.has(-1) or _cuisses.has(-1):
		return
	_repartir_de_l_animation(sk)
	var vers_sk := sk.global_transform.affine_inverse()
	var haut := (vers_sk.basis * Vector3.UP)          # un mètre vertical du monde, dans le repère du squelette
	for i in 2:
		var pied_anim := sk.get_bone_global_pose(_pieds[i])
		pieds_monde[i] = sk.global_transform * pied_anim.origin
		pointes_monde[i] = sk.global_transform * (pied_anim * (_pointe_locale[i] as Vector3))
	if poids <= 0.001:
		return
	# 1. le bassin descend du plus grand creux
	var creux := minf(minf(float(ecarts[0]), float(ecarts[1])), 0.0) * poids
	var cheville := []                                  # cheville (origine du pied) vue du tibia, dans l'animation
	var cible := []                                     # où va chaque pied, repère du squelette
	for i in 2:
		var pied := sk.get_bone_global_pose(_pieds[i])
		cheville.append(sk.get_bone_global_pose(_tibias[i]).affine_inverse() * pied.origin)
		cible.append(pied.origin + haut * float(ecarts[i]) * poids)
	if creux < 0.0:
		var parent := sk.get_bone_global_pose(sk.get_bone_parent(_bassin))
		sk.set_bone_pose_position(_bassin, sk.get_bone_pose_position(_bassin) + parent.basis.inverse() * (haut * creux))
	for i in 2:
		_plier(sk, i, cheville[i], cible[i])
		_poser_pied(sk, i, cible[i], vers_sk.basis * (normales[i] as Vector3), haut)
		_sortir_la_pointe(sk, i, vers_sk, haut)
	_memoriser(sk)


# 3. Jambe `i` repliée pour que le bout du tibia (la cheville) atteigne `t`, genou dans le plan de l'animation.
func _plier(sk: Skeleton3D, i: int, cheville: Vector3, t: Vector3) -> void:
	var h := sk.get_bone_global_pose(_cuisses[i]).origin
	var tibia := sk.get_bone_global_pose(_tibias[i])
	var k := tibia.origin
	var e := tibia * cheville
	var l1 := h.distance_to(k)
	var l2 := k.distance_to(e)
	var d := clampf(h.distance_to(t), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var angle_voulu := acos(clampf((l1 * l1 + l2 * l2 - d * d) / (2.0 * l1 * l2), -1.0, 1.0))
	var angle := (h - k).angle_to(e - k)
	var axe := (h - k).cross(e - k)
	if axe.length() > 0.0001 and absf(angle_voulu - angle) > 0.0001:
		_tourner(sk, _tibias[i], Quaternion(axe.normalized(), angle_voulu - angle))
	e = sk.get_bone_global_pose(_tibias[i]) * cheville
	var de := e - h
	var dt := t - h
	if de.length() > 0.0001 and dt.length() > 0.0001:
		var q := Quaternion(de.normalized(), dt.normalized())
		if q.get_angle() > 0.0001:
			_tourner(sk, _cuisses[i], q)


# 2. Pied `i` posé en `t` ; incliné sur la pente (normale `n`, repère du squelette) tant qu'il est posé.
func _poser_pied(sk: Skeleton3D, i: int, t: Vector3, n: Vector3, haut: Vector3) -> void:
	var p := _pieds[i]
	var parent := sk.get_bone_global_pose(sk.get_bone_parent(p))
	sk.set_bone_pose_position(p, parent.affine_inverse() * t)
	# levée d'animation du pied : sa hauteur au-dessus du sol plat de l'animation (origine du squelette), en mètres
	var levee := _levee(sk, i, haut)
	var pose := clampf(1.0 - (levee - LEVEE_POSE) / (LEVEE_LIBRE - LEVEE_POSE), 0.0, 1.0) * poids
	if pose <= 0.001 or n.length() < 0.001:
		return
	var q := Quaternion(haut.normalized(), n.normalized())
	q = Quaternion.IDENTITY.slerp(q, pose)
	_tourner(sk, p, q)


# 4. La pointe de la chaussure ne descend pas sous le sol mesuré sous elle. Posé juste devant une bordure, le pied roule
# sur sa pointe en fin d'appui, et la pointe, passée au-dessus de la bordure, y entrait (mesuré : 14,5 cm pendant
# 5 images, à chaque bordure). Le pied pivote alors à la cheville pour la relever, POINTE_ANGLE_MAX au plus. Sur une
# pente, le pied incliné a déjà sa pointe au sol : rien ne change.
func _sortir_la_pointe(sk: Skeleton3D, i: int, vers_sk: Transform3D, haut: Vector3) -> void:
	var sol := float(sols_pointe[i])
	if sol == -INF:
		return
	var h := haut.normalized()
	var pied := sk.get_bone_global_pose(_pieds[i])
	var pointe := pied * (_pointe_locale[i] as Vector3)
	var pointe_monde := sk.global_transform * pointe
	var manque := (vers_sk * Vector3(pointe_monde.x, sol, pointe_monde.z)).dot(h) - pointe.dot(h)
	if manque <= 0.002:
		return
	var v := pointe - pied.origin
	var axe := v.cross(h)
	if axe.length() < 0.0001:
		return
	var angle := asin(clampf((v.dot(h) + manque) / v.length(), -1.0, 1.0)) - asin(clampf(v.dot(h) / v.length(), -1.0, 1.0))
	_tourner(sk, _pieds[i], Quaternion(axe.normalized(), clampf(angle, 0.0, POINTE_ANGLE_MAX) * poids))


func _levee(sk: Skeleton3D, i: int, haut: Vector3) -> float:
	var base := _pos_base.get(_pieds[i], Vector3.ZERO) as Vector3
	var parent := sk.get_bone_global_pose(sk.get_bone_parent(_pieds[i]))
	var origine_anim := parent * base
	return origine_anim.dot(haut.normalized()) / haut.length()


# Tourne l'os `b` de `q` dans le repère du squelette, autour de son origine.
func _tourner(sk: Skeleton3D, b: int, q: Quaternion) -> void:
	var g := sk.get_bone_global_pose(b)
	var parent := sk.get_bone_parent(b)
	var pg := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
	sk.set_bone_pose_rotation(b, (pg.basis.inverse() * (Basis(q) * g.basis)).get_rotation_quaternion())


func _os_ecrits() -> PackedInt32Array:
	var l := PackedInt32Array([_bassin])
	l.append_array(_cuisses)
	l.append_array(_tibias)
	l.append_array(_pieds)
	return l


# Au premier passage de l'image (ou si l'animation a réécrit l'os depuis), la pose trouvée est celle de l'animation :
# on la relève. Aux passages suivants, les os portent encore NOTRE résultat : on remet la pose relevée.
func _repartir_de_l_animation(sk: Skeleton3D) -> void:
	var nouvelle := Engine.get_process_frames() != _image
	_image = Engine.get_process_frames()
	for b in _os_ecrits():
		var r := sk.get_bone_pose_rotation(b)
		var p := sk.get_bone_pose_position(b)
		var re: Variant = _rot_ecrite.get(b)
		var pe: Variant = _pos_ecrite.get(b)
		var a_nous: bool = re is Quaternion and absf(r.dot(re)) > 0.99999 and pe is Vector3 and p.is_equal_approx(pe)
		if nouvelle or not a_nous:
			_rot_base[b] = r
			_pos_base[b] = p
		else:
			sk.set_bone_pose_rotation(b, _rot_base[b])
			sk.set_bone_pose_position(b, _pos_base[b])


func _memoriser(sk: Skeleton3D) -> void:
	for b in _os_ecrits():
		_rot_ecrite[b] = sk.get_bone_pose_rotation(b)
		_pos_ecrite[b] = sk.get_bone_pose_position(b)
