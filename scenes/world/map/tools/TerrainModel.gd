extends RefCounted

# Relief de la carte 3D, calculé à partir de MapSpec : bruit doux, collines, plateaux aplanis, vallée de la rivière,
# plans d'eau, remontée des bords hors de la zone explorable. Grille de 4 m sur l'emprise TERRAIN.
# Sous le sol des districts existants, le terrain passe juste en dessous de leur sol (caché, collision couverte par la
# leur) et sous le bassin il descend sous les fonds : les tuiles y sont trouées au rendu.
# Partagé par TerrainBake (étape 1) et les générateurs suivants (routes, quartiers), qui creusent ou aplanissent la même
# grille de hauteurs avant de recuire les tuiles.

const Spec := preload("res://scenes/world/map/MapSpec.gd")
const CELL := 4.0
const RIVER_BANK_WIDTH := 36.0     # m de berge entre l'eau et le terrain naturel (plus large sous une colline)
const RIVER_BANK_TOP := 0.55       # haut de berge : 1,5 m au-dessus de l'eau
const RIVER_BED_EDGE := -2.2       # fond au bord de l'eau
const RIVER_BED_CENTER := -7.6     # fond au milieu du lit
const LAND_FLOOR := 0.4            # plus bas du relief naturel, au-dessus de l'eau (-0,95)
const CITY_UNDER := -0.08          # sous le sol des districts
const HARBOR_UNDER := -9.8         # sous les fonds du bassin
# Sols des 4 districts et du quai, eau et fonds du bassin (relevés dans World.tscn).
const CITY_GROUNDS := [
	Rect2(-520, -461, 560, 380), Rect2(-952, -469, 560, 388), Rect2(-520, -173, 560, 380),
	Rect2(-952, -173, 560, 380), Rect2(-520, -500, 560, 40),
]
const HARBOR_WATER := Rect2(-500, -650, 500, 156)

var width: int
var depth: int
var lake_levels := {}
var _noise := FastNoiseLite.new()
var _river_x := PackedFloat32Array()      # par rangée de 4 m : abscisse de l'axe
var _river_half := PackedFloat32Array()   # demi-largeur
var _river_cos := PackedFloat32Array()    # |dz/ds| : ramène l'écart horizontal à la distance perpendiculaire


func _init() -> void:
	width = int(Spec.TERRAIN.size.x / CELL) + 1
	depth = int(Spec.TERRAIN.size.y / CELL) + 1
	_noise.seed = Spec.NOISE["seed"]
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = Spec.NOISE["frequency"]
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = Spec.NOISE["octaves"]
	_build_river_rows()
	for lake: Dictionary in Spec.LAKES:
		lake_levels[lake["id"]] = _lake_level(lake)


func grid_to_world(i: int, j: int) -> Vector2:
	return Spec.TERRAIN.position + Vector2(i, j) * CELL


func build_heights() -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	heights.resize(width * depth)
	for j in depth:
		for i in width:
			heights[j * width + i] = baked_height(grid_to_world(i, j))
	return heights


# Hauteur cuite : relief naturel, sauf sous le centre-ville et le bassin existants.
func baked_height(p: Vector2) -> float:
	if HARBOR_WATER.has_point(p):
		return HARBOR_UNDER
	if is_city_ground(p):
		return CITY_UNDER
	return height_at(p)


func is_city_ground(p: Vector2) -> bool:
	for rect: Rect2 in CITY_GROUNDS:
		if rect.has_point(p):
			return true
	return false


func is_excluded(p: Vector2) -> bool:
	return HARBOR_WATER.has_point(p) or is_city_ground(p)


func height_at(p: Vector2) -> float:
	var h := _base_height(p)
	for lake: Dictionary in Spec.LAKES:
		var r: float = ((p - lake["center"]) / lake["radii"]).length()
		if r < 1.8:
			var level: float = lake_levels[lake["id"]]
			if r < 1.0:
				h = level - 0.5 - 2.5 * smoothstep(0.0, 0.8, 1.0 - r)
			else:
				h = lerpf(level + 0.35, h, smoothstep(1.0, 1.8, r))
	var info := river_info(p)
	if info.x < 0.0:
		h = lerpf(RIVER_BED_EDGE, RIVER_BED_CENTER, smoothstep(0.0, 0.6, clampf(-info.x / info.y, 0.0, 1.0)))
	else:
		var bank := RIVER_BANK_WIDTH + maxf(0.0, h - RIVER_BANK_TOP) * 1.6
		if info.x < bank:
			h = lerpf(RIVER_BANK_TOP, h, smoothstep(0.0, bank, info.x))
	return clampf(h, -9.0, 90.0)


