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

# PIÈGE GDSCRIPT, payé le 2026-09-20 : `bool(x)` N'ACCEPTE PAS `null`. Or `get("prop")` rend `null`
# quand la propriété n'existe pas, et les DEUX voitures du jeu ne déclarent pas les mêmes : `Car` a
# `driven_by_player`, `PlayerCarPhysics` a `Controlled`. `bool(body.get("Controlled"))` sur une Car
# levait donc « Nonexistent 'bool' constructor » à CHAQUE IMAGE, et l'erreur en cours de dispatch
# d'entrée cassait la propagation : le [E] au comptoir des boutiques n'ouvrait plus leur panneau,
# à l'autre bout du jeu. On compare donc à `true`, qui accepte `null`.
const Parts := preload("res://scenes/world/VehicleLightParts.gd")
const OPTIC_MATERIAL := "res://scenes/world/vehicle_optic_material.tres"
const BRAKE_MATERIAL := "res://scenes/world/vehicle_brake_material.tres"
const TAIL_MATERIAL := "res://scenes/world/vehicle_tail_material.tres"
# Un matériau par ÉTAT, jamais par véhicule. L'ordre est celui des indices utilisés partout ici.
const GYRO_ROUGE := 0
const GYRO_BLEU := 1
const GYRO_ETEINT := 2
const GYRO_BLANC := 3
const GYRO_AMBRE := 4
const GYRO_MATERIALS := ["res://scenes/world/vehicle_gyro_rouge_material.tres",
		"res://scenes/world/vehicle_gyro_bleu_material.tres",
		"res://scenes/world/vehicle_gyro_eteint_material.tres",
		"res://scenes/world/vehicle_gyro_blanc_material.tres",
		"res://scenes/world/vehicle_gyro_ambre_material.tres"]
const CATALOGUE := "res://resources/vehicle_models"

# RYTHME ET COULEURS, calés sur une vraie rampe américaine moderne :
#
#  - la rampe est COUPÉE EN DEUX et les deux moitiés ALTERNENT : elles ne clignotent jamais ensemble.
#    Sur une voiture de police la moitié gauche est ROUGE, la droite BLEUE ; sur une ambulance et un
#    camion de pompiers, rouge et BLANC.
#  - chaque phase porte un DOUBLE ÉCLAT : allumé, éteint, allumé, éteint. C'est ce battement rapide
#    qui fait le rendu moderne ; une moitié allumée d'un trait fait gyrophare des années 70.
#  - l'AMBRE ne sert qu'à l'ARRIÈRE des camions de pompiers, pour dévier la circulation. Il n'est
#    jamais mêlé au rouge et bleu, et aucune voiture de police n'en porte.
#
# Huit temps de 0,125 s, soit une période d'une seconde : deux éclats par seconde et par moitié.
# TOUT LE MONDE SUR LA MÊME PHASE, sur l'horloge du moteur et non sur un compteur par véhicule :
# c'est ce qui permet cinq matériaux pour toute la ville au lieu d'un par voiture.
const GYRO_PERIODE := 1.0
const GYRO_TEMPS_N := 8
const GYRO_GAUCHE := [true, false, true, false, false, false, false, false]
const GYRO_DROITE := [false, false, false, false, true, false, true, false]
const GYRO_AMBRE_T := [true, false, true, false, true, false, true, false]

# GYROPHARES ÉTEINTS PAR DÉFAUT. Ils s'allumeront sur événement (meurtre, incendie, crime) ; le
# déclencheur est prêt — `allumer_urgences()` et `set_gyro()` — mais le système d'événements n'est
# pas construit. En attendant, le joueur qui conduit un véhicule d'urgence bascule avec R.
@export var gyro_par_defaut := false

# LE GYROPHARE DOIT ÉCLAIRER LE DÉCOR, pas seulement briller sur le véhicule : murs, sol, PNJ. Un
# bassin BORNÉ d'OmniLight3D (une source qui envoie dans toutes les directions, ce qu'est un
# gyrophare) se pose sur les véhicules allumés, LE JOUEUR D'ABORD. Sans borne, une ville en alerte
# ferait autant de sources que de véhicules d'urgence.
@export var bassin_gyro := 3
const GYRO_LIGHT_RANGE := 16.0
const GYRO_LIGHT_ENERGY := 6.0

