class_name MapRailPath
extends Resource

# Tracé de la voie ferrée de la carte 3D, écrit par RoadBake (generated/roads/rail_path.tres) et lu par RailPath.gd
# pour faire rouler les trains. Tout est en coordonnées monde.
#
# `points` est l'axe de la voie AU NIVEAU DU CHAMPIGNON DU RAIL, c'est-à-dire la plateforme plus RoadBake.RAIL_TOP :
# c'est la hauteur exacte où porte une roue, pas celle du ballast. Le pas est celui du réseau (RoadNetwork.STEP, 4 m),
# et `arc` donne l'abscisse curviligne cumulée de chaque point, ce qui permet de placer une caisse à une distance
# donnée sans reparcourir la ligne.
#
# La voie est UNIQUE et se termine par deux culs-de-sac : `ends` les décrit, `dir` pointant vers l'extérieur de la
# carte. `crossings` liste les passages à niveau, avec la demi-largeur de la coupure de plateforme (`half_gap`), qui
# est aussi la demi-emprise du carrefour route/rail.

@export var points := PackedVector3Array()
@export var arc := PackedFloat32Array()
@export var step := 4.0
@export var gauge := 1.435
@export var length := 0.0
@export var min_radius := 0.0                  # rayon de courbure minimal mesuré sur trois points consécutifs
@export var max_grade := 0.0                   # pente maximale mesurée (tangente, pas pourcentage)
@export var ends: Array[Dictionary] = []       # {"pos": Vector3, "dir": Vector2 (vers l'extérieur), "s": float}
@export var crossings: Array[Dictionary] = []  # {"pos": Vector3, "s": float, "half_gap": float, "road": String, "road_width": float}


# Point de la voie à l'abscisse `s` (mètres depuis ends[0]), extrapolé droit au-delà des bouts.
func at(s: float) -> Vector3:
	var n := points.size()
	if n == 0:
		return Vector3.ZERO
	if n == 1 or s <= 0.0:
		return points[0]
	if s >= arc[n - 1]:
		return points[n - 1]
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if arc[mid] <= s:
			lo = mid
		else:
			hi = mid
	var span := maxf(arc[hi] - arc[lo], 0.0001)
	return points[lo].lerp(points[hi], clampf((s - arc[lo]) / span, 0.0, 1.0))


# Direction unitaire de la voie à l'abscisse `s`, dans le sens des abscisses croissantes.
func heading(s: float) -> Vector3:
	var half := maxf(step * 0.5, 0.5)
	var a := at(maxf(s - half, 0.0))
	var b := at(minf(s + half, length))
	var d := b - a
	return Vector3.FORWARD if d.length_squared() < 0.000001 else d.normalized()
