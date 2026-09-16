extends SkeletonModifier3D
class_name JumpPoseModifier

# Pose de saut PROCÉDURALE, ajoutée par-dessus l'animation de locomotion via le
# système SkeletonModifier3D de Godot 4 (le modificateur tourne APRÈS que
# l'AnimationMixer a écrit la pose de la frame -> on compose une rotation locale
# additive sur quelques os).
#
# Pourquoi pas les anims de UAL1_Standard.glb :
#   Suit.gltf est un rig Quaternius (os "Hips", "UpperArm.L"...). UAL est un rig
#   Unreal Mannequin (os "pelvis", "upperarm_l"...). Ce ne sont PAS que des noms
#   différents :
#     - hiérarchie des jambes différente : dans Quaternius "Foot.L" est enfant de
#       "Root", pas de "LowerLeg.L" (qui est une feuille) -> un pied retargeté ne
#       suit jamais le tibia.
#     - rest poses sans aucun rapport (relevé os par os) -> un simple renommage
#       de tracks tord les membres ; le retargeting BoneMap ne rattrape pas les
#       pieds.
#   Pour un mouvement à jambes lourdes comme le saut, une pose en code est plus
#   fiable et sans dépendance d'import. Cf. le message de la tâche pour le
#   comparatif complet des deux squelettes.

# Piloté par Player : 0 au sol, 1 en l'air (fondu géré côté Player).
@export_range(0.0, 1.0) var blend := 0.0
# +1 = phase de poussée (on monte), 0 = apex, -1 = réception (on descend).
@export_range(-1.0, 1.0) var phase := 0.0

# Multiplicateur global : baisse-le si la pose clippe dans le corps.
@export_range(0.0, 1.5) var pose_strength := 1.0

# Angles en DEGRÉS, repère local de l'os. AMPLITUDES RÉDUITES (les valeurs
# précédentes faisaient rentrer les mains dans le torse).
@export var thigh_tuck_deg := 24.0        # cuisses ramenées vers le buste (apex) - était 42
@export var thigh_launch_deg := -8.0      # jambes qui traînent à la poussée - était -14
@export var knee_bend_deg := 38.0         # flexion du genou (apex) - était 66
@export var upper_arm_deg := 8.0          # bras : léger seulement - était 24
@export var lower_arm_deg := 12.0         # coude : léger - était 30
@export var hips_lean_deg := 6.0          # léger buste en avant - était 9

# Axes de flexion séparés jambes / bras (le renommage SkeletonProfileHumanoid a
# pu changer l'orientation locale des os). À inverser (-1) ou passer en Z si le
# pliage part du mauvais côté.
@export var leg_flex_axis := Vector3(1, 0, 0)
@export var arm_flex_axis := Vector3(1, 0, 0)
# true : le bras droit tourne à l'opposé du gauche (paire symétrique). Si les
# deux bras partent du même côté / dans le torse, essaie de basculer ce flag.
@export var mirror_arms := true

# Clé logique -> noms d'os possibles. Le squelette de Suit.gltf a été renommé
# sur SkeletonProfileHumanoid (retargeting Godot) -> on essaie d'abord les noms
# du profil, puis les noms Quaternius d'origine (au cas où le renommage ne
# serait pas actif, ou pour un autre modèle).
const BONE_ALIASES := {
	"hips": ["Hips", "Body"],
	"thigh_l": ["LeftUpperLeg", "UpperLeg.L"],
	"thigh_r": ["RightUpperLeg", "UpperLeg.R"],
	"calf_l": ["LeftLowerLeg", "LowerLeg.L"],
	"calf_r": ["RightLowerLeg", "LowerLeg.R"],
	"uparm_l": ["LeftUpperArm", "UpperArm.L"],
	"uparm_r": ["RightUpperArm", "UpperArm.R"],
	"loarm_l": ["LeftLowerArm", "LowerArm.L"],
	"loarm_r": ["RightLowerArm", "LowerArm.R"],
}

var _sk: Skeleton3D
var _idx: Dictionary = {}
var _resolved := false

# FRAMERATE-INDÉPENDANCE.
# La pose écrite est ABSOLUE : res = pose_mixer(os) * rotation(phase). Elle ne
# dépend QUE de la pose d'animation courante et de la phase (blend/phase, elles-
# mêmes recalculées chaque frame par le Player depuis is_on_floor()/velocity.y),
# jamais du résultat précédent -> même rendu à 60 ou 200 FPS.
# Le piège à éviter : _apply() peut tourner plusieurs fois par frame (le
# BoneAttachment3D de l'arme force des recalculs du squelette). Si on relisait
# get_bone_pose_rotation() comme base à chaque passage, on composerait
# res * rotation encore et encore -> accumulation -> membres qui sur-tournent,
# d'autant plus vite que le FPS est haut. On mémorise donc la "pose mixer" par os
# et on ne la recapture QUE quand l'os a réellement été réécrit par le mixer
# (test insensible au signe du quaternion, cf. _add).
var _base: Dictionary = {}          # clé -> Quaternion pose mixer capturée
var _last_result: Dictionary = {}   # clé -> Quaternion dernier résultat qu'on a écrit
var _frame := -1

