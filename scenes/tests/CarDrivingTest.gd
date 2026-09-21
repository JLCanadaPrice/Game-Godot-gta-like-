extends Node3D

# Harnais de test de conduite (headless) : pose PlayerCarPhysics.tscn a plat
# sur le sol (Controlled = true), puis simule au clavier virtuel
# (Input.action_press/release) trois phases successives - acceleration en
# ligne droite, virage a pleine gaz, freinage jusqu'a l'arret - et imprime
# vitesse/inclinaison/cap a chaque tick physique.
#
# Depuis le 2026-09-21 la sonde rend aussi un verdict (CAR_DRIVING_RESULT) : elle ne rendait que des
# chiffres, et une batterie qui ne cherche qu'une ligne RESULT a manqué en silence que la voiture
# finissait sur le toit. Critères : la caisse ne penche jamais au-delà de 18° (min_up_dot >= 0,95) et
# la voiture s'arrête pendant le freinage puis reste arrêtée.
#
# Le frein est relâché DÈS L'ARRÊT, comme le ferait un conducteur : la boîte automatique du pack passe
# en marche arrière quand on garde le frein enfoncé à l'arrêt (frein maintenu = recul, voulu). Avant
# le 2026-09-21 la sonde tenait le frein 4 s d'affilée ; avec une voiture qui s'arrête en ~1,3 s, elle
# aurait mesuré la marche arrière et non le freinage.
#
# Lancer : Godot --headless --fixed-fps 60 res://scenes/tests/CarDrivingTest.tscn

# Hauteur de repos MESURÉE (2026-09-21) : origine à sol + 0,6785 m, depuis que les rayons de roue sont
# à l'échelle (0,81 m). L'ancienne valeur 2,57 m venait des rayons de 2,7 m laissés à l'échelle du pack.
const REST_Y := 0.68
const PHASE_ACCEL := 4.0
const PHASE_TURN := 3.0
const PHASE_BRAKE := 4.0 # durée MAXIMALE du freinage ; il s'arrête plus tôt si la voiture est arrêtée
const STOP_SPEED := 0.05
const MIN_UP_DOT_OK := 0.95

@onready var car: RigidBody3D = $PlayerCarPhysics

var _t := 0.0
var _phase := 0
var _phase_t := 0.0
var _min_up_dot := 1.0
var _brake_from := Vector3.ZERO
var _brake_speed := 0.0
var _stop_time := -1.0
var _stop_dist := -1.0

func _ready() -> void:
	car.global_position = Vector3(0.0, REST_Y, 0.0)
	car.rotation = Vector3.ZERO
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.Controlled = true
	print("DRIVE_TEST_BEGIN mass=%.2f" % car.mass)

func _physics_process(delta: float) -> void:
	_t += delta
	_phase_t += delta

	Input.action_release("gas")
	Input.action_release("brake")
	Input.action_release("left")
	Input.action_release("right")

	var speed := car.linear_velocity.length()
	var phase_name := ""
	if _phase == 0:
		phase_name = "accel"
		Input.action_press("gas")
		if _phase_t >= PHASE_ACCEL:
			_phase = 1
			_phase_t = 0.0
	elif _phase == 1:
		phase_name = "turn"
		Input.action_press("gas")
		Input.action_press("right")
		if _phase_t >= PHASE_TURN:
			_phase = 2
			_phase_t = 0.0
			_brake_from = car.global_position
			_brake_speed = speed
	elif _phase == 2:
		phase_name = "brake"
		if speed < STOP_SPEED:
			# Arrêtée : on relâche le frein (sinon la boîte enclenche la marche arrière).
			_stop_time = _phase_t
			_stop_dist = Vector2(car.global_position.x - _brake_from.x, car.global_position.z - _brake_from.z).length()
			_phase = 3
			_phase_t = 0.0
		else:
			Input.action_press("brake")
			if _phase_t >= PHASE_BRAKE:
				_phase = 3
				_phase_t = 0.0
	else:
		phase_name = "done"

	var up_dot : float = car.global_transform.basis.y.dot(Vector3.UP)
	_min_up_dot = minf(_min_up_dot, up_dot)
	var yaw_deg : float = car.rotation_degrees.y

	print("t=%.3f phase=%s speed=%.3f up_dot=%.4f yaw=%.2f pos=(%.2f,%.2f,%.2f)" % [
		_t, phase_name, speed, up_dot, yaw_deg,
		car.global_position.x, car.global_position.y, car.global_position.z])

	var ended := ""
	if _phase == 3 and _phase_t >= 0.5 and speed < STOP_SPEED:
		ended = "DRIVE_TEST_END"
	elif _t >= PHASE_ACCEL + PHASE_TURN + PHASE_BRAKE + 4.0:
		ended = "DRIVE_TEST_END(timeout)"
	if ended != "":
		print("%s final_speed=%.5f min_up_dot=%.4f yaw=%.2f brake_from=%.2f stop_time=%.3f stop_dist=%.2f" % [
			ended, speed, _min_up_dot, yaw_deg, _brake_speed, _stop_time, _stop_dist])
		var fails := []
		if _min_up_dot < MIN_UP_DOT_OK:
			fails.append("caisse penchée au-delà de 18° (min_up_dot=%.4f)" % _min_up_dot)
		if _stop_time < 0.0:
			fails.append("jamais arrêtée pendant le freinage")
		if ended != "DRIVE_TEST_END":
			fails.append("pas arrêtée en fin de sonde (final_speed=%.4f)" % speed)
		print("CAR_DRIVING_RESULT %s" % ("OK" if fails.is_empty() else "FAIL : " + " ; ".join(fails)))
		get_tree().quit()
