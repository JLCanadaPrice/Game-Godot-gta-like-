extends Node

# Banc de RENDU fenêtré (pas headless : le GPU compte) dans la vraie carte à 4 districts, joueur et caméra réels.
# Situation signalée par le joueur : caméra au coin de la carte tournée vers le croisement des 4 districts, donc
# toute la ville dans le champ (far 4000 m, FOV horizontal ~107° en 16:9).
# Par phase : FPS réel (vsync coupée, pas de plafond), 1 % low, temps CPU du rendu (setup + culling + listes, mesuré
# par le RenderingServer), temps GPU, appels de dessin / objets (surfaces) / primitives de la passe visible et des
# passes d'ombre, temps process / physique, compilations de pipelines pendant la mesure.
# Contenu dessiné relevé par famille (instances, surfaces, triangles, matériaux distincts) : doit rester identique
# avant / après une optimisation qui ne retire rien (les MultiMesh de CityRenderOptimizer comptent leurs instances).
#
#  (défaut)            : ville statique (spawners à 0) aux coins SE et NW avec la caméra du joueur, coin SE vu de
#                        40 m de haut, puis trafic plein (252 voitures / 315 PNJ) au coin SE.
#  --breakdown         : ville statique, coin SE ; référence puis chaque famille masquée tour à tour et ombres du
#                        soleil coupées -> part réelle de chaque famille dans le coût de rendu.
#  --verify-occlusion  : vues fixes (sol, hauteur, rues, toits, devant les vitrines) et trajets en mouvement rendus sans
#                        puis avec occlusion culling, comparés pixel à pixel, y compris les frames qui suivent une
#                        coupe de caméra -> l'occlusion ne doit rien faire disparaître de visible au-delà de liserés
#                        lointains de quelques pixels, propres au tampon de Godot (SLIVER_MAX_PX, cf. _verify_occlusion).
#                        Images des écarts écrites dans --out=<dossier> (défaut user://render_verify).
#  --verify-multimesh  : mêmes vues fixes avec les MeshInstance3D d'origine puis les MultiMesh qui les remplacent
#                        (occlusion culling coupé pendant la comparaison : vérifiée à part) -> image identique.
#  --no-occlusion, --no-multimesh, --multimesh : force une optimisation de CityRenderOptimizer (ablation) ; sans
#                        option, ses réglages livrés (occlusion oui, multimesh non).
#  --lod-threshold=<px> : seuil de LOD du viewport (défaut 1 ; 0 = LOD0 partout, isole les écarts dus au choix du LOD).
#  --lod-bias-batiments=<x> : lod_bias des bâtiments du kit (CityRenderOptimizer.building_lod_bias) pour la mesure.
#  --verify-lod=<x>    : vues fixes rendues sans puis avec un lod_bias x sur les bâtiments lointains ; de près
#                        (CityRenderOptimizer.lod_near_radius) rien ne doit changer (cf. _verify_lod).
#  --occlusion-rays=<n> : rayons du tampon d'occultation par thread (sans option : project.godot, 2048 ; défaut de
#                        Godot 512 ; plus = tampon plus fin).
#  --ignore-occlusion=<familles> : jamais masqués par l'occlusion, ex. trottoirs,routes,decals (cf. CATS) ; pour les
#                        décalques et spots, sans réglage dédié, c'est tout leur culling qui est ignoré (frustum compris).
#
# Lancer : Godot_console --path <projet> [--resolution 1920x1080] res://scenes/tests/RenderPerfTest.tscn -- [options]

const WORLD := preload("res://scenes/world/World.tscn")
const CITY_CENTER := Vector3(-460.0, 0.0, -172.0)
const VIEWS := {
	"coin_SE": Vector3(-20.5, 2.0, -467.5),
	"coin_NW": Vector3(-899.5, 2.0, 123.5),
}
const HIGH_VIEW := Vector3(-20.5, 40.0, -467.5)
const CATS := ["trottoirs", "routes", "batiments", "decals", "spots", "lampadaires", "feux", "autres"]
const BREAKDOWN := [
	["référence", ""], ["sans trottoirs", "trottoirs"], ["sans routes", "routes"], ["sans bâtiments", "batiments"],
	["sans décalques", "decals"], ["sans spots", "spots"], ["sans lampadaires", "lampadaires"], ["sans feux", "feux"],
	["sans ombres du soleil", "@shadow"], ["référence (contrôle de dérive)", ""],
]
const DIFF_THRESHOLD := 24          # somme des écarts R+G+B (sur 765) au-delà de laquelle un pixel compte
const SLIVER_MAX_PX := 8            # px par frame tolérés par --verify-occlusion (liserés lointains, cf. _verify_occlusion)

var _world: Node3D
var _player: CharacterBody3D
var _player_cam: Camera3D
var _free_cam: Camera3D
var _cars
var _npcs
var _traffic := [0, 0]
var _vp: RID
var _sun: DirectionalLight3D
var _nodes := {}
var _measuring := false
var _last_usec := 0
var _s := {}
var _args := PackedStringArray()


func _ready() -> void:
	print("RENDER_PERF_BEGIN")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_args = OS.get_cmdline_user_args()
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var t0 := Time.get_ticks_msec()
	_world = WORLD.instantiate()
	_cars = _world.get_node("CarSpawner")
	_npcs = _world.get_node("NpcSpawner")
	_traffic = [_cars.max_active, _npcs.max_active]
	_cars.max_active = 0
	_npcs.max_active = 0
	var occlusion_rays: int = ProjectSettings.get_setting("rendering/occlusion_culling/occlusion_rays_per_thread")
	for a in _args:
		if a.begins_with("--lod-threshold="):
			get_viewport().mesh_lod_threshold = a.trim_prefix("--lod-threshold=").to_float()
		if a.begins_with("--occlusion-rays="):
			occlusion_rays = a.trim_prefix("--occlusion-rays=").to_int()
			RenderingServer.viewport_set_occlusion_rays_per_thread(occlusion_rays)
	var optimizer = _world.get_node_or_null("CityRenderOptimizer")
	if optimizer != null:
		# sans option : réglages de CityRenderOptimizer tels que livrés
		if "--no-occlusion" in _args:
			optimizer.occlusion = false
		if "--multimesh" in _args:
			optimizer.multimesh = true
		if _arg("--lod-bias-batiments=") != "":
			optimizer.building_lod_bias = _arg("--lod-bias-batiments=").to_float()
		# --verify-multimesh construit les MultiMesh lui-même, en gardant les sources pour comparer
		if "--no-multimesh" in _args or "--verify-multimesh" in _args:
			optimizer.multimesh = false
	add_child(_world)
	await get_tree().process_frame
	print("RENDER_PERF_LOAD World.tscn instancié et optimisé en %d ms, %d nœuds | optimiseur : %s | occlusion culling du viewport : %s"
			% [Time.get_ticks_msec() - t0, Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			"absent" if optimizer == null else "%d boîtes d'occultation, %d instances en %d MultiMesh" % [optimizer.occluders, optimizer.batched_instances, optimizer.multimesh_nodes],
			get_viewport().use_occlusion_culling])
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	_player.set_process_unhandled_input(false)
	_player.set_process_input(false)
	_player_cam = get_viewport().get_camera_3d()
	_free_cam = Camera3D.new()
	_free_cam.fov = _player_cam.fov
	_free_cam.near = _player_cam.near
	_free_cam.far = _player_cam.far
	add_child(_free_cam)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	print("RENDER_PERF_ENV %s | %s | fenêtre %s | vsync %d | tampon d'occultation : %d rayons par thread, %d threads logiques"
			% [RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_driver_name(), get_window().size,
			DisplayServer.window_get_vsync_mode(), occlusion_rays, OS.get_processor_count()])
	_collect()
	for a in _args:
		if a.begins_with("--ignore-occlusion="):
			for family in a.trim_prefix("--ignore-occlusion=").split(","):
				for n in _nodes[family]:
					if n is GeometryInstance3D:
						n.ignore_occlusion_culling = true
					else:
						# décalques, spots : pas de propriété dédiée, le culling entier est ignoré (frustum compris)
						RenderingServer.instance_set_ignore_culling(n.get_instance(), true)
	_print_content()
	if "--verify-occlusion" in _args:
		await _verify_occlusion()
	elif "--verify-multimesh" in _args:
		await _verify_multimesh()
	elif _arg("--verify-lod=") != "":
		await _verify_lod(_arg("--verify-lod=").to_float())
	elif "--breakdown" in _args:
		await _place("coin_SE", 8.0)
		for step: Array in BREAKDOWN:
			_toggle(step[1], false)
			await get_tree().create_timer(2.0).timeout
			await _measure("coin_SE statique, " + step[0], 5.0)
			_toggle(step[1], true)
	else:
		var spawn := _player.global_transform
		await _place("coin_SE", 8.0)
		await _measure("coin_SE, ville statique", 8.0)
		await _place("coin_NW", 4.0)
		await _measure("coin_NW, ville statique", 8.0)
		_look_from(HIGH_VIEW, CITY_CENTER)
		await get_tree().create_timer(4.0).timeout
		await _measure("coin_SE vu de 40 m, ville statique", 8.0)
		_player_cam.make_current()
		_player.global_transform = spawn
		_player.velocity = Vector3.ZERO
		_cars.max_active = _traffic[0]
		_npcs.max_active = _traffic[1]
		var t := 0.0
		while t < 60.0 and (_count("vehicle") < _traffic[0] * 0.95 or _count("npc") < _traffic[1] * 0.95):
			await get_tree().create_timer(1.0).timeout
			t += 1.0
		print("RENDER_PERF_FILL %d voitures / %d PNJ après %.0f s" % [_count("vehicle"), _count("npc"), t])
		await _place("coin_SE", 3.0)
		await _measure("coin_SE, trafic plein", 8.0)
	print("RENDER_PERF_END")
	get_tree().quit()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _measuring and _last_usec > 0:
		var v := get_viewport()
		_s.frame.append((now - _last_usec) / 1000.0)
		_s.cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(_vp) + RenderingServer.get_frame_setup_time_cpu())
		_s.gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(_vp))
		_s.process.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		_s.physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		_s.draw.append(v.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
		_s.objects.append(v.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME))
		_s.prims.append(v.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME))
		_s.sdraw.append(v.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
		_s.sobjects.append(v.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_OBJECTS_IN_FRAME))
	_last_usec = now


