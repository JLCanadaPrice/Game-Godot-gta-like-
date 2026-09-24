extends Node3D

# BANC D'ESSAI DES CHÂSSIS (2026-09-24, CLAUDE.md §14). Chaque véhicule, monté en conduite réaliste avec les réglages de
# SA fiche (FichesVehicules, resources/vehicle_physics/fiches_vehicules.csv), passe les mêmes essais sur un sol plat de
# 8 km, deux bordures (0,15 m, celle des trottoirs de la carte ; 0,17 m, celle de la raquette de l'aérogare) et la
# collision cuite d'un parking à étages :
#  - repos : garde au sol de la coque, pneus sur le sol ;
#  - accélération pied au plancher : 0-50, 0-100 km/h, vitesse atteinte, rapports (et rétrogradages en pleine
#    accélération : une boîte qui hésite) ;
#  - freinage fort depuis 100 km/h (sa vitesse de pointe si elle est plus basse) : distance, et droit ;
#  - PAS DE TONNEAU : braquage à fond, vitesse tenue, à 50, 80, 110 km/h et à la vitesse de pointe : roulis, roues levées,
#    glissade. Il glisse ou il sous-vire ; il ne se couche pas ;
#  - bordures de 0,15 et 0,17 m, de face et à 30°, à 3 m/s : la coque ne touche pas ;
#  - entrée du parking à étages à 4 et 7 m/s, s'il passe sous la barre de 2,15 m : la coque ne touche pas.
# Échoue sur : une caisse à plus de 45° de la verticale, deux roues d'un même côté en l'air plus de 0,3 s, un contact de
# coque sur une bordure ou à l'entrée du parking, une boîte restée en première, 50 km/h (ou sa vitesse de pointe si elle
# est plus basse) pas atteints en 30 s, un freinage qui dévie de plus de 15°, un véhicule sans châssis.
# Rapporté sans être jugé : garde au sol du DESSOUS DU MODÈLE (ce qu'on voit) sur les bordures et à l'entrée du parking —
# les modèles les plus bas (9 à 15 cm) passent visuellement dans l'arête d'une bordure de 15 cm prise de face.
# Arguments après « -- » : --modeles=id1,id2 (par défaut les six silhouettes de réglage), --tous, --lot=i/n (i-ème part
# de n de la liste, pour répartir sur plusieurs processus), --phases=a,b, --trace.
# Lancer : Godot --headless --fixed-fps 60 res://scenes/tests/ChassisBancTest.tscn [-- --tous --lot=1/4]

const CAR := preload("res://scenes/vehicles/Car.tscn")
const CarScript := preload("res://scenes/vehicles/Car.gd")
const PARKING := "res://scenes/world/downtown/generated/buildings/parking_collision.res"
const SILHOUETTES := ["city_microcar", "city_sedan_01", "city_sports_car_02", "city_suv_02", "city_truck_01", "city_bus_01"]
const PHASES := ["repos", "acceleration", "freinage", "virage_50", "virage_80", "virage_110", "virage_vmax",
		"bordure_15_face", "bordure_15_biais", "bordure_17_face", "bordure_17_biais", "parking"]
const KMH := 1.0 / 3.6
const DEPART_ACCEL := Vector3(-3000.0, 0.0, 1000.0)
const DEPART_FREIN := Vector3(-3000.0, 0.0, 0.0)
const DEPART_VIRAGE := Vector3(-3000.0, 0.0, -1500.0)
const BORDURES := {"15": [Vector3(1500.0, 0.0, 1500.0), 0.15], "17": [Vector3(1500.0, 0.0, 1700.0), 0.17]}
const BORDURE_TAILLE := Vector2(30.0, 12.0)
const PARKING_POS := Vector3(2500.0, 0.0, 2500.0)
const BARRE := 2.15
const ACCEL_DUREE := 40.0
const VIRAGE_LIGNE := 1.5
const VIRAGE_BRAQUE := 3.5
const VIRAGE_APRES := 2.0

