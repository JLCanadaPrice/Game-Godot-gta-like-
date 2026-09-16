extends Node3D

# Bâtiments d'une cellule de la carte 3D (DistrictsBake) affichés par instanciation GPU : un MultiMeshInstance3D par
# modèle, construit au démarrage à partir des positions cuites (un MultiMesh cuit sans serveur de rendu perd ses
# positions, elles sont donc gardées ici en tableau). Collision et occulteurs sont des noeuds statiques à côté.

@export var meshes: Array[Mesh] = []
# par modèle : STRIDE flottants par bâtiment (base x, y, z, origine, teinte r, g, b, a)
@export var instance_data: Array[PackedFloat32Array] = []
@export var ranges := PackedFloat32Array()                  # par modèle : portée de visibilité (m)
@export var shadows := true
# facultatif, par modèle : 4 flottants par instance (INSTANCE_CUSTOM des shaders, ex. espèce d'arbre lointain)
@export var instance_custom: Array[PackedFloat32Array] = []

const STRIDE := 16


func _ready() -> void:
	for i in mini(meshes.size(), instance_data.size()):
		var data := instance_data[i]
		var count := data.size() / STRIDE
		if count == 0 or meshes[i] == null:
			continue
		var custom := instance_custom[i] if i < instance_custom.size() else PackedFloat32Array()
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.use_custom_data = custom.size() >= count * 4
		multimesh.mesh = meshes[i]
		multimesh.instance_count = count
		for n in count:
			var o := n * STRIDE
			var basis := Basis(Vector3(data[o], data[o + 1], data[o + 2]), Vector3(data[o + 3], data[o + 4], data[o + 5]), Vector3(data[o + 6], data[o + 7], data[o + 8]))
			multimesh.set_instance_transform(n, Transform3D(basis, Vector3(data[o + 9], data[o + 10], data[o + 11])))
			multimesh.set_instance_color(n, Color(data[o + 12], data[o + 13], data[o + 14], data[o + 15]))
			if multimesh.use_custom_data:
				multimesh.set_instance_custom_data(n, Color(custom[n * 4], custom[n * 4 + 1], custom[n * 4 + 2], custom[n * 4 + 3]))
		var instance := MultiMeshInstance3D.new()
		instance.name = "Model_%d" % i
		instance.multimesh = multimesh
		instance.visibility_range_end = ranges[i] if i < ranges.size() else 700.0
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
