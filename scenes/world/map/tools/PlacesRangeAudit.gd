extends SceneTree

# Sonde de lecture seule (2026-09-18) sur la scène cuite Places.tscn : elle répond à « qu'est-ce qui reste dessiné au
# loin ». Elle descend dans les scènes instanciées, ce que _own() de PlacesBake ne fait pas, donc elle voit l'arbre tel
# que le jeu le monte, pas tel que le fichier .tscn l'écrit.
#  - un relevé par MeshInstance3D : lieu, nom, s'il vient d'une scène instanciée, sa portée de disparition, ses
#    surfaces (une surface = un appel de dessin), ses triangles, sa boîte MESURÉE sur le maillage et son matériau ;
#  - un total par lieu, avec le compte de ceux dont la portée est 0, c'est-à-dire jamais coupés, et les matériaux
#    distincts qu'ils portent : c'est ce qui dit si on peut les fusionner en un seul maillage sans perdre de couleur ;
#  - par vue de scenes/tests/MapShotsTest.gd : ce qui tombe dans le champ, à quelle distance, la taille que ça occupe
#    encore à l'écran, et ce que couperaient deux barèmes : celui de _fbx_model (hauteur x 115) et le même appliqué à
#    la plus grande dimension de la boîte, qui vaut mieux pour un objet plus large que haut.
#
# Lancer : Godot --headless --path <projet> --script res://scenes/world/map/tools/PlacesRangeAudit.gd

const PLACES := "res://scenes/world/map/generated/Places.tscn"
const Shots := preload("res://scenes/tests/MapShotsTest.gd")
const FOV := 75.0            # Camera3D.new() : champ vertical par défaut, et MapShotsTest ne le change pas
const HAUTEUR_PX := 450.0    # résolution des relevés (800x450), celle sur laquelle le barème x 115 est calibré
const ASPECT := 16.0 / 9.0
const FAR := 4000.0          # cam.far de MapShotsTest
const NEAR := 0.05
const RAD_PAR_PIXEL := deg_to_rad(FOV) / HAUTEUR_PX

var rows: Array = []


func _init() -> void:
	var root := (load(PLACES) as PackedScene).instantiate()
	for place in root.get_children():
		_collect(place, place, String(place.name), false)
	root.free()

	# --- relevé maillage par maillage -------------------------------------------------------------------------------
	print("RANGE_HEAD lieu;noeud;instancie;portee_m;surfaces;triangles;dx_m;dy_m;dz_m;materiau;centre_x;centre_y;centre_z")
	for r: Dictionary in rows:
		var box: AABB = r["aabb"]
		var c := box.get_center()
		print("RANGE_MESH %s;%s;%s;%.0f;%d;%d;%.2f;%.2f;%.2f;%s;%.0f;%.1f;%.0f"
				% [r["place"], r["node"], "oui" if r["instanced"] else "non", r["range"], r["surfaces"],
				r["triangles"], box.size.x, box.size.y, box.size.z, r["material"], c.x, c.y, c.z])

	# --- total par lieu ----------------------------------------------------------------------------------------------
	var by_place := {}
	for r: Dictionary in rows:
		var p: String = r["place"]
		if not by_place.has(p):
			by_place[p] = {"n": 0, "zero": 0, "surf_zero": 0, "tri_zero": 0, "mats": {}}
		var e: Dictionary = by_place[p]
		e["n"] += 1
		if float(r["range"]) <= 0.0:
			e["zero"] += 1
			e["surf_zero"] += int(r["surfaces"])
			e["tri_zero"] += int(r["triangles"])
			(e["mats"] as Dictionary)[r["material"]] = true
	var total := {"n": 0, "zero": 0, "surf_zero": 0, "tri_zero": 0}
	for p in by_place:
		var e: Dictionary = by_place[p]
		for k in total:
			total[k] += e[k]
		if int(e["zero"]) == 0:
			print("RANGE_LIEU %s maillages=%d dont_portee_0=0" % [p, e["n"]])
			continue
		print("RANGE_LIEU %s maillages=%d dont_portee_0=%d (%d surfaces, %d triangles jamais coupes) materiaux_distincts=%d : %s"
				% [p, e["n"], e["zero"], e["surf_zero"], e["tri_zero"], (e["mats"] as Dictionary).size(),
				" ".join((e["mats"] as Dictionary).keys())])
	print("RANGE_TOTAL maillages=%d dont_portee_0=%d | surfaces_jamais_coupees=%d | triangles_jamais_coupes=%d"
			% [total["n"], total["zero"], total["surf_zero"], total["tri_zero"]])

	# --- ce que ça coûte depuis les caméras de référence --------------------------------------------------------------
	print("RANGE_VUE_HEAD vue;maillages_dans_le_champ;portee_0_dans_le_champ;surfaces;coupes_bareme_hauteur;coupes_bareme_plus_grande_dim;plus_loin_m")
	for view: Array in Shots.VIEWS:
		var from: Vector3 = view[1]
		var sol: bool = view.size() > 3 and view[3] == "sol"
		var planes := _frustum(from, view[2])
		var seen := 0
		var zero := 0
		var zero_surf := 0
		var cut_h := 0
		var cut_d := 0
		var farthest := 0.0
		var detail: Array = []
		for r: Dictionary in rows:
			var box: AABB = r["aabb"]
			if not _in_frustum(box, planes):
				continue
			seen += 1
			if float(r["range"]) > 0.0:
				continue
			var d := from.distance_to(box.get_center())
			var big: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
			zero += 1
			zero_surf += int(r["surfaces"])
			farthest = maxf(farthest, d)
			if d > _bareme(box.size.y):
				cut_h += 1
			if d > _bareme(big):
				cut_d += 1
			detail.append("%s@%.0fm(%.1fpx_haut,%.1fpx_large)"
					% [r["node"], d, box.size.y / (d * RAD_PAR_PIXEL), big / (d * RAD_PAR_PIXEL)])
		if zero == 0:
			continue
		print("RANGE_VUE %s%s;%d;%d;%d;%d;%d;%.0f | %s"
				% [view[0], " (sol, hauteur approchee)" if sol else "", seen, zero, zero_surf, cut_h, cut_d,
				farthest, " ".join(detail)])
	quit()


