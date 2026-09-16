extends GPUParticles3D

# Éclaboussure de sang : émet une fois puis se libère.

func _ready() -> void:
	one_shot = true
	emitting = true
	await get_tree().create_timer(lifetime + 0.4).timeout
	queue_free()
