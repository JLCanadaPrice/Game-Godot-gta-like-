extends Node3D

# Phares des véhicules (chantier jour/nuit). Allumés la nuit, éteints le jour, pilotés par le même
# signal `hour_changed` que les lampadaires et les fenêtres.
#
# ON ALLUME LA GÉOMÉTRIE DU MODÈLE, on n'ajoute rien par-dessus. VehicleLightParts extrait du
# maillage de chaque modèle les triangles qui SONT déjà les optiques — repérés par la couleur de
# palette qu'ils échantillonnent ET par leur position sur la caisse, les deux étant nécessaires (la
# couleur seule confond un phare avec une vitre, la position seule confond une optique avec la
# tôle). Ces triangles-là sont redessinés par-dessus eux-mêmes avec le matériau allumé.
#
# DEUX NIVEAUX, volontairement séparés parce qu'ils n'ont pas du tout le même coût :
#
#  1. L'ÉMISSION, sur tous les véhicules proches. Les optiques d'un MÊME MODÈLE tiennent dans un
#     MultiMesh — même géométrie, même matériau — donc UN appel de dessin par modèle visible, pas
#     par voiture. À 252 voitures tirées dans 72 modèles, seuls les modèles réellement présents à
#     l'écran coûtent quelque chose.
#  2. DE VRAIES LUMIÈRES, un bassin BORNÉ de SpotLight3D qui éclairent réellement la route, repris
#     du bassin de StreetLights. Le joueur est prioritaire, puis les véhicules les plus proches. Une
#     lumière n'ajoute aucun appel de dessin mais coûte dans la passe d'ombrage : 252 voitures x 2
#     seraient 504 sources, ce qu'on ne peut pas se permettre sur l'UHD 750.

const Parts := preload("res://scenes/world/VehicleLightParts.gd")
const OPTIC_MATERIAL := "res://scenes/world/vehicle_optic_material.tres"

# Rôles qui portent un gyrophare : sur une voiture civile, la peinture du toit passerait le test de
# couleur et on allumerait un toit. Sert dès l'extraction.
const ROLES_URGENCE := ["police", "emergency", "swat"]

@export var enabled := true
@export var portee := 260.0              # au-delà, une optique fait moins d'un pixel
@export var vraies_lumieres := true
@export var bassin := 6                  # paires de phares réellement éclairantes (12 SpotLight3D)

# Réglages des spots, calés sur la géométrie : optique à ~0,6 m du sol, on veut poser une vraie
# flaque sur la chaussée devant la voiture sans écraser le premier plan.
const SPOT_ANGLE := 30.0
const SPOT_RANGE := 30.0
const SPOT_ENERGY := 5.0
const SPOT_COLOR := Color(1.00, 0.97, 0.89)
const SPOT_TILT := 0.16                  # plongée du cône vers la route
const SPOT_AVANCE := 0.15                # m devant le nez, pour ne pas éclairer sa propre carrosserie

var _night := 0.0
var _material: StandardMaterial3D
var _par_modele := {}                    # chemin de modèle -> {"mm": MultiMeshInstance3D, "n": int}
var _spots: Array[SpotLight3D] = []
var _modeles_dessines := 0
var _optiques := 0


func _ready() -> void:
	if not enabled:
		return
	_material = load(OPTIC_MATERIAL)
	var cycle := get_parent().get_node_or_null("DayNight") if get_parent() != null else null
	if cycle != null:
		cycle.hour_changed.connect(_on_hour_changed)
		_apply_night(cycle.night_factor())
	else:
		_apply_night(1.0)
	print("VEHICLE_LIGHTS pret, portee %.0f m, bassin %d paires de vrais phares" % [portee, bassin])


func _on_hour_changed(_hour: float, night: float) -> void:
	if not is_equal_approx(night, _night):
		_apply_night(night)


func _apply_night(night: float) -> void:
	_night = night
	var allume := night > 0.0
	# un modèle sans optique repérable est mémorisé avec un calque nul : il ne faut pas le suivre
	for cle in _par_modele:
		var mi = _par_modele[cle]["mm"]
		if mi != null:
			(mi as MultiMeshInstance3D).visible = false
	for s in _spots:
		s.visible = allume
		s.light_energy = SPOT_ENERGY * night


func _process(_delta: float) -> void:
	if not enabled or _night <= 0.0:
		_vider()
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var oeil := cam.global_position
	var portee2 := portee * portee
	# regroupement par MODÈLE : c'est la condition du MultiMesh, une instance ne peut porter qu'un
	# seul maillage et chaque modèle a ses propres optiques
	var par_modele := {}
	var candidats: Array = []
	for v in get_tree().get_nodes_in_group(&"vehicle"):
		var body := v as Node3D
		if body == null or not body.is_inside_tree() or not body.visible:
			continue
		var d := body.global_position.distance_squared_to(oeil)
		if d > portee2:
			continue
		var racine := _racine_modele(body)
		if racine == null:
			continue
		var cle := _cle(body)
		if cle == "":
			continue
		if not par_modele.has(cle):
			par_modele[cle] = []
		par_modele[cle].append(racine)
		candidats.append([d, body, racine])
	_modeles_dessines = 0
	_optiques = 0
	# un modèle sans optique repérable est mémorisé avec un calque nul : il ne faut pas le suivre
	for cle in _par_modele:
		var mi = _par_modele[cle]["mm"]
		if mi != null:
			(mi as MultiMeshInstance3D).visible = false
	for cle in par_modele:
		var racines: Array = par_modele[cle]
		var calque := _calque(cle, racines[0])
		if calque == null:
			continue
		var mm := calque.multimesh
		if mm.instance_count < racines.size():
			mm.instance_count = racines.size()
		for i in racines.size():
			mm.set_instance_transform(i, (racines[i] as Node3D).global_transform)
		mm.visible_instance_count = racines.size()
		calque.visible = true
		_modeles_dessines += 1
		_optiques += racines.size()
	if vraies_lumieres:
		_eclairer(candidats)


