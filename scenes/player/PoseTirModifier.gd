extends SkeletonModifier3D
class_name PoseTirModifier

# BRAS TENDU EN POSITION DE TIR (2026-09-25, CLAUDE.md §16). Arme sortie, le bras droit du joueur prend la pose de
# l'animation Idle_Gun_Pointing du pack (bras tendu à 98 %, horizontal, droit devant : mesuré), PAR-DESSUS l'animation
# de locomotion : les jambes continuent de marcher, le bras gauche de se balancer. Un SkeletonModifier3D tourne après
# que l'AnimationPlayer a écrit la pose de l'image, comme JumpPoseModifier : pas d'AnimationTree à monter, et le
# reste du code du joueur (AnimationPlayer.play) ne change pas.
#
# Puis le bras VISE : il pivote à l'épaule pour que le CANON de l'arme pointe sur `cible` (le point sous le réticule,
# donné par le joueur), au plus ANGLE_MAX. C'est ce qui suit la caméra en hauteur (le pack n'a pas de pose de visée
# haute ou basse utilisable : celles d'UAL1, reciblées sur ce squelette, pointent à gauche et vers le bas — mesuré) et
# ce qui garde l'arme sur la cible quand le buste tourne (course en diagonale) ou se balance (course).
#
# Enfin le RECUL : le canon relevé de `recul` radians au coude, que le joueur remet à zéro en quelques centièmes de
# seconde. À la place de l'animation de tir en corps entier, qui figeait les jambes pendant le tir (pieds qui glissent).
#
# La pose écrite ne dépend que de la pose de l'animation et des réglages de l'image : même rendu quel que soit le nombre
# de passages par image (cf. le piège d'accumulation expliqué dans JumpPoseModifier).

const ANGLE_MAX := 1.396             # rad (80°) : rotation de visée au plus, à l'épaule

@export_range(0.0, 1.0) var poids := 0.0      # 0 : l'animation seule ; 1 : bras en position de tir
var viser := false                             # vrai : le canon est pointé sur `cible`
var cible := Vector3.ZERO                      # point visé, dans le monde
var recul := 0.0                               # rad : canon relevé par le tir

var _pose := {}                                # os -> rotation locale dans la pose de tir
var _os := PackedInt32Array()                  # bras droit : épaule, bras, avant-bras, main, doigts
var _bras := -1
var _coude := -1
var _main := -1
var _canon := Vector3.RIGHT                    # axe du canon, dans le repère de l'os de la main
var _bouche := Vector3.ZERO                    # bouche du canon, dans le repère de l'os de la main
var _base := {}                                # os -> rotation locale de l'ANIMATION, relevée au premier passage de l'image
var _ecrit := {}                               # os -> dernière rotation qu'on y a écrite
var _image := -1


# Relève la pose de tir sur l'animation `clip` (la pose telle que le moteur l'écrit, os absents du clip compris) et
# l'arme dans la main : `arme_dans_main` est la transformation de l'arme dans le repère de l'os de la main, l'axe du
# canon est son +X et `bouche` le bout du canon dans le repère de l'arme (cf. Weapon.gd).
func preparer(anim: AnimationPlayer, clip: String, arme_dans_main: Transform3D, bouche: Vector3) -> void:
	var sk := get_skeleton()
	_bras = sk.find_bone("RightUpperArm")
	_coude = sk.find_bone("RightLowerArm")
	_main = sk.find_bone("RightHand")
	_os.clear()
	var epaule := sk.find_bone("RightShoulder")
	for b in sk.get_bone_count():
		if b == epaule or _descend_de(sk, b, epaule):
			_os.append(b)
	var avant := anim.current_animation
	anim.play(clip)
	anim.seek(0.0, true)
	for b in _os:
		_pose[b] = sk.get_bone_pose_rotation(b)
	if avant != "":
		anim.play(avant)
	_canon = (arme_dans_main.basis * Vector3.RIGHT).normalized()
	_bouche = arme_dans_main * bouche


func _descend_de(sk: Skeleton3D, b: int, ancetre: int) -> bool:
	var p := sk.get_bone_parent(b)
	while p >= 0:
		if p == ancetre:
			return true
		p = sk.get_bone_parent(p)
	return false


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or _main < 0 or poids <= 0.001:
		_ecrit.clear()
		return
	# Le squelette peut repasser ses modificateurs plusieurs fois dans une image : on repart alors de la pose de
	# l'animation relevée au premier passage, pas de NOTRE résultat resté dans les os — sinon le recul (et le fondu
	# de la pose) s'ajouteraient à eux-mêmes. « Encore à nous » : même rotation que notre dernière écriture, au
	# signe près du quaternion (cf. JumpPoseModifier._add).
	var nouvelle := Engine.get_process_frames() != _image
	_image = Engine.get_process_frames()
	for b in _os:
		var cur := sk.get_bone_pose_rotation(b)
		var e: Variant = _ecrit.get(b)
		if nouvelle or not (e is Quaternion and absf(cur.dot(e)) > 0.99999):
			_base[b] = cur
		sk.set_bone_pose_rotation(b, (_base[b] as Quaternion).slerp(_pose[b], poids))
	_modifier(sk)
	for b in _os:
		_ecrit[b] = sk.get_bone_pose_rotation(b)


# Le canon pointé sur la cible (ou, sans visée, laissé dans l'axe de la pose), relevé du recul, par une rotation du
# bras à l'épaule. Deux passes : la première tourne le canon dans la bonne direction, la seconde corrige le déplacement
# de la bouche (elle a bougé avec le bras) ; au-delà, l'écart est sous le dixième de degré à 2 m.
func _modifier(sk: Skeleton3D) -> void:
	if not viser and recul <= 0.0:
		return
	var monde_vers_sk := sk.global_transform.affine_inverse()
	var haut := (monde_vers_sk.basis * Vector3.UP).normalized()
	var c := monde_vers_sk * cible
	var axe_pose := Vector3.ZERO
	for passe in 2:
		var main := sk.get_bone_global_pose(_main)
		var canon := (main.basis * _canon).normalized()
		var voulu := canon
		if viser:
			voulu = c - main * _bouche
			if voulu.length() < 0.3:
				return
			voulu = voulu.normalized()
		elif passe == 0:
			axe_pose = canon
		else:
			voulu = axe_pose
		if recul > 0.0:
			var axe := voulu.cross(haut)
			if axe.length() > 0.01:
				voulu = Quaternion(axe.normalized(), recul * poids) * voulu
		var q := Quaternion(canon, voulu)
		var angle := q.get_angle()
		if angle < 0.0005:
			return
		q = Quaternion.IDENTITY.slerp(q, minf(1.0, ANGLE_MAX / angle) * (poids if viser else 1.0))
		_tourner(sk, _bras, q)


# Tourne l'os `b` de `q` dans le repère du squelette (autour de son origine : l'épaule, le coude).
func _tourner(sk: Skeleton3D, b: int, q: Quaternion) -> void:
	var g := sk.get_bone_global_pose(b)
	var p := sk.get_bone_parent(b)
	var pg := sk.get_bone_global_pose(p) if p >= 0 else Transform3D.IDENTITY
	sk.set_bone_pose_rotation(b, (pg.basis.inverse() * (Basis(q) * g.basis)).get_rotation_quaternion())
