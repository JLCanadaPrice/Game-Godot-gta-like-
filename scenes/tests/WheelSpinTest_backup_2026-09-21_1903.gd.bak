extends Node3D

# LES ROUES ROULENT À L'ENDROIT, sur TOUS les modèles du catalogue (2026-09-21).
#
# Le joueur voyait les roues « tourner vers le haut au lieu de rouler vers l'avant », sur toutes les
# voitures. Trois causes, mesurées sur les 72 modèles posés comme en jeu :
#  - sur les six modèles d'origine du jeu (normalcar1, normalcar2, sportscar, sportscar2, suv, taxi),
#    18 roues roulaient VRAIMENT à l'envers : leur X local pointe vers +X de la voiture, pas -X ;
#  - la roue avant droite de normalcar2 a son pivot à 0,32 m de son centre : elle tournait en excentrique ;
#  - partout ailleurs, le sens était juste, mais à la vitesse de croisière le pas par image dépassait la
#    demi-période de la jante (38° par image pour une jante octogonale de 45°) : l'oeil voyait la roue
#    reculer. C'est l'effet stroboscopique, et c'est lui que le joueur voyait sur « toutes » les voitures.
# Car._mesurer_roue donne maintenant à chaque roue son axe, son sens, son rayon réel, son centre et un pas
# maximal par image AFFICHÉE. Ce test pose une VRAIE Car de chaque modèle et vérifie, roue par roue, avec le
# vrai _update_visuals :
#  1. l'axe de roulement est l'essieu (le X de la voiture) ;
#  2. une vitesse POSITIVE fait avancer le HAUT du pneu vers l'avant de la voiture (-Z) ;
#  3. le rayon est plausible (0,15 à 0,8 m : le blindé SWAT porte des roues de 0,72 m, mesurées) ;
#  4. à 12 m/s et 60 images/s, le pas par image reste sous la moitié de la période de la jante ;
#  5. la roue tourne autour de SON CENTRE : le milieu de ses maillages ne bouge pas (normalcar2 avait une
#     roue au pivot décalé, qui tournait en excentrique) ;
#  6. IMAGE LENTE : à 15 images/s, quatre pas physiques de 1/60 s s'enchaînent entre deux images affichées
#     (_update_visuals tourne dans _physics_process). Leur somme reste sous la demi-période de la jante et
#     dans le bon sens, et l'image suivante tourne de nouveau — l'UHD 750 de référence rend entre 10 et 30
#     images/s, c'est là que l'effet stroboscopique reviendrait si le plafond valait par pas physique.
#
# Lancer : Godot --headless --path <projet> res://scenes/tests/WheelSpinTest.tscn

const CAR := preload("res://scenes/vehicles/Car.tscn")
const CATALOGUE := "res://resources/vehicle_models"
const V_PAS := 1.0             # m/s pour le contrôle de sens : un petit pas, sans ambiguïté
const DT := 0.05
const V_CROISIERE := 12.0      # m/s, vitesse de la circulation (CarSpawner)
const IMAGE := 1.0 / 60.0
const PAS_PAR_IMAGE_LENTE := 4 # pas physiques entre deux images affichées, à 15 images/s

var _fautes: Array[String] = []


