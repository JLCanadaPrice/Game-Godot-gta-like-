extends Node3D

# Harnais de test automatisé (headless) : lâche PlayerCarPhysics.tscn depuis
# DROP_HEIGHT au-dessus d'un sol plat, sans contrôle joueur (Controlled reste
# false), et imprime l'état physique réel (y, dérive latérale XZ depuis le
# point de chute, vitesse linéaire/angulaire) à chaque tick physique jusqu'à
# DURATION secondes ou stabilisation soutenue, puis quitte.
#
# Lancer : Godot --headless --fixed-fps 60 res://scenes/tests/CarDropTest.tscn

@export var DROP_HEIGHT := 10.0
const DURATION := 8.0
const SETTLE_LIN_EPS := 0.05
const SETTLE_ANG_EPS := 0.05
const SETTLE_HOLD := 0.5

# Isolation du diagnostic "boucle d'assistance au braquage" (car.gd:
# steer = ... - velocity.x*assist + rvelocity.y*assistAngular, active dès que
# assistance_factor > 0, donc même à l'arrêt / sans aucune entrée joueur).
@export var disable_steering_assist := false

@export var debug_wheel_forces := false

@onready var car: RigidBody3D = $PlayerCarPhysics
@onready var _wheels := {
	"fr": car.get_node("fr"),
	"fl": car.get_node("fl"),
	"rr": car.get_node("rr"),
	"rl": car.get_node("rl"),
}

var _spawn_xz := Vector2.ZERO
var _t := 0.0
var _settle_hold_t := 0.0
var _settle_time := -1.0

func _ready() -> void:
	car.global_position = Vector3(0.0, DROP_HEIGHT, 0.0)
	car.rotation = Vector3.ZERO
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	_spawn_xz = Vector2(car.global_position.x, car.global_position.z)

	var assist_note := "unchanged"
	if disable_steering_assist:
		var sim := get_node_or_null("/root/VitaVehicleSimulation")
		if sim != null:
			sim.set("SteeringAssistance", 0.0)
			sim.set("SteeringAssistanceAngular", 0.0)
			assist_note = "SteeringAssistance=0 SteeringAssistanceAngular=0"
		else:
			assist_note = "AUTOLOAD INTROUVABLE"

	print("DROP_TEST_BEGIN height=%.3f mass=%.2f steering_assist=%s" % [DROP_HEIGHT, car.mass, assist_note])

func _physics_process(delta: float) -> void:
	_t += delta
	var y := car.global_position.y
	var xz := Vector2(car.global_position.x, car.global_position.z)
	var drift := xz.distance_to(_spawn_xz)
	var lin := car.linear_velocity.length()
	var ang := car.angular_velocity.length()
	var up_dot : float = car.global_transform.basis.y.dot(Vector3.UP)

	print("t=%.3f y=%.4f drift=%.4f lin=%.4f ang=%.4f up_dot=%.4f avel=%s" % [_t, y, drift, lin, ang, up_dot, car.angular_velocity])

	if debug_wheel_forces and int(_t*60.0) % 30 == 0:
		for wname in ["fr", "fl", "rr", "rl"]:
			var w = _wheels[wname]
			var f: Vector3 = w.directional_force
			print("  wheel=%s colliding=%s global_y=%.4f Fx=%.4f Fy=%.4f Fz=%.4f compress=%.4f rd=%.4f" % [
				wname, w.is_colliding(), w.global_position.y, f.x, f.y, f.z, w.compress, w.rd])

	if lin < SETTLE_LIN_EPS and ang < SETTLE_ANG_EPS:
		_settle_hold_t += delta
		if _settle_hold_t >= SETTLE_HOLD and _settle_time < 0.0:
			_settle_time = _t
	else:
		_settle_hold_t = 0.0

	if _t >= DURATION or (_settle_time > 0.0 and _t >= _settle_time + 1.0):
		print("DROP_TEST_END final_y=%.4f final_drift=%.4f settle_time=%s up_dot=%.4f rotation_deg=%s" % [
			y, drift, ("%.3f" % _settle_time) if _settle_time > 0.0 else "none",
			up_dot, car.rotation_degrees])
		get_tree().quit()