func _place(view: String, settle: float) -> void:
	_player_cam.make_current()
	_player.global_position = VIEWS[view]
	_player.velocity = Vector3.ZERO
	_player.look_at(Vector3(CITY_CENTER.x, _player.global_position.y, CITY_CENTER.z), Vector3.UP)
	_player.get_node("SpringArm3D").rotation = Vector3.ZERO
	await get_tree().create_timer(settle).timeout
	print("RENDER_PERF_VIEW %s : joueur posé en %s, caméra en %s" % [view, _player.global_position.snappedf(0.1),
			get_viewport().get_camera_3d().global_position.snappedf(0.1)])


func _look_from(eye: Vector3, target: Vector3) -> void:
	_free_cam.global_position = eye
	_free_cam.look_at(target, Vector3.UP)
	_free_cam.make_current()


func _measure(label: String, seconds: float) -> void:
	for k in ["frame", "cpu", "gpu", "process", "physics", "draw", "objects", "prims", "sdraw", "sobjects"]:
		_s[k] = []
	var compiles := _compilations()
	_last_usec = 0
	_measuring = true
	var t0 := Time.get_ticks_usec()
	await get_tree().create_timer(seconds).timeout
	_measuring = false
	var elapsed := (Time.get_ticks_usec() - t0) / 1000000.0
	var sorted: Array = _s.frame.duplicate()
	sorted.sort()
	var n := sorted.size()
	print("RENDER_PERF %s | %.1f FPS (frame %.2f ms, p95 %.2f, 1%% low %.1f FPS) | rendu CPU %.2f ms, GPU %.2f ms | process %.2f ms, physique %.2f ms | visible : %.0f appels de dessin, %.0f objets, %.0f primitives | ombres : %.0f appels, %.0f objets | %d compilations de pipelines | %d frames"
			% [label, n / elapsed, _mean(_s.frame), sorted[int(n * 0.95)], 1000.0 / sorted[mini(int(n * 0.99), n - 1)],
			_mean(_s.cpu), _mean(_s.gpu), _mean(_s.process), _mean(_s.physics), _mean(_s.draw), _mean(_s.objects),
			_mean(_s.prims), _mean(_s.sdraw), _mean(_s.sobjects), _compilations() - compiles, n])


