extends CharacterBody3D

const SPEED := 5.0              # marche normale
const SPRINT_SPEED := 13.5      # course (Shift maintenu) = SPEED * 2.7
const JUMP_VELOCITY := 6.0      # ~+33 % vs 4.5 -> saut nettement plus haut
const MOUSE_SENSITIVITY := 0.003
const COYOTE_TIME := 0.12      # on peut encore sauter juste après avoir quitté le sol
const JUMP_BUFFER := 0.12      # un appui saut est mémorisé ce court instant
const FREE_LOOK_RETURN_SPEED := 12.0   # vitesse de recentrage du corps quand on lâche Alt

const SWIM_SPEED := 2.5                    # déplacement horizontal en nageant, réduit vs SPEED
const SWIM_SURFACE_CORRECT_SPEED := 4.0    # "flottabilité" : vitesse de rappel vers la surface

const BULLET := preload("res://scenes/weapons/Bullet.tscn")
const WeaponRes := preload("res://scripts/data/WeaponData.gd")
const JumpPoseMod := preload("res://scenes/player/JumpPoseModifier.gd")

signal ammo_changed(current_ammo: int, reserve_ammo: int)
signal weapon_equipped_changed(equipped: bool)

# Debug temporaire : imprime l'état d'animation chaque frame physique.
@export var debug_anim := false
# Debug FREEZE : imprime n° de frame physique + delta + état (sol/saut/direction/
# arme/anim) à CHAQUE frame physique. Sert à voir dans le log, juste avant un
# gel, si : (a) le n° de frame se répète -> ré-entrance/boucle ; (b) le n° de
# frame avance mais `dt` explose (0.016 -> 0.5 -> 2...) -> effondrement perf
# (surcharge GPU/CPU), pas une boucle logique.
@export var debug_freeze := false

# Rotation Y du modèle pour compenser son orientation native (0 ou 180 selon
# l'export). À revérifier pour chaque modèle.
@export var model_yaw_deg := 180.0

# true  : pistolet skinné intégré au modèle Suit (calé par le rig).
# false : vrai modèle d'arme (assets/weapon_models/, chargé par Weapon.gd)
#         affiché à la place -> régler weapon_hand_offset / _rotation_deg dans le
#         repère de Wrist.R + les exports model_* de Weapon.gd.
# Passé à false pour utiliser le vrai Pistol_1.
@export var use_model_pistol := false

# CORRECTIF RÉSIDUEL du calage géométrique (GripPoint de Weapon.tscn aligné sur
# l'os RightHand, cf. _apply_weapon_pose). Valeurs figées après réglage live via
# l'arbre Remote : arme bien tenue dans la paume, canon vers l'avant.
@export var weapon_hand_offset := Vector3(0.05, -0.05, 0.13)
@export var weapon_hand_rotation_deg := Vector3(180.0, -75.0, 90.0)
# Squelette Suit.gltf renommé sur SkeletonProfileHumanoid par le retargeting ->
# "RightHand" (ex-"Wrist.R"). Le fallback dans _attach_weapon_to_hand couvre les deux.
@export var right_hand_bone := "RightHand"
# Si true : ré-applique placement modèle + arme chaque frame -> éditable EN JEU
# via l'arbre "Remote" de l'éditeur. Passe à false une fois figé.
@export var tune_weapon_live := true
# Le modèle Suit est déjà texturé "costume" ; laisse false. Passe à true pour
# forcer une repalette via _apply_suit_colors().
@export var recolor_suit := false
# Anims pistolet haut du corps depuis UAL1 (retargeté). Si la visée/reload
# apparaît figée ou en T-pose (track paths qui ne résolvent pas sur le
# squelette renommé), repasse à false -> retour à Idle_Gun / Gun_Shoot de Suit.
#
# GARDÉ À false ce tour-ci : le Rest Fixer vient d'être DÉSACTIVÉ sur l'import de
# Suit.gltf -> son squelette de repos n'est plus normalisé sur le profil, alors
# que les anims UAL, elles, ont été retargetées AVEC Rest Fixer. Fort risque que
# la pose de visée UAL soit maintenant déformée sur ce nouveau repos. On valide
# d'abord ville + arme + saut + marche, PUIS on rebranche UAL et on regarde la
# visée à part (il faudra sans doute aligner le Rest Fixer entre Suit et UAL).
@export var use_ual_pistol := false

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D
@onready var muzzle_point: Node3D = $Weapon/MuzzlePoint  # bout du canon de l'arme placeholder
@onready var model: Node3D = $PlayerModel

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _coyote := 0.0
var _jump_buffer := 0.0

# Regard libre (Alt maintenu) : la souris X tourne la SpringArm seule, pas le
# corps. Au relâchement, le corps pivote pour absorber spring_arm.rotation.y
# (cap caméra monde inchangé) puis on repasse en contrôle normal.
var _free_look := false
var _free_look_returning := false

