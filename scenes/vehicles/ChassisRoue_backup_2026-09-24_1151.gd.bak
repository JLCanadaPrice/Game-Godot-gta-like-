extends "res://assets/car_physics/MAIN/wheel.gd"

# ROUE DU CHÂSSIS RÉEL (essai du 2026-09-24, cf. ChassisReel.gd et CLAUDE.md §13). La roue du pack VitaVehicle telle
# quelle — rayon, suspension, modèle de pneu —, avec deux ajouts qui ne touchent pas à sa physique :
#  - le temps passé dans son _physics_process, versé au châssis pour la mesure du coût (ChassisReel.cout_dernier_pas_us) ;
#  - `repartir(v)` : remet à jour les deux relevés de position dont le pack tire sa vitesse (`velocity_last`,
#    `velocity2_last`, différence d'une image à l'autre x 60). Faute de quoi, au premier pas après sa création ou après
#    un gel, la roue lit l'écart entre sa position et l'origine du monde (ou l'endroit où elle était gelée) comme une
#    vitesse, et l'amortisseur la renvoie en l'air.


func _physics_process(_delta):
	var t0 := Time.get_ticks_usec()
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