# Vérifications pixel à pixel, arbre en pause (feux figés) et océan masqué (son shader animé bruite l'image). Une image
# "avec" est comparée à une image "sans" de la même pose ; un pixel n'est suspect que si deux images "sans" de cette
# pose y sont identiques (hors bruit). Objets dessinés relevés sans / avec : une comparaison où l'optimisation ne
# retire rien ne prouve rien.
#
# Occlusion : Godot décale les rayons du tampon d'occultation (occlusion_culling/jitter_projection) sur un cycle de
# 9 frames et garde dessiné 9 frames tout objet vu visible ; un objet que le tampon juge caché disparaît aussitôt.
# Juste après une coupe de caméra, un objet visible par un interstice plus fin qu'un texel du tampon (~10 px d'écran en
# 1152x648) peut donc manquer tant qu'aucun rayon décalé ne l'a vu, et une vue comparée moins de 9 frames après un
# changement ne teste rien de ce que la vue précédente montrait. D'où :
#  - chaque vue atteinte par une coupe depuis la vue précédente, occlusion active, puis comparée sur 18 frames :
#    les 9 qui suivent la coupe, puis 9 minuteries échues (tout le cycle de décalage) ;
#  - des trajets le long des rues (65 km/h, caméra balayant ±35°) et au-dessus des toits, rendus sans puis avec
#    occlusion, comparés frame par frame.
#
# Écarts qui restent, mesurés le 2026-09-16 en 1152x648 sur plusieurs passes, tampon à 512 puis 2048 rayons par
# thread, et identifiés par sondes (surcouche magenta sur l'objet dessiné au pixel, exemptions ciblées d'occlusion) :
#  - vues stables, 2 à 3 px (vue 02 ; vue 17 à 2048) : la même tuile de trottoir est dessinée, seul son ombrage
#    bascule ; passage piéton à 708 m (vue 02) appliqué ou non par le cluster de Godot (boîtes rastérisées au 1/16 de
#    l'écran), ombrage de tuile à 266 m (vue 17), bascules qui se produisent aussi SANS occlusion pour 1 mm de caméra
#    ou en masquant des spots à plus de 150 m ;
#  - en mouvement, 1 à 5 px sur quelques frames (trajets 02 et 05) : liserés de géométrie lointaine vus par un
#    interstice plus fin qu'un texel du tampon, retirés par intermittence (0 px si toute la géométrie est exemptée,
#    toujours présents en n'exemptant que les petits objets ou que les bâtiments, à 512 comme à 2048 rayons) ;
#  - juste après une coupe, jusqu'à 8 px sur la 1re frame (vue 19 : liseré de façade entre deux bâtiments).
# Verdict OK tant qu'aucune frame ne dépasse SLIVER_MAX_PX : un objet proche retiré, ou une boîte d'occultation qui
# déborde d'un bâtiment, en coûte des dizaines à des milliers.
func _verify_occlusion() -> void:
	var out_dir := _begin_verify()
	var vp := get_viewport()
	var sums := {"stable": 0, "mouvement": 0, "coupe": 0}
	var peaks := {"stable": 0, "mouvement": 0, "coupe": 0}
	var where := {"stable": [], "mouvement": [], "coupe": []}
	var views := _verify_views()
	for i in views.size():
		var v: Array = views[i]
		var prev: Array = views[i - 1]
		_look_from(v[1], v[2])
		vp.use_occlusion_culling = false
		var ref := await _shot_after(4)
		var ref2 := await _shot_after(4)
		var off_objects := _objects()
		vp.use_occlusion_culling = true
		_look_from(prev[1], prev[2])
		await _shot_after(10)
		_look_from(v[1], v[2])
		var mask := _new_mask(ref)
		var counts: Array[int] = []
		var worst: Image = null
		var min_objects := off_objects
		for f in 18:
			var shot := await _shot_after(1)
			min_objects = mini(min_objects, _objects())
			counts.append(_diff(ref, shot, [ref2], mask))
			if counts[f] > 0 and (worst == null or counts[f] >= counts.max()):
				worst = shot
		_tally(sums, peaks, where, "coupe", counts.slice(0, 9), "vue %02d" % i)
		_tally(sums, peaks, where, "stable", counts.slice(9), "vue %02d" % i)
		if worst != null:
			_save_bad(out_dir, "occlusion_vue_%02d_%s" % [i, v[0]], ref, worst, mask)
		print("RENDER_VERIFY %02d %-22s oeil %s -> %s | objets dessinés sans / avec occlusion : %d / %d (min %d) | bruit %d px | pixels suspects : %s sur les 9 frames après la coupe, %s sur les 9 suivantes"
				% [i, v[0], v[1].snappedf(0.1), v[2].snappedf(0.1), off_objects, _objects(), min_objects,
				_diff(ref, ref2, [], null), counts.slice(0, 9), counts.slice(9)])
	var paths := _verify_paths()
	for p in paths.size():
		var poses: Array = paths[p][1]
		var refs: Array[Image] = []
		var refs2 := []                      # par frame : [seconde image sans occlusion] si elle diffère (bruit)
		var off_objects := 0
		var noise := 0
		vp.use_occlusion_culling = false
		for t: Transform3D in poses:
			_free_cam.global_transform = t
			refs.append(await _shot_after(1))
			off_objects += _objects()
		for k in poses.size():
			_free_cam.global_transform = poses[k]
			var shot := await _shot_after(1)
			var n := _diff(refs[k], shot, [], null)
			noise += n
			refs2.append([shot] if n > 0 else [])
		vp.use_occlusion_culling = true
		_free_cam.global_transform = poses[0]
		await _shot_after(10)
		var on_objects := 0
		var counts: Array[int] = []
		for k in poses.size():
			_free_cam.global_transform = poses[k]
			var shot := await _shot_after(1)
			on_objects += _objects()
			var mask := _new_mask(shot)
			counts.append(_diff(refs[k], shot, refs2[k], mask))
			if counts[k] > 0 and counts[k] >= counts.max():
				_save_bad(out_dir, "occlusion_trajet_%02d_frame_%02d" % [p, k], refs[k], shot, mask)
		_tally(sums, peaks, where, "mouvement", counts, "trajet %02d" % p)
		print("RENDER_VERIFY_TRAJET %02d %-5s %s -> %s | objets dessinés moyens sans / avec occlusion : %d / %d | bruit %d px | %d pixels suspects sur %d frames%s"
				% [p, paths[p][0], poses[0].origin.snappedf(0.1), poses[-1].origin.snappedf(0.1), off_objects / poses.size(),
				on_objects / poses.size(), noise, _sum(counts), poses.size(), " (par frame : %s)" % [counts] if _sum(counts) > 0 else ""])
	var line := ""
	for kind: String in sums:
		line += " | %s : %d px, max %d px/frame%s" % [kind, sums[kind], peaks[kind], " %s" % [where[kind]] if sums[kind] > 0 else ""]
	print("RENDER_VERIFY_RESULT occlusion %s | %d vues (9 frames après coupe + 9 stables), %d trajets de 48 frames%s | seuil %d px/frame | image %s"
			% ["OK" if peaks.values().max() <= SLIVER_MAX_PX else "ECART", views.size(), paths.size(), line, SLIVER_MAX_PX, get_window().size])
	_end_verify()