var weapon                     # WeaponData (via preload, indépendant du cache global)
var weapon_equipped := false   # dégainé/rangé, bascule avec "toggle_weapon" (touche 1)
var _fire_cooldown := 0.0
var _reloading := false
var _reload_timer := 0.0
var _ignore_next_shoot := false   # le clic qui re-capture la souris ne doit pas tirer

var _anim: AnimationPlayer
var _skel: Skeleton3D
var _current_anim := ""
var _jump_mod                        # JumpPoseModifier (pose de saut additive), non typé -> accès dynamique
var _air_blend := 0.0                 # 0 au sol, 1 en l'air (fondu)

# --- conduite ---
const FOOT_SPRING_LENGTH := 4.0
const DRIVE_SPRING_LENGTH := 8.0     # caméra reculée en conduite
const DRIVE_ZOOM_EXTRA := 3.5        # dézoom supplémentaire à vitesse max

# --- intérieur (ApartmentInterior -> set_indoor) ---
const FOOT_PIVOT_HEIGHT := 1.6       # hauteur de la SpringArm dans Player.tscn
const FOOT_ARM_MARGIN := 0.01        # marge par défaut de SpringArm3D
const INDOOR_SPRING_LENGTH := 1.8    # bras rapproché : plafond des appartements à 2,80 m
const INDOOR_PIVOT_HEIGHT := 1.45
const INDOOR_SHOULDER_OFFSET := 0.4  # visée légèrement décalée vers l'épaule droite
const INDOOR_ARM_MARGIN := 0.2       # garde la caméra à distance des murs
const CAMERA_BLEND_SPEED := 6.0
var _indoor_zones := 0               # compteur : tolère des zones intérieures qui se touchent
var _shoulder := 0.0
var _driving := false
var _current_car: Node3D = null
var _cars_in_range: Array = []
var _swimming := false
var _water_zones: Array = []
var _water_surface_y := 0.0
var _foot_parent: Node = null
var _weapon_node: Node3D
var _pistol_ref: Node3D               # mesh "Pistol" du modèle (caché) servant de repère
var _weapon_base_xform := Transform3D.IDENTITY  # pose locale de base (calée sur _pistol_ref)
var _shoot_lock := 0.0                # temps restant où l'anim de tir prime sur la locomotion

func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# garde le perso "collé" au sol sur les petites bosses (routes/trottoirs) en
	# courant, pour que is_on_floor() reste fiable au moment d'un saut
	floor_snap_length = 0.4

	weapon = WeaponRes.new()
	# émet l'état initial après tous les _ready() (le HUD se connecte au sien)
	call_deferred("_emit_ammo")
	call_deferred("_emit_weapon_state")

	_setup_model()

