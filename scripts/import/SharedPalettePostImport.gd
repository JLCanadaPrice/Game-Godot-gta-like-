@tool
extends EditorScenePostImport
## Post-import des packs de véhicules à palette unique (assigné dans leurs .glb.import). Chaque .glb embarque
## sa propre copie de la même palette, que Godot extrairait en une texture par fichier, chargée séparément en
## mémoire vidéo (205 copies pour City Vehicles). On branche à la place UNE palette partagée par pack.
##  - City Vehicles : import en "Discard All Textures" ; les 205 matériaux utilisent tous la palette (vérifié
##    dans les .glb), elle est donc posée sur chaque matériau.
##  - Low Poly Cars : extraction conservée car quelques matériaux sont unis ; seule une texture existante est
##    remplacée par la palette partagée.

const PACKS := {
	"res://assets/vehicle_models_extra/city_vehicles_UNVERIFIED_LICENSE/": {
		"palette": "res://assets/vehicle_models_extra/city_vehicles_UNVERIFIED_LICENSE/city_vehicles_palette.png",
		"all_materials": true,
	},
	"res://assets/vehicle_models_extra/lowpoly_cars_free_cc0/": {
		"palette": "res://assets/vehicle_models_extra/lowpoly_cars_free_cc0/lowpoly_cars_palette.png",
		"all_materials": false,
	},
}


func _post_import(scene: Node) -> Object:
	var source := get_source_file()
	for folder: String in PACKS:
		if not source.begins_with(folder):
			continue
		var pack: Dictionary = PACKS[folder]
		var palette := load(pack.palette) as Texture2D
		if palette == null:
			push_error("palette partagée introuvable : %s (import de %s)" % [pack.palette, source])
			return scene
		for node in scene.find_children("*", "MeshInstance3D", true, false):
			var mesh := (node as MeshInstance3D).mesh
			if mesh == null:
				continue
			for s in mesh.get_surface_count():
				var mat := mesh.surface_get_material(s) as BaseMaterial3D
				if mat != null and (pack.all_materials or mat.albedo_texture != null):
					mat.albedo_texture = palette
		break
	return scene