var _modeles: Array = []          # [id, chemin du modèle]
var _k := -1
var _voiture: Node3D
var _ch: RigidBody3D
var _phases: Array = []
var _i := 0
var _t := 0.0
var _e := {}
var _res := {}
var _tableau: Array[String] = []
var _fautes: Array[String] = []
var _h_repos := 0.45
var _trace := false
var _bordures := {}
var _parking: StaticBody3D
var _dessous := PackedVector3Array()


func _ready() -> void:
	var sol := _statique(Vector3(0.0, -0.5, 0.0), BoxShape3D.new(), "Sol")
	(sol.get_child(0) as CollisionShape3D).shape.size = Vector3(8000.0, 1.0, 8000.0)
	for cle in BORDURES:
		var b := BoxShape3D.new()
		var h: float = BORDURES[cle][1]
		b.size = Vector3(BORDURE_TAILLE.x, h, BORDURE_TAILLE.y)
		_bordures[cle] = _statique((BORDURES[cle][0] as Vector3) + Vector3(0.0, h * 0.5, 0.0), b, "Bordure_" + cle)
	_parking = _statique(PARKING_POS, load(PARKING), "Parking")
	var ids: Array = SILHOUETTES.duplicate()
	var lot := Vector2i(1, 1)
	_phases = PHASES.duplicate()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--modeles="):
			ids = Array(a.substr(10).split(","))
		elif a == "--tous":
			ids = []
			var fichiers := DirAccess.get_files_at("res://resources/vehicle_models/")
			fichiers.sort()
			for f in fichiers:
				if f.ends_with(".tres"):
					ids.append(f.get_basename())
		elif a.begins_with("--lot="):
			var p := a.substr(6).split("/")
			lot = Vector2i(int(p[0]), int(p[1]))
		elif a.begins_with("--phases="):
			_phases = Array(a.substr(9).split(","))
		elif a == "--trace":
			_trace = true
	for j in ids.size():
		if j % lot.y != lot.x - 1:
			continue
		var d = load("res://resources/vehicle_models/%s.tres" % ids[j])
		if d == null:
			_faute("%s : modèle inconnu" % ids[j])
			continue
		_modeles.append([String(ids[j]), String(d.model_paths[0])])
	print("CHASSIS_BANC %d véhicule(s) : %s" % [_modeles.size(), ", ".join(_modeles.map(func(m): return m[0]))])
	CarScript.conduite_reelle = true
	_suivant()


func _statique(pos: Vector3, forme: Shape3D, nom: String) -> StaticBody3D:
	var corps := StaticBody3D.new()
	corps.name = nom
	var cs := CollisionShape3D.new()
	cs.shape = forme
	corps.add_child(cs)
	corps.position = pos
	add_child(corps)
	return corps


func _faute(texte: String) -> void:
	_fautes.append(texte)
	print("CHASSIS_BANC_FAUTE %s" % texte)


func _id() -> String:
	return String(_modeles[_k][0])


func _fiche() -> Dictionary:
	return FichesVehicules.fiche(_id())


func _vmax() -> float:
	return FichesVehicules.nombre(_fiche(), "vitesse_max_kmh") * KMH


# --- boucle ------------------------------------------------------------------------------------------------------

func _suivant() -> void:
	if _voiture != null:
		_resume()
		remove_child(_voiture)
		_voiture.queue_free()
		_voiture = null
		_ch = null
	_k += 1
	if _k >= _modeles.size():
		_fin()
		return
	_voiture = CAR.instantiate() as Node3D
	_voiture.set("forced_model_path", String(_modeles[_k][1]))
	_voiture.name = "Banc_" + _id()
	add_child(_voiture)
	_voiture.set("has_npc_driver", false)
	_voiture.global_position = DEPART_ACCEL + Vector3(0.0, 1.0, 0.0)
	_voiture.call("park")
	_voiture.call("start_drive")
	_ch = _voiture.call("chassis")
	_res = {}
	_dessous = PackedVector3Array()
	_i = 0
	_t = 0.0
	_e = {}
	if _ch == null:
		_faute("%s : pas de châssis réaliste" % _id())
		_voiture.call("stop_drive")
		_suivant()


