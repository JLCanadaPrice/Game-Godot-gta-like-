extends Node

# Test headless du JOUEUR À PIED (2026-09-25, CLAUDE.md §16) : le VRAI joueur (Player.tscn) sur un sol plat d'essai près
# de l'origine, piloté par ses actions comme au clavier.
#
#  1. PIEDS
#   - l'import de Suit.gltf garde les pistes de POSITION des pieds dans Walk et Run (le reciblage humanoïde les
#     supprimait : pieds figés, pointe enfoncée de 18 à 20 cm, pied traîné à la vitesse du corps) ;
#   - en avançant (5 m/s) : Run, joué à 5 / 3,02 ; les pieds bougent (pas d'au moins 0,6 m dans le sens du déplacement, repère
#     du joueur) et restent POSÉS pendant l'appui : vitesse médiane de l'os du pied sous (plancher + 0,1) x la vitesse
#     du corps. Le plancher est ce que donne la même mesure quand l'animation est jouée exactement à sa vitesse propre
#     (le déroulé du pied, talon puis pointe) : 0,16-0,17 pour Run et les courses de côté, 0,14 et 0,44 pour Run_Back
#     (pied gauche, pied droit), mesuré sur la pose. La SEMELLE (le plus bas des sommets des chaussures, par peau
#     linéaire comme le moteur) reste au sol : 5e et 95e centiles pendant l'appui entre -3 et +3 cm ;
#   - reculer, aller à gauche, à droite : Run_Back, Run_Left, Run_Right, pieds posés ; en diagonale avant droite : Run,
#     modèle tourné de 45° vers la droite, pieds posés ;
#   - Maj (13,5 m/s) : Run à la cadence maximale (2) ; le glissement qui reste est imprimé (c'est la vitesse de course
#     qui dépasse ce que l'animation peut suivre, pas un défaut du test) ;
#   - arrêt : Idle, pieds immobiles.
#
# Lancer : Godot --headless --path <projet> --fixed-fps 60 res://scenes/tests/JoueurAPiedTest.tscn

const JOUEUR := preload("res://scenes/player/Player.tscn")
const PLANCHER := {"Run": [0.17, 0.17], "Run_Back": [0.14, 0.44], "Run_Left": [0.17, 0.17], "Run_Right": [0.17, 0.17]}
const PIEDS := ["LeftFoot", "RightFoot"]

var _errors: Array[String] = []
var _player: CharacterBody3D
var _skel: Skeleton3D
var _anim: AnimationPlayer
var _infl := {"LeftFoot": [], "RightFoot": []}   # sommets des chaussures : [[os, sommet lié, poids], ...]
var _releves: Array = []
var _enregistre := false
var _prec := {}


func _ready() -> void:
	print("JOUEUR_A_PIED_TEST_BEGIN")
	process_priority = 1000   # relevés après l'animation de l'image
	var sol := StaticBody3D.new()
	var forme := CollisionShape3D.new()
	var boite := BoxShape3D.new()
	boite.size = Vector3(400.0, 2.0, 400.0)
	forme.shape = boite
	sol.add_child(forme)
	add_child(sol)
	sol.position = Vector3(0.0, -1.0, 0.0)
	_player = JOUEUR.instantiate() as CharacterBody3D
	add_child(_player)
	_player.global_position = Vector3(0.0, 1.0, 0.0)
	await _frames(40)
	_skel = _player.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_anim = _player.get("_anim") as AnimationPlayer
	_peau()
	_check_pistes()
	await _check_marche("avance", ["move_forward"], "Run", 5.0)
	await _check_marche("recule", ["move_back"], "Run_Back", 5.0)
	await _check_marche("gauche", ["move_left"], "Run_Left", 5.0)
	await _check_marche("droite", ["move_right"], "Run_Right", 5.0)
	await _check_marche("diagonale", ["move_forward", "move_right"], "Run", 5.0)
	await _check_course()
	await _check_arret()
	print("JOUEUR_A_PIED_RESULT %s %s" % ["OK" if _errors.is_empty() else "FAIL", " | ".join(_errors)])
	get_tree().quit(0 if _errors.is_empty() else 1)