# Distance signée au bord de la rivière (négative dans l'eau) et demi-largeur locale.
func river_info(p: Vector2) -> Vector2:
	var row := clampi(int(roundf((p.y - Spec.TERRAIN.position.y) / CELL)), 0, _river_x.size() - 1)
	return Vector2(absf(p.x - _river_x[row]) * _river_cos[row] - _river_half[row], _river_half[row])


# Axe de la rivière lissé (Catmull-Rom), du nord au sud.
func river_curve(step: float) -> Array:
	var raw: Array = Spec.RIVER
	var out: Array = []
	for k in raw.size() - 1:
		var p0: Vector2 = raw[maxi(k - 1, 0)][0]
		var p1: Vector2 = raw[k][0]
		var p2: Vector2 = raw[k + 1][0]
		var p3: Vector2 = raw[mini(k + 2, raw.size() - 1)][0]
		var n := maxi(1, ceili(p1.distance_to(p2) / step))
		for s in n:
			var t := float(s) / n
			var t2 := t * t
			var t3 := t2 * t
			var pos := 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
			out.append([pos, lerpf(raw[k][1], raw[k + 1][1], t)])
	out.append([raw[raw.size() - 1][0], raw[raw.size() - 1][1]])
	return out


func _build_river_rows() -> void:
	var curve := river_curve(5.0)
	_river_x.resize(depth)
	_river_half.resize(depth)
	_river_cos.resize(depth)
	var k := 0
	for j in depth:
		var z := Spec.TERRAIN.position.y + j * CELL
		while k < curve.size() - 2 and (curve[k + 1][0] as Vector2).y < z:
			k += 1
		var a: Vector2 = curve[k][0]
		var b: Vector2 = curve[k + 1][0]
		var t := clampf((z - a.y) / maxf(b.y - a.y, 0.001), 0.0, 1.0)
		var dir := (b - a).normalized()
		_river_x[j] = lerpf(a.x, b.x, t)
		_river_half[j] = lerpf(curve[k][1], curve[k + 1][1], t) * 0.5
		_river_cos[j] = maxf(absf(dir.y), 0.35)


func _base_height(p: Vector2) -> float:
	var h := _noise.get_noise_2d(p.x, p.y) * float(Spec.NOISE["amplitude"])
	for hill: Array in Spec.HILLS:
		var d := p.distance_to(hill[0])
		if d < hill[1]:
			h += hill[2] * 0.5 * (1.0 + cos(PI * d / hill[1]))
	h = maxf(h, LAND_FLOOR)   # pas de cuvette sèche sous le niveau de l'eau hors rivière et lacs
	for plateau: Dictionary in Spec.PLATEAUS:
		var d := _outside_distance(plateau["rect"], p)
		if d < plateau["blend"]:
			h = lerpf(h, plateau["height"], 1.0 - smoothstep(0.0, plateau["blend"], d))
	var out := _outside_distance(Spec.PLAYABLE, p)
	if out > 0.0:
		h += Spec.EDGE_RISE["height"] * smoothstep(0.0, Spec.EDGE_RISE["width"], out)
	return h


# Niveau d'un plan d'eau : sous le point le plus bas de sa rive naturelle.
func _lake_level(lake: Dictionary) -> float:
	var lowest := INF
	for k in 24:
		var a := TAU * k / 24.0
		lowest = minf(lowest, _base_height(lake["center"] + Vector2(cos(a), sin(a)) * lake["radii"] * 1.15))
	return lowest - 0.8


func _outside_distance(rect: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(rect.position.x - p.x, 0.0), p.x - rect.end.x)
	var dz := maxf(maxf(rect.position.y - p.y, 0.0), p.y - rect.end.y)
	return Vector2(dx, dz).length()