func _physics_process(delta: float) -> void:
	if _ch == null:
		return
	_t += delta
	if _i >= _phases.size():
		_suivant()
		return
	var phase: String = _phases[_i]
	var fini := false
	if phase.begins_with("virage_"):
		fini = _p_virage(phase)
	elif phase.begins_with("bordure_"):
		fini = _p_bordure(phase)
	else:
		fini = bool(call("_p_" + phase, phase))
	if _trace and Engine.get_physics_frames() % 15 == 0:
		var glisse := 0.0
		for w in _ch.get("c_pws"):
			glisse = maxf(glisse, absf(float(w.wv) * float(w.w_size) * float(_ch.get("LengthScale"))) - absf(_v()))
		var roues := []
		for w in _ch.get("roues"):
			roues.append("%s %.1f" % [w.name, float(w.wv) * float(w.w_size) * float(_ch.get("LengthScale"))])
		print("BANC_TRACE %s %s t=%.2f v=%.1f km/h rapport=%s tr/min=%.0f gaz=%.2f glisse=%.1f penche=%.1f° pos=%s volant=%.3f lacet=%.3f roues=%s" % [
				_id(), phase, _t, _v() * 3.6, _ch.call("rapport"), float(_ch.get("rpm")), float(_ch.get("gaspedal")),
				glisse, _penche(), str(_ch.global_position.snappedf(0.01)), float(_ch.get("steer")), _ch.angular_velocity.y, str(roues)])
	if _trace and _t < 0.02:
		var pos := []
		for w in _ch.get("roues"):
			pos.append("%s %s" % [w.name, str((w as Node3D).position.snappedf(0.001))])
		print("BANC_ROUES %s %s cdg=%s %s" % [_id(), phase, str(_ch.center_of_mass.snappedf(0.001)), str(pos)])
	if fini or _t > 70.0:
		if not fini:
			_faute("%s : phase « %s » pas finie en 70 s" % [_id(), phase])
		_pedales()
		_i += 1
		_t = 0.0
		_e = {}


# --- outils ------------------------------------------------------------------------------------------------------

func _pedales(gaz := false, frein := false, droite := false, gauche := false) -> void:
	for a in ["gas", "brake", "left", "right", "handbrake"]:
		Input.action_release(a)
	if gaz:
		Input.action_press("gas")
	if frein:
		Input.action_press("brake")
	if droite:
		Input.action_press("right")
	if gauche:
		Input.action_press("left")


func _v() -> float:
	return float(_ch.call("vitesse_avant"))


func _regule(cible: float, droite := false) -> void:
	var v := _v()
	_pedales(v < cible, v > cible + 1.5, droite)


func _penche() -> float:
	return rad_to_deg(acos(clampf(_ch.global_transform.basis.y.dot(Vector3.UP), -1.0, 1.0)))


func _placer(sol: Vector3, cap: float, v := 0.0) -> void:
	var xf := Transform3D(Basis(Vector3.UP, cap), sol + Vector3.UP * (_h_repos + 0.02))
	_voiture.global_transform = xf
	_ch.global_transform = xf * CarScript.repere_chassis()
	_ch.call("repartir", -xf.basis.z * v)


func _cap_vers_x() -> float:
	return -PI * 0.5


# Roues du châssis en l'air, par côté (gauche : +x du châssis ; noms « fl », « rl », « rl1 »...).
func _roues_en_l_air() -> Vector2i:
	var g := 0
	var d := 0
	var ng := 0
	var nd := 0
	for w in _ch.get("roues"):
		var gauche: bool = String(w.name).substr(1, 1) == "l"
		if gauche:
			ng += 1
		else:
			nd += 1
		if not w.is_colliding():
			if gauche:
				g += 1
			else:
				d += 1
	return Vector2i(1 if g == ng else 0, 1 if d == nd else 0)