func _unhandled_input(event: InputEvent) -> void:
	# Alt : regard libre. À la relâche, on lance le recentrage du corps.
	if event.is_action_pressed("free_look") and not _driving:
		_free_look = true
		_free_look_returning = false
	elif event.is_action_released("free_look"):
		_free_look = false
		_free_look_returning = absf(spring_arm.rotation.y) > 0.001

	# Rotation caméra à la souris (style third-person classique)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		var yaw_delta: float = -mm.relative.x * MOUSE_SENSITIVITY
		var pitch_delta: float = -mm.relative.y * MOUSE_SENSITIVITY
		# Pitch : toujours sur la SpringArm.
		spring_arm.rotation.x = clampf(spring_arm.rotation.x + pitch_delta,
			deg_to_rad(-70), deg_to_rad(45))
		# Yaw : sur le CORPS normalement ; sur la SpringArm SEULE en regard libre.
		if _free_look:
			spring_arm.rotation.y = wrapf(spring_arm.rotation.y + yaw_delta, -PI, PI)
		else:
			rotate_y(yaw_delta)

	# Échap pour relâcher la souris (utile en dev, à retirer/adapter plus tard)
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Clic gauche dans la fenêtre pour RE-CAPTURER la souris (comportement PC
	# habituel : Échap libère, un clic recapture). On ne le fait PAS quand un
	# panneau UI gère lui-même la souris (BuildingPurchaseUI / BusinessPanel) :
	# sinon on cacherait le curseur alors que l'utilisateur veut cliquer les
	# boutons. Le MapMenu met le jeu en pause -> _unhandled_input du Player ne
	# tourne pas dans ce cas, rien à gérer.
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE \
			and not _ui_owns_mouse():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_ignore_next_shoot = true
		get_viewport().set_input_as_handled()

	# Touche 1 : dégainer / ranger l'arme (pas en conduite)
	if event.is_action_pressed("toggle_weapon") and not _driving:
		weapon_equipped = not weapon_equipped
		_update_weapon_visibility()
		weapon_equipped_changed.emit(weapon_equipped)

	# E : monter / descendre d'un véhicule
	if event.is_action_pressed("interact"):
		if _driving:
			_exit_vehicle()
		else:
			_try_enter_vehicle()

# Après relâchement de Alt : le corps pivote pour absorber le yaw accumulé sur
# la SpringArm. On transfère l'écart bras -> corps par pas, en retirant autant
# à spring_arm.rotation.y : le cap monde de la caméra ne bouge pas, seul le
# corps tourne, jusqu'à faire face à ce qu'on regardait.
func _update_free_look_return(delta: float) -> void:
	# filet : si l'event de relâche de Alt a été manqué (perte de focus fenêtre)
	if _free_look and not Input.is_action_pressed("free_look"):
		_free_look = false
		_free_look_returning = absf(spring_arm.rotation.y) > 0.001
	if not _free_look_returning:
		return
	var remaining: float = spring_arm.rotation.y
	if absf(remaining) < 0.01:
		rotate_y(remaining)
		spring_arm.rotation.y = 0.0
		_free_look_returning = false
		return
	var step: float = remaining * clampf(delta * FREE_LOOK_RETURN_SPEED, 0.0, 1.0)
	rotate_y(step)                    # le corps tourne de `step`...
	spring_arm.rotation.y -= step     # ...et la caméra se re-centre d'autant

# Vrai si un panneau UI qui pilote lui-même Input.mouse_mode est ouvert
# (BuildingPurchaseUI / BusinessPanel / InventoryPanel / MapMenu /
# PhonePanel / CarDealershipPanel / ApartmentAgencyPanel) -> on laisse la
# souris libre. ContactsPanel a été retiré (redondant avec l'onglet
# Contacts du téléphone) ; ContactsManager.gd (les données) reste intact.
func _ui_owns_mouse() -> bool:
	for grp in ["building_purchase_ui", "business_panel", "inventory_panel", "map_menu", "phone_panel", "car_dealership_panel", "apartment_agency_panel"]:
		for n in get_tree().get_nodes_in_group(grp):
			if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
				return true
	return false

# --- Caméra intérieure ----------------------------------------------------

# Appelé par ApartmentInterior quand le joueur entre dans / sort de sa zone intérieure.
func set_indoor(inside: bool) -> void:
	_indoor_zones = maxi(_indoor_zones + (1 if inside else -1), 0)

func is_indoor() -> bool:
	return _indoor_zones > 0

# À pied : en intérieur, bras court, pivot plus bas et léger décalage d'épaule. C'est le pivot qui se
# décale (pas un h_offset) : le rayon de tir part toujours du centre de l'écran. Fondu dans les deux
# sens. La SpringArm garde sa collision : les murs rapprochent encore la caméra dans les coins.
func _update_foot_camera(delta: float) -> void:
	var inside := is_indoor()
	var k := clampf(delta * CAMERA_BLEND_SPEED, 0.0, 1.0)
	spring_arm.spring_length = lerpf(spring_arm.spring_length, INDOOR_SPRING_LENGTH if inside else FOOT_SPRING_LENGTH, k)
	_shoulder = lerpf(_shoulder, INDOOR_SHOULDER_OFFSET if inside else 0.0, k)
	var pivot_y := lerpf(spring_arm.position.y, INDOOR_PIVOT_HEIGHT if inside else FOOT_PIVOT_HEIGHT, k)
	spring_arm.position = Vector3(0.0, pivot_y, 0.0) + spring_arm.basis.x * _shoulder
	spring_arm.margin = INDOOR_ARM_MARGIN if inside else FOOT_ARM_MARGIN

func _physics_process(delta: float) -> void:
	if _driving:
		_update_drive_camera(delta)   # la voiture gère le reste ; la SpringArm suit le siège
		return

	if _swimming:
		_physics_process_swim(delta)
		return

	_update_free_look_return(delta)
	_update_foot_camera(delta)
	_handle_weapon(delta)
	_shoot_lock = maxf(_shoot_lock - delta, 0.0)

	if is_on_floor():
		_coyote = COYOTE_TIME
	else:
		velocity.y -= gravity * delta
		_coyote -= delta

	if Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_BUFFER
	else:
		_jump_buffer -= delta

	# saut valide même en pleine course : un appui bufferisé + une fenêtre coyote
	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		_jump_buffer = 0.0
		_coyote = 0.0

	# input_dir en 2D (x = gauche/droite, y = avant/arrière) projeté sur le plan horizontal
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# course seulement si l'action est maintenue ET qu'on se déplace réellement
	var sprinting := Input.is_action_pressed("sprint") and direction != Vector3.ZERO
	var speed := SPRINT_SPEED if sprinting else SPEED

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	if is_on_floor():
		StepClimb.try_climb(self, direction)

	move_and_slide()

	var planar_speed := Vector2(velocity.x, velocity.z).length()
	_update_animation(planar_speed, sprinting)
	_update_jump_pose(delta)

	if debug_freeze:
		print("[frz] pf=%d dt=%.4f floor=%s vy=%+.2f airblend=%.2f dir=(%.2f,%.2f) planar=%.2f sprint=%s equip=%s anim='%s' jmpblend=%.2f jmpphase=%+.2f" % [
			Engine.get_physics_frames(), delta, is_on_floor(), velocity.y, _air_blend,
			velocity.x, velocity.z, planar_speed, sprinting, weapon_equipped,
			_current_anim,
			(_jump_mod.blend if _jump_mod != null else -1.0),
			(_jump_mod.phase if _jump_mod != null else 0.0)])

	if tune_weapon_live:
		if model != null:
			model.rotation_degrees.y = model_yaw_deg
		_apply_weapon_pose()

# --- Modèle / animation ---------------------------------------------

# Calque visuel (doit correspondre à Car.tscn/NPC.tscn et au cull_mask exclu
# par les décalques de passage piéton dans World.tscn) : exclut le joueur de
# la projection des décalques, qui sinon "fuient" sur son modèle comme elles
# le faisaient sur les voitures/PNJ avant leur fix. Aucun autre système du
# projet (lumières, caméra, minimap...) ne filtre sur ce calque -- vérifié
# via une recherche de `cull_mask`/`.layers` sur tout le projet, seuls
# Car.gd/NPC.gd/TrafficLight.gd/LampPoleLayer.gd et les décalques eux-mêmes
# l'utilisent -- donc sans risque de casser autre chose.
const DECAL_EXCLUDE_LAYERS := 4

func _setup_model() -> void:
	if model == null:
		push_warning("PlayerModel absent : le visuel humanoïde n'est pas chargé")
		return

	# Suit.gltf est une instance statique dans Player.tscn (pas chargée au
	# runtime comme les modèles de Car/NPC), mais reste un descendant interne
	# d'une scène instanciée : on applique le calque ICI en script plutôt que
	# de modifier la propriété directement dans le .tscn, pour éviter le
	# risque de corruption déjà rencontré en forçant un owner sur un noeud
	# interne d'une instance (duplication de noeud lors du pack()/save()).
	for n in model.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).layers = DECAL_EXCLUDE_LAYERS

	model.rotation_degrees.y = model_yaw_deg
	if recolor_suit:
		_apply_suit_colors()

	# retrouve le pistolet intégré du modèle (mesh skinné dans la main).
	# Sa visibilité est décidée plus bas selon use_model_pistol.
	for n in model.find_children("*istol*", "", true, false):
		var n3 := n as Node3D
		if n3 != null:
			_pistol_ref = n3
			break

	var anims := model.find_children("*", "AnimationPlayer", true, false)
	if not anims.is_empty():
		_anim = anims[0] as AnimationPlayer
		# force la boucle sur la locomotion (pas sur les anims "one-shot")
		for a in _anim.get_animation_list():
			var low: String = String(a).to_lower()
			var loco := low.contains("idle") or low.contains("run") or low.contains("walk")
			var oneshot := low.contains("shoot") or low.contains("hit") or low.contains("death") \
				or low.contains("punch") or low.contains("kick") or low.contains("roll") \
				or low.contains("interact") or low.contains("wave") or low.contains("slash") \
				or low.contains("pointing")
			if loco and not oneshot:
				var res := _anim.get_animation(a)
				if res != null:
					res.loop_mode = Animation.LOOP_LINEAR
		print("[Player] Animations du modèle : ", _anim.get_animation_list())
		_load_upper_body_anims()
		if _anim.has_animation("Idle"):
			_anim.play("Idle")
			_current_anim = "Idle"
	else:
		push_warning("Aucun AnimationPlayer trouvé dans le modèle")

	var skels := model.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		_skel = skels[0] as Skeleton3D
		var bones := []
		for i in _skel.get_bone_count():
			bones.append(_skel.get_bone_name(i))
		print("[Player] Os du squelette : ", bones)
		_attach_weapon_to_hand()
		_jump_mod = JumpPoseMod.new()
		_jump_mod.name = "JumpPose"
		_jump_mod.debug_calls = debug_freeze   # 1 seul flag pilote les 2 traces
		_skel.add_child(_jump_mod)   # doit être enfant direct du Skeleton3D
	else:
		push_warning("Aucun Skeleton3D trouvé dans le modèle")

