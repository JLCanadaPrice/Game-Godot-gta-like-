extends "res://scenes/buildings/Building.gd"

# Immeuble haut achetable : même comportement que Building (zone Area3D + panneau
# d'achat), mais la hauteur du volume est pilotée par `tower_height`. Une seule
# scène couvre toutes les tailles ; on redimensionne le mesh et les collisions
# par transformation de noeud (pas de mutation des ressources partagées).

const BASE_MESH_H := 4.0    # hauteur du BoxMesh de la scène
const BASE_SOLID_H := 4.0   # hauteur du BoxShape solide
const BASE_ZONE_H := 5.0    # hauteur du BoxShape de détection

@export var tower_height: float = 20.0

func _ready() -> void:
	_apply_height()
	super._ready()

func _apply_height() -> void:
	# Une fois BuildingKitBaker a figé un vrai modèle ("KitModel", nombre
	# d'étages fixe), le stretch runtime ci-dessous ne doit plus s'appliquer :
	# il déformerait la collision fraîchement ajustée à l'AABB du modèle bake.
	# tower_height ne sert alors plus qu'à choisir le modèle au moment du bake.
	if has_node("KitModel"):
		return
	var h: float = maxf(tower_height, BASE_MESH_H)

	var mesh_node: MeshInstance3D = $MeshInstance3D
	mesh_node.scale = Vector3(1.0, h / BASE_MESH_H, 1.0)
	mesh_node.position.y = h * 0.5

	var solid: CollisionShape3D = $StaticBody3D/CollisionShape3D
	solid.scale = Vector3(1.0, h / BASE_SOLID_H, 1.0)
	solid.position.y = h * 0.5

	# Zone d'achat : hauteur = immeuble + marge, empreinte au sol inchangée.
	var zone: CollisionShape3D = $CollisionShape3D
	zone.scale = Vector3(1.0, (h + 4.0) / BASE_ZONE_H, 1.0)
	zone.position.y = h * 0.5

	# Panneau d'achat au niveau de l'entrée (pas au sommet de la tour).
	$InteractPrompt.position.y = 4.0
