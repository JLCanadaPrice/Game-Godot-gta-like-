extends Node3D

# Harnais de test de conduite (headless) : pose PlayerCarPhysics.tscn a plat
# sur le sol (Controlled = true), puis simule au clavier virtuel
# (Input.action_press/release) trois phases successives - acceleration en
# ligne droite, virage a pleine gaz, freinage jusqu'a l'arret - et imprime
# vitesse/inclinaison/cap a chaque tick physique. Sert a confirmer que le
# correctif anti-tonneau (car.gd:_anti_rollover_correction) n'interfere pas
# avec le feeling de conduite normal (severite doit rester a 0 tant que les
# 4 roues restent a peu pres egalement chargees).
#
# Lancer : Godot --headless --fixed-fps 60 res://scenes/tests/CarDrivingTest.tscn

const REST_Y := 2.57 # hauteur de repos empirique (cf. essais de chute)
const PHASE_ACCEL := 4.0
const PHASE_TURN := 3.0
const PHASE_BRAKE := 4.0

@onready var car: RigidBody3D = $PlayerCarPhysics

var _t := 0.0
var _phase := 0
var _phase_t := 0.0
var _min_up_dot := 1.0

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
	elif _phase == 2:
		phase_name = "brake"
		Input.action_press("brake")
		if _phase_t >= PHASE_BRAKE:
			_phase = 3
			_phase_t = 0.0
	else:
		phase_name = "done"

	var speed := car.linear_velocity.length()
	var up_dot : float = car.global_transform.basis.y.dot(Vector3.UP)
	_min_up_dot = minf(_min_up_dot, up_dot)
	var yaw_deg : float = car.rotation_degrees.y

	print("t=%.3f phase=%s speed=%.3f up_dot=%.4f yaw=%.2f pos=(%.2f,%.2f,%.2f)" % [
		_t, phase_name, speed, up_dot, yaw_deg,
		car.global_position.x, car.global_position.y, car.global_position.z])

	if _phase == 3 and _phase_t >= 0.5 and speed < 0.05:
		print("DRIVE_TEST_END final_speed=%.4f min_up_dot=%.4f yaw=%.2f" % [speed, _min_up_dot, yaw_deg])
		get_tree().quit()
	elif _t >= PHASE_ACCEL + PHASE_TURN + PHASE_BRAKE + 4.0:
		print("DRIVE_TEST_END(timeout) final_speed=%.4f min_up_dot=%.4f yaw=%.2f" % [speed, _min_up_dot, yaw_deg])
		get_tree().quit()