# Anims HAUT DU CORPS depuis UAL1_Standard.glb (retargetées sur le même profil
# SkeletonProfileHumanoid que Suit.gltf). On NE prend PAS les anims de jambes
# de UAL : le pied de Suit.gltf n'est pas enfant de la jambe -> retarget qui
# étire les pieds. Les jambes restent 100 % sur les anims d'origine Suit.gltf.
# Ces anims-ci ne servent que joueur immobile + arme dégainée.
# IMPORTANT : pointer vers la copie À LA RACINE de assets/animations/, PAS vers
# assets/animations/UAL1_full/Unreal-Godot/. Seul le fichier racine a son
# BoneMap + SkeletonProfileHumanoid configurés à la main dans l'éditeur : c'est
# ce qui retargete les pistes d'anim sur les os de Suit.gltf (Hips, Spine,
# RightHand...). La copie brute du sous-dossier UAL1_full/ n'est pas retargetée
# -> pistes qui ciblent pelvis/spine_02/hand_r et warnings "couldn't resolve
# track". Le fichier racine a été restauré depuis nvvv.zip après que le
# dézippage du pack l'a écrasé.
const UAL1_LIB := "res://assets/animations/UAL1_Standard.glb"
const UB_ANIMS := ["Pistol_Aim_Neutral", "Pistol_Reload", "Pistol_Shoot"]