func _contacts(corps: Node) -> bool:
	return corps in _ch.get_colliding_bodies()


# Garde au sol de la coque (bas de ses formes au-dessus du sol plat, y = 0).
# Diagnostic (--trace) : où la coque touche `corps`, dans le repère du châssis (avant en +z), et l'état des roues.
func _trace_contacts(corps: Node, phase: String) -> void:
	var etat := PhysicsServer3D.body_get_direct_state(_ch.get_rid())
	if etat == null:
		return
	var roues := []
	for w in _ch.get("roues"):
		roues.append("%s:%s%.2f" % [w.name, "" if w.is_colliding() else "air ", float(w.get("compress"))])
	for i in etat.get_contact_count():
		if etat.get_contact_collider_object(i) == corps:
			var p: Vector3 = _ch.global_transform.affine_inverse() * etat.get_contact_local_position(i)   # position MONDE, malgré le nom
			print("BANC_CONTACT %s %s t=%.2f point=%s tangage=%.1f° roues=%s" % [_id(), phase, _t, str(p.snappedf(0.01)),
					rad_to_deg(asin(clampf(_ch.global_transform.basis.z.y, -1.0, 1.0))), " ".join(roues)])


func _garde_coque() -> float:
	var bas := INF
	for c in _ch.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is ConvexPolygonShape3D:
			var xf := (c as CollisionShape3D).global_transform
			for p in ((c as CollisionShape3D).shape as ConvexPolygonShape3D).points:
				bas = minf(bas, (xf * p).y)
	return bas


# Dessous du modèle, roues exceptées (cf. ConduiteReelleTest) : le point le plus bas de chaque tranche de 3 cm.
func _profil_dessous() -> PackedVector3Array:
	var modele: Node3D = _voiture.get("_model")
	var roues: Array = _voiture.get("_wheels")
	var vers_voiture := _voiture.global_transform.affine_inverse()
	var vers_modele := modele.global_transform.affine_inverse()
	var tranches := {}
	for n in modele.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var roue := false
		for w: Node3D in roues:
			if w == mi or w.is_ancestor_of(mi):
				roue = true
		if roue or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			for p: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var g := mi.global_transform * p
				var q := vers_voiture * g
				var k := int(floor(q.z / 0.03))
				if not tranches.has(k) or q.y < float((tranches[k] as Array)[0]):
					tranches[k] = [q.y, vers_modele * g]
	# une tranche dont le point le plus bas est haut (la visière du toit d'un fourgon, qui dépasse du reste) n'est pas du
	# dessous : son rayon de mesure partirait au-dessus de la barre de hauteur et la prendrait pour le sol
	var haut_max := (_voiture.call("boite_caisse") as AABB).position.y + 0.8
	var out := PackedVector3Array()
	for k in tranches:
		if float((tranches[k] as Array)[0]) < haut_max:
			out.append((tranches[k] as Array)[1])
	return out


func _garde_dessous() -> float:
	if _dessous.is_empty():
		return INF
	var modele: Node3D = _voiture.get("_model")
	var xf := modele.global_transform
	var espace := get_world_3d().direct_space_state
	var exclus: Array[RID] = _voiture.call("rids_exclus")
	var mini := INF
	for q in _dessous:
		var p := xf * q
		var hit := espace.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.6, p + Vector3.DOWN * 1.5, 1, exclus))
		if not hit.is_empty():
			mini = minf(mini, p.y - (hit["position"] as Vector3).y)
	return mini


# --- phases (rendent true quand elles sont finies) ---------------------------------------------------------------

