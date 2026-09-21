extends Node3D

# PARKING À ÉTAGES (Business_ParkingStructure) : ce qui le rend praticable, vérifié sur les exemplaires CUITS.
#
#  1. COLLISION PAR DALLE : sur chaque plateau de chaque exemplaire, un piéton (la capsule du joueur, rayon 0,4 m,
#     hauteur 1,8 m) et une voiture (Car.tscn, laissée là) lâchés à 1 m au-dessus du plancher s'y posent et y
#     restent. Avec l'ancienne boîte pleine, ils se posaient sur le TOIT de la boîte, 18 m plus haut.
#
#  2. RAYON DE BRAQUAGE DU JOUEUR, mesuré sur le vrai Car._drive_physics (arc parcouru / lacet) : 5,5 m à 3 m/s,
#     10 m à 16 m/s (inchangé). Il valait 10 m à toute vitesse : impossible de tourner dans un parking.
#  3. RAMPE À 12 % : la voiture du joueur monte une vraie pente continue de 12 % (plat, pente, plat, sans ressaut aux
#     raccords), arrive en haut, puis redescend en marche arrière. À mi-pente, son modèle a l'assiette de la pente
#     (nez levé en montée) et ses roues touchent la pente : écart entre le bas de chaque roue et la pente sous 8 cm.
#     La boîte de collision restant horizontale, l'essieu arrière flottait avant à 0,27 m.
#
# Les plateaux sont relevés sur le maillage cuit (ParkingStructureKit.planchers), pas recopiés d'une constante.
#
# Lancer : Godot --headless --path <projet> res://scenes/tests/ParkingStructureTest.tscn

const Kit := preload("res://scenes/world/map/tools/ParkingStructureKit.gd")
const CENTRE_VILLE := "res://scenes/world/downtown/generated/Buildings.tscn"
const CAR := preload("res://scenes/vehicles/Car.tscn")
const BERLINE := "res://assets/vehicle_models_extra/city_vehicles_UNVERIFIED_LICENSE/Sedans/Veh_Sedan_01_Blue.glb"
const GRAVITE := 9.8
const DUREE := 2.0
# Points de lâcher, repère du modèle : bande sud (z -5), loin des poteaux (z ~0) et des tours.
const PIETON := Vector3(-4.0, 0.0, -5.0)
const VOITURE := Vector3(6.0, 0.0, -5.5)

var _fautes: Array[String] = []
var _pietons: Array = []     # [CharacterBody3D, altitude attendue du pied, libellé]
var _voitures: Array = []    # [Car, plancher, libellé]
var _t := 0.0
var _repos_voiture := 0.0    # hauteur de l'origine d'une voiture posée sur un sol plat (relevée sur le sol témoin)
var _temoin: Node3D
var _phase := "dalles"
var _pilote: Node3D          # voiture conduite par le « joueur » (start_drive), sur le sol témoin
var _vitesses := [3.0, 8.0, 16.0]
var _k_vitesse := 0
var _t_phase := 0.0
var _arc := 0.0
var _lacet := 0.0
var _prec := Vector3.ZERO
var _prec_lacet := 0.0
var _rayons := []
var _rampe_mi := {}          # relevé à mi-pente
var _rampe_haut := -1.0      # temps d'arrivée en haut
var _rampe_bas := -1.0       # temps de retour en bas
var _rampe_y_max := -INF
const TEMOIN_Z := 3000.0
const RAMPE_X := 30.0
const PENTE := 0.12
const RAMPE_LONG := 20.0