func _load_upper_body_anims() -> void:
	if _anim == null or not use_ual_pistol:
		return
	var scene := load(UAL1_LIB) as PackedScene
	if scene == null:
		push_warning("[Player] UAL1_Standard introuvable — anims pistolet indisponibles")
		return
	var inst := scene.instantiate()
	var aps := inst.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		inst.queue_free()
		return
	var src := aps[0] as AnimationPlayer
	var lib := AnimationLibrary.new()
	for src_lib_name in src.get_animation_library_list():
		var sl := src.get_animation_library(src_lib_name)
		for a in sl.get_animation_list():
			if String(a) in UB_ANIMS:
				lib.add_animation(a, sl.get_animation(a).duplicate())
	inst.queue_free()
	if lib.get_animation_list().is_empty():
		push_warning("[Player] UAL1 : aucune anim pistolet retrouvée (noms/retarget ?)")
		return
	if _anim.has_animation_library("ual"):
		_anim.remove_animation_library("ual")
	_anim.add_animation_library("ual", lib)
	# l'aim est une pose tenue -> boucle ; reload/shoot en one-shot explicite
	var aim := _anim.get_animation("ual/Pistol_Aim_Neutral")
	if aim != null:
		aim.loop_mode = Animation.LOOP_LINEAR
	for one_shot: String in ["ual/Pistol_Reload", "ual/Pistol_Shoot"]:
		var r := _anim.get_animation(one_shot)
		if r != null:
			r.loop_mode = Animation.LOOP_NONE
	print("[Player] anims haut du corps UAL : ", lib.get_animation_list())

# Repalette optionnelle (recolor_suit) : ne change QUE l'albedo des matériaux
# repérés par nom (Suit / Tie / White / Black). Le reste des propriétés est
# conservé (duplicate + override par surface). Off par défaut : le modèle Suit
# est déjà correctement texturé.
func _apply_suit_colors() -> void:
	var suit := {
		"suit": Color(0.10, 0.10, 0.12),    # veste/pantalon : charbon
		"tie": Color(0.28, 0.05, 0.09),     # cravate : bordeaux
		"white": Color(0.90, 0.89, 0.85),   # chemise : blanc cassé
		"black": Color(0.05, 0.05, 0.06),   # chaussures : quasi-noir
	}
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i)
			if src == null:
				continue
			var mat_name := src.resource_name.to_lower()
			var found := Color(0, 0, 0, 0)  # alpha 0 = pas de correspondance
			for key in suit:
				if mat_name.contains(key):
					found = suit[key]
			print("[Player] surface %d : matériau '%s'%s" % [
				i, src.resource_name, ("" if found.a == 0.0 else " -> recoloré")])
			if found.a == 0.0:
				continue
			var dup := src.duplicate() as Material
			if dup is BaseMaterial3D:
				(dup as BaseMaterial3D).albedo_color = found
				mi.set_surface_override_material(i, dup)

func _attach_weapon_to_hand() -> void:
	var weapon_node := get_node_or_null("Weapon") as Node3D
	if weapon_node == null or _skel == null:
		return

	var bone := right_hand_bone
	if _skel.find_bone(bone) == -1:
		bone = ""
		for i in _skel.get_bone_count():
			var bn: String = _skel.get_bone_name(i).to_lower()
			if (bn.contains("hand") or bn.contains("wrist")) \
				and (bn.ends_with(".r") or bn.ends_with("_r") or bn.contains("right")):
				bone = _skel.get_bone_name(i)
				break
	if bone == "":
		push_warning("Os de la main droite introuvable — arme laissée sur le Player")
		return

	var attach := BoneAttachment3D.new()
	attach.name = "RightHandAttach"
	_skel.add_child(attach)
	attach.bone_name = bone

	weapon_node.reparent(attach, false)
	weapon_node.transform = Transform3D.IDENTITY
	# NB : le "Pistol" du modèle est un mesh SKINNÉ (transform de noeud = identité),
	# donc on ne peut pas s'en servir comme repère de transform. Base = identité
	# dans le repère de Wrist.R ; le placement vient des exports weapon_hand_*.
	_weapon_base_xform = Transform3D.IDENTITY
	_weapon_node = weapon_node

	# Weapon.tscn est un noeud à part (pas dans Suit.gltf) -> pas couvert par
	# la boucle sur `model` plus haut dans _setup_model(). Même calque pour
	# la même raison (éviter que le décalque de passage piéton s'y projette).
	for wn in _weapon_node.find_children("*", "MeshInstance3D", true, false):
		(wn as MeshInstance3D).layers = DECAL_EXCLUDE_LAYERS

	_update_weapon_visibility()
	_apply_weapon_pose()
	print("[Player] Arme attachée à l'os : ", bone, " | pistolet modèle : ", use_model_pistol)