# --- garde-fou anti-boucle (debug freeze) ---
# _in_apply : si _apply() se ré-entre (set_bone_pose_rotation qui redéclenche
#   synchroniquement _process_modification) -> vraie récursion -> on coupe et on
#   logge une fois. _calls_this_frame : compte les passages de _apply() par frame
#   physique ; s'il grimpe anormalement (skeleton re-marqué "dirty" en boucle),
#   on le voit dans le log juste avant un éventuel gel.
var _in_apply := false
var _dbg_frame := -1
var _dbg_calls := 0
@export var debug_calls := false

func _ready() -> void:
	_resolve()

func _resolve() -> void:
	_sk = get_skeleton()
	_idx.clear()
	_resolved = false
	if _sk == null:
		return
	for key in BONE_ALIASES:
		var found := -1
		for nm in BONE_ALIASES[key]:
			var i := _sk.find_bone(nm)
			if i != -1:
				found = i
				break
		_idx[key] = found
	_base.clear()
	_last_result.clear()
	_resolved = true

# Godot appelle l'un ou l'autre selon la version -> on couvre les deux.
func _process_modification() -> void:
	_apply()

func _process_modification_with_delta(_delta: float) -> void:
	_apply()

func _apply() -> void:
	if blend <= 0.001:
		_base.clear()
		_last_result.clear()
		return
	if _sk == null or not _resolved:
		_resolve()
		if _sk == null:
			return

	# ré-entrance = récursion synchrone -> on refuse et on logge une seule fois
	if _in_apply:
		push_error("[JumpPoseModifier] _apply() RÉ-ENTRANT — boucle de modification détectée, passage ignoré")
		return
	_in_apply = true

	if debug_calls:
		var f := Engine.get_physics_frames()
		if f == _dbg_frame:
			_dbg_calls += 1
			if _dbg_calls == 3 or _dbg_calls == 20 or _dbg_calls == 200:
				print("[jpm] frame physique %d : %d appels de _apply() dans la même frame" % [f, _dbg_calls])
		else:
			_dbg_frame = f
			_dbg_calls = 1

	var la: Vector3 = leg_flex_axis.normalized()
	var aa: Vector3 = arm_flex_axis.normalized()
	var s: float = blend * pose_strength
	var arm_r: float = -1.0 if mirror_arms else 1.0
	var launch: float = clampf(phase, 0.0, 1.0)     # 0..1 en montée
	var land: float = clampf(-phase, 0.0, 1.0)      # 0..1 en descente

	# cuisses : traînantes à la poussée -> tuck à l'apex -> se détendent un peu
	# vers le sol à la réception
	var thigh: float = lerpf(thigh_tuck_deg, thigh_launch_deg, launch)
	thigh = lerpf(thigh, thigh_tuck_deg * 0.35, land)
	var knee: float = lerpf(knee_bend_deg, knee_bend_deg * 0.45, land)

	var new_frame := Engine.get_physics_frames() != _frame

	_add("hips", la, -hips_lean_deg * s, new_frame)
	_add("thigh_l", la, -thigh * s, new_frame)
	_add("thigh_r", la, -thigh * s, new_frame)
	_add("calf_l", la, knee * s, new_frame)
	_add("calf_r", la, knee * s, new_frame)
	_add("uparm_l", aa, upper_arm_deg * s, new_frame)
	_add("uparm_r", aa, upper_arm_deg * s * arm_r, new_frame)
	_add("loarm_l", aa, -lower_arm_deg * s, new_frame)
	_add("loarm_r", aa, -lower_arm_deg * s * arm_r, new_frame)

	_frame = Engine.get_physics_frames()
	_in_apply = false

# Écrit une rotation locale ABSOLUE : res = pose_mixer * rotation(deg).
# `base` (pose_mixer) est (re)capturée quand :
#   - c'est une nouvelle frame physique (le mixer a forcément rejoué), OU
#   - l'os ne porte plus NOTRE dernier résultat -> quelqu'un (le mixer sur une
#     frame idle, un autre modificateur) l'a réécrit entre-temps.
# Sinon on réutilise la base mémorisée -> repasser 2, 20 ou 200 fois dans la
# frame donne exactement le même résultat. Le test d'égalité se fait sur le
# produit scalaire (|dot|~1), INSENSIBLE au signe du quaternion : set/get peut
# renvoyer -q pour la même rotation, et is_equal_approx() s'y laissait piéger
# (il voyait "réécrit" -> il recomposait -> accumulation qui repartait).
func _add(key: String, axis: Vector3, deg: float, new_frame: bool) -> void:
	var idx: int = _idx.get(key, -1)
	if idx < 0:
		return
	var cur: Quaternion = _sk.get_bone_pose_rotation(idx)
	var last_res: Variant = _last_result.get(key)
	var still_ours := last_res is Quaternion and absf(cur.dot(last_res)) > 0.99999
	if new_frame or not still_ours:
		_base[key] = cur                      # (re)capture la pose du mixer
	var res: Quaternion = (_base[key] as Quaternion) * Quaternion(axis, deg_to_rad(deg))
	_sk.set_bone_pose_rotation(idx, res)
	_last_result[key] = res