# Rôles qui portent un gyrophare : sur une voiture civile, la peinture du toit passerait le test de
# couleur et on allumerait un toit. Sert dès l'extraction.
const ROLES_URGENCE := ["police", "emergency", "swat"]

@export var enabled := true
@export var portee := 260.0              # au-delà, une optique fait moins d'un pixel
@export var vraies_lumieres := true
@export var bassin := 6                  # paires de phares réellement éclairantes (12 SpotLight3D)
# Fige le gyrophare sur un état, pour la capture : sans ça l'éclat ne dure que 0,20 s et on ne
# photographie pas la couleur qu'on veut. -1 = il clignote normalement. N'a d'effet que sur l'image.
@export var gyro_force := -1

# Réglages des spots, calés sur la géométrie : optique à ~0,6 m du sol, on veut poser une vraie
# flaque sur la chaussée devant la voiture sans écraser le premier plan.
const SPOT_ANGLE := 30.0
const SPOT_RANGE := 30.0
const SPOT_ENERGY := 5.0
const SPOT_COLOR := Color(1.00, 0.97, 0.89)
const SPOT_TILT := 0.16                  # plongée du cône vers la route
const SPOT_AVANCE := 0.15                # m devant le nez, pour ne pas éclairer sa propre carrosserie

# FEUX DE POSITION ET DE FREINAGE, deux niveaux sur la MÊME géométrie d'optique arrière :
#   - la nuit, tout véhicule roulant a ses feux rouges allumés en permanence (matériau `position`) ;
#   - dès qu'il freine, il passe au matériau `freinage`, deux fois plus lumineux.
# Un véhicule est dans UN seul des deux états : les deux calques dessinent les mêmes triangles au
# même endroit, les poser ensemble ferait un combat en z. D'où deux listes disjointes.
#
# LE FREINAGE ÉCLAIRE LE SOL. Un bassin BORNÉ de SpotLight3D rouges, dirigés vers l'arrière et vers
# le bas, se pose sur les véhicules qui freinent — LE JOUEUR D'ABORD. Même raison que partout
# ailleurs : 252 voitures x 1 lumière de frein seraient 252 sources dans la passe d'ombrage.
@export var bassin_frein := 4
const FREIN_ANGLE := 48.0
const FREIN_RANGE := 9.0
const FREIN_ENERGY := 3.0
const FREIN_COLOR := Color(1.00, 0.10, 0.06)
const FREIN_RECUL := 0.25                # m derrière la poupe
const FREIN_PLONGEE := 0.55              # le cône regarde vers l'arrière ET vers le bas

var _night := 0.0
var _material: StandardMaterial3D
var _mat_frein: StandardMaterial3D
var _mat_position: StandardMaterial3D
var _spots_frein: Array[SpotLight3D] = []
var _mats_gyro: Array = []
var _roles := {}                         # chemin de modèle -> rôle du catalogue
var _gyro_etat := -1
var _gyros_allumes := {}                 # id d'instance -> true, pour les véhicules dont la rampe tourne
var _omnis_gyro: Array[OmniLight3D] = []
var _par_modele := {}                    # chemin de modèle -> {"mm": MultiMeshInstance3D, "n": int}
var _spots: Array[SpotLight3D] = []
var _modeles_dessines := 0
var _optiques := 0


func _ready() -> void:
	if not enabled:
		return
	_material = load(OPTIC_MATERIAL)
	_mat_frein = load(BRAKE_MATERIAL)
	_mat_position = load(TAIL_MATERIAL)
	for m in GYRO_MATERIALS:
		_mats_gyro.append(load(m))
	_lire_roles()
	var cycle := get_parent().get_node_or_null("DayNight") if get_parent() != null else null
	if cycle != null:
		cycle.hour_changed.connect(_on_hour_changed)
		_apply_night(cycle.night_factor())
	else:
		_apply_night(1.0)
	print("VEHICLE_LIGHTS pret, portee %.0f m, bassin %d paires de vrais phares" % [portee, bassin])