# Montre le pistolet (celui du modèle si use_model_pistol, sinon le mesh de
# Weapon.tscn) UNIQUEMENT si weapon_equipped. MuzzlePoint reste toujours actif.
func _update_weapon_visibility() -> void:
	var show_model_gun := weapon_equipped and use_model_pistol
	var show_tscn_gun := weapon_equipped and not use_model_pistol
	if _pistol_ref != null and is_instance_valid(_pistol_ref):
		_pistol_ref.visible = show_model_gun
	if _weapon_node != null:
		for c in _weapon_node.find_children("*", "MeshInstance3D", true, false):
			var m := c as Node3D
			if m != null:
				m.visible = show_tscn_gun

func _emit_weapon_state() -> void:
	weapon_equipped_changed.emit(weapon_equipped)

# Place l'arme dans le repère de l'os RightHand pour que son GripPoint tombe sur
# l'origine de l'os. Systématique : Weapon.transform = correction · GripPoint⁻¹.
# `correction` (weapon_hand_offset/rotation) n'est qu'un petit rattrapage.
# Ré-appliqué chaque frame si tune_weapon_live (réglage à chaud via l'arbre Remote).
func _apply_weapon_pose() -> void:
	if _weapon_node == null:
		return
	var grip_xf := Transform3D.IDENTITY
	if _weapon_node.has_method("grip_transform"):
		grip_xf = _weapon_node.grip_transform()
	var corr := Transform3D(
		Basis.from_euler(Vector3(
			deg_to_rad(weapon_hand_rotation_deg.x),
			deg_to_rad(weapon_hand_rotation_deg.y),
			deg_to_rad(weapon_hand_rotation_deg.z))),
		weapon_hand_offset)
	_weapon_node.transform = corr * grip_xf.affine_inverse()

func _update_animation(planar_speed: float, sprinting: bool) -> void:
	if _anim == null or _shoot_lock > 0.0:
		return

	# CAUSE DU BUG DE SAUT : cette fonction ne regardait QUE planar_speed
	# (horizontal). Un saut ne change que velocity.y -> la cible d'anim ne
	# changeait jamais -> _anim.play() jamais rappelé -> le clip sol continuait.
	# Option (a) : branche "en l'air" explicite avec un clip distinct.
	var airborne := not is_on_floor()
	var anim := ""
	var sscale := 1.0

	if airborne:
		# base neutre : la pose de saut est ajoutée en additif par
		# JumpPoseModifier (_update_jump_pose), pas besoin d'un clip dédié
		anim = _pick_anim("Idle_Gun" if weapon_equipped else "Idle", "Idle")
		sscale = 1.0
	elif planar_speed > 0.5:
		# EN MOUVEMENT : toujours les anims de jambes d'origine Suit.gltf
		# (les anims UAL retargetées étirent les pieds sur ce squelette).
		anim = _pick_anim("Run" if sprinting else "Walk", "Walk")
	elif weapon_equipped and _reloading and _anim.has_animation("ual/Pistol_Reload"):
		anim = "ual/Pistol_Reload"
	elif weapon_equipped and _anim.has_animation("ual/Pistol_Aim_Neutral"):
		# IMMOBILE + arme dégainée : pose de visée haut du corps (UAL retargeté).
		anim = "ual/Pistol_Aim_Neutral"
	else:
		anim = _pick_anim("Idle_Gun" if weapon_equipped else "Idle", "Idle")

	if debug_anim:
		print("[anim] sol=%s vy=%.1f planar=%.1f equip=%s -> cible='%s' existe=%s | joue='%s' playing=%s" % [
			is_on_floor(), velocity.y, planar_speed, weapon_equipped,
			anim, (anim != "" and _anim.has_animation(anim)),
			_anim.current_animation, _anim.is_playing()])

	if anim == "":
		return
	_anim.speed_scale = sscale
	if anim != _current_anim:
		_current_anim = anim
		_anim.play(anim, 0.12)

# Pilote la pose de saut procédurale : fondu d'influence selon is_on_floor() et
# phase selon la vitesse verticale. C'est ICI que le saut est "branché" sur
# l'état en l'air, indépendamment de la locomotion horizontale.
func _update_jump_pose(delta: float) -> void:
	if _jump_mod == null:
		return
	var target := 0.0 if is_on_floor() else 1.0
	# entrée franche en l'air, sortie plus douce (petit amorti à la réception)
	var rate := 16.0 if target > _air_blend else 10.0
	_air_blend = move_toward(_air_blend, target, rate * delta)
	_jump_mod.blend = _air_blend
	_jump_mod.phase = clampf(velocity.y / JUMP_VELOCITY, -1.0, 1.0)

