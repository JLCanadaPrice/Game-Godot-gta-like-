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
]
const SETTLE_FRAMES := 40

var _out := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	var only: PackedStringArray = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--views="):
			only = arg.substr(8).split(",")
	var world := WORLD.instantiate()
	add_child(world)
	for spawner_name in ["CarSpawner", "NpcSpawner"]:
		world.get_node(spawner_name).set_process(false)
	var cam := Camera3D.new()
	cam.far = 4000.0
	add_child(cam)
	cam.make_current()
	for view: Array in VIEWS:
		if not only.is_empty() and not only.has(view[0]):
			continue
		cam.global_position = view[1]
		cam.look_at(view[2], Vector3.UP)
		for k in SETTLE_FRAMES:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if _out != "":
			img.save_png(_out.path_join(String(view[0]) + ".png"))
		print("MAP_SHOT %s : %d appels de dessin, %d objets, %.2f M primitives, %.0f FPS"
				% [view[0], RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1e6,
				Engine.get_frames_per_second()])
	get_tree().quit(0)