func _tally(sums: Dictionary, peaks: Dictionary, where: Dictionary, kind: String, counts: Array, label: String) -> void:
	sums[kind] += _sum(counts)
	peaks[kind] = maxi(peaks[kind], counts.max())
	if _sum(counts) > 0:
		where[kind].append(label)


# MultiMesh : MeshInstance3D d'origine affichées puis masquées au profit des MultiMesh, construits ici par
# CityRenderOptimizer (sources libérées à la fin, comme au lancement normal) ; occlusion coupée, vérifiée à part.
# LOD0 partout pendant la comparaison : un MultiMesh choisit son LOD sur la boîte de toute sa cellule, plus proche que
# celle de chaque instance, donc un détail égal ou plus fin. Au seuil normal, seuls quelques pixels de poteaux lointains
# changent (mesuré le 2026-09-16 : 16 px sur 34 vues, 0 en LOD0), jamais un objet ; en LOD0 l'image doit être identique.
func _verify_multimesh() -> void:
	var out_dir := _begin_verify()
	var lod_threshold := get_viewport().mesh_lod_threshold
	get_viewport().mesh_lod_threshold = 0.0
	get_viewport().use_occlusion_culling = false
	var optimizer = _world.get_node("CityRenderOptimizer")
	var sources: Array[MeshInstance3D] = optimizer.batch_static_meshes(_world)
	var batched := optimizer.find_children("*", "MultiMeshInstance3D", false, false)
	print("RENDER_VERIFY_MULTIMESH %d MeshInstance3D -> %d instances en %d MultiMesh"
			% [sources.size(), optimizer.batched_instances, batched.size()])
	var total := 0
	var bad := 0
	var views := _verify_views()
	for i in views.size():
		var v: Array = views[i]
		_look_from(v[1], v[2])
		for mi in sources:
			mi.visible = true
		for mmi: MultiMeshInstance3D in batched:
			mmi.visible = false
		var ref := await _shot_after(4)
		var ref2 := await _shot_after(4)
		var off_objects := _objects()
		for mi in sources:
			mi.visible = false
		for mmi: MultiMeshInstance3D in batched:
			mmi.visible = true
		var shot := await _shot_after(4)
		var mask := _new_mask(ref)
		var suspicious := _diff(ref, shot, [ref2], mask)
		total += suspicious
		if suspicious > 0:
			bad += 1
			_save_bad(out_dir, "multimesh_vue_%02d_%s" % [i, v[0]], ref, shot, mask)
		print("RENDER_VERIFY %02d %-22s oeil %s -> %s | objets dessinés sans / avec MultiMesh : %d / %d | bruit %d px | %d pixels suspects"
				% [i, v[0], v[1].snappedf(0.1), v[2].snappedf(0.1), off_objects, _objects(), _diff(ref, ref2, [], null), suspicious])
	print("RENDER_VERIFY_RESULT multimesh %s | %d vues en LOD0, %d avec écart, %d pixels suspects au total (image %s)"
			% ["OK" if total == 0 else "ECART", views.size(), bad, total, get_window().size])
	get_viewport().mesh_lod_threshold = lod_threshold
	for mi in sources:
		mi.queue_free()
	_end_verify()