func _ready() -> void:
	var d := DirAccess.open(CATALOGUE)
	var fichiers := Array(d.get_files()).filter(func(f): return f.ends_with(".tres"))
	fichiers.sort()
	var voitures: Array = []
	var k := 0
	for f: String in fichiers:
		var data = load(CATALOGUE.path_join(f))
		if data == null or data.model_paths.is_empty():
			continue
		var car := CAR.instantiate() as Node3D
		car.set("forced_model_path", String(data.model_paths[0]))
		add_child(car)
		car.global_position = Vector3(float(k) * 12.0, 200.0, 0.0)
		k += 1
		voitures.append([f.get_basename(), car])
	await get_tree().process_frame
	await get_tree().process_frame
	var roues_total := 0
	var pire_pivot := 0.0
	var pire_pivot_ou := ""
	var excentrees := PackedStringArray()
	var par_symetrie := {}
	var rayons := Vector2(INF, -INF)
	for pair: Array in voitures:
		var nom: String = pair[0]
		var car: Node3D = pair[1]
		car.set_physics_process(false)
		var roues: Array = car.get("_wheels")
		if roues.is_empty():
			_fautes.append("%s : aucune roue repérée" % nom)
			continue
		var inv_car := car.global_transform.affine_inverse()
		# sommet de chaque pneu, AVANT le pas
		var hauts := {}
		var centres := {}
		for w: Node3D in roues:
			hauts[w] = _sommet(w)
			centres[w] = _centre(w)
		car.call("_update_visuals", DT, V_PAS, 0.0)
		for w: Node3D in roues:
			roues_total += 1
			var m: Array = car.call("mesure_roue", w)
			if m.size() < 4:
				_fautes.append("%s / %s : aucune mesure de roue" % [nom, w.name])
				continue
			var axe: Vector3 = m[0]
			var rayon: float = m[1]
			var pas_max: float = m[2]
			var n_sym: int = m[3]
			# écart entre l'origine du noeud et le centre de la roue, DANS LE PLAN DE LA ROUE (l'écart le long de
			# l'essieu est sans effet), en mètres dans le repère de la voiture : c'est le rayon du cercle que la
			# roue décrivait quand elle tournait autour de l'origine de son noeud
			var ecart := inv_car.basis * w.global_transform.basis * (m[4] as Vector3)
			var ecart_pivot := Vector2(ecart.y, ecart.z).length()
			if ecart_pivot > 0.01:
				excentrees.append("%s/%s %.2f m" % [nom, w.name, ecart_pivot])
			if ecart_pivot > pire_pivot:
				pire_pivot = ecart_pivot
				pire_pivot_ou = "%s / %s" % [nom, w.name]
			par_symetrie[n_sym] = int(par_symetrie.get(n_sym, 0)) + 1
			if n_sym < 5:
				print("WHEEL_SPIN_DETAIL %s / %s : %d branches seulement, rayon %.3f m" % [nom, w.name, n_sym, rayon])
			rayons = Vector2(minf(rayons.x, rayon), maxf(rayons.y, rayon))
			# 1. essieu : l'axe de roulement, vu de la voiture, est latéral
			var b := inv_car.basis * w.global_transform.basis
			if absf((b * axe).normalized().x) < 0.9:
				_fautes.append("%s / %s : axe de roulement pas latéral (%s dans le repère de la voiture)" % [nom, w.name, str((b * axe).normalized())])
			# 2. sens : le haut du pneu va vers l'avant (-Z de la voiture)
			var avant: Array = hauts[w]
			var apres: Vector3 = w.global_transform * (avant[1] as Vector3)
			var depl := inv_car.basis * (apres - (avant[0] as Vector3))
			if depl.z >= 0.0:
				_fautes.append("%s / %s : le haut du pneu RECULE quand la voiture avance (%+.4f m vers l'avant)" % [nom, w.name, -depl.z])
			# 5. rotation autour du centre de la roue : son milieu ne bouge pas
			var derive := (_centre(w) - (centres[w] as Vector3)).length()
			if derive > 0.005:
				_fautes.append("%s / %s : la roue tourne en EXCENTRIQUE, son centre se deplace de %.3f m" % [nom, w.name, derive])
			# 3. rayon plausible
			if rayon < 0.15 or rayon > 0.8:
				_fautes.append("%s / %s : rayon %.3f m hors de 0,15 - 0,8 m" % [nom, w.name, rayon])
			# 4. stroboscope : à la vitesse de croisière, le pas par image reste sous la demi-période
			if n_sym > 1:
				var pas := minf(V_CROISIERE / rayon * IMAGE, pas_max)
				if pas >= PI / float(n_sym):
					_fautes.append("%s / %s : %.1f° par image à 12 m/s pour une jante de %d branches (demi-période %.1f°) : la roue paraîtrait reculer"
							% [nom, w.name, rad_to_deg(pas), n_sym, 180.0 / float(n_sym)])
	# 6. image lente : plusieurs pas physiques dans la MÊME image affichée
	await get_tree().process_frame
	var lentes := 0
	var pire_lente := 0.0
	var angles_avant := {}
	for pair: Array in voitures:
		var car: Node3D = pair[1]
		var ang: Dictionary = car.get("_wheel_angle")
		for w: Node3D in car.get("_wheels"):
			angles_avant[w] = float(ang.get(w, 0.0))
		for i in PAS_PAR_IMAGE_LENTE:
			car.call("_update_visuals", IMAGE, V_CROISIERE, 0.0)
	for pair: Array in voitures:
		var nom: String = pair[0]
		var car: Node3D = pair[1]
		var ang: Dictionary = car.get("_wheel_angle")
		for w: Node3D in car.get("_wheels"):
			var m: Array = car.call("mesure_roue", w)
			if m.size() < 4 or int(m[3]) <= 1:
				continue
			var tour := wrapf(float(ang[w]) - float(angles_avant[w]), -PI, PI)
			var demi := PI / float(m[3])
			lentes += 1
			pire_lente = maxf(pire_lente, tour / demi)
			if tour <= 0.0 or tour >= demi:
				_fautes.append("%s / %s : %.1f° entre deux images a 15 images/s pour une jante de %d branches (demi-periode %.1f°)"
						% [nom, w.name, rad_to_deg(tour), int(m[3]), rad_to_deg(demi)])
	# ... et l'image suivante roule de nouveau : le plafond vaut par image, il ne bloque pas la roue
	await get_tree().process_frame
	for pair: Array in voitures:
		var nom: String = pair[0]
		var car: Node3D = pair[1]
		var ang: Dictionary = car.get("_wheel_angle")
		var avant := {}
		for w: Node3D in car.get("_wheels"):
			avant[w] = float(ang.get(w, 0.0))
		car.call("_update_visuals", IMAGE, V_CROISIERE, 0.0)
		for w: Node3D in car.get("_wheels"):
			if wrapf(float(ang[w]) - float(avant[w]), -PI, PI) <= 0.0:
				_fautes.append("%s / %s : la roue ne tourne plus a l'image suivante" % [nom, w.name])
	print("WHEEL_SPIN_IMAGE_LENTE %d roues a 15 images/s (%d pas physiques par image) : pas le plus grand %.0f %% de la demi-periode de sa jante"
			% [lentes, PAS_PAR_IMAGE_LENTE, pire_lente * 100.0])
	var sym := PackedStringArray()
	var cles := par_symetrie.keys()
	cles.sort()
	for c in cles:
		sym.append("%d branches : %d" % [c, par_symetrie[c]])
	print("WHEEL_SPIN %d modeles, %d roues, rayons %.3f a %.3f m, symetries { %s }, pivot le plus decale %.3f m (%s)"
			% [voitures.size(), roues_total, rayons.x, rayons.y, ", ".join(sym), pire_pivot, pire_pivot_ou])
	print("WHEEL_SPIN_PIVOTS %d roue(s) au pivot hors du centre (> 1 cm dans le plan de la roue), toutes corrigees : %s"
			% [excentrees.size(), ", ".join(excentrees)])
	if _fautes.is_empty():
		print("WHEEL_SPIN_RESULT OK")
	else:
		for f in _fautes.slice(0, 40):
			print("WHEEL_SPIN_FAUTE %s" % f)
		print("WHEEL_SPIN_RESULT FAIL %d faute(s)" % _fautes.size())
	get_tree().quit(0)


# Milieu de la boîte monde des maillages d'une roue.
func _centre(w: Node3D) -> Vector3:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
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
				lo = lo.min(g)
				hi = hi.max(g)
	return (lo + hi) * 0.5


# Sommet du pneu dans le monde, et le même point dans le repère LOCAL de la roue : [monde, local].
func _sommet(w: Node3D) -> Array:
	var haut := Vector3(0, -INF, 0)
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
				if g.y > haut.y:
					haut = g
	return [haut, w.global_transform.affine_inverse() * haut]
