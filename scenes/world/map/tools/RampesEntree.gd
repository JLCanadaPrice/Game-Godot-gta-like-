extends RefCounted

# RAMPES DE COLLISION INVISIBLES DEVANT LES ENTRÉES (2026-09-23, décision du joueur, CLAUDE.md §12).
#
# Depuis la collision exacte, on marche jusqu'aux portes. Sur ces dix modèles, le palier de l'entrée reste hors de portée
# de StepClimb (0,40 m au plus) : bloc de pierre plein de 0,50 à 0,68 m devant la porte des maisons georgiennes alt01,
# 02, 03 et 05 ; perron de l'alt04, contremarche de 0,40 m sous un palier à 0,75 m ; deck de 0,43 m des supérettes ;
# terrasse de 0,68 m de la pizzeria ; escalier raide de trois marches de 0,24 m à la porte arrière du pub ; dernière
# marche de la maison de ville, trop peu profonde devant la porte. Le joueur ne veut PAS d'une limite de marche plus haute
# (il grimperait sur des murets et des capots) : une rampe de collision, invisible, fait monter ; l'escalier visible reste.
# Relevé par un audit de tous les modèles posés (capsule du joueur par ligne de façade, palier au rayon) puis regardé à
# l'image : les socles le long des murs (cabinet médical, petits commerces alt01, lofts, soubassements) et les cônes du
# DataCenter ne sont pas des entrées et n'en ont pas.
#
# Chaque rampe est un quadrilatère dans le repère du modèle : pied (y = -0,05, le terrain aplani sous la base) puis haut
# (le bord avant du palier, 5 mm au-dessus). Mesuré sur le maillage : palier = plus haut plat de 0,40 m devant le mur ;
# pente = 40° au plus (la limite de sol du joueur est 45°), et moins si un nez de marche l'exige : comme dans le parking
# à étages, la rampe passe au-dessus de CHAQUE nez, sinon le pied bute sur la contremarche. Les marches étant plus raides
# que 40°, la rampe dépasse devant la boîte du modèle : 0,21 à 0,59 m (0 pour le pub et la maison de ville).
# verifier() rejoue ces deux conditions à chaque cuisson : palier présent au bord haut, aucun dessus du modèle au-dessus
# de la rampe.

const RAMPES := {
	# palier 0,68 m, bord z 6,15, 40°, 2,75 m de large ; dépasse de 0,42 m
	"Residential_GeorgianHome_alt01": [[Vector3(-5.400, -0.05, 7.017), Vector3(-2.650, -0.05, 7.017), Vector3(-2.650, 0.685, 6.153), Vector3(-5.400, 0.685, 6.153)]],
	# palier 0,50 m, bord z 4,97, 40°, 3,35 m ; 0,21 m
	"Residential_GeorgianHome_alt02": [[Vector3(-5.400, -0.05, 5.622), Vector3(-2.050, -0.05, 5.622), Vector3(-2.050, 0.505, 4.971), Vector3(-5.400, 0.505, 4.971)]],
	# palier 0,63 m, bord z 4,85, 40°, 3,25 m ; 0,25 m
	"Residential_GeorgianHome_alt03": [[Vector3(-5.400, -0.05, 5.663), Vector3(-2.150, -0.05, 5.663), Vector3(-2.150, 0.637, 4.851), Vector3(-5.400, 0.637, 4.851)]],
	# palier 0,75 m sur toute la façade, bord z 4,73, 40°, 10,85 m ; 0,28 m
	"Residential_GeorgianHome_alt04": [[Vector3(-5.450, -0.05, 5.688), Vector3(5.400, -0.05, 5.688), Vector3(5.400, 0.758, 4.731), Vector3(-5.450, 0.758, 4.731)]],
	# palier 0,50 m, bord z 4,97, 40°, 3,25 m ; 0,21 m
	"Residential_GeorgianHome_alt05": [[Vector3(-5.400, -0.05, 5.622), Vector3(-2.150, -0.05, 5.622), Vector3(-2.150, 0.505, 4.971), Vector3(-5.400, 0.505, 4.971)]],
	# deck 0,43 m, bord z 11,64, 40°, toute la façade (21,55 m) ; 0,55 m
	"Business_ConvenienceStore_alt01": [[Vector3(-11.350, -0.05, 12.213), Vector3(10.200, -0.05, 12.213), Vector3(10.200, 0.435, 11.645), Vector3(-11.350, 0.435, 11.645)]],
	"Business_ConvenienceStore_alt02": [[Vector3(-11.350, -0.05, 12.213), Vector3(10.200, -0.05, 12.213), Vector3(10.200, 0.435, 11.645), Vector3(-11.350, 0.435, 11.645)]],
	# terrasse 0,68 m, bord z 9,89, 40°, 10,55 m ; 0,59 m
	"Business_PizzaRestaurant": [[Vector3(-5.350, -0.05, 10.760), Vector3(5.200, -0.05, 10.760), Vector3(5.200, 0.686, 9.888), Vector3(-5.350, 0.686, 9.888)]],
	# porte arrière : escalier qui monte vers +x le long de la façade -Z ; palier 0,77 m, bord x 0,42 ; 30,3° pour passer
	# au-dessus du nez de la marche basse (x -0,80, 0,06 m) ; 1,80 m de large, jusqu'au socle du mur
	"Business_Pub": [[Vector3(-0.980, -0.05, -8.020), Vector3(-0.980, -0.05, -6.220), Vector3(0.420, 0.774, -6.220), Vector3(0.420, 0.774, -8.020)]],
	# palier devant la porte 0,46 m, bord z 5,25 ; 27,5° pour passer au-dessus du nez à 0,29 m ; 1,70 m, dans la boîte
	"Residential_Townhouse": [[Vector3(-0.850, -0.05, 6.224), Vector3(0.850, -0.05, 6.224), Vector3(0.850, 0.463, 5.246), Vector3(-0.850, 0.463, 5.246)]],
}