func _ready() -> void:
	# sol témoin : une dalle plate à y = 0, loin de tout, pour relever la hauteur de repos d'une voiture
	var sol := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var boite := BoxShape3D.new()
	boite.size = Vector3(140, 1, 140)
	cs.shape = boite
	cs.position.y = -0.5
	sol.add_child(cs)
	sol.position = Vector3(0, 0, TEMOIN_Z)
	add_child(sol)
	_temoin = _voiture(Vector3(-30, 1.0, TEMOIN_Z), "temoin")
	_rampe()
	_pilote = CAR.instantiate() as Node3D
	_pilote.set("forced_model_path", BERLINE)
	_pilote.name = "Pilote"
	add_child(_pilote)
	_pilote.global_position = Vector3(0, 1.0, TEMOIN_Z + 30.0)
	var ville: Node3D = (load(CENTRE_VILLE) as PackedScene).instantiate()
	add_child(ville)
	var parkings: Array = []
	for b in ville.get_children():
		if String(b.get_meta("model", "")) == Kit.CLE:
			parkings.append(b)
	if parkings.size() != 3:
		_fautes.append("%d parking(s) a etages au centre-ville au lieu de 3" % parkings.size())
	for b: Node3D in parkings:
		var mi := b.get_node("Mesh") as MeshInstance3D
		var cs2 := b.get_node_or_null("StaticBody3D/CollisionShape3D") as CollisionShape3D
		if cs2 == null or not (cs2.shape is ConcavePolygonShape3D):
			_fautes.append("%s : collision %s, pas les triangles du modele" % [b.name, "absente" if cs2 == null else cs2.shape.get_class()])
		var planchers := Kit.planchers(mi.mesh)
		print("PARKING %s en %s : planchers %s" % [b.name, str(b.global_position.snapped(Vector3.ONE * 0.01)), str(planchers)])
		if planchers.size() != 5:
			_fautes.append("%s : %d plateaux releves au lieu de 5" % [b.name, planchers.size()])
		for k in planchers.size():
			var y: float = planchers[k]
			var p := b.global_transform * (PIETON + Vector3(0, y + 1.0, 0))
			_pietons.append([_pieton(p), (b.global_transform * Vector3(0, y, 0)).y, "%s niveau %d" % [b.name, k]])
			var c := b.global_transform * (VOITURE + Vector3(0, y + 1.0, 0))
			_voitures.append([_voiture(c, "%s niveau %d" % [b.name, k]), (b.global_transform * Vector3(0, y, 0)).y, "%s niveau %d" % [b.name, k]])


func _pieton(p: Vector3) -> CharacterBody3D:
	var corps := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	cs.shape = capsule
	corps.add_child(cs)
	corps.floor_snap_length = 0.4
	add_child(corps)
	corps.global_position = p
	return corps


func _voiture(p: Vector3, nom: String) -> Node3D:
	var car := CAR.instantiate() as Node3D
	car.set("forced_model_path", BERLINE)
	car.name = "Voiture_" + nom.validate_node_name()
	add_child(car)
	car.global_position = p
	car.call("park")
	return car


# Rampe témoin, d'un seul tenant (triangles jointifs) : plat de 10 m, pente de 12 % sur 20 m, plat de 10 m en haut.
# La voiture monte vers -z (son avant).
func _rampe() -> void:
	var y1 := PENTE * RAMPE_LONG
	var z0 := TEMOIN_Z
	var prof := [[z0 + 10.0, 0.001], [z0, 0.001], [z0 - RAMPE_LONG, y1], [z0 - RAMPE_LONG - 10.0, y1]]
	var faces := PackedVector3Array()
	for k in prof.size() - 1:
		var a: Array = prof[k]
		var b: Array = prof[k + 1]
		var p0 := Vector3(RAMPE_X - 5.0, a[1], a[0])
		var p1 := Vector3(RAMPE_X + 5.0, a[1], a[0])
		var p2 := Vector3(RAMPE_X + 5.0, b[1], b[0])
		var p3 := Vector3(RAMPE_X - 5.0, b[1], b[0])
		faces.append_array(PackedVector3Array([p0, p1, p2, p0, p2, p3]))
	var forme := ConcavePolygonShape3D.new()
	forme.set_faces(faces)
	forme.backface_collision = true
	var corps := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = forme
	corps.add_child(cs)
	add_child(corps)


func _hauteur_rampe(z: float) -> float:
	return clampf((TEMOIN_Z - z) * PENTE, 0.0, PENTE * RAMPE_LONG)


func _physics_process(delta: float) -> void:
	_t += delta
	match _phase:
		"dalles":
			for e: Array in _pietons:
				var corps: CharacterBody3D = e[0]
				corps.velocity.y = 0.0 if corps.is_on_floor() else corps.velocity.y - GRAVITE * delta
				corps.move_and_slide()
			if _t >= DUREE:
				_bilan_dalles()
				_pilote.call("start_drive")
				_phase = "braquage"
				_t_phase = 0.0
		"braquage":
			_braquage(delta)
		"rampe":
			_montee(delta)


