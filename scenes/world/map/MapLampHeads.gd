class_name MapLampHeads
extends Resource

# Position de chaque LUMINAIRE de la carte — le bloc au bout de la crosse, pas le pied du mât.
# Écrit par RoadBake (generated/roads/lamp_heads.tres) et par DowntownFurnitureBake
# (downtown/generated/lamp_heads.tres), lu par StreetLights.gd pour poser ses vraies lumières
# sur les lampadaires les plus proches du joueur.
#
# Pourquoi une ressource et pas une lecture de la scène cuite : les lampadaires sont FUSIONNÉS
# par cellule en un seul maillage (RoadBake) ou par bloc et par famille (DowntownFurnitureBake).
# Il n'existe aucun nœud par lampadaire, donc aucune position individuelle à relire. Seul le
# cuiseur, qui pose les transformations, connaît ces positions ; il faut donc qu'il les écrive.
#
# Les décalages du luminaire dans le repère du modèle ont été MESURÉS sur les sommets des quatre
# .glb le 2026-09-19 (sonde probe_luminaire), en prenant les sommets au-delà de 70 % de l'écart
# maximal à l'axe du mât :
#
#   lamp_1.glb      (route, simple) : centre (1.229, 6.205, 0.004), boîte 0.391 x 0.258 x 0.386
#   lamp_2.glb      (route, double) : centre (±1.268, 6.145, 0.005), boîte 0.440 x 0.306 x 0.386
#   lamp_single.glb (centre-ville)  : centre (1.626, 6.227, 0.002), boîte 0.141 x 0.221 x 0.351
#   lamp_double.glb (centre-ville)  : centre (±1.563, 6.227, 0.002), boîte 0.114 x 0.221 x 0.351
#
# `heads` est en coordonnées monde. `aims` donne, pour chaque luminaire, la direction horizontale
# de la crosse (du mât vers la lampe) : elle sert à incliner légèrement le cône vers la chaussée,
# et elle servira aussi si on veut un jour orienter autre chose depuis ces points.

@export var heads := PackedVector3Array()
@export var aims := PackedVector3Array()   # unitaire, horizontal, du mât vers le luminaire


func size() -> int:
	return heads.size()


# Boîte englobante de tous les luminaires : sert aux tests et au découpage spatial.
func bounds() -> AABB:
	if heads.is_empty():
		return AABB()
	var b := AABB(heads[0], Vector3.ZERO)
	for p in heads:
		b = b.expand(p)
	return b