# Rôle de chaque modèle, lu une fois dans le catalogue : on n'extrait un gyrophare QUE sur les
# véhicules qui en portent un, sinon la peinture de toit d'une civile passerait le test de couleur.
func _lire_roles() -> void:
	var d := DirAccess.open(CATALOGUE)
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".tres"):
			var data = load(CATALOGUE.path_join(f))
			if data != null and not data.model_paths.is_empty():
				_roles[String(data.model_paths[0])] = str(data.role)
		f = d.get_next()


func _urgence(cle: String) -> bool:
	return String(_roles.get(cle, "")) in ["police", "emergency", "swat"]


func _on_hour_changed(_hour: float, night: float) -> void:
	if not is_equal_approx(night, _night):
		_apply_night(night)


func _apply_night(night: float) -> void:
	_night = night
	var allume := night > 0.0
	# un modèle sans optique repérable est mémorisé avec un calque nul : il ne faut pas le suivre
	for cle in _par_modele:
		for fam in _par_modele[cle]:
			var mi = _par_modele[cle][fam]
			if mi is MultiMeshInstance3D:
				(mi as MultiMeshInstance3D).visible = false
	for s in _spots:
		s.visible = allume
		s.light_energy = SPOT_ENERGY * night


func _process(_delta: float) -> void:
	# Pas de sortie sur la nuit : les FEUX DE FREINAGE servent surtout de jour, et les GYROPHARES
	# clignotent en permanence. Seuls les phares et les vrais spots suivent le crépuscule.
	if not enabled:
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
	var freinent := {}
	var position := {}
	var gyros := {}
	var candidats: Array = []
	var candidats_frein: Array = []
	var gyros_bodies: Array = []
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
		# Une voiture GAREE n'allume rien : ni phares, ni feux de position, ni vrai faisceau. Personne
		# n'est dedans. Sans ce filtre, les 22 vehicules en stationnement des lieux roulaient toute la
		# nuit phares allumes devant le commissariat, l'hopital et les casernes — vu a l'image le
		# 2026-09-20. Leur GYROPHARE, lui, reste pilotable : une voiture de patrouille garee dont la
		# rampe tourne est une situation normale.
		var gare: bool = body.has_method("is_parked") and body.call("is_parked")
		if not gare:
			if not par_modele.has(cle):
				par_modele[cle] = []
			par_modele[cle].append(racine)
		var freine: bool = body.has_method("brake_lights_on") and body.call("brake_lights_on")
		if freine:
			freinent[cle] = freinent.get(cle, []) + [racine]
			candidats_frein.append([d, body, racine])
		elif _night > 0.0 and not gare:
			# Feux de position : tout véhicule qui ROULE et ne freine pas, la nuit. Listes DISJOINTES,
			# sinon les deux calques dessinent les mêmes triangles au même endroit. Une voiture garée
			# est exclue : personne dedans, aucune raison que ses feux soient allumés.
			position[cle] = position.get(cle, []) + [racine]
		if _urgence(cle) and gyro_on(body):
			gyros[cle] = gyros.get(cle, []) + [racine]
			gyros_bodies.append([d, body, racine, cle])
		if not gare:
			candidats.append([d, body, racine])
	_modeles_dessines = 0
	_optiques = 0
	# un modèle sans optique repérable est mémorisé avec un calque nul : il ne faut pas le suivre
	for cle in _par_modele:
		for fam in _par_modele[cle]:
			var mi = _par_modele[cle][fam]
			if mi is MultiMeshInstance3D:
				(mi as MultiMeshInstance3D).visible = false
	# phares : seulement la nuit
	if _night > 0.0:
		for cle in par_modele:
			_poser(cle, par_modele[cle], "phares")
	# feux de freinage : de jour comme de nuit
	for cle in freinent:
		_poser(cle, freinent[cle], "feux")
	# feux de position : la nuit, sur les véhicules qui NE freinent pas
	for cle in position:
		_poser(cle, position[cle], "position")
	# GYROPHARES : seulement ceux qui sont ALLUMÉS, et tout le monde sur la MÊME phase.
	var temps: int = gyro_force if gyro_force >= 0 else int(fmod(Time.get_ticks_msec() * 0.001, GYRO_PERIODE) / (GYRO_PERIODE / GYRO_TEMPS_N))
	temps = clampi(temps, 0, GYRO_TEMPS_N - 1)
	_gyro_etat = temps
	for cle in gyros:
		var couleurs := _couleurs_gyro(cle)
		for cote: String in ["gyro_g", "gyro_d", "gyro_ar"]:
			var mi := _poser(cle, gyros[cle], cote)
			if mi == null:
				continue
			var allume: bool = (GYRO_GAUCHE[temps] if cote == "gyro_g"
					else (GYRO_DROITE[temps] if cote == "gyro_d" else GYRO_AMBRE_T[temps]))
			# on change le POINTEUR de matériau, jamais le matériau : cinq matériaux pour la ville
			mi.multimesh.mesh.surface_set_material(0, _mats_gyro[couleurs[cote] if allume else GYRO_ETEINT])
	_eclairer_gyros(gyros_bodies, temps)
	if vraies_lumieres and _night > 0.0:
		_eclairer(candidats)
	elif not _spots.is_empty():
		for s in _spots:
			s.visible = false
	if vraies_lumieres:
		_eclairer_freins(candidats_frein)
	elif not _spots_frein.is_empty():
		for s in _spots_frein:
			s.visible = false