func _p_repos(_phase: String) -> bool:
	if not _e.has("pose"):
		_e["pose"] = true
		_placer(DEPART_ACCEL, _cap_vers_x())
		return false
	_pedales()
	if _t < 1.5:
		return false
	_h_repos = _voiture.global_position.y
	if _dessous.is_empty():
		_dessous = _profil_dessous()
	var rayons: Dictionary = _voiture.get("_wheel_radius")
	var centres: Dictionary = _voiture.get("_wheel_centre")
	var pneus := 0.0
	for w: Node3D in _voiture.get("_wheels"):
		var c: Vector3 = w.global_transform * (centres.get(w, Vector3.ZERO) as Vector3)
		pneus = maxf(pneus, absf(c.y - float(rayons.get(w, 0.3))))
	_res["repos"] = {"garde_coque": _garde_coque(), "garde_dessous": _garde_dessous(), "pneus": pneus, "penche": _penche()}
	return true


func _p_acceleration(_phase: String) -> bool:
	var v := _v()
	if not _e.has("t50"):
		_e["t50"] = -1.0
		_e["t100"] = -1.0
		_e["vmax"] = 0.0
		_e["rapport_max"] = 0
		_e["montees"] = 0
		_e["hesitations"] = 0
		_e["rapport"] = int(_ch.get("gear"))
		_e["t_vmax"] = -1.0
	_pedales(true)
	var g := int(_ch.get("gear"))
	if g != int(_e["rapport"]):
		if g > int(_e["rapport"]):
			_e["montees"] = int(_e["montees"]) + 1
		elif int(_e["rapport"]) > 0 and v > 3.0:
			_e["hesitations"] = int(_e["hesitations"]) + 1
		_e["rapport"] = g
	_e["rapport_max"] = maxi(int(_e["rapport_max"]), g)
	if float(_e["t50"]) < 0.0 and v >= 50.0 * KMH:
		_e["t50"] = _t
	if float(_e["t100"]) < 0.0 and v >= 100.0 * KMH:
		_e["t100"] = _t
	if v > float(_e["vmax"]) + 0.05:
		_e["vmax"] = v
		_e["t_vmax"] = _t
	var plafond := _t - float(_e["t_vmax"]) > 4.0 and _t > 8.0
	if _t < ACCEL_DUREE and not plafond:
		return false
	_res["acceleration"] = {"t50": _e["t50"], "t100": _e["t100"], "vmax": float(_e["vmax"]) * 3.6, "t_vmax": _e["t_vmax"],
			"rapport_max": _e["rapport_max"], "montees": _e["montees"], "hesitations": _e["hesitations"]}
	return true


func _p_freinage(_phase: String) -> bool:
	var v0 := minf(100.0 * KMH, _vmax() * 0.95)
	if not _e.has("phase"):
		_e["phase"] = "lance"
		_placer(DEPART_FREIN, _cap_vers_x(), v0)
		return false
	match String(_e["phase"]):
		"lance":
			_regule(v0)
			if _t > 2.0:
				_e["phase"] = "freine"
				_e["x0"] = _voiture.global_position
				_e["cap0"] = _voiture.rotation.y
				_e["t0"] = _t
				_e["v0"] = _v()
		"freine":
			_pedales(false, true)
			if _trace and Engine.get_physics_frames() % 6 == 0:
				var gl := []
				for w in _ch.get("roues"):
					gl.append("%s %.1f" % [w.name, float(w.wv) * float(w.w_size) * float(_ch.get("LengthScale")) - _v()])
				print("BANC_FREIN %s t=%.2f v=%.1f km/h pedale=%.2f ligne=%.2f abs=%.2f glisse=%s" % [_id(), _t - float(_e["t0"]),
						_v() * 3.6, float(_ch.get("brakepedal")), float(_ch.get("brakeline")), float(_ch.get("brake_allowed")), str(gl)])
			if _v() < 0.3:
				var d := (_voiture.global_position - (_e["x0"] as Vector3))
				d.y = 0.0
				var dcap := rad_to_deg(absf(wrapf(_voiture.rotation.y - float(_e["cap0"]), -PI, PI)))
				_res["freinage"] = {"v0": float(_e["v0"]) * 3.6, "distance": d.length(), "temps": _t - float(_e["t0"]), "cap": dcap}
				return true
			if _t - float(_e.get("t0", _t)) > 20.0:
				_res["freinage"] = {"v0": float(_e["v0"]) * 3.6, "distance": -1.0, "temps": -1.0, "cap": 0.0}
				return true
	return false