func _vider() -> void:
	# un modèle sans optique repérable est mémorisé avec un calque nul : il ne faut pas le suivre
	for cle in _par_modele:
		var mi = _par_modele[cle]["mm"]
		if mi != null:
			(mi as MultiMeshInstance3D).visible = false
	for s in _spots:
		s.visible = false


# Clé de regroupement : le modèle tiré par Car dans le catalogue. Sans elle les 72 modèles
# partageraient les optiques du premier rencontré.
func _cle(body: Node3D) -> String:
	var m = body.get("model_path")
	if m != null and String(m) != "":
		return String(m)
	return body.scene_file_path if body.scene_file_path != "" else String(body.name)


# Le noeud qui porte le modèle : c'est SA transformation qui place les optiques, parce qu'il porte
# l'échelle du catalogue, le demi-tour de model_yaw_deg et le décalage vertical.
func _racine_modele(body: Node3D) -> Node3D:
	var m = body.get("_model")
	if m != null and m is Node3D:
		return m as Node3D
	for c in body.get_children():
		if c is Node3D and (c as Node3D).find_children("*", "MeshInstance3D", true, false).size() > 0:
			return c as Node3D
	return null


# Calque d'un modèle : extraction des optiques à la première rencontre, puis réutilisation. Rend
# null si le modèle n'a aucune optique repérable — bus sans phare de verre clair, pack lowpoly dont
# toutes les pièces sont grises : ceux-là restent éteints, comme convenu.
func _calque(cle: String, racine: Node3D) -> MultiMeshInstance3D:
	if _par_modele.has(cle):
		return _par_modele[cle]["mm"]
	var parts := Parts.extraire(racine, false)
	var maille := Parts.maillage(parts["phares"], _material)
	if maille == null:
		_par_modele[cle] = {"mm": null}
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = maille
	mm.instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = "Optics_" + cle.get_file().get_basename()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# L'emprise d'un MultiMesh dont les instances bougent ne peut pas être devinée par le moteur :
	# sans ça il la calcule sur les transformations du moment et la circulation qui s'éloigne
	# disparaît d'un coup. On la fixe à la carte entière.
	mi.custom_aabb = AABB(Vector3(-2500, -50, -2500), Vector3(5000, 400, 5000))
	mi.visible = false
	add_child(mi)
	_par_modele[cle] = {"mm": mi}
	return mi


# Bassin borné de vrais phares. Joueur d'abord, puis les plus proches de la caméra.
func _eclairer(candidats: Array) -> void:
	candidats.sort_custom(func(a, b):
		var pa: bool = a[1].has_method("is_occupied") and a[1].call("is_occupied")
		var pb: bool = b[1].has_method("is_occupied") and b[1].call("is_occupied")
		if pa != pb:
			return pa
		return a[0] < b[0])
	var vises: int = mini(bassin, candidats.size())
	while _spots.size() < vises * 2:
		var l := SpotLight3D.new()
		l.spot_angle = SPOT_ANGLE
		l.spot_range = SPOT_RANGE
		l.light_color = SPOT_COLOR
		l.shadow_enabled = false   # l'ombre portée de 12 phares doublerait le coût pour rien
		add_child(l)
		_spots.append(l)
	for i in _spots.size():
		var paire := i / 2
		if paire >= vises:
			_spots[i].visible = false
			continue
		var racine: Node3D = candidats[paire][2]
		var info := Parts.caisse(racine)
		var boite: AABB = info["aabb"]
		if boite.size.z <= 0.0:
			_spots[i].visible = false
			continue
		var xf := racine.global_transform
		# l'avant du modèle est son +Z ; les optiques sont à mi-hauteur, écartées de l'axe
		var z := boite.end.z + SPOT_AVANCE
		var y := boite.position.y + boite.size.y * 0.42
		var dx := boite.size.x * 0.5 * 0.62 * (-1.0 if i % 2 == 0 else 1.0)
		var cx := boite.get_center().x
		var l := _spots[i]
		l.visible = true
		l.light_energy = SPOT_ENERGY * _night
		l.global_position = xf * Vector3(cx + dx, y, z)
		var avant: Vector3 = (xf.basis * Vector3(0, 0, 1)).normalized()
		l.look_at(l.global_position + avant - Vector3(0, SPOT_TILT, 0), Vector3.UP)