# Pose les instances d'une famille pour un modèle. Rend le calque, ou null s'il n'existe pas.
func _poser(cle: String, racines: Array, fam: String) -> MultiMeshInstance3D:
	if racines.is_empty():
		return null
	var calque := _calque(cle, racines[0], fam)
	if calque == null:
		return null
	var mm := calque.multimesh
	if mm.instance_count < racines.size():
		mm.instance_count = racines.size()
	for i in racines.size():
		var xf := (racines[i] as Node3D).global_transform
		mm.set_instance_transform(i, xf)
	mm.visible_instance_count = racines.size()
	calque.visible = true
	_modeles_dessines += 1
	_optiques += racines.size()
	return calque


func _vider() -> void:
	# un modèle sans optique repérable est mémorisé avec un calque nul : il ne faut pas le suivre
	for cle in _par_modele:
		for fam in _par_modele[cle]:
			var mi = _par_modele[cle][fam]
			if mi is MultiMeshInstance3D:
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
func _calque(cle: String, racine: Node3D, fam: String) -> MultiMeshInstance3D:
	if not _par_modele.has(cle):
		var parts := Parts.extraire(racine, _urgence(cle))
		var entree := {}
		# « position » n'est pas une extraction de plus : c'est EXACTEMENT la géométrie de « feux »,
		# habillée du matériau de veilleuse. Deux calques, une seule découpe.
		for f in ["phares", "feux", "position", "gyro", "gyro_g", "gyro_d", "gyro_ar"]:
			var source: String = "feux" if f == "position" else f
			var mat: Material = _material
			if f == "feux":
				mat = _mat_frein
			elif f == "position":
				mat = _mat_position
			elif f.begins_with("gyro"):
				mat = _mats_gyro[GYRO_ETEINT]
			entree[f] = _instancier(cle, f, Parts.maillage(parts[source], mat))
		entree["gyro_centre"] = parts["gyro_centre"]
		_par_modele[cle] = entree
	return _par_modele[cle][fam]


# Un calque : un MultiMesh sur le maillage d'optiques du modèle. Rend null si le modèle n'a pas
# cette optique — le pack lowpoly n'a aucune couleur d'optique distincte, le bus pas de verre clair
# à l'avant, l'ambulance pas de rouge à l'arrière. Ceux-là restent éteints (cf. CLAUDE.md §6).
func _instancier(cle: String, fam: String, maille: ArrayMesh) -> MultiMeshInstance3D:
	if maille == null:
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = maille
	mm.instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = "%s_%s" % [fam, cle.get_file().get_basename()]
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# L'emprise d'un MultiMesh dont les instances bougent ne peut pas être devinée par le moteur :
	# sans ça il la calcule sur les transformations du moment et la circulation qui s'éloigne
	# disparaît d'un coup. On la fixe à la carte entière.
	mi.custom_aabb = AABB(Vector3(-2500, -50, -2500), Vector3(5000, 400, 5000))
	mi.visible = false
	add_child(mi)
	return mi


