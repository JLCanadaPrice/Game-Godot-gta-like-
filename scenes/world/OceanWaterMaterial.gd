extends Node3D

# Applique le materiau d'eau (shader) sur le mesh d'ocean instancie
# (ocean_mesh.glb) au runtime plutot que via un override de propriete
# serialise dans la scene : meme raison que LampPoleLayer.gd, on evite
# de toucher a un noeud interne d'une instance .glb dans le fichier
# .tscn sauvegarde.
@export var water_material: ShaderMaterial

func _ready() -> void:
	for c in get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).set_surface_override_material(0, water_material)