# Barème de _fbx_model : on garde le modèle tant qu'il couvre plus de trois pixels (450 px pour 75° de champ, soit
# 0,0029 rad par pixel, donc taille x 115), borné à 250..1500 m.
func _bareme(taille: float) -> float:
	return clampf(taille * 115.0, 250.0, 1500.0)


func _collect(node: Node, root: Node, place: String, instanced: bool) -> void:
	for child in node.get_children():
		var inside := instanced or child.scene_file_path != ""
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh != null:
				var xf := Transform3D.IDENTITY
				var walk: Node = mi
				while walk != null and walk != root.get_parent():
					if walk is Node3D:
						xf = (walk as Node3D).transform * xf
					walk = walk.get_parent()
				var surfaces := mi.mesh.get_surface_count()
				var tris := 0
				var mats: Array = []
				for s in surfaces:
					var arr: Array = mi.mesh.surface_get_arrays(s)
					var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
					if idx.is_empty():
						tris += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
					else:
						tris += idx.size() / 3
					var mat := mi.get_active_material(s)
					var label := "aucun"
					if mat != null:
						label = mat.resource_path.get_file() if mat.resource_path != "" else mat.resource_name
						if label == "":
							label = "%s#%d" % [mat.get_class(), mat.get_instance_id()]
					if not mats.has(label):
						mats.append(label)
				rows.append({"place": place, "node": String(mi.name), "instanced": instanced,
						"range": mi.visibility_range_end, "surfaces": surfaces, "triangles": tris,
						"material": "+".join(mats), "aabb": xf * mi.mesh.get_aabb()})
		_collect(child, root, place, inside)


# Les six plans du tronc de cône, normales tournées VERS L'INTÉRIEUR (le signe est vérifié sur l'axe de visée, qui est
# forcément dedans, plutôt que déduit d'une convention).
func _frustum(from: Vector3, to: Vector3) -> Array:
	var f := (to - from).normalized()
	var r := f.cross(Vector3.UP).normalized()
	var u := r.cross(f).normalized()
	var vh := deg_to_rad(FOV) * 0.5
	var hh := atan(tan(vh) * ASPECT)
	var planes: Array = [Plane(f, from + f * NEAR), Plane(-f, from + f * FAR)]
	for pair: Array in [[f * cos(vh) + u * sin(vh), r], [f * cos(vh) - u * sin(vh), r],
			[f * cos(hh) + r * sin(hh), u], [f * cos(hh) - r * sin(hh), u]]:
		var n: Vector3 = (pair[0] as Vector3).cross(pair[1] as Vector3).normalized()
		planes.append(Plane(n if n.dot(f) >= 0.0 else -n, from))
	return planes


func _in_frustum(box: AABB, planes: Array) -> bool:
	for plane: Plane in planes:
		var support := Vector3(
				box.end.x if plane.normal.x > 0.0 else box.position.x,
				box.end.y if plane.normal.y > 0.0 else box.position.y,
				box.end.z if plane.normal.z > 0.0 else box.position.z)
		if plane.distance_to(support) < 0.0:
			return false
	return true