# LOD des bâtiments : chaque vue rendue sans puis avec CityRenderOptimizer.building_lod_bias = `bias` (appliqué par
# update_building_lods au-delà de lod_near_radius de la caméra ; il faut un building_lod_bias différent de 1 au
# chargement). D'abord avec les seuls bâtiments à moins de lod_near_radius (les autres masqués dans les deux rendus) :
# rien ne doit changer de près, 0 px. Puis scène entière, pour mémoire : pixels et primitives qui changent au loin.
# Mesuré le 2026-09-16 avec un lod_bias appliqué à TOUS les bâtiments (sans distance) : 0,25 -> 47 778 px de près sur
# 34 vues, 0,5 -> 5 667 px ; d'où la distance.
func _verify_lod(bias: float) -> void:
	var out_dir := _begin_verify()
	var optimizer = _world.get_node("CityRenderOptimizer")
	var shipped: float = optimizer.building_lod_bias
	var radius: float = optimizer.lod_near_radius
	var meshes: Array[MeshInstance3D] = optimizer.building_meshes(_world)
	var near_total := 0
	var far_total := 0
	var bad := []
	var views := _verify_views()
	for i in views.size():
		var v: Array = views[i]
		_look_from(v[1], v[2])
		var counts := []
		var prims := []
		for near_only in [true, false]:
			for mi in meshes:
				var aabb: AABB = mi.global_transform * mi.get_aabb()
				mi.visible = not near_only or v[1].distance_to(v[1].clamp(aabb.position, aabb.end)) <= radius
			optimizer.building_lod_bias = 1.0
			optimizer.update_building_lods(true)
			var ref := await _shot_after(12)
			var prims_ref := get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
			optimizer.building_lod_bias = bias
			optimizer.update_building_lods(true)
			var shot := await _shot_after(4)
			prims.append([prims_ref, get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)])
			optimizer.building_lod_bias = 1.0
			optimizer.update_building_lods(true)
			var ref2 := await _shot_after(4)
			var mask := _new_mask(ref)
			counts.append(_diff(ref, shot, [ref2], mask))
			if near_only and counts[0] > 0:
				_save_bad(out_dir, "lod_vue_%02d_%s" % [i, v[0]], ref, shot, mask)
		near_total += counts[0]
		far_total += counts[1]
		if counts[0] > 0:
			bad.append("vue %02d" % i)
		print("RENDER_VERIFY %02d %-22s | lod_bias %.2f | bâtiments à moins de %.0f m seuls : %d px différents | scène entière : %d px différents, primitives %d -> %d"
				% [i, v[0], bias, radius, counts[0], counts[1], prims[1][0], prims[1][1]])
	for mi in meshes:
		mi.visible = true
	optimizer.building_lod_bias = shipped
	optimizer.update_building_lods(true)
	print("RENDER_VERIFY_RESULT lod %s | lod_bias %.2f au-delà de %.0f m, %d vues | de près : %d px%s | scène entière : %d px | image %s"
			% ["OK" if near_total == 0 else "ECART", bias, radius, views.size(), near_total,
			" dans %s" % [bad] if near_total > 0 else "", far_total, get_window().size])
	_end_verify()


func _arg(prefix: String) -> String:
	for a in _args:
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""


func _begin_verify() -> String:
	# Le monde hérite du PROCESS_MODE_ALWAYS de ce banc : sans le repasser en PAUSABLE, la pause ne fige rien et les
	# feux changent d'état entre deux images d'une même pose (faux écarts).
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	get_tree().paused = true
	for n in _world.find_children("*", "", true, false):
		if n.scene_file_path.ends_with("ocean_mesh.glb"):
			n.visible = false
	var out_dir := "user://render_verify"
	for a in _args:
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	return out_dir


func _end_verify() -> void:
	get_viewport().use_occlusion_culling = ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling")
	get_tree().paused = false
	_world.process_mode = Node.PROCESS_MODE_INHERIT


# Image de la frame dessinée après `frames` frames, en RGB8 (format attendu par _diff).
func _shot_after(frames: int) -> Image:
	for f in frames:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	return img


