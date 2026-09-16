class_name ApartmentData
extends Resource

# Définition statique d'un bien achetable à l'agence immobilière (un .tres
# par bien, sous resources/apartments/), même convention que CarData/
# BuildingData. Résidence PERSONNELLE du joueur -- pas d'équivalent
# passive_income comme BuildingData, ce n'est pas un investissement.
# world_position : inutilisé pour l'instant (pas de lieu visitable en V1),
# prêt pour la future téléportation sans retravailler la structure.

@export var id: String
@export var display_name: String
@export var neighborhood: String
@export var price: int
@export var world_position: Vector3 = Vector3.ZERO

# Coquille d'intérieur (assets/apartments/shells) : même empreinte au sol que le bâtiment city_kit
# correspondant -- Small = Building_Small_1, Medium = Building_Medium_2_001, Large = Building_Large_2.
@export_enum("Small", "Medium", "Large") var shell_size: String = "Small"

const SHELL_DIR := "res://assets/apartments/shells/"

func shell_path() -> String:
	return SHELL_DIR + "Apartment_%s_Shell.glb" % shell_size

func ceiling_path() -> String:
	return SHELL_DIR + "Apartment_%s_Ceiling.glb" % shell_size