func _check_pistes() -> void:
	var manque: PackedStringArray = []
	for clip: String in ["Walk", "Run"]:
		var a := _anim.get_animation(clip)
		for os: String in PIEDS:
			if a.find_track(NodePath("%GeneralSkeleton:" + os), Animation.TYPE_POSITION_3D) < 0:
				manque.append("%s/%s" % [clip, os])
	var ok := manque.is_empty()
	print("JOUEUR_A_PIED_PISTES position des pieds dans Walk et Run : %s | %s" % ["présentes" if ok else "MANQUE " + ", ".join(manque), _ok(ok)])
	if not ok:
		_errors.append("pistes de position des pieds")


# Avance avec `actions` : 0,6 s de mise en train, puis 1,5 s de relevés.
func _check_marche(nom: String, actions: Array, clip_attendu: String, vitesse: float) -> void:
	var r := await _mesure(actions)
	var ok: bool = r["anim"] == clip_attendu and absf(float(r["corps"]) - vitesse) < 0.05
	var txt := "JOUEUR_A_PIED_%s %s : corps %.2f m/s, anim %s x %.2f, modèle tourné de %+.0f° |" % [nom.to_upper(), actions,
			r["corps"], r["anim"], r["cadence"], rad_to_deg(float(_player.get("_lacet_modele")))]
	if nom == "diagonale":
		ok = ok and absf(rad_to_deg(float(_player.get("_lacet_modele"))) - 45.0) < 3.0
	for k in PIEDS.size():
		var p: Dictionary = r[PIEDS[k]]
		var plafond: float = (float(PLANCHER.get(clip_attendu, [0.17, 0.17])[k]) + 0.1) * vitesse
		var ok_pied: bool = float(p["ampl"]) >= 0.6 and float(p["glisse"]) <= plafond \
				and float(p["bas"]) >= -0.03 and float(p["haut"]) <= 0.03
		ok = ok and ok_pied
		txt += " %s : %.2f m de pas, glisse %.2f m/s (au plus %.2f), semelle %+.3f / %+.3f m |" % [PIEDS[k].trim_suffix("Foot"),
				p["ampl"], p["glisse"], plafond, p["bas"], p["haut"]]
	print(txt + " " + _ok(ok))
	if not ok:
		_errors.append(nom)


func _check_course() -> void:
	var r := await _mesure(["move_forward", "sprint"])
	var ok: bool = r["anim"] == "Run" and absf(float(r["cadence"]) - 2.0) < 0.01
	print("JOUEUR_A_PIED_COURSE Maj : corps %.2f m/s, anim %s x %.2f (cadence maximale) ; les pieds glissent encore de %.2f / %.2f m/s | %s" % [
			r["corps"], r["anim"], r["cadence"], r["LeftFoot"]["glisse"], r["RightFoot"]["glisse"], _ok(ok)])
	if not ok:
		_errors.append("course")


func _check_arret() -> void:
	var r := await _mesure([])
	var ok: bool = r["anim"] == "Idle" and float(r["LeftFoot"]["glisse"]) < 0.05 and float(r["RightFoot"]["glisse"]) < 0.05
	print("JOUEUR_A_PIED_ARRET anim %s, pieds %.2f / %.2f m/s | %s" % [r["anim"], r["LeftFoot"]["glisse"], r["RightFoot"]["glisse"], _ok(ok)])
	if not ok:
		_errors.append("arrêt")