func _braquage(delta: float) -> void:
	var v: float = _vitesses[_k_vitesse]
	_pilote.set("_drive_speed", v)
	Input.action_press("move_left")
	_t_phase += delta
	var p := _pilote.global_position
	var lacet := _pilote.global_rotation.y
	if _t_phase > 0.5:
		_arc += Vector2(p.x - _prec.x, p.z - _prec.z).length()
		_lacet += absf(wrapf(lacet - _prec_lacet, -PI, PI))
	_prec = p
	_prec_lacet = lacet
	if _t_phase >= 1.5:
		_rayons.append([v, _arc / maxf(_lacet, 0.0001)])
		_arc = 0.0
		_lacet = 0.0
		_t_phase = 0.0
		_k_vitesse += 1
		if _k_vitesse >= _vitesses.size():
			Input.action_release("move_left")
			_phase = "rampe"
			_pilote.set("_drive_speed", 0.0)
			_pilote.global_position = Vector3(RAMPE_X, 1.0, TEMOIN_Z + 8.0)
			_pilote.global_rotation = Vector3.ZERO
			_pilote.set("velocity", Vector3.ZERO)


func _montee(delta: float) -> void:
	_t_phase += delta
	var p := _pilote.global_position
	_rampe_y_max = maxf(_rampe_y_max, p.y)
	if _rampe_haut < 0.0:
		_pilote.set("_drive_speed", 4.0)
		if _rampe_mi.is_empty() and p.z < TEMOIN_Z - RAMPE_LONG * 0.5 and p.z > TEMOIN_Z - RAMPE_LONG * 0.5 - 1.0 and _t_phase > 1.0:
			_rampe_mi = _releve_roues()
		if p.z < TEMOIN_Z - RAMPE_LONG - 4.0:
			_rampe_haut = _t_phase
	else:
		_pilote.set("_drive_speed", -3.0)
		if p.z > TEMOIN_Z + 3.0:
			_rampe_bas = _t_phase
	if _rampe_bas > 0.0 or _t_phase > 30.0:
		_bilan()


# À mi-pente : assiette du modèle et écart du bas de chaque roue à la pente.
func _releve_roues() -> Dictionary:
	var pire := 0.0
	var ecarts := PackedStringArray()
	for w: Node3D in _pilote.get("_wheels"):
		var bas := INF
		var xz := Vector2.ZERO
		var meshes := w.find_children("*", "MeshInstance3D", true, false)
		if w is MeshInstance3D:
			meshes.append(w)
		for mi_n in meshes:
			var mi := mi_n as MeshInstance3D
			if mi.mesh == null:
				continue
			for s in mi.mesh.get_surface_count():
				for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
					var g := mi.global_transform * v
					if g.y < bas:
						bas = g.y
						xz = Vector2(g.x, g.z)
		var ecart := bas - _hauteur_rampe(xz.y)
		pire = maxf(pire, absf(ecart))
		ecarts.append("%s %+.3f" % [w.name, ecart])
	var modele: Node3D = _pilote.get("_model")
	var nez := (modele.global_transform * Vector3(0, 0.5, 2.0)).y - (modele.global_transform * Vector3(0, 0.5, -2.0)).y
	var out := {"pire": pire, "ecarts": ", ".join(ecarts), "pente": rad_to_deg(float(_pilote.get("_pente"))), "nez_moins_arriere": nez}
	# même relevé SANS l'assiette (le comportement d'avant) : la physique est la même, seul le modèle change
	var pente: float = _pilote.get("_pente")
	_pilote.set("_pente", 0.0)
	_pilote.call("_update_visuals", 0.0, 0.0, 0.0)
	var sans := 0.0
	for w: Node3D in _pilote.get("_wheels"):
		var bas := INF
		var xz := Vector2.ZERO
		var meshes := w.find_children("*", "MeshInstance3D", true, false)
		if w is MeshInstance3D:
			meshes.append(w)
		for mi_n in meshes:
			var mi := mi_n as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
					var g := mi.global_transform * v
					if g.y < bas:
						bas = g.y
						xz = Vector2(g.x, g.z)
		sans = maxf(sans, bas - _hauteur_rampe(xz.y))
	out["sans_assiette"] = sans
	_pilote.set("_pente", pente)
	_pilote.call("_update_visuals", 0.0, 0.0, 0.0)
	return out