func _p_virage(phase: String) -> bool:
	var cible := _vmax() if phase == "virage_vmax" else float(phase.substr(7)) * KMH
	if cible > _vmax() + 0.5:
		return true      # au-delà de sa vitesse de pointe
	if not _e.has("phase"):
		_e["phase"] = "ligne"
		_e["penche"] = 0.0
		_e["up_min"] = 1.0
		_e["leve"] = 0.0
		_e["leve_max"] = 0.0
		_e["a_lat"] = 0.0
		_e["derive"] = 0.0
		_e["v_braque"] = 0.0
		_placer(DEPART_VIRAGE, _cap_vers_x(), cible)
		return false
	var up := _ch.global_transform.basis.y.dot(Vector3.UP)
	_e["up_min"] = minf(float(_e["up_min"]), up)
	_e["penche"] = maxf(float(_e["penche"]), _penche())
	var leve := _roues_en_l_air()
	if leve.x + leve.y > 0:
		_e["leve"] = float(_e["leve"]) + get_physics_process_delta_time()
		_e["leve_max"] = maxf(float(_e["leve_max"]), float(_e["leve"]))
	else:
		_e["leve"] = 0.0
	var vh := _ch.linear_velocity
	vh.y = 0.0
	match String(_e["phase"]):
		"ligne":
			_regule(cible)
			if _t > VIRAGE_LIGNE:
				_e["phase"] = "braque"
				_e["t0"] = _t
				_e["v_braque"] = _v()
		"braque":
			_regule(cible, true)
			# accélération latérale VRAIE : la variation de la vitesse perpendiculaire à elle-même, sur 10 pas (v x lacet
			# la surestime dès que la voiture pivote plus vite que sa trajectoire ne tourne)
			var hist: Array = _e.get("hist", [])
			hist.append(vh)
			if hist.size() > 10:
				hist.pop_front()
				var dv: Vector3 = (hist.back() as Vector3) - (hist.front() as Vector3)
				var dir := ((hist.back() as Vector3) + (hist.front() as Vector3)).normalized()
				var a_perp := (dv - dir * dv.dot(dir)).length() / (9.0 / 60.0)
				_e["a_lat"] = maxf(float(_e["a_lat"]), a_perp)
			_e["hist"] = hist
			var avant := _ch.global_transform.basis.z
			avant.y = 0.0
			if vh.length() > 2.0 and avant.length() > 0.1:
				_e["derive"] = maxf(float(_e["derive"]), rad_to_deg(vh.normalized().angle_to(avant.normalized())))
			if _t - float(_e["t0"]) > VIRAGE_BRAQUE:
				_e["phase"] = "apres"
				_e["t0"] = _t
		"apres":
			_pedales()
			if _t - float(_e["t0"]) > VIRAGE_APRES:
				_res[phase] = {"v": float(_e["v_braque"]) * 3.6, "penche": _e["penche"], "up_min": _e["up_min"],
						"leve": _e["leve_max"], "a_lat": _e["a_lat"], "derive": _e["derive"], "up_fin": up}
				return true
	return false