func _play_shoot_anim() -> void:
	if _anim == null:
		return
	var fast := Vector2(velocity.x, velocity.z).length() > SPEED + 1.0
	var anim := ""
	# en mouvement -> anim de tir d'origine Suit (jambes correctes) ; immobile ->
	# tir haut du corps UAL retargeté si dispo.
	if fast:
		anim = _pick_anim("Run_Shoot", "")
	elif _anim.has_animation("ual/Pistol_Shoot"):
		anim = "ual/Pistol_Shoot"
	if anim == "":
		anim = _pick_anim("Idle_Gun_Shoot", "Gun_Shoot")
	if anim == "":
		return

	var res := _anim.get_animation(anim)
	var length: float = maxf(res.length if res != null else 0.3, 0.12)
	var fr: float = weapon.fire_rate if weapon != null else 0.3
	# L'anim de tir doit tenir dans l'intervalle fire_rate : si elle est plus
	# longue, on l'ACCÉLÈRE pour qu'elle finisse pile quand le tir suivant est
	# permis (jamais ralentie : un recul au ralenti est moche). Si elle est plus
	# courte, vitesse normale et elle se pose avant le tir suivant.
	var target: float = clampf(fr, 0.1, length)
	var spd_scale: float = length / target             # >= 1.0
	_anim.speed_scale = spd_scale
	_anim.play(anim, 0.05)
	_anim.seek(0.0, true)                               # redémarrage FRANC depuis le début à chaque tir
	_current_anim = anim
	_shoot_lock = clampf(length / spd_scale, 0.1, 0.6) # = durée réelle de lecture (= target)

# renvoie `first` si dispo, sinon `fallback` si dispo, sinon ""
func _pick_anim(first: String, fallback: String) -> String:
	if _anim.has_animation(first):
		return first
	if fallback != "" and _anim.has_animation(fallback):
		return fallback
	return ""

# --- Arme -----------------------------------------------------------

func _handle_weapon(delta: float) -> void:
	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)

	if _reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_reloading = false
			weapon.do_reload()
			_emit_ammo()
		return

	if not weapon_equipped:
		return  # arme rangée : le tir et le rechargement ne font rien

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return  # menu ouvert : le clic sert à l'UI, pas à tirer

	if Input.is_action_just_pressed("reload") and weapon.can_reload():
		_reloading = true
		_reload_timer = weapon.reload_time
		return

	# Regard libre (Alt maintenu) : on regarde juste autour, aucun tir possible
	# (ni balle, ni son, ni décompte de munitions).
	if _free_look:
		return

	if Input.is_action_pressed("shoot") and _fire_cooldown <= 0.0 and weapon.current_ammo > 0:
		if _ignore_next_shoot:
			_ignore_next_shoot = false   # ce clic a servi à re-capturer la souris, pas à tirer
		else:
			_shoot()
	elif not Input.is_action_pressed("shoot"):
		_ignore_next_shoot = false

func _shoot() -> void:
	weapon.current_ammo -= 1
	_fire_cooldown = weapon.fire_rate
	_emit_ammo()
	_play_shoot_anim()

	var from: Vector3 = camera.global_position
	var to: Vector3 = from - camera.global_transform.basis.z * weapon.shot_range

	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = 0b11  # bit 1 = murs/monde, bit 2 = PNJ
	params.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(params)

	var impact: Vector3 = to
	if hit:
		impact = hit["position"]
		var col = hit["collider"]
		if col != null and col.is_in_group("npc") and col.has_method("take_damage"):
			col.take_damage(weapon.damage, hit["position"], hit["normal"])

	var b: Node3D = BULLET.instantiate()
	get_parent().add_child(b)
	b.setup(muzzle_point.global_position, impact)

func _emit_ammo() -> void:
	ammo_changed.emit(weapon.current_ammo, weapon.reserve_ammo)

# --- Natation --------------------------------------------------------
# Zone dédiée (WaterZone.gd, Area3D en plus de la collision solide déjà
# existante sur les plans d'eau) : appelle ces deux méthodes à
# l'entrée/sortie, même principe que notify_car_in_range côté véhicules.

func notify_water_entered(zone: Node3D) -> void:
	if not _water_zones.has(zone):
		_water_zones.append(zone)
	_swimming = true
	_water_surface_y = zone.global_position.y
	velocity.y = 0.0

func notify_water_exited(zone: Node3D) -> void:
	_water_zones.erase(zone)
	if _water_zones.is_empty():
		_swimming = false
	else:
		_water_surface_y = (_water_zones[0] as Node3D).global_position.y