func _mesure(actions: Array) -> Dictionary:
	for a: String in actions:
		Input.action_press(a)
	await _frames(36)
	_releves.clear()
	_prec.clear()
	_enregistre = true
	await _frames(90)
	_enregistre = false
	for a: String in actions:
		Input.action_release(a)
	var corps := PackedFloat32Array()
	var anims := {}
	for e: Dictionary in _releves:
		corps.append(float(e["v"]))
		anims[e["anim"]] = int(anims.get(e["anim"], 0)) + 1
	var anim := ""
	for a: String in anims:
		if anim == "" or int(anims[a]) > int(anims[anim]):
			anim = a
	var r := {"corps": _q(corps, 0.5), "anim": anim, "cadence": float(_releves[-1]["cadence"])}
	# amplitude du pas dans le SENS du déplacement (repère du joueur) : d'avant en arrière en avançant, de côté en pas chassés
	var sens := Vector3.ZERO
	for a: String in actions:
		sens += {"move_forward": Vector3.FORWARD, "move_back": Vector3.BACK, "move_left": Vector3.LEFT, "move_right": Vector3.RIGHT}.get(a, Vector3.ZERO)
	sens = sens.normalized() if sens != Vector3.ZERO else Vector3.FORWARD
	for os: String in PIEDS:
		var zmin := INF
		var zmax := -INF
		var lmin := INF
		for e: Dictionary in _releves:
			var l: float = (e[os]["local"] as Vector3).dot(sens)
			zmin = minf(zmin, l)
			zmax = maxf(zmax, l)
			lmin = minf(lmin, float(e[os]["semelle_loc"]))
		var glisse := PackedFloat32Array()
		var haut := PackedFloat32Array()
		for e: Dictionary in _releves:
			if float(e[os]["semelle_loc"]) <= lmin + 0.025 and e[os].has("v"):
				glisse.append(float(e[os]["v"]))
				haut.append(float(e[os]["semelle"]))
		r[os] = {"ampl": zmax - zmin, "glisse": _q(glisse, 0.5), "bas": _q(haut, 0.05), "haut": _q(haut, 0.95)}
	return r


func _process(delta: float) -> void:
	if not _enregistre or delta <= 0.0:
		return
	var xf := _player.global_transform
	var e := {"v": Vector2(_player.velocity.x, _player.velocity.z).length(), "anim": String(_anim.current_animation),
			"cadence": _anim.speed_scale}
	for os: String in PIEDS:
		var g := _skel.global_transform * _skel.get_bone_global_pose(_skel.find_bone(os))
		var s := _semelle(os)
		var d := {"local": xf.affine_inverse() * g.origin, "semelle": s.y, "semelle_loc": (xf.affine_inverse() * s).y + 0.9}
		if _prec.has(os):
			var dv: Vector3 = (g.origin - (_prec[os] as Vector3)) / delta
			d["v"] = Vector2(dv.x, dv.z).length()
		_prec[os] = g.origin
		e[os] = d
	_releves.append(e)


# Sommets des chaussures (maillage Suit_Feet), rangés à gauche ou à droite selon leur os dominant (pied ou tibia du
# côté), avec toutes leurs influences, pour la peau linéaire de _semelle.
func _peau() -> void:
	var cote := {"LeftFoot": "LeftFoot", "LeftLowerLeg": "LeftFoot", "RightFoot": "RightFoot", "RightLowerLeg": "RightFoot"}
	for n in _player.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.skin == null or mi.mesh == null or not String(mi.name).contains("Feet"):
			continue
		var bind_os := PackedInt32Array()
		for b in mi.skin.get_bind_count():
			bind_os.append(_skel.find_bone(String(mi.skin.get_bind_name(b))))
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var we: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			if bo.is_empty():
				continue
			var par := bo.size() / v.size()
			for i in v.size():
				var infl := []
				var best := -1
				var best_w := -1.0
				for k in par:
					var w := we[i * par + k]
					if w <= 0.0:
						continue
					infl.append([bind_os[bo[i * par + k]], mi.skin.get_bind_pose(bo[i * par + k]) * v[i], w])
					if w > best_w:
						best_w = w
						best = bind_os[bo[i * par + k]]
				var c: String = cote.get(_skel.get_bone_name(best), "")
				if c != "":
					(_infl[c] as Array).append(infl)


# Point le plus bas de la chaussure, dans le monde.
func _semelle(os: String) -> Vector3:
	var bas := Vector3(0.0, INF, 0.0)
	var poses := {}
	for infl: Array in _infl[os]:
		var p := Vector3.ZERO
		for e: Array in infl:
			if not poses.has(e[0]):
				poses[e[0]] = _skel.global_transform * _skel.get_bone_global_pose(e[0])
			p += (poses[e[0]] as Transform3D) * (e[1] as Vector3) * float(e[2])
		if p.y < bas.y:
			bas = p
	return bas


func _q(a: PackedFloat32Array, q: float) -> float:
	if a.is_empty():
		return NAN
	var b := a.duplicate()
	b.sort()
	return b[clampi(int(q * b.size()), 0, b.size() - 1)]


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _ok(ok: bool) -> String:
	return "OK" if ok else "ÉCHEC"