func _p_bordure(phase: String) -> bool:
	var cle := phase.substr(8, 2)
	var biais := phase.ends_with("biais")
	var centre: Vector3 = BORDURES[cle][0]
	var corps: StaticBody3D = _bordures[cle]
	var cap := deg_to_rad(30.0) if biais else 0.0
	var avant := Vector3(-sin(cap), 0.0, -cos(cap))
	if not _e.has("depart"):
		var face := Vector3(centre.x, 0.0, centre.z + BORDURE_TAILLE.y * 0.5)
		_e["depart"] = face - avant * 9.0
		_e["contact"] = 0
		_e["garde"] = INF
		_placer(_e["depart"], cap)
		return false
	if _t < 0.5:
		_pedales()
		return false
	_regule(3.0)
	if _contacts(corps):
		_e["contact"] = int(_e["contact"]) + 1
		if _trace:
			_trace_contacts(corps, phase)
	var g := _garde_dessous()
	_e["garde"] = minf(float(_e["garde"]), g)
	var parcours := (_voiture.global_position - (_e["depart"] as Vector3)).dot(avant)
	if parcours < 9.0 + BORDURE_TAILLE.y / cos(cap) + 5.0 and _t < 30.0:
		return false
	_res[phase] = {"contact": _e["contact"], "garde_dessous": _e["garde"], "franchie": parcours >= 9.0 + BORDURE_TAILLE.y / cos(cap) + 5.0}
	return true


func _p_parking(_phase: String) -> bool:
	var hauteur: float = (_voiture.call("boite_caisse") as AABB).size.y - 0.04
	if hauteur > BARRE:
		_res["parking"] = {"trop_haut": hauteur}
		return true
	if not _e.has("k"):
		_e["k"] = 0
		_e["lignes"] = []
		_e["contact"] = 0
		_e["garde"] = INF
		_placer(PARKING_POS + Vector3(0.0, 0.0, 24.0), 0.0)
		return false
	var vitesse := 4.0 if int(_e["k"]) == 0 else 7.0
	var z := _voiture.global_position.z - PARKING_POS.z
	if _t < 0.5:
		_pedales()
		return false
	if z > 1.0:
		_regule(vitesse)
		if _contacts(_parking):
			_e["contact"] = int(_e["contact"]) + 1
		if z < 20.0:
			var g := _garde_dessous()
			_e["garde"] = minf(float(_e["garde"]), g)
			if _trace and (Engine.get_physics_frames() % 6 == 0 or g < 0.1):
				print("BANC_PARKING %s z=%.2f y=%.3f v=%.1f garde=%.3f tangage=%.1f°" % [_id(), z, _voiture.global_position.y, _v(), g,
						rad_to_deg(asin(clampf(_ch.global_transform.basis.z.y, -1.0, 1.0)))])
		return false
	if _v() > 0.3:
		_pedales(false, true)
		return false
	_e["k"] = int(_e["k"]) + 1
	if int(_e["k"]) < 2:
		_placer(PARKING_POS + Vector3(0.0, 0.0, 24.0), 0.0)
		_t = 0.0
		return false
	_res["parking"] = {"contact": _e["contact"], "garde_dessous": _e["garde"]}
	return true


# --- bilan -------------------------------------------------------------------------------------------------------

