extends Node3D

# Véhicules EN STATIONNEMENT des lieux : voitures de patrouille du Central Precinct, ambulances du
# St. Anselm, camions des quatre casernes du centre-ville, voitures du parking de l'aéroport.
#
# POURQUOI CE NŒUD EXISTE. Jusqu'au 2026-09-20 ces véhicules étaient CUITS EN DÉCOR : leur maillage
# était fusionné dans celui du lieu et leur collision était une boîte du lieu. Ils n'étaient donc pas
# des véhicules du tout — une voiture de police devant le commissariat était un morceau de bâtiment,
# impossible à ouvrir, à voler ou à allumer. Les cuissons écrivent maintenant une FICHE par véhicule
# (modèle, position, cap) et c'est ici qu'on instancie une VRAIE Car : même scène, même catalogue,
# même zone d'interaction, donc même façon de monter dedans que pour n'importe quelle voiture de la
# rue. Le rôle du catalogue suit avec, et c'est ce qui donne son gyrophare à la voiture de patrouille
# — éteint par défaut, comme tous les autres.
#
# Elles ne roulent pas : on ne leur donne AUCUN trajet (`setup()` n'est jamais appelé), et `park()`
# les met dans l'état « laissée là », le seul qui laisse la gravité les poser au sol quand elles
# n'ont pas de trajet. Elles ne disparaissent pas non plus : le compte à rebours d'abandon n'est armé
# que lorsque le joueur les quitte, exactement comme une voiture de la rue.
#
# EFFET DE BORD TRAITÉ : LoopSpawner plafonnait la circulation en comptant TOUT le groupe `vehicle`.
# Ces véhicules-là en font partie et sont présents en permanence : les compter revenait à retirer
# autant de voitures à la circulation de fond. LoopSpawner ne compte plus que ses propres enfants.

const CAR := preload("res://scenes/vehicles/Car.tscn")
const PLACES_JSON := "res://scenes/world/map/generated/places/places.json"
const DOWNTOWN_JSON := "res://scenes/world/downtown/generated/parked.json"
# Lâchées un peu au-dessus du sol relevé à la cuisson : la caisse se pose d'elle-même à la bonne
# hauteur au lieu de dépendre d'un décalage par modèle. 0,60 m suffit pour tous les gabarits du
# catalogue, camion de pompiers compris.
const DROP := 0.60

@export var enabled := true

var _poses := 0
var _manquants := 0


func _ready() -> void:
	if not enabled:
		return
	for chemin in [PLACES_JSON, DOWNTOWN_JSON]:
		if not FileAccess.file_exists(chemin):
			push_warning("ParkedVehicles : %s absent, cuisson à relancer" % chemin)
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(chemin))
		if typeof(data) != TYPE_DICTIONARY or not data.has("parked"):
			continue
		for fiche: Dictionary in data["parked"]:
			_poser(fiche)
	print("PARKED_VEHICLES %d véhicule(s) en stationnement, %d modèle(s) introuvable(s)" % [_poses, _manquants])


func _poser(fiche: Dictionary) -> void:
	var modele := String(fiche.get("model", ""))
	if modele == "" or not ResourceLoader.exists(modele):
		_manquants += 1
		return
	var pos: Array = fiche.get("pos", [0, 0, 0])
	var car := CAR.instantiate()
	# avant add_child : Car._ready lit forced_model_path pour charger le modèle et ses réglages
	car.forced_model_path = modele
	car.name = "Gare_%s_%d" % [String(fiche.get("place", "lieu")), _poses]
	add_child(car)
	# Le cap enregistré est celui du MODÈLE BRUT. Une Car tourne sa caisse de rotation.y et son modèle
	# de model_yaw_deg par-dessus (180° pour tout le catalogue city_*) : on retire donc ce lacet, sinon
	# chaque véhicule garé regarde à l'opposé de ce que la cuisson avait posé.
	car.global_position = Vector3(float(pos[0]), float(pos[1]) + DROP, float(pos[2]))
	car.rotation.y = float(fiche.get("yaw", 0.0)) - deg_to_rad(float(car.model_yaw_deg))
	if car.has_method("park"):
		car.park()
	_poses += 1
