extends Node

# Captures fenêtrées de la carte 3D (pas headless : le rendu compte) : vues fixes, image PNG et compteurs de rendu
# indépendants du GPU (appels de dessin, objets, primitives) par vue. Spawners coupés.
# Sert au contrôle visuel des étapes et à suivre le budget de rendu ; les FPS de la machine de travail ne disent rien
# de la machine de référence (Intel UHD 750), les compteurs si.
#
# Lancer : Godot --path <projet> --resolution 1152x648 res://scenes/tests/MapShotsTest.tscn -- --out=<dossier> [--views=nom1,nom2]

const WORLD := preload("res://scenes/world/World.tscn")
# [nom, position caméra, point visé]
const VIEWS := [
	["survol_centre_vers_nord_ouest", Vector3(150, 320, 250), Vector3(-900, 0, -500)],
	["rue_ouest_vers_riviere", Vector3(-935, 1.8, -178), Vector3(-1300, 2, -178)],
	["collines_nord_ouest_vers_centre", Vector3(-1150, 45, -1150), Vector3(-460, 10, -172)],
	["riviere_vers_nord", Vector3(-1120, 3, 60), Vector3(-1230, 2, -700)],
	["campagne_est_vers_ouest", Vector3(1600, 25, -420), Vector3(900, 5, -300)],
	["aeroport_plateau", Vector3(300, 40, -800), Vector3(700, 5, -1200)],
	["echangeur_nord_ouest", Vector3(-500, 95, -520), Vector3(-700, 0, -700)],
	["pont_autoroute_nord", Vector3(-1030, 22, -610), Vector3(-1250, 5, -700)],
	["voie_express_ouest", Vector3(-985, 14, -40), Vector3(-1028, 0, -320)],
	["echangeur_sud_ouest", Vector3(-230, 85, 600), Vector3(-380, 0, 770)],
	["tunnel_sud", Vector3(-322, 9, 870), Vector3(-328, 2, 1010)],
	["echangeur_nord_est", Vector3(860, 95, -420), Vector3(1050, 0, -596)],
	["bretelles_tranchee_est", Vector3(850, 18, -575), Vector3(905, -4, -640)],
	["artere_pont_riviere", Vector3(-1070, 12, -150), Vector3(-1250, 4, -175)],
	["carrefour_willow_lake", Vector3(-1535, 28, -130), Vector3(-1578, 10, -172)],
	["rond_point_echo", Vector3(175, 45, -255), Vector3(110, 0, -316)],
	["losange_aeroport", Vector3(170, 60, -560), Vector3(60, 0, -700)],
	["entree_ouest_centre_ville", Vector3(-1000, 10, -195), Vector3(-892, 1, -172)],
	["lampadaires_artere_urbaine", Vector3(-1606, 18, -8), Vector3(-1624, 8, -80)],
	["lampadaires_echangeur", Vector3(-330, 22, 690), Vector3(-380, 8, 770)],
	# étape 4 : quartiers ("sol" : hauteurs mesurées depuis le sol sous la caméra et sous le point visé)
	["quartier_eastside_artere", Vector3(160, 2.2, -312), Vector3(460, 2, -305)],
	["quartier_railyard_survol", Vector3(-150, 80, 700), Vector3(-380, 0, 400)],
	["quartier_westbank_rue", Vector3(-1255.2, 1.7, 165.9), Vector3(-1245.6, 1.5, 265.4), "sol"],
	["quartier_willow_lake_survol", Vector3(-1350, 110, 60), Vector3(-1600, 0, -250)],
	["quartier_eastgate_rue", Vector3(1098.6, 1.7, 338.0), Vector3(1104.4, 1.5, 238.2), "sol"],
	["quartier_bluffview_survol", Vector3(-850, 120, -700), Vector3(-1000, 0, -1050)],
	["quartier_midtown_nord", Vector3(-230, 50, -700), Vector3(-380, 0, -1000)],
	# étape 4b : voie ferrée
	["voie_ferree_pont_riviere", Vector3(-790, 9, 628), Vector3(-850, 3, 560)],
	["voie_ferree_passage_niveau", Vector3(-372, 9, 226), Vector3(-389, 0.5, 252)],
	["voie_ferree_viaduc_est", Vector3(690, 22, 380), Vector3(810, 4, 294)],
	["voie_ferree_sur_voie_express", Vector3(-652, -3.8, 519), Vector3(-716, -2, 468)],
	["voie_ferree_portail_est", Vector3(2060, 12, 235), Vector3(2172, 4, 196), "sol"],
	["voie_ferree_heurtoir_ouest", Vector3(-2140, 2.5, 792), Vector3(-2172, 0.5, 800), "sol"],
	# étape 5 : lieux
	["lieu_aeroport_survol", Vector3(300, 120, -950), Vector3(650, 5, -1300)],
	["lieu_aeroport_aerogare", Vector3(470, 7.3, -1172), Vector3(470, 10, -1229)],
	["lieu_motel", Vector3(-420, 12, 560), Vector3(-485, 3, 590)],
	["lieu_ranch", Vector3(1650, 30, -175), Vector3(1720, 8, -80)],
	["lieu_planque", Vector3(680, 14, -105), Vector3(647, 5, -55)],
	["lieu_greenfield", Vector3(-400, 30, -880), Vector3(-490, 2, -965)],
	["lieu_echo_circle", Vector3(160, 12, -280), Vector3(110, 6, -316)],
	["lieu_hotel", Vector3(-880, 8, -470), Vector3(-925, 25, -424)],
	["lieu_hopital", Vector3(-250, 10, 110), Vector3(-280, 8, 168)],
	["lieu_commissariat", Vector3(-690, 6, 115), Vector3(-713, 6, 158)],
	["lieu_liberty_motors", Vector3(40, 10, -440), Vector3(15, 2, -395)],
	["lieu_casino", Vector3(-520, 45, -300), Vector3(-586, 30, -365)],
	# étape 6 : végétation
	["foret_cedar_gulch_sous_bois", Vector3(-1950, 1.7, 150), Vector3(-1900, 3.0, 60), "sol"],
	["foret_nord_ouest_survol", Vector3(-1500, 90, -700), Vector3(-1900, 10, -1100)],
	["bordure_est_depuis_campagne", Vector3(1900, 20, -300), Vector3(2300, 20, -500)],
	# chantier du centre-ville : vues fixes valables avant et après la reconstruction (caméras sur les voies de
	# circulation des axes conservés, sur le quai ou en hauteur), mesurées avant (référence) puis après
	["cv_main_street_vers_nord", Vector3(-529, 1.7, -100), Vector3(-529, 3, -460)],
	["cv_boulevard_vers_ouest", Vector3(-100, 1.7, -175), Vector3(-892, 3, -175)],
	["cv_rue_du_casino", Vector3(-420, 1.7, -318), Vector3(-800, 3, -318)],
	["cv_rue_est_vers_nord", Vector3(-170, 1.7, 100), Vector3(-170, 3, -460)],
	["cv_quai_vers_ville", Vector3(-250, 1.7, -490), Vector3(-300, 20, -100)],
	["cv_coeur_40m", Vector3(-460, 40, -100), Vector3(-600, 0, -300)],
	["cv_survol_sud_est", Vector3(-100, 90, 300), Vector3(-500, 0, -150)],
	# chantier des routes, bouts de bretelles (2026-09-18) : caméras À HAUTEUR DE CONDUITE sur le trajet lui-même,
	# tournées vers la partie étroite du biseau. Coordonnées relevées sur le trajet des rubans (RampPoints).
	["bretelle_insertion_no_sol", Vector3(-903.3, 8.4, -715.7), Vector3(-938.3, 8.6, -711.3)],
	["bretelle_sortie_no_sol", Vector3(-943.3, 9.4, -690.2), Vector3(-913.3, 8.1, -684.3)],
	["bretelle_losange_n9_sol", Vector3(198.3, 1.9, -682.0), Vector3(233.4, 0.8, -685.7)],
	["bretelle_coupe_n9_d20", Vector3(233.4, 5.0, -706.0), Vector3(233.4, 0.2, -678.0)],
	["bretelle_coupe_n9_d40", Vector3(213.3, 5.0, -706.0), Vector3(213.3, 0.2, -678.0)],
	["bretelle_coupe_n9_d55", Vector3(198.3, 5.5, -706.0), Vector3(198.3, 0.4, -676.0)],
	["bretelle_survol_n9", Vector3(268.0, 26.0, -655.0), Vector3(200.0, 0.0, -684.0)],
	# chantier de Northgate Rise (2026-09-18) : à hauteur d'homme, altitudes ABSOLUES (le mode "sol" élève aussi le point
	# visé, et un point visé au-dessus du bâtiment accroche son toit à 70 m : la caméra finissait tournée vers le ciel).
	# Sol relevé : 7,14 m devant le coin sud-ouest, 9,54 m au portail, 9,18 m sur la plate-forme ; yeux à 1,7 m.
	["chantier_rue_sol", Vector3(-302.0, 8.8, -1372.0), Vector3(-248.0, 22.0, -1306.0)],
	["chantier_portail_sol", Vector3(-288.0, 11.2, -1300.0), Vector3(-232.0, 14.0, -1310.0)],
	["chantier_interieur_sol", Vector3(-274.0, 10.9, -1344.0), Vector3(-252.0, 26.0, -1288.0)],
	# Chantier jour/nuit : vues DE NUIT, au sol, à hauteur d'homme. Les 12 vues de référence sont
	# toutes diurnes ; mesurées de jour elles ne prouvent rien sur le coût de l'éclairage nocturne,
	# puisque les halos sont cachés et les vraies lumières éteintes. Le 5e champ force l'heure.
	["nuit_artere_urbaine_sol", Vector3(-1606.0, 1.7, -8.0), Vector3(-1624.0, 1.5, -80.0), "sol", 1.0],
	["nuit_centre_ville_sol", Vector3(-892.0, 1.7, -172.0), Vector3(-700.0, 1.6, -172.0), "sol", 1.0],
	["nuit_echangeur_sol", Vector3(-330.0, 1.7, 690.0), Vector3(-380.0, 4.0, 770.0), "sol", 1.0],
	["nuit_rond_point_echo_sol", Vector3(175.0, 1.7, -255.0), Vector3(110.0, 1.5, -316.0), "sol", 1.0],
	["nuit_quartier_westbank_sol", Vector3(-1255.2, 1.7, 165.9), Vector3(-1245.6, 1.5, 265.4), "sol", 1.0],
	["nuit_echo_circle_sol", Vector3(-520.0, 1.7, -300.0), Vector3(-586.0, 3.0, -365.0), "sol", 1.0],
	# Crépuscule et lever, mêmes caméras : c'est là que le fondu des lampadaires se juge.
	["crepuscule_artere_sol", Vector3(-1606.0, 1.7, -8.0), Vector3(-1624.0, 1.5, -80.0), "sol", 19.8],
	# lampadaires sous un ouvrage (2026-09-19) : les 4 mâts que RoadBake refuse désormais de poser.
	# Altitudes ABSOLUES et à hauteur d'homme — le mode "sol" ne convient pas ici, il relèverait la
	# caméra sur le TABLIER au lieu de la laisser dessous, dans la tranchée ou sous le viaduc.
	# Sol relevé : tranchée à -6,15 m (pied de mât -5,30), trottoir sous le viaduc de l'est à +1,17 m.
	["mat_tranchee_ouest_sol", Vector3(-695.8, -4.45, -748.0), Vector3(-695.8, -4.2, -800.0)],
	["mat_tranchee_est_sol", Vector3(-719.4, -4.45, -607.0), Vector3(-719.4, -4.2, -660.0)],
	["mat_viaduc_est_sol", Vector3(30.0, 2.87, 797.0), Vector3(75.0, 4.6, 773.0)],
	["mat_viaduc_est_contre_sol", Vector3(86.0, 2.73, 770.0), Vector3(40.0, 4.6, 794.0)],
	# fenêtres allumées (2026-09-19). Toutes AU SOL, à hauteur d'homme, à 1 h du matin.
	# Le centre-ville roule à +0,200 m (chaussée 0,05 + trottoir 0,15), d'où les altitudes absolues
	# des vues rapprochées : le mode "sol" relèverait aussi le point visé et, visé au pied d'une
	# tour de 263 m, il accrocherait la tour elle-même et retournerait la caméra vers le ciel.
	["nuit_gratte_ciels_sol", Vector3(-430.0, 1.9, -232.0), Vector3(-585.0, 30.0, -280.0), "", 1.0],
	["nuit_gratte_ciels_rue_sol", Vector3(-520.0, 1.9, -90.0), Vector3(-560.0, 40.0, -240.0), "", 1.0],
	["jour_gratte_ciels_sol", Vector3(-430.0, 1.9, -232.0), Vector3(-585.0, 30.0, -280.0), "", 12.0],
	# la ville DE LOIN, debout sur les collines du nord-ouest à 1,1 km : le mode "sol" pose la caméra
	# à hauteur d'homme sur le relief et vise le sol au pied des tours. C'est la vue qui dit si la
	# skyline vit la nuit ou si la ville reste noire au-delà de la bascule HLOD (650 m).
	["nuit_skyline_collines_sol", Vector3(-1150.0, 1.7, -1150.0), Vector3(-550.0, 1.5, -230.0), "sol", 1.0],
	["jour_skyline_collines_sol", Vector3(-1150.0, 1.7, -1150.0), Vector3(-550.0, 1.5, -230.0), "sol", 12.0],
	# quartier de la carte : les 1 196 bâtiments, pour voir que ça vit aussi hors du centre-ville
	["nuit_quartier_westbank_sol2", Vector3(-1255.2, 1.7, 165.9), Vector3(-1245.6, 1.5, 265.4), "sol", 1.0],
	["aube_artere_sol", Vector3(-1606.0, 1.7, -8.0), Vector3(-1624.0, 1.5, -80.0), "sol", 6.2],
]
const SETTLE_FRAMES := 40

