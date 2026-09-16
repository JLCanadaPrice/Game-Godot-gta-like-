extends Node3D

# Balle purement visuelle : la détection de touche est faite par le raycast
# côté Player. Ici on se contente d'aller vite en ligne droite du canon vers
# le point d'impact, puis de se détruire.

const SPEED := 200.0
const MAX_LIFETIME := 0.7

var _target: Vector3
var _life := 0.0

func setup(from: Vector3, to: Vector3) -> void:
	global_position = from
	_target = to
	var dir := to - from
	if dir.length() > 0.05 and absf(dir.normalized().dot(Vector3.UP)) < 0.99:
		look_at(to, Vector3.UP)

func _process(delta: float) -> void:
	_life += delta
	var to_target := _target - global_position
	var step := SPEED * delta
	if to_target.length() <= step or _life >= MAX_LIFETIME:
		queue_free()
		return
	global_position += to_target.normalized() * step