# Ce modèle porte-t-il cette famille d'optique ? Sert aux outils de capture, qui doivent cadrer sur
# un véhicule qui a vraiment le feu qu'on veut montrer.
func a_famille(body: Node3D, fam: String) -> bool:
	var cle := _cle(body)
	var racine := _racine_modele(body)
	if cle == "" or racine == null:
		return false
	return _calque(cle, racine, fam) != null


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


# Flaque rouge au sol derrière les véhicules qui freinent. Bassin BORNÉ, LE JOUEUR D'ABORD : c'est
# son propre freinage qu'il regarde, et il doit l'avoir quoi qu'il arrive. Le reste du bassin va aux
# véhicules les plus proches. Aucune ombre : une ombre par lumière ponctuelle est un rendu de scène
# complet par lumière.
func _eclairer_freins(candidats: Array) -> void:
	# LA FLAQUE NE SORT QUE LA NUIT. Les OPTIQUES, elles, s'allument de jour comme de nuit — c'est la
	# correction demandee. Mais un vrai feu de freinage n'eclaire pas la chaussee en plein soleil :
	# laisser la flaque de jour posait une tache rose sur l'asphalte derriere chaque voiture qui
	# ralentit, vu a l'image le 2026-09-20. Elle suit donc le facteur nuit, comme les phares.
	if _night <= 0.0:
		for l in _spots_frein:
			l.visible = false
		return
	if _spots_frein.is_empty():
		for i in bassin_frein:
			var l := SpotLight3D.new()
			l.name = "Frein_%d" % i
			l.spot_angle = FREIN_ANGLE
			l.spot_range = FREIN_RANGE
			l.spot_attenuation = 1.2
			l.light_color = FREIN_COLOR
			l.light_energy = FREIN_ENERGY
			l.shadow_enabled = false
			l.visible = false
			add_child(l)
			_spots_frein.append(l)
	# joueur en tête, puis du plus proche au plus loin
	candidats.sort_custom(func(a, b):
		var pa: bool = a[1].get("driven_by_player") == true or a[1].get("Controlled") == true
		var pb: bool = b[1].get("driven_by_player") == true or b[1].get("Controlled") == true
		if pa != pb:
			return pa
		return a[0] < b[0])
	for k in _spots_frein.size():
		if k >= candidats.size():
			_spots_frein[k].visible = false
			continue
		var racine: Node3D = candidats[k][2]
		var xf := racine.global_transform
		# l'avant du modèle est son +Z : la poupe est donc en -Z, et le cône regarde vers l'arrière
		var arriere := -xf.basis.z.normalized()
		var pos := xf.origin + arriere * FREIN_RECUL + Vector3(0, 0.55, 0)
		var l := _spots_frein[k]
		l.visible = true
		l.light_energy = FREIN_ENERGY * _night
		l.global_position = pos
		l.look_at(pos + arriere + Vector3(0, -FREIN_PLONGEE, 0), Vector3.UP)


# --- gyrophares : allumage, couleurs, éclairage du décor -------------------------------------------------------------

# Couleurs de la rampe selon CE QU'EST le véhicule, pas selon son nom de fichier seul : le rôle vient
# du catalogue (police, emergency, swat), et seul le camion de pompiers porte de l'ambre à l'arrière.
func _couleurs_gyro(cle: String) -> Dictionary:
	var role := String(_roles.get(cle, ""))
	if role == "police" or role == "swat":
		return {"gyro_g": GYRO_ROUGE, "gyro_d": GYRO_BLEU, "gyro_ar": GYRO_ROUGE}
	# urgences : rouge et blanc. L'ambre de l'arrière est réservé aux camions de pompiers.
	var ambre: int = GYRO_AMBRE if cle.to_lower().contains("fire") else GYRO_BLANC
	return {"gyro_g": GYRO_ROUGE, "gyro_d": GYRO_BLANC, "gyro_ar": ambre}


# Ce véhicule a-t-il sa rampe allumée ? Éteinte par défaut (cf. gyro_par_defaut).
func gyro_on(body: Node3D) -> bool:
	if body == null:
		return false
	return _gyros_allumes.get(body.get_instance_id(), gyro_par_defaut) == true