func _bilan_dalles() -> void:
	_repos_voiture = _temoin.global_position.y
	var pire_pieton := 0.0
	for e: Array in _pietons:
		var corps: CharacterBody3D = e[0]
		var pied := corps.global_position.y - 0.9
		var ecart := absf(pied - float(e[1]))
		pire_pieton = maxf(pire_pieton, ecart)
		if not corps.is_on_floor() or ecart > 0.05:
			_fautes.append("pieton %s : pied a %.2f m pour un plancher a %.2f (%s)" % [e[2], pied, e[1], "au sol" if corps.is_on_floor() else "EN L'AIR"])
	var pire_voiture := 0.0
	for e: Array in _voitures:
		var car: Node3D = e[0]
		var ecart := absf(car.global_position.y - float(e[1]) - _repos_voiture)
		pire_voiture = maxf(pire_voiture, ecart)
		if ecart > 0.05:
			_fautes.append("voiture %s : origine a %.2f m pour un plancher a %.2f (repos %.2f)" % [e[2], car.global_position.y, e[1], _repos_voiture])
	print("PARKING_DALLES %d pietons et %d voitures poses sur les plateaux : ecart au plancher %.3f m au pire (pietons), %.3f m (voitures)"
			% [_pietons.size(), _voitures.size(), pire_pieton, pire_voiture])


func _bilan() -> void:
	set_physics_process(false)
	var txt := PackedStringArray()
	for r: Array in _rayons:
		txt.append("%.0f m/s : %.2f m" % [r[0], r[1]])
		var attendu: float = _pilote.call("rayon_braquage", r[0])
		if absf(float(r[1]) - attendu) > 0.35:
			_fautes.append("rayon de braquage a %.0f m/s : %.2f m mesures pour %.2f attendus" % [r[0], r[1], attendu])
	print("PARKING_BRAQUAGE rayon de braquage mesure (joueur, braquage a fond) : %s" % ", ".join(txt))
	if _rayons.size() == 3 and (float(_rayons[0][1]) > 6.0 or absf(float(_rayons[2][1]) - 10.0) > 0.35):
		_fautes.append("braquage : %.2f m a 3 m/s (attendu 5,5), %.2f m a 16 m/s (attendu 10, inchange)" % [_rayons[0][1], _rayons[2][1]])
	if _rampe_mi.is_empty():
		_fautes.append("rampe a 12 pour cent : la voiture n'a jamais atteint le milieu de la pente (y max %.2f)" % _rampe_y_max)
	else:
		print("PARKING_RAMPE a mi-pente : assiette %.2f deg (pente %.2f deg), nez %+.3f m au-dessus de l'arriere, roues : %s"
				% [_rampe_mi["pente"], rad_to_deg(atan(PENTE)), _rampe_mi["nez_moins_arriere"], _rampe_mi["ecarts"]])
		print("PARKING_RAMPE sans l'assiette (le comportement d'avant, meme physique) : la roue la plus haute flottait a %.3f m de la pente" % _rampe_mi["sans_assiette"])
		if float(_rampe_mi["pire"]) > 0.08:
			_fautes.append("rampe a 12 pour cent : une roue a %.3f m de la pente" % _rampe_mi["pire"])
		if absf(float(_rampe_mi["pente"]) - rad_to_deg(atan(PENTE))) > 0.8 or float(_rampe_mi["nez_moins_arriere"]) <= 0.0:
			_fautes.append("rampe a 12 pour cent : assiette %.2f deg, nez %+.3f m (le nez doit etre plus haut en montee)" % [_rampe_mi["pente"], _rampe_mi["nez_moins_arriere"]])
	print("PARKING_RAMPE montee jusqu'en haut en %.1f s, redescente en marche arriere en %.1f s (y max %.2f m pour un palier a %.2f)"
			% [_rampe_haut, _rampe_bas - _rampe_haut if _rampe_bas > 0.0 else -1.0, _rampe_y_max, PENTE * RAMPE_LONG])
	if _rampe_haut < 0.0:
		_fautes.append("rampe a 12 pour cent : la voiture n'est jamais arrivee en haut")
	if _rampe_bas < 0.0:
		_fautes.append("rampe a 12 pour cent : la voiture n'est jamais redescendue")
	if _fautes.is_empty():
		print("PARKING_STRUCTURE_RESULT OK")
	else:
		for f in _fautes.slice(0, 30):
			print("PARKING_STRUCTURE_FAUTE %s" % f)
		print("PARKING_STRUCTURE_RESULT FAIL %d faute(s)" % _fautes.size())
	get_tree().quit()
