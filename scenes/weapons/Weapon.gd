extends Node3D

# Modèle d'arme RÉEL (assets/weapon_models/) chargé au runtime.
#
# Calage dans la main : PLUS de nombres magiques. Un Marker3D "GripPoint" est
# posé à l'endroit où la main serre la crosse ; Player._apply_weapon_pose()
# place ensuite l'arme pour que GripPoint coïncide avec l'origine de l'os
# RightHand (cf. Player.gd). weapon_hand_offset/rotation ne servent plus que de
# petit correctif résiduel.
#
# GÉOMÉTRIE relevée dans Pistol_1.fbx (bornes des 580 sommets, repère mesh brut) :
#   X : -0.34 .. 1.48  -> AXE DU CANON, bouche vers +X
#   Z : -0.41 .. 0.75  -> VERTICAL, haut du slide vers +Z, bas de la crosse -Z
#   Y : -0.16 .. 0.16  -> épaisseur
# L'origine du mesh est vers l'arrière/haut de la crosse.

const WEAPON_MODEL := "res://assets/weapon_models/Pistol_1.fbx"

# Pistol_1.fbx rendu ≈ taille du perso à l'échelle 1.0 -> /10.
@export var model_scale := 0.1
# Orientation : gérée par la base du node GripPoint (dans Weapon.tscn). On ne
# tourne plus le modèle ici. Laissé exposé au cas où.
@export var model_rotation_deg := Vector3.ZERO
@export var model_offset := Vector3.ZERO

# Position ESTIMÉE de la prise en main, en unités MESH brutes (voir bornes
# ci-dessus). À affiner : la main serre l'arrière de l'arme, sous le slide.
@export var grip_mesh_pos := Vector3(-0.05, 0.0, -0.16)
# Bout du canon, unités MESH brutes (X max, ~centre du slide en hauteur).
@export var muzzle_mesh_pos := Vector3(1.48, 0.0, 0.30)

var _model: Node3D
@onready var _grip: Marker3D = $GripPoint
@onready var _muzzle: Marker3D = $MuzzlePoint

func _ready() -> void:
	var scene := load(WEAPON_MODEL) as PackedScene
	if scene == null:
		push_warning("Weapon : modèle introuvable " + WEAPON_MODEL)
		return
	_model = scene.instantiate() as Node3D
	add_child(_model)
	_model.name = "Model"
	_model.scale *= model_scale
	_model.rotation_degrees = model_rotation_deg
	_model.position = model_offset

	# GripPoint / MuzzlePoint : les repères sont AUTHORÉS en unités mesh dans
	# Weapon.tscn (à model_scale = 0.1). On repositionne ici selon le vrai
	# model_scale pour rester juste s'il change ; la BASE (orientation) posée
	# dans le .tscn est conservée.
	_grip.position = grip_mesh_pos * model_scale
	_muzzle.position = muzzle_mesh_pos * model_scale

# Transform rigide du point de prise, dans le repère de ce node "Weapon".
func grip_transform() -> Transform3D:
	return _grip.transform
