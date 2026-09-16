@tool
extends StaticBody3D

# Bâtiment décoratif non-interactif : simple bloc pour densifier les quartiers.
# Taille et teinte aléatoires — appliquées UNE FOIS puis figées (bake).

const Facade := preload("res://scripts/facade_factory.gd")

# true = les valeurs random ont déjà été posées et sauvegardées -> ne rien
# refaire au lancement (sinon le prop se re-randomise/dérive à chaque F5).
@export var baked := false

func _ready() -> void:
	# En éditeur (bake), c'est PropScatter qui appelle randomize_and_face()
	# explicitement. Au runtime, on ne (re)randomise que si pas encore figé.
	if Engine.is_editor_hint():
		return
	if not baked:
		randomize_and_face()

func randomize_and_face() -> void:
	scale = Vector3(
		randf_range(0.7, 1.6),
		randf_range(0.9, 3.4),
		randf_range(0.7, 1.6))
	position += Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-3.0, 3.0))
	rotate_y(randf_range(-0.25, 0.25))

	var mi: MeshInstance3D = $MeshInstance3D
	if mi.mesh != null:
		mi.material_override = Facade.build(mi.get_aabb().size, mi.global_transform.basis.get_scale())