var _out := ""
var _hour := -1.0
var _cycle: Node = null
var _sans_image := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	var only: PackedStringArray = []
	var bassin := -1
	var toutes := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--views="):
			only = arg.substr(8).split(",")
		elif arg.begins_with("--heure="):
			_hour = arg.substr(8).to_float()
		elif arg.begins_with("--bassin="):
			bassin = arg.substr(9).to_int()
		elif arg == "--toutes-lampes":
			toutes = true
		elif arg == "--sans-image":
			# Mesure seule, sans get_image(). C'est get_image() qui fait décrocher le GPU au-delà de
			# 800x450 (DXGI_ERROR_DEVICE_REMOVED, cf. CLAUDE.md §6), pas le rendu : sans lui on peut
			# mesurer en 1920x1080, résolution à laquelle le GPU est enfin assez chargé pour que la
			# différence entre 0 et 1540 lumières sorte du bruit. Les IMAGES, elles, restent en
			# 800x450.
			_sans_image = true
	var world := WORLD.instantiate()
	# Réglages de l'éclairage AVANT _ready : StreetLights crée son bassin au premier allumage, et
	# c'est tout l'intérêt de ces deux options de pouvoir comparer des tailles de bassin, et l'option
	# « une vraie lumière par lampadaire », sans recompiler quoi que ce soit.
	var lights := world.get_node_or_null("StreetLights")
	if lights != null:
		if bassin >= 0:
			lights.set("pool", bassin)
		if toutes:
			lights.set("all_lights", true)
	add_child(world)
	_cycle = world.get_node_or_null("DayNight")
	if _cycle != null:
		_cycle.set("show_clock", false)
		# cycle figé : sans ça l'heure dériverait de 40 images entre deux vues, et deux mesures de
		# la même vue ne seraient pas comparables
		_cycle.set("paused", true)
		if _hour >= 0.0:
			_cycle.call("set_hour", _hour)
	for spawner_name in ["CarSpawner", "NpcSpawner"]:
		world.get_node(spawner_name).set_process(false)
	var cam := Camera3D.new()
	cam.far = 4000.0
	add_child(cam)
	cam.make_current()
	# Temps GPU par image. Les appels de dessin ne mesurent PAS le coût des lumières : une
	# OmniLight3D ou une SpotLight3D n'ajoute aucun appel, elle ajoute du travail dans la passe
	# d'ombrage. Sans cette mesure, comparer « 0 lumière » et « 1540 lumières » donnerait exactement
	# le même chiffre et ne prouverait rien.
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	# Sans ça, le temps d'image mesuré est celui de l'écran, pas celui de la scène, et toutes les
	# options se valent à 60 Hz près.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for k in 3:
		await get_tree().physics_frame
	for view: Array in VIEWS:
		if not only.is_empty() and not only.has(view[0]):
			continue
		var from: Vector3 = view[1]
		var to: Vector3 = view[2]
		if view.size() > 3 and view[3] == "sol":
			from.y += _ground(from)
			to.y += _ground(to)
		if _cycle != null:
			# heure propre à la vue si elle en impose une, sinon celle de --heure=, sinon celle du
			# cycle telle quelle
			if view.size() > 4:
				_cycle.call("set_hour", float(view[4]))
			elif _hour >= 0.0:
				_cycle.call("set_hour", _hour)
		cam.global_position = from
		cam.look_at(to, Vector3.UP)
		for k in SETTLE_FRAMES:
			await get_tree().process_frame
		# moyenne du temps GPU sur les 20 dernières images : une image isolée est trop bruitée pour
		# départager deux réglages d'éclairage
		# Temps d'image AU MUR, mesuré à l'horloge, médiane sur 120 images. Les deux compteurs de
		# Godot (viewport_get_measured_render_time_gpu/cpu) se sont montrés inexploitables sur cette
		# machine le 2026-09-19 : ils donnaient « 0 lumière » plus lent que « 1540 lumières » et la
		# même valeur au centième pour des bassins de 8, 32 et 64. L'horloge, elle, ne ment pas sur
		# ce qu'une image coûte réellement.
		var rid := get_viewport().get_viewport_rid()
		var mesures: Array[float] = []
		var cpu := 0.0
		var t_prec := Time.get_ticks_usec()
		for k in 120:
			await get_tree().process_frame
			var t := Time.get_ticks_usec()
			mesures.append((t - t_prec) / 1000.0)
			t_prec = t
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
		cpu /= 120.0
		# médiane, pas moyenne : une image isolée où le pilote recompile un pipeline fausse une
		# moyenne et ne déplace pas une médiane
		mesures.sort()
		var gpu: float = mesures[mesures.size() / 2]
		await RenderingServer.frame_post_draw
		if not _sans_image:
			var img := get_viewport().get_texture().get_image()
			if _out != "":
				img.save_png(_out.path_join(String(view[0]) + ".png"))
		print("MAP_SHOT %s [%05.2f h] : %d appels de dessin, %d objets, %.2f M primitives, image %.3f ms, rendu CPU %.2f ms"
				% [view[0], (_cycle.get("hour") if _cycle != null else 0.0),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1e6,
				gpu, cpu])
	get_tree().quit(0)


func _ground(p: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(Vector3(p.x, 500.0, p.z), Vector3(p.x, -200.0, p.z))
	var hit := get_viewport().world_3d.direct_space_state.intersect_ray(query)
	return 0.0 if hit.is_empty() else (hit["position"] as Vector3).y