func _objects() -> int:
	return get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME)


func _new_mask(like: Image) -> Image:
	return Image.create_empty(like.get_width(), like.get_height(), false, Image.FORMAT_RGBA8)


func _save_bad(out_dir: String, name: String, ref: Image, shot: Image, mask: Image) -> void:
	ref.save_png("%s/%s_sans.png" % [out_dir, name])
	shot.save_png("%s/%s_avec.png" % [out_dir, name])
	mask.save_png("%s/%s_ecart.png" % [out_dir, name])


# Trajets de 48 frames le long d'une arête du Circuit (au moins 20 m), à 0,3 m par frame (65 km/h à 60 FPS), caméra
# balayant ±35° autour du sens de la rue (jusqu'à ~4,6° par frame) : 6 à hauteur d'yeux, 2 à hauteur de toits.
func _verify_paths() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260917
	var circuit: CircuitPath = _world.get_node("Circuit")
	var long_edges := []
	for e in circuit.edges.size():
		if circuit.edges[e]["length"] >= 20.0:
			long_edges.append(e)
	var paths := []
	for p in 8:
		var e: int = long_edges[rng.randi() % long_edges.size()]
		var from: int = circuit.edges[e]["a"] if rng.randf() < 0.5 else circuit.edges[e]["b"]
		var step: float = minf(0.3, circuit.edges[e]["length"] / 48.0)
		var high := p >= 6
		var lift := Vector3(0.0, rng.randf_range(25.0, 35.0) if high else 1.7, 0.0)
		var pitch := -0.35 if high else 0.02
		var phase := rng.randf() * TAU
		var poses := []
		for k in 48:
			var dir := circuit.direction_at(e, from, k * step)
			var yaw := atan2(dir.x, dir.z) + deg_to_rad(35.0) * sin(phase + TAU * k / 48.0)
			var eye := circuit.sample(e, from, k * step) + lift
			poses.append(Transform3D(Basis.IDENTITY, eye).looking_at(eye + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)), Vector3.UP))
		paths.append(["toits" if high else "rue", poses])
	return paths


func _sum(values: Array) -> int:
	var total := 0
	for v in values:
		total += v
	return total


func _verify_views() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260916
	var views := []
	for corner: String in VIEWS:
		views.append([corner + "_sol", VIEWS[corner] + Vector3(0.0, 0.6, 0.0), CITY_CENTER])
		views.append([corner + "_40m", VIEWS[corner] + Vector3(0.0, 38.0, 0.0), CITY_CENTER])
	var circuit: Array = _world.get_node("Circuit").nodes
	for i in 14:
		var p: Vector3 = circuit[rng.randi() % circuit.size()] + Vector3(rng.randf_range(-6.0, 6.0), 1.7, rng.randf_range(-6.0, 6.0))
		var yaw := rng.randf() * TAU
		views.append(["rue", p, p + Vector3(sin(yaw), rng.randf_range(-0.05, 0.1), cos(yaw)) * 60.0])
	for i in 6:
		var p: Vector3 = circuit[rng.randi() % circuit.size()] + Vector3(rng.randf_range(-30.0, 30.0), rng.randf_range(31.0, 38.0), rng.randf_range(-30.0, 30.0))
		var yaw := rng.randf() * TAU
		views.append(["toits", p, p + Vector3(sin(yaw), rng.randf_range(-0.6, -0.1), cos(yaw)) * 60.0])
	# Devant la façade avant d'un modèle du kit (vitrine du rez-de-chaussée, côté +Z local), en face puis en biais.
	var kits := _world.find_children("KitModel", "", true, false)
	for i in 10:
		var mi := kits[rng.randi() % kits.size()].get_node("Mesh") as MeshInstance3D
		var c := mi.mesh.get_aabb().get_center()
		var side := rng.randf_range(-6.0, 6.0)
		views.append(["vitrine", mi.global_transform * Vector3(c.x + side, 1.7, 5.0), mi.global_transform * Vector3(c.x - side, 1.5, -8.0)])
	return views


