extends Camera3D

# Caméra libre de la scène de tri des véhicules (outil de test). Vol sans collision ni gravité, souris capturée.
# Touches lues en BRUT (Input.is_key_pressed) et non par des actions du projet : la scène doit tourner seule, sans
# dépendre de la configuration d'entrées du jeu.
#
# ZQSD ou WASD : avancer / reculer / gauche / droite (les deux dispositions sont acceptées)
# Espace / Ctrl : monter / descendre        Maj : x4        molette : vitesse de croisière
# Échap : libérer la souris                 Entrée ou clic : la reprendre

const SPEED_MIN := 2.0
const SPEED_MAX := 120.0
const BOOST := 4.0
const SENSITIVITY := 0.0022

var speed := 18.0
var _yaw := 0.0
var _pitch := 0.0


func _ready() -> void:
	_yaw = rotation.y
	_pitch = rotation.x
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * SENSITIVITY
		_pitch = clampf(_pitch - motion.relative.y * SENSITIVITY, -1.5, 1.5)
		rotation = Vector3(_pitch, _yaw, 0.0)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			speed = clampf(speed * 1.25, SPEED_MIN, SPEED_MAX)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			speed = clampf(speed / 1.25, SPEED_MIN, SPEED_MAX)
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and (event as InputEventKey).pressed:
		var key := (event as InputEventKey).keycode
		if key == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif key == KEY_ENTER or key == KEY_KP_ENTER:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_UP):
		dir -= basis.z
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir += basis.z
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_LEFT):
		dir -= basis.x
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir += basis.x
	if Input.is_key_pressed(KEY_SPACE):
		dir += Vector3.UP
	if Input.is_key_pressed(KEY_CTRL):
		dir -= Vector3.UP
	if dir.length_squared() < 0.0001:
		return
	var v := speed * (BOOST if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	global_position += dir.normalized() * v * delta