# Pas de gravité normale : rappel doux (P-controller clampé) vers la
# surface pour simuler une légère flottabilité, plutôt qu'une vraie
# simulation de flottaison. Déplacement horizontal à vitesse réduite
# (SWIM_SPEED), sur le plan de l'eau seulement -- pas de plongée/saut ici,
# hors du périmètre demandé.
func _physics_process_swim(delta: float) -> void:
	var y_diff := _water_surface_y - global_position.y
	velocity.y = clampf(y_diff * SWIM_SURFACE_CORRECT_SPEED, -SWIM_SPEED, SWIM_SPEED)

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SWIM_SPEED
		velocity.z = direction.z * SWIM_SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SWIM_SPEED)
		velocity.z = move_toward(velocity.z, 0, SWIM_SPEED)

	move_and_slide()

# --- Véhicules -----------------------------------------------------

func notify_car_in_range(car: Node) -> void:
	if not _cars_in_range.has(car):
		_cars_in_range.append(car)

func notify_car_out_of_range(car: Node) -> void:
	_cars_in_range.erase(car)

func _try_enter_vehicle() -> void:
	# Ne garde que les voitures encore valides et libres. On NE prend PAS
	# bêtement _cars_in_range[0] : après un vol, l'épave qu'on vient de quitter
	# reste dans la zone (donc dans la liste) et, n'étant plus "occupée", était
	# resélectionnée en boucle -> on remontait toujours dans la même voiture,
	# celle dont le conducteur PNJ avait déjà été éjecté. On prend la PLUS PROCHE.
	_cars_in_range = _cars_in_range.filter(func(c): return is_instance_valid(c) and not c.is_occupied())
	if _cars_in_range.is_empty():
		return
	var car: Node3D = null
	var best_d := INF
	for c in _cars_in_range:
		var d: float = global_position.distance_squared_to((c as Node3D).global_position)
		if d < best_d:
			best_d = d
			car = c as Node3D
	if car == null:
		return
	_enter_vehicle(car)

func _enter_vehicle(car: Node3D) -> void:
	_driving = true
	_current_car = car
	_foot_parent = get_parent()

	# Toujours tenté : eject_driver() vérifie lui-même has_npc_driver et ne
	# fait rien si cette voiture n'a pas/plus de conducteur (déjà volée avant).
	# Évite un double contrôle fragile (lecture dynamique de propriété ici en
	# plus de la vérification interne) qui pouvait faire rater l'éjection.
	if car.has_method("eject_driver"):
		car.eject_driver()   # fait apparaître le PNJ conducteur qui court se mettre à l'abri

	# coupe la physique / le visuel piéton
	velocity = Vector3.ZERO
	($CollisionShape3D as CollisionShape3D).set_deferred("disabled", true)
	collision_layer = 0
	collision_mask = 0
	if model != null:
		model.visible = false

	# assoit le joueur sur le siège -> la SpringArm (enfant du Player) suit la voiture
	var seat: Node3D = car.get_node("DriverSeat")
	reparent(seat, false)
	transform = Transform3D.IDENTITY
	_free_look = false
	_free_look_returning = false
	spring_arm.rotation.x = deg_to_rad(-18)
	spring_arm.rotation.y = 0.0
	spring_arm.spring_length = DRIVE_SPRING_LENGTH

	car.start_drive()

func _exit_vehicle() -> void:
	var car := _current_car
	if car == null:
		_driving = false
		return
	var car_yaw: float = car.global_rotation.y
	car.stop_drive()

	var exit_pos: Vector3 = (car.get_node("ExitPoint") as Node3D).global_position
	reparent(_foot_parent, false)
	# à côté de la portière ; y fixe raisonnable (le perso retombe au sol)
	global_position = Vector3(exit_pos.x, 1.3, exit_pos.z)
	rotation = Vector3(0, car_yaw, 0)   # face au même cap que la voiture

	($CollisionShape3D as CollisionShape3D).set_deferred("disabled", false)
	collision_layer = 1
	collision_mask = 7
	if model != null:
		model.visible = true
	velocity = Vector3.ZERO
	_free_look = false
	_free_look_returning = false
	spring_arm.rotation.x = deg_to_rad(-10)
	spring_arm.rotation.y = 0.0
	spring_arm.spring_length = FOOT_SPRING_LENGTH

	_driving = false
	_current_car = null

func _update_drive_camera(delta: float) -> void:
	if _current_car == null:
		return
	var sp := 0.0
	if _current_car.has_method("get_drive_speed"):
		sp = absf(_current_car.get_drive_speed())
	var t := clampf(sp / 24.0, 0.0, 1.0)   # 24 = DRIVE_MAX_SPEED de Car.gd
	var target_len := DRIVE_SPRING_LENGTH + t * DRIVE_ZOOM_EXTRA
	spring_arm.spring_length = lerpf(spring_arm.spring_length, target_len, clampf(delta * 3.0, 0.0, 1.0))