# Pixels dont R+G+B diffèrent de plus de DIFF_THRESHOLD entre a et b, images RGB8 (cf. _shot_after : le viewport rend
# du RGB, 3 octets par pixel), sauf là où l'une des images `stable` (même pose, autre frame) diffère elle aussi de a
# (bruit). Comparaison native par ligne, détail pixel par pixel sur les lignes qui diffèrent.
func _diff(a: Image, b: Image, stable: Array, mask: Image) -> int:
	var da := a.get_data()
	var db := b.get_data()
	var ds := stable.map(func(img: Image) -> PackedByteArray: return img.get_data())
	var w := a.get_width()
	var stride := w * 3
	var count := 0
	for y in a.get_height():
		var ra := da.slice(y * stride, (y + 1) * stride)
		var rb := db.slice(y * stride, (y + 1) * stride)
		if ra == rb:
			continue
		var rs := ds.map(func(d: PackedByteArray) -> PackedByteArray: return d.slice(y * stride, (y + 1) * stride))
		for x in w:
			var i := x * 3
			if absi(ra[i] - rb[i]) + absi(ra[i + 1] - rb[i + 1]) + absi(ra[i + 2] - rb[i + 2]) <= DIFF_THRESHOLD:
				continue
			var unstable := false
			for rc: PackedByteArray in rs:
				if absi(ra[i] - rc[i]) + absi(ra[i + 1] - rc[i + 1]) + absi(ra[i + 2] - rc[i + 2]) > DIFF_THRESHOLD:
					unstable = true
					break
			if unstable:
				continue
			count += 1
			if mask != null:
				mask.set_pixel(x, y, Color.RED)
	return count


func _collect() -> void:
	for c in CATS:
		_nodes[c] = []
	for n in _world.find_children("*", "VisualInstance3D", true, false):
		if n is DirectionalLight3D:
			_sun = n
			continue
		_nodes[_classify(n)].append(n)


func _classify(n: Node) -> String:
	if n is Decal:
		return "decals"
	if n is Light3D:
		return "spots"
	var p := n
	while p != null and p != _world:
		if p is TrafficLight:
			return "feux"
		var f: String = p.get_meta(&"batched_scene", p.scene_file_path)
		if f.ends_with("lamp_1.glb"):
			return "lampadaires"
		if f.ends_with("Sidewalk_Straight_3m.gltf"):
			return "trottoirs"
		if f.begins_with("res://assets/modular_roads/Road"):
			return "routes"
		if p.name == &"Buildings":
			return "batiments"
		p = p.get_parent()
	return "autres"


# Ce qui est réellement dessiné, par famille : doit être identique avant / après (rien retiré).
func _print_content() -> void:
	var tris_of := {}
	var total := [0, 0, 0, 0]
	for c in CATS:
		var nodes := 0
		var inst := 0
		var surf := 0
		var tris := 0
		var mats := {}
		for n in _nodes[c]:
			# boîtes d'occultation : jamais dessinées (mais masquées avec leur famille par _toggle)
			if not n.is_visible_in_tree() or n is OccluderInstance3D:
				continue
			nodes += 1
			var mesh: Mesh = null
			var count := 1
			if n is MeshInstance3D:
				mesh = n.mesh
			elif n is MultiMeshInstance3D and n.multimesh != null:
				mesh = n.multimesh.mesh
				count = n.multimesh.visible_instance_count if n.multimesh.visible_instance_count >= 0 else n.multimesh.instance_count
			if mesh == null:
				inst += 1
				continue
			if not tris_of.has(mesh):
				tris_of[mesh] = mesh.get_faces().size() / 3
			inst += count
			surf += mesh.get_surface_count() * count
			tris += tris_of[mesh] * count
			for i in mesh.get_surface_count():
				var m: Material = n.get_active_material(i) if n is MeshInstance3D else (n.material_override if n.material_override else mesh.surface_get_material(i))
				if m != null:
					mats[m] = true
		print("RENDER_PERF_CONTENT %-12s %5d nœuds de rendu -> %5d instances, %6d surfaces, %8d triangles, %4d matériaux distincts" % [c, nodes, inst, surf, tris, mats.size()])
		total[0] += nodes
		total[1] += inst
		total[2] += surf
		total[3] += tris
	print("RENDER_PERF_CONTENT %-12s %5d nœuds de rendu -> %5d instances, %6d surfaces, %8d triangles" % ["TOTAL", total[0], total[1], total[2], total[3]])


func _toggle(what: String, on: bool) -> void:
	if what == "":
		return
	if what == "@shadow":
		_sun.shadow_enabled = on
		return
	for n in _nodes[what]:
		if on:
			n.visible = n.get_meta(&"_bench_was_visible", true)
		else:
			n.set_meta(&"_bench_was_visible", n.visible)
			n.visible = false


func _compilations() -> int:
	var total := 0
	for info in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
		total += RenderingServer.get_rendering_info(info)
	return total


func _count(group: StringName) -> int:
	return get_tree().get_nodes_in_group(group).size()


func _mean(values: Array) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total / maxf(values.size(), 1.0)