# Triangles des rampes d'un modèle, dans son repère (deux par rampe ; la forme du modèle est à deux faces).
static func triangles(nom: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	for q: Array in RAMPES.get(nom, []):
		out.append_array(PackedVector3Array([q[0], q[1], q[2], q[0], q[2], q[3]]))
	return out


# Contrôle d'une rampe contre le maillage du modèle : le palier doit être au bord haut, et aucun dessus du modèle ne doit
# dépasser la rampe (un nez de marche qui la traverse arrête le pied). Rend la liste des fautes.
static func verifier(nom: String, faces_modele: PackedVector3Array) -> PackedStringArray:
	var fautes: PackedStringArray = []
	var tm := TriangleMesh.new()
	tm.create_from_faces(faces_modele)
	for q: Array in RAMPES.get(nom, []):
		var p0: Vector3 = q[0]
		var p1: Vector3 = q[1]
		var p2: Vector3 = q[2]
		var p3: Vector3 = q[3]
		var montee := Vector3(p3.x - p0.x, 0, p3.z - p0.z).normalized()
		var milieu := (p2 + p3) * 0.5 + montee * 0.05
		var pal := tm.intersect_segment(Vector3(milieu.x, milieu.y + 0.3, milieu.z), Vector3(milieu.x, milieu.y - 0.3, milieu.z))
		if pal.is_empty() or absf((pal["position"] as Vector3).y - p2.y) > 0.03:
			fautes.append("%s : pas de palier à %.2f m au bord haut de la rampe" % [nom, p2.y])
		var pas := 0.1
		var ni := maxi(2, ceili((p0.distance_to(p1)) / pas))
		var nj := maxi(2, ceili(Vector3(p3.x - p0.x, 0, p3.z - p0.z).length() / pas))
		for i in ni + 1:
			for j in nj:
				var fi := float(i) / ni
				var fj := float(j) / nj
				var bas := p0.lerp(p1, fi)
				var haut := p3.lerp(p2, fi)
				var p := bas.lerp(haut, fj)
				var dessus := tm.intersect_segment(Vector3(p.x, p.y + 0.6, p.z), Vector3(p.x, p.y + 0.01, p.z))
				if not dessus.is_empty():
					fautes.append("%s : le modèle dépasse la rampe de %.2f m en (%.2f, %.2f)" % [nom, (dessus["position"] as Vector3).y - p.y, p.x, p.z])
					return fautes
	return fautes