# Allume ou éteint la rampe d'UN véhicule. C'est le point d'entrée du futur système d'événements
# (meurtre, incendie, crime) : rien d'autre n'est à écrire côté éclairage.
func set_gyro(body: Node3D, on: bool) -> void:
	if body == null:
		return
	_gyros_allumes[body.get_instance_id()] = on


func toggle_gyro(body: Node3D) -> bool:
	var on := not gyro_on(body)
	set_gyro(body, on)
	return on


# Allume ou éteint TOUS les véhicules d'urgence présents. L'autre moitié du déclencheur : un
# événement de ville appellera ceci, le système d'événements lui-même n'est pas construit.
func allumer_urgences(on: bool) -> int:
	var n := 0
	for v in get_tree().get_nodes_in_group(&"vehicle"):
		var body := v as Node3D
		if body == null or not _urgence(_cle(body)):
			continue
		set_gyro(body, on)
		n += 1
	return n


# Le véhicule que le joueur conduit, s'il en conduit un. Les deux voitures du jeu ne le disent pas
# de la même façon : Car expose `driven_by_player`, PlayerCarPhysics expose `Controlled`.
func vehicule_du_joueur() -> Node3D:
	for v in get_tree().get_nodes_in_group(&"vehicle"):
		var body := v as Node3D
		if body == null or not body.is_inside_tree():
			continue
		if body.get("driven_by_player") == true or body.get("Controlled") == true:
			return body
	return null


# Touche R : bascule la rampe du véhicule d'urgence que le joueur conduit. Sans effet s'il est à
# pied ou au volant d'une voiture ordinaire — une berline civile n'a pas de gyrophare à allumer.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if (event as InputEventKey).keycode != KEY_R:
		return
	var body := vehicule_du_joueur()
	if body == null or not _urgence(_cle(body)):
		return
	print("VEHICLE_LIGHTS gyrophare %s sur %s" % ["ALLUMÉ" if toggle_gyro(body) else "éteint", _cle(body).get_file()])


# Le gyrophare éclaire le décor. OmniLight3D et non SpotLight3D : une rampe envoie dans toutes les
# directions, c'est ce qui fait battre les murs et le sol autour d'elle. Bassin BORNÉ, joueur
# d'abord. Aucune ombre : une ombre par lumière ponctuelle est un rendu de scène complet par lumière.
func _eclairer_gyros(candidats: Array, temps: int) -> void:
	if not vraies_lumieres:
		for l in _omnis_gyro:
			l.visible = false
		return
	if _omnis_gyro.is_empty():
		for i in bassin_gyro:
			var l := OmniLight3D.new()
			l.name = "Gyro_%d" % i
			l.omni_range = GYRO_LIGHT_RANGE
			l.light_energy = GYRO_LIGHT_ENERGY
			l.shadow_enabled = false
			l.visible = false
			add_child(l)
			_omnis_gyro.append(l)
	candidats.sort_custom(func(a, b):
		var pa: bool = a[1].get("driven_by_player") == true or a[1].get("Controlled") == true
		var pb: bool = b[1].get("driven_by_player") == true or b[1].get("Controlled") == true
		if pa != pb:
			return pa
		return a[0] < b[0])
	for k in _omnis_gyro.size():
		var l := _omnis_gyro[k]
		if k >= candidats.size():
			l.visible = false
			continue
		# la lumière suit la MÊME phase que la rampe : elle s'éteint sur les temps morts, et c'est ce
		# battement-là qu'on voit courir sur les façades
		var gauche: bool = GYRO_GAUCHE[temps]
		var droite: bool = GYRO_DROITE[temps]
		if not (gauche or droite):
			l.visible = false
			continue
		var cle := String(candidats[k][3])
		var couleurs := _couleurs_gyro(cle)
		var mat := _mats_gyro[couleurs["gyro_g"] if gauche else couleurs["gyro_d"]] as StandardMaterial3D
		var racine: Node3D = candidats[k][2]
		var entree = _par_modele.get(cle)
		var centre: Vector3 = (entree["gyro_centre"] as Vector3) if entree != null and entree.has("gyro_centre") else Vector3(0, 1.4, 0)
		l.visible = true
		l.global_position = racine.global_transform * centre
		l.light_color = mat.albedo_color if mat != null else Color.RED
