extends "res://assets/car_physics/MAIN/wheel.gd"

# ROUE DU CHÂSSIS RÉEL (essai du 2026-09-24, cf. ChassisReel.gd et CLAUDE.md §13). La roue du pack VitaVehicle telle
# quelle — rayon, suspension, modèle de pneu —, avec deux ajouts qui ne touchent pas à sa physique :
#  - le temps passé dans son _physics_process, versé au châssis pour la mesure du coût (ChassisReel.cout_dernier_pas_us) ;
#  - `repartir(v)` : remet à jour les deux relevés de position dont le pack tire sa vitesse (`velocity_last`,
#    `velocity2_last`, différence d'une image à l'autre x 60). Faute de quoi, au premier pas après sa création ou après
#    un gel, la roue lit l'écart entre sa position et l'origine du monde (ou l'endroit où elle était gelée) comme une
#    vitesse, et l'amortisseur la renvoie en l'air.
# Et un ABS ROUE PAR ROUE (2026-09-24, CLAUDE.md §14), qui remplace celui du pack (coupé par ChassisReel). Celui du pack
# agit sur la ligne de frein de TOUTES les roues à la fois, par à-coups (1, 0,5, 0) : à chaque relâchement, plus rien ne
# freine. Mesuré sur la berline à 100 km/h : 8,2 m/s² de moyenne pour 9,5 demandés, 52 m d'arrêt. Ici, seule la roue qui
# glisse de plus de ABS_GLISSE (+ ABS_RELATIF de la vitesse) est desserrée, progressivement, puis resserrée.

const ABS_GLISSE := 2.0          # m/s : le pneu du pack donne toute son adhérence vers 1,5 à 2 m/s de glissement
const ABS_RELATIF := 0.05
const ABS_DESSERRE := 0.8        # par pas, tant que la roue glisse trop
const ABS_RESSERRE := 0.08       # par pas, sinon
const ABS_MIN := 0.2
const ABS_V_MIN := 2.0           # m/s : en dessous, pas d'ABS (l'arrêt se finit roues bloquées, comme en vrai)

var _abs := 1.0
var _biais := -1.0


func _physics_process(_delta):
	var t0 := Time.get_ticks_usec()
	_abs_roue()
	super(_delta)
	if self == car.roues.back():
		car.apres_roues()   # résistance au roulement, traînée, adhérence à l'arrêt : après les impulsions des 4 roues
	car.cout_roues_us += Time.get_ticks_usec() - t0


# `v_monde` : vitesse du châssis au moment de la reprise ; `wv_depart` : vitesse de rotation qui y correspond (pas de
# glissement au premier pas).
func repartir(v_monde: Vector3, wv_depart: float) -> void:
	var pas := 1.0 / float(Engine.physics_ticks_per_second)
	velocity_last = $velocity.global_position - v_monde * pas
	velocity2_last = $geometry.global_position - v_monde * pas
	wv = wv_depart
	output_wv = wv_depart


# ABS de cette roue : sa part du freinage (B_Bias, réglée par ChassisReel) desserrée tant que la roue freinée tourne
# nettement moins vite que le sol ne défile sous elle.
func _abs_roue() -> void:
	if _biais < 0.0:
		_biais = B_Bias
	if car.brakeline <= 0.05 or not is_colliding():
		_abs = minf(1.0, _abs + ABS_RESSERRE)
	else:
		var avant := global_transform.basis.z
		var v_sol: float = (car.linear_velocity + car.angular_velocity.cross(global_position - car.global_position)).dot(avant)
		var v_roue: float = float(wv) * float(car._tailles.get(self, 1.0)) * float(car.LengthScale)
		if absf(v_sol) > ABS_V_MIN and signf(v_sol) * (v_roue - v_sol) < -(ABS_GLISSE + ABS_RELATIF * absf(v_sol)):
			_abs = maxf(ABS_MIN, _abs * ABS_DESSERRE)
		else:
			_abs = minf(1.0, _abs + ABS_RESSERRE)
	B_Bias = _biais * _abs
