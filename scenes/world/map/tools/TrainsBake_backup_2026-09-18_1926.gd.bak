extends SceneTree

# Chantier des trains, étape 2 : cuisson des caisses du pack en maillages fusionnés.
#
# Chaque modèle du pack arrive en 4 à 9 surfaces, une par matériau, et AUCUN de ces matériaux n'a de texture : ce sont
# des couleurs unies. Les surfaces sont donc fusionnées en UNE SEULE, la couleur du matériau passant dans la couleur
# de sommet, et toutes les caisses partagent un unique StandardMaterial3D (couleur de sommet en albédo). Résultat :
# un appel de dessin par caisse au lieu de quatre à neuf, et un seul matériau pour tout le matériel roulant.
#
# L'émission est NEUTRALISÉE : l'importateur FBX l'active sur chaque matériau (le joueur ne veut pas de trains qui
# brillent la nuit). Le matériau cuit n'a pas d'émission du tout.
#
# Les caisses sont tournées d'un quart de tour : le pack les modélise couchées le long de +X, alors qu'un Node3D de
# Godot regarde vers -Z. Après cuisson, l'avant de la caisse est sur -Z, donc un simple look_at suffit à la poser.
# L'origine reste au niveau du rail (le bas des roues est à y = 0 dans le pack, mesuré).
#
# Sortie : generated/trains/<nom>.res + trains.json (dimensions MESURÉES sur les sommets, lues par Train.gd).
#
# Lancer : Godot --headless --path <projet> --script res://scenes/world/map/tools/TrainsBake.gd

const SRC := "res://assets/Modular Train Pack-zip/"
const OUT := "res://scenes/world/map/generated/trains"
const MODELS := {
	"HighSpeed_Front": "High Speed Front/HighSpeed_Front.fbx",
	"HighSpeed_Wagon": "High Speed Wagon/HighSpeed_Wagon.fbx",
	"CargoTrain_Front": "Cargo Train Front/CargoTrain_Front.fbx",
	"CargoTrain_Wagon": "Cargo Train Wagon/CargoTrain_Wagon.fbx",
	"CargoTrain_Container": "Cargo Train Container/CargoTrain_Container.fbx",
	"CargoTrain_CoalContainer": "Cargo Train Coal Conta/CargoTrain_CoalContainer.fbx",
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var turn := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)   # +X du pack -> -Z de Godot
	var summary := {}
	var problems: Array[String] = []
	for name: String in MODELS:
		var path: String = SRC + MODELS[name]
		if not ResourceLoader.exists(path):
			problems.append("%s absent (%s)" % [name, path])
			continue
		var node := (load(path) as PackedScene).instantiate()
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var tris := 0
		var surfaces := 0
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for mi: MeshInstance3D in _meshes(node):
			var xf := turn * _relative(mi, node)
			var normal_basis := xf.basis.inverse().transposed()
			for s in mi.mesh.get_surface_count():
				surfaces += 1
				var arrays := mi.mesh.surface_get_arrays(s)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
				var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var mat := mi.mesh.surface_get_material(s)
				var col := Color.WHITE
				if mat is BaseMaterial3D:
					col = (mat as BaseMaterial3D).albedo_color
				var count := idx.size() if idx.size() > 0 else verts.size()
				tris += count / 3
				for k in count:
					var v := idx[k] if idx.size() > 0 else k
					var p: Vector3 = xf * verts[v]
					lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
					hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
					st.set_color(col)
					if v < normals.size():
						st.set_normal((normal_basis * normals[v]).normalized())
					st.add_vertex(p)
		node.queue_free()
		if tris == 0:
			problems.append("%s : aucun triangle" % name)
			continue
		var mesh := st.commit()
		# De quel côté est le nez ? Mesuré, pas supposé : on compare la section moyenne (demi-largeur x hauteur) du
		# premier et du dernier sixième de la caisse. Le nez est l'extrémité la plus fine. Si elle est sur +Z, la
		# caisse est retournée pour que TOUTES les caisses cuites aient leur avant sur -Z, comme un Node3D de Godot.
		var nose_plus_z := _nose_at_plus_z(mesh)
		if nose_plus_z:
			var flip := SurfaceTool.new()
			flip.begin(Mesh.PRIMITIVE_TRIANGLES)
			flip.append_from(mesh, 0, Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO))
			mesh = flip.commit()
			var swap := lo.z
			lo.z = -hi.z
			hi.z = -swap
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(mesh, 0, Transform3D.IDENTITY)
		st.index()
		mesh = st.commit()
		mesh.surface_set_material(0, _material())
		mesh.resource_name = name
		var res_path := OUT.path_join(name + ".res")
		var err := ResourceSaver.save(mesh, res_path)
		if err != OK:
			problems.append("%s : écriture %s en erreur %d" % [name, res_path, err])
			continue
		# après le quart de tour, la longueur de la caisse est sur Z et sa largeur sur X
		var size := hi - lo
		summary[name] = {"longueur": snappedf(size.z, 0.001), "largeur": snappedf(size.x, 0.001), "hauteur": snappedf(size.y, 0.001),
				"avant": snappedf(lo.z, 0.001), "arriere": snappedf(hi.z, 0.001), "bas": snappedf(lo.y, 0.001),
				"triangles": tris, "retournee": nose_plus_z}
		print("TRAINS_BAKE %-26s %5d tri, %d surfaces fusionnées en 1 | longueur %.3f m, largeur %.3f m, hauteur %.3f m, bas y %.3f | nez remis sur -Z : %s"
				% [name, tris, surfaces, size.z, size.x, size.y, lo.y, "oui" if nose_plus_z else "non (déjà)"])
	var f := FileAccess.open(OUT.path_join("trains.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(summary, "  "))
	f.close()
	var widest := 0.0
	var tallest := 0.0
	for name: String in summary:
		widest = maxf(widest, float(summary[name]["largeur"]))
		tallest = maxf(tallest, float(summary[name]["hauteur"]))
	print("TRAINS_BAKE %d caisses cuites dans %s | caisse la plus large %.3f m, la plus haute %.3f m"
			% [summary.size(), OUT, widest, tallest])
	if not problems.is_empty():
		print("TRAINS_BAKE_ERROR " + " | ".join(problems))
	quit(0 if problems.is_empty() else 1)


# Section moyenne (demi-largeur x hauteur) du premier et du dernier sixième de la caisse : le nez est l'extrémité la
# plus fine. Renvoie vrai si cette extrémité est du côté +Z.
func _nose_at_plus_z(mesh: ArrayMesh) -> bool:
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var lo := verts[0].z
	var hi := verts[0].z
	for p in verts:
		lo = minf(lo, p.z)
		hi = maxf(hi, p.z)
	var span := maxf(hi - lo, 0.001)
	var slices := 12
	var wide := PackedFloat32Array()
	var tall := PackedFloat32Array()
	wide.resize(slices)
	tall.resize(slices)
	for p in verts:
		var k := clampi(int((p.z - lo) / span * slices), 0, slices - 1)
		wide[k] = maxf(wide[k], absf(p.x))
		tall[k] = maxf(tall[k], p.y)
	var front := (wide[0] * tall[0] + wide[1] * tall[1]) * 0.5
	var back := (wide[slices - 1] * tall[slices - 1] + wide[slices - 2] * tall[slices - 2]) * 0.5
	return back < front - 0.02


# Matériau unique de tout le matériel roulant : la couleur vient du sommet, pas d'émission, pas de texture.
func _material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = "train"
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color.WHITE
	m.roughness = 0.65
	m.metallic = 0.0
	m.emission_enabled = false
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


func _relative(n: Node3D, top: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != top:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf
