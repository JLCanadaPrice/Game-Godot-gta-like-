extends SceneTree

# EXPORT POUR LES ENVELOPPES PAR PIÈCE (2026-09-23, CLAUDE.md §12). Les camions, bus et pick-up ont leurs enveloppes de
# déplacement faites PAR PIÈCE dans Blender (enveloppes_pieces.py) : une enveloppe convexe unique relie le toit de la
# cabine au bout de la benne. Cet outil écrit, pour ces modèles, les triangles de chaque pièce (caisse, roues, pièces
# séparées comme la tourelle du blindé) dans le repère de la VOITURE, posés exactement comme Car._setup_model pose le
# modèle (échelle, lacet et décalage du catalogue). Rien n'est écrit dans le projet : le fichier va où on le dit.
#
# Chaîne :
#   Godot --headless --path <projet> --script res://scenes/vehicles/tools/EnveloppesExport.gd -- --sortie=<export.json>
#   blender -b --factory-startup --python scenes/vehicles/tools/enveloppes_pieces.py -- --entree=<export.json>
#       --sortie=<projet>/scenes/vehicles/enveloppes_pieces.json --images=<dossier hors du dépôt>

const VehicleCatalog := preload("res://scripts/data/VehicleCatalog.gd")
# mêmes familles que WheelSpinTest (FAMILLES)
const FAMILLES := {"bus": ["city_bus", "city_coach"],
		"camion": ["city_truck", "city_garbage", "city_firetruck", "city_utility", "city_police_truck", "city_swat"],
		"pick-up": ["city_pickup"]}


func _init() -> void:
	var sortie := "user://enveloppes_export.json"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sortie="):
			sortie = a.get_slice("=", 1)
	var export := {}
	for m in VehicleCatalog.models():
		var famille := _famille(m.id)
		if famille == "" or m.model_paths.is_empty():
			continue
		var voiture := Node3D.new()
		var modele := (load(m.model_paths[0]) as PackedScene).instantiate() as Node3D
		voiture.add_child(modele)
		modele.scale = Vector3.ONE * m.model_scale
		modele.rotation_degrees.y = m.model_yaw_deg
		modele.position.y = m.model_y_offset
		var pieces: Array = []
		var liste := modele.find_children("*", "MeshInstance3D", true, false)
		if modele is MeshInstance3D:
			liste.append(modele)
		for n in liste:
			var mi := n as MeshInstance3D
			if mi.mesh == null or not mi.visible:
				continue
			var faces := _xf_dans(mi, voiture) * mi.mesh.get_faces()
			var plat: Array = []
			for v in faces:
				plat.append_array([snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)])
			pieces.append({"nom": String(modele.get_path_to(mi)), "roue": _est_roue(mi, modele), "sommets": plat})
		export[m.id] = {"famille": famille, "pieces": pieces}
		voiture.free()
	var f := FileAccess.open(sortie, FileAccess.WRITE)
	f.store_string(JSON.stringify(export))
	f.close()
	print("ENVELOPPES_EXPORT %d modeles -> %s" % [export.size(), ProjectSettings.globalize_path(sortie)])
	quit(0)


func _famille(id: String) -> String:
	for f in FAMILLES:
		for p in FAMILLES[f]:
			if id.begins_with(p):
				return f
	return ""


# Transformation d'un noeud dans le repère de `racine`, composée à la main (comme Car._xf_dans_voiture) : dans un script
# --script lancé depuis _init, les noeuds ne sont pas encore dans l'arbre et global_transform rend l'identité.
func _xf_dans(n: Node, racine: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur := n
	while cur != null and cur != racine:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


# Comme Car._setup_model, qui repère ses roues par le motif « *heel* » : la pièce ou un de ses parents.
func _est_roue(n: Node, modele: Node) -> bool:
	var cur := n
	while cur != null and cur != modele.get_parent():
		if String(cur.name).contains("heel"):
			return true
		cur = cur.get_parent()
	return false
