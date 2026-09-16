@tool
extends EditorScenePostImport
## Script de post-import des bâtiments Everything Library (assigné dans leurs .glb.import) : leurs couleurs
## sont des couleurs de sommets COLOR_0 sans texture, mais l'import glTF de Godot 4.7 n'active pas
## "vertex_color_use_as_albedo" sur leurs matériaux, ce qui les rend blancs. On l'active sur chaque
## matériau dont la surface porte des couleurs de sommets.


func _post_import(scene: Node) -> Object:
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	if scene is MeshInstance3D:
		meshes.append(scene)
	for node in meshes:
		var mesh := (node as MeshInstance3D).mesh as ArrayMesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			if (mesh.surface_get_format(s) & Mesh.ARRAY_FORMAT_COLOR) == 0:
				continue
			var mat := mesh.surface_get_material(s) as BaseMaterial3D
			if mat != null:
				mat.vertex_color_use_as_albedo = true
	return scene