func _resume() -> void:
	var id := _id()
	var f := _fiche()
	var morceaux: Array[String] = []
	var r: Dictionary = _res.get("repos", {})
	if not r.is_empty():
		morceaux.append("repos : coque à %.3f m du sol, dessous du modèle à %.3f m, pneus à %.3f m" % [r["garde_coque"], r["garde_dessous"], r["pneus"]])
	var a: Dictionary = _res.get("acceleration", {})
	if not a.is_empty():
		morceaux.append("0-50 %s, 0-100 %s, %.0f km/h atteints (%s), rapport %d, %d rétrogradage(s) en pleine accélération" % [
				_temps(a["t50"]), _temps(a["t100"]), a["vmax"], _temps(a["t_vmax"]), a["rapport_max"], a["hesitations"]])
		if int(a["rapport_max"]) < 2:
			_faute("%s : la boîte ne quitte pas la première" % id)
		var cible50 := minf(50.0, FichesVehicules.nombre(f, "vitesse_max_kmh") * 0.9)
		if a["vmax"] < cible50 - 0.1 and (float(a["t50"]) < 0.0 or float(a["t50"]) > 30.0):
			_faute("%s : %.0f km/h pas atteints en 30 s (%.0f au plus)" % [id, cible50, a["vmax"]])
	var fr: Dictionary = _res.get("freinage", {})
	if not fr.is_empty():
		morceaux.append("freinage depuis %.0f km/h : %.1f m en %.2f s, cap %.1f°" % [fr["v0"], fr["distance"], fr["temps"], fr["cap"]])
		if float(fr["cap"]) > 15.0 or float(fr["distance"]) < 0.0:
			_faute("%s : freinage instable (cap %.1f°, distance %.1f m)" % [id, fr["cap"], fr["distance"]])
	for ph in ["virage_50", "virage_80", "virage_110", "virage_vmax"]:
		var v: Dictionary = _res.get(ph, {})
		if v.is_empty():
			continue
		morceaux.append("%s (%.0f km/h) : %.1f° de roulis, %.1f m/s², dérive %.0f°, roues levées %.2f s, caisse %.0f° au pire" % [
				ph, v["v"], _roulis(v), v["a_lat"], v["derive"], v["leve"], rad_to_deg(acos(clampf(v["up_min"], -1.0, 1.0)))])
		if float(v["up_min"]) < cos(deg_to_rad(45.0)) or float(v["up_fin"]) < 0.9:
			_faute("%s : %s, le véhicule se couche (caisse à %.0f°)" % [id, ph, rad_to_deg(acos(clampf(v["up_min"], -1.0, 1.0)))])
		if float(v["leve"]) > 0.3:
			_faute("%s : %s, deux roues d'un même côté en l'air %.2f s" % [id, ph, v["leve"]])
	for ph in ["bordure_15_face", "bordure_15_biais", "bordure_17_face", "bordure_17_biais"]:
		var b: Dictionary = _res.get(ph, {})
		if b.is_empty():
			continue
		morceaux.append("%s : coque %d pas, dessous du modèle %.3f m%s" % [ph, b["contact"], b["garde_dessous"], "" if b["franchie"] else ", PAS FRANCHIE"])
		if int(b["contact"]) > 0:
			_faute("%s : %s, la coque touche (%d pas)" % [id, ph, b["contact"]])
		if not bool(b["franchie"]):
			_faute("%s : %s pas franchie" % [id, ph])
	var p: Dictionary = _res.get("parking", {})
	if p.has("trop_haut"):
		morceaux.append("parking : %.2f m de haut, arrêté par la barre" % p["trop_haut"])
	elif not p.is_empty():
		morceaux.append("entrée de parking : coque %d pas, dessous du modèle %.3f m" % [p["contact"], p["garde_dessous"]])
		if int(p["contact"]) > 0:
			_faute("%s : entrée de parking, la coque touche (%d pas)" % [id, p["contact"]])
	print("CHASSIS_BANC %s (%s kg, %s kW, %s km/h) : %s" % [id, FichesVehicules.nombre(f, "masse_kg"),
			FichesVehicules.nombre(f, "puissance_kw"), FichesVehicules.nombre(f, "vitesse_max_kmh"), " ; ".join(morceaux)])
	_tableau.append(JSON.stringify({"id": id, "res": _res}))


func _roulis(v: Dictionary) -> float:
	return float(v["penche"])


func _temps(t) -> String:
	return "%.1f s" % float(t) if float(t) >= 0.0 else "—"


func _fin() -> void:
	_pedales()
	for l in _tableau:
		print("CHASSIS_BANC_JSON " + l)
	print("CHASSIS_BANC_RESULT %s" % ("OK" if _fautes.is_empty() else "FAIL : " + " ; ".join(_fautes)))
	CarScript.conduite_reelle = false
	get_tree().quit()
