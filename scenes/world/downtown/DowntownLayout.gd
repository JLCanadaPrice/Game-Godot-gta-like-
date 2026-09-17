extends RefCounted

# Géométrie dérivée du plan de masse du centre-ville (DowntownSpec) : tronçons de rue avec leur profil en travers,
# carrefours et leurs branches, passages piétons et coins de trottoir, îlots (cases de la trame que ne sépare aucune
# rue), intérieurs constructibles, zones et ruelles. Déterministe et sans scène : aperçu, générateurs et tests.
#
# Conventions : tronçon "x" = rue nord-sud (x constant, from/to en z) ; tronçon "z" = rue est-ouest (z constant,
# from/to en x). Côté −1 d'un tronçon : −X (rue nord-sud) ou −Z (rue est-ouest) ; côté +1 : l'autre. Branches d'un
# carrefour : N (−Z), S (+Z), W (−X), E (+X).

const Spec := preload("res://scenes/world/downtown/DowntownSpec.gd")

const CROSSWALK_WIDTH := 3.0
const PED_INSET_MIN := 1.0        # chemin piéton : au milieu du trottoir, entre 1 et 2,5 m du bord de la chaussée
const PED_INSET_MAX := 2.5

var xs: Array[float] = []         # lignes des rues nord-sud, croissantes
var zs: Array[float] = []         # lignes des rues est-ouest, croissantes
var segments: Array[Dictionary] = []
var nodes: Array[Dictionary] = []
var blocks: Array[Dictionary] = []
var alleys: Array[Dictionary] = []
var _node_at := {}                # Vector2i(x, z) arrondis -> indice de carrefour


func _init() -> void:
	for street: Dictionary in Spec.X_STREETS:
		xs.append(float(street["x"]))
	for street: Dictionary in Spec.Z_STREETS:
		zs.append(float(street["z"]))
	xs.sort()
	zs.sort()
	_build_segments()
	_build_nodes()
	_build_blocks()
	_build_alleys()


# --- profils ----------------------------------------------------------------------------------------------------------

static func half_width(profile_name: String, one_way: bool) -> float:
	var p: Dictionary = Spec.PROFILES[profile_name]
	if one_way:
		return int(p["lanes"]) * float(p["lane"]) * 0.5 + float(p["parking"])
	return int(p["lanes"]) * float(p["lane"]) + float(p["median"]) * 0.5 + float(p["parking"])


# Décalages latéraux des voies (+ = à droite du sens de marche), cf. CircuitPath.lane_offset.
static func lane_offsets(profile_name: String, one_way: bool) -> PackedFloat32Array:
	var p: Dictionary = Spec.PROFILES[profile_name]
	var out := PackedFloat32Array()
	var lane := float(p["lane"])
	for k in int(p["lanes"]):
		if one_way:
			out.append(-int(p["lanes"]) * lane * 0.5 + lane * (k + 0.5))
		else:
			out.append(float(p["median"]) * 0.5 + lane * (k + 0.5))
	return out


func _build_segments() -> void:
	for pair: Array in [["x", Spec.X_STREETS, Spec.Z_STREETS], ["z", Spec.Z_STREETS, Spec.X_STREETS]]:
		var axis: String = pair[0]
		var cross_axis := "z" if axis == "x" else "x"
		for street: Dictionary in pair[1]:
			var at := float(street[axis])
			var dir := int(street.get("dir", 0))
			var outer := int(street.get("outer", 0))
			for span: Array in street["spans"]:
				var profile: String = span[2]
				var options: Dictionary = span[3] if span.size() > 3 else {}
				# arrêts : extrémités du tronçon et croisements avec une rue transversale réellement présente à cet endroit
				var stops: Array[float] = [float(span[0]), float(span[1])]
				for other: Dictionary in pair[2]:
					var c := float(other[cross_axis])
					if c <= float(span[0]) + 0.01 or c >= float(span[1]) - 0.01:
						continue
					for other_span: Array in other["spans"]:
						if at >= float(other_span[0]) - 0.01 and at <= float(other_span[1]) + 0.01:
							stops.append(c)
							break
				stops.sort()
				for k in stops.size() - 1:
					var p: Dictionary = Spec.PROFILES[profile]
					var sidewalks := [float(p["sidewalk"]), float(p["sidewalk"])]
					if outer != 0:
						sidewalks[0 if outer < 0 else 1] = Spec.OUTER_SIDEWALK
					if options.has("sidewalks"):
						sidewalks = [float(options["sidewalks"][0]), float(options["sidewalks"][1])]
					segments.append({
						"axis": axis, "at": at, "from": stops[k], "to": stops[k + 1], "profile": profile,
						"name": street["name"], "dir": dir, "one_way": dir != 0, "outer": outer,
						"half": half_width(profile, dir != 0), "lanes": lane_offsets(profile, dir != 0),
						"median": float(p["median"]), "sidewalks": sidewalks, "a": -1, "b": -1,
					})


func _build_nodes() -> void:
	for i in segments.size():
		var s: Dictionary = segments[i]
		for end: String in ["from", "to"]:
			var pos := Vector2(float(s["at"]), float(s[end])) if s["axis"] == "x" else Vector2(float(s[end]), float(s["at"]))
			var key := Vector2i(roundi(pos.x), roundi(pos.y))
			if not _node_at.has(key):
				_node_at[key] = nodes.size()
				nodes.append({"pos": pos, "arms": {}})
			var n: int = _node_at[key]
			s["a" if end == "from" else "b"] = n
			var arm: String
			if s["axis"] == "x":
				arm = "N" if end == "to" else "S"
			else:
				arm = "W" if end == "to" else "E"
			nodes[n]["arms"][arm] = i
	for n in nodes.size():
		var node: Dictionary = nodes[n]
		var arms: Dictionary = node["arms"]
		node["lit"] = arms.size() >= 3
		node["hx"] = _max_half(arms, ["N", "S"])
		node["hz"] = _max_half(arms, ["W", "E"])
		# chemin piéton de chaque côté du carrefour, au milieu du trottoir le plus étroit de la rue transversale
		node["ped_x_neg"] = float(node["hx"]) + _ped_inset(arms, ["N", "S"], 0)
		node["ped_x_pos"] = float(node["hx"]) + _ped_inset(arms, ["N", "S"], 1)
		node["ped_z_neg"] = float(node["hz"]) + _ped_inset(arms, ["W", "E"], 0)
		node["ped_z_pos"] = float(node["hz"]) + _ped_inset(arms, ["W", "E"], 1)


func _max_half(arms: Dictionary, keys: Array) -> float:
	var h := 0.0
	for k: String in keys:
		if arms.has(k):
			h = maxf(h, float(segments[arms[k]]["half"]))
	return h


func _ped_inset(arms: Dictionary, keys: Array, side: int) -> float:
	var width := INF
	for k: String in keys:
		if arms.has(k):
			width = minf(width, float(segments[arms[k]]["sidewalks"][side]))
	if width == INF:
		width = 3.5
	return clampf(width * 0.5, PED_INSET_MIN, PED_INSET_MAX)


func node_index(pos: Vector2) -> int:
	return int(_node_at.get(Vector2i(roundi(pos.x), roundi(pos.y)), -1))


func node_pos3(n: int) -> Vector3:
	var p: Vector2 = nodes[n]["pos"]
	return Vector3(p.x, 0.0, p.y)


# Unitaire horizontal (x, z) de la branche `arm`, du carrefour vers l'extérieur.
static func arm_dir(arm: String) -> Vector2:
	match arm:
		"N":
			return Vector2(0, -1)
		"S":
			return Vector2(0, 1)
		"W":
			return Vector2(-1, 0)
	return Vector2(1, 0)


# Passage piéton de la branche `arm` du carrefour `n` : bande de CROSSWALK_WIDTH m en travers de la chaussée de la
# branche, centrée sur le chemin piéton qui longe la rue transversale. {"rect": Rect2 (x, z), "stop": distance du
# centre du carrefour au bord de la bande côté voiture qui arrive (CircuitPath.crosswalk_stop_dist), "a"/"b" : coins
# de trottoir reliés}.
func crosswalk(n: int, arm: String) -> Dictionary:
	var node: Dictionary = nodes[n]
	var p: Vector2 = node["pos"]
	var seg: Dictionary = segments[node["arms"][arm]]
	var half := float(seg["half"])
	var off: float
	match arm:
		"N":
			off = float(node["ped_z_neg"])
		"S":
			off = float(node["ped_z_pos"])
		"W":
			off = float(node["ped_x_neg"])
		_:
			off = float(node["ped_x_pos"])
	var d := arm_dir(arm)
	var c := p + d * off
	var rect: Rect2
	var corner_a: Vector2
	var corner_b: Vector2
	if arm == "N" or arm == "S":
		rect = Rect2(p.x - half, c.y - CROSSWALK_WIDTH * 0.5, half * 2.0, CROSSWALK_WIDTH)
		corner_a = Vector2(p.x - float(node["ped_x_neg"]), c.y)
		corner_b = Vector2(p.x + float(node["ped_x_pos"]), c.y)
	else:
		rect = Rect2(c.x - CROSSWALK_WIDTH * 0.5, p.y - half, CROSSWALK_WIDTH, half * 2.0)
		corner_a = Vector2(c.x, p.y - float(node["ped_z_neg"]))
		corner_b = Vector2(c.x, p.y + float(node["ped_z_pos"]))
	return {"rect": rect, "stop": off + CROSSWALK_WIDTH * 0.5, "a": corner_a, "b": corner_b}


# Coin de trottoir (chemin piéton) du carrefour `n` : sx, sz = −1 ou +1.
func ped_corner(n: int, sx: int, sz: int) -> Vector2:
	var node: Dictionary = nodes[n]
	var p: Vector2 = node["pos"]
	return Vector2(p.x + (float(node["ped_x_pos"]) if sx > 0 else -float(node["ped_x_neg"])),
			p.y + (float(node["ped_z_pos"]) if sz > 0 else -float(node["ped_z_neg"])))


# Emprise (x, z) de la chaussée d'un tronçon, entre les boîtes des carrefours de ses extrémités.
func carriageway_rect(i: int) -> Rect2:
	var s: Dictionary = segments[i]
	var half := float(s["half"])
	var start := float(s["from"]) + _box_half(int(s["a"]), s["axis"])
	var end := float(s["to"]) - _box_half(int(s["b"]), s["axis"])
	if s["axis"] == "x":
		return Rect2(float(s["at"]) - half, start, half * 2.0, end - start)
	return Rect2(start, float(s["at"]) - half, end - start, half * 2.0)


# Emprise du trottoir d'un côté (−1 / +1) d'un tronçon, entre les trottoirs des rues transversales.
func sidewalk_rect(i: int, side: int) -> Rect2:
	var s: Dictionary = segments[i]
	var half := float(s["half"])
	var width := float(s["sidewalks"][0 if side < 0 else 1])
	var start := float(s["from"]) + _box_half(int(s["a"]), s["axis"])
	var end := float(s["to"]) - _box_half(int(s["b"]), s["axis"])
	var lo := float(s["at"]) + (half if side > 0 else -half - width)
	if s["axis"] == "x":
		return Rect2(lo, start, width, end - start)
	return Rect2(start, lo, end - start, width)


# Demi-taille de la boîte du carrefour `n` le long de l'axe d'un tronçon "x" (en z) ou "z" (en x).
func _box_half(n: int, axis: String) -> float:
	return float(nodes[n]["hz"]) if axis == "x" else float(nodes[n]["hx"])


# --- îlots ------------------------------------------------------------------------------------------------------------

func _covered(axis: String, at: float, lo: float, hi: float) -> bool:
	var mid := (lo + hi) * 0.5
	for s: Dictionary in segments:
		if s["axis"] == axis and absf(float(s["at"]) - at) < 0.01 and mid > float(s["from"]) and mid < float(s["to"]):
			return true
	return false


func _build_blocks() -> void:
	var nx := xs.size() - 1
	var nz := zs.size() - 1
	var parent := PackedInt32Array()
	parent.resize(nx * nz)
	for k in parent.size():
		parent[k] = k
	for j in nz:
		for i in nx:
			if i + 1 < nx and not _covered("x", xs[i + 1], zs[j], zs[j + 1]):
				_union(parent, j * nx + i, j * nx + i + 1)
			if j + 1 < nz and not _covered("z", zs[j + 1], xs[i], xs[i + 1]):
				_union(parent, j * nx + i, (j + 1) * nx + i)
	var groups := {}
	for j in nz:
		for i in nx:
			var root := _find(parent, j * nx + i)
			if not groups.has(root):
				groups[root] = [i, j, i, j, 0]
			var g: Array = groups[root]
			groups[root] = [mini(g[0], i), mini(g[1], j), maxi(g[2], i), maxi(g[3], j), int(g[4]) + 1]
	var keys := groups.keys()
	keys.sort()
	for root: int in keys:
		var g: Array = groups[root]
		var outer := Rect2(xs[g[0]], zs[g[1]], xs[g[2] + 1] - xs[g[0]], zs[g[3] + 1] - zs[g[1]])
		var west := xs[g[0]] + _side_extent("x", xs[g[0]], zs[g[1]], zs[g[3] + 1], 1)
		var east := xs[g[2] + 1] - _side_extent("x", xs[g[2] + 1], zs[g[1]], zs[g[3] + 1], -1)
		var north := zs[g[1]] + _side_extent("z", zs[g[1]], xs[g[0]], xs[g[2] + 1], 1)
		var south := zs[g[3] + 1] - _side_extent("z", zs[g[3] + 1], xs[g[0]], xs[g[2] + 1], -1)
		var block := {"cells": Rect2i(g[0], g[1], g[2] - g[0] + 1, g[3] - g[1] + 1), "cell_count": g[4], "outer": outer,
				"interior": Rect2(west, north, east - west, south - north), "zone": "lowrise", "name": "", "plaza": false}
		var center := outer.get_center()
		for zone: Dictionary in Spec.ZONES:
			var r: Rect2 = zone["rect"]
			if center.x >= r.position.x and center.x <= r.end.x and center.y >= r.position.y and center.y <= r.end.y:
				block["zone"] = zone["zone"]
				block["name"] = zone.get("name", "")
				block["plaza"] = bool(zone.get("plaza", false))
				break
		blocks.append(block)


# Largeur (demi-chaussée + trottoir) occupée côté `side` par la rue `axis` = `at` le long de [lo, hi] : la plus grande
# des tronçons qui bordent l'îlot.
func _side_extent(axis: String, at: float, lo: float, hi: float, side: int) -> float:
	var extent := 0.0
	for s: Dictionary in segments:
		if s["axis"] != axis or absf(float(s["at"]) - at) > 0.01:
			continue
		if float(s["to"]) <= lo + 0.01 or float(s["from"]) >= hi - 0.01:
			continue
		extent = maxf(extent, float(s["half"]) + float(s["sidewalks"][0 if side < 0 else 1]))
	return extent


func _find(parent: PackedInt32Array, k: int) -> int:
	while parent[k] != k:
		k = parent[k]
	return k


func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[maxi(ra, rb)] = mini(ra, rb)


# Ruelle au milieu d'un îlot sur deux de la trame (cases alternées), parallèle aux rues bordières les plus importantes :
# les bâtiments donnent sur celles-ci, la ruelle dessert l'arrière. "rect" : entre les intérieurs ; "curb_rect" :
# jusqu'aux bordures des rues qu'elle rejoint (bateau à travers le trottoir).
func _build_alleys() -> void:
	var w := Spec.ALLEY_WIDTH
	for b in blocks.size():
		var block: Dictionary = blocks[b]
		var inner: Rect2 = block["interior"]
		var cells: Rect2i = block["cells"]
		if not Spec.ALLEY_ZONES.has(block["zone"]) or cells.size != Vector2i.ONE or (cells.position.x + cells.position.y) % 2 == 1:
			continue
		if inner.size.x < Spec.ALLEY_MIN_BLOCK or inner.size.y < Spec.ALLEY_MIN_BLOCK:
			continue
		var outer: Rect2 = block["outer"]
		var rank_ns := _rank("z", outer.position.y, outer.position.x, outer.end.x) + _rank("z", outer.end.y, outer.position.x, outer.end.x)
		var rank_we := _rank("x", outer.position.x, outer.position.y, outer.end.y) + _rank("x", outer.end.x, outer.position.y, outer.end.y)
		var alley := {"block": b}
		if rank_ns >= rank_we:
			var z := inner.get_center().y
			var west := outer.position.x + float(_segment_on("x", outer.position.x, outer.position.y, outer.end.y).get("half", 0.0))
			var east := outer.end.x - float(_segment_on("x", outer.end.x, outer.position.y, outer.end.y).get("half", 0.0))
			alley["axis"] = "z"
			alley["rect"] = Rect2(inner.position.x, z - w * 0.5, inner.size.x, w)
			alley["curb_rect"] = Rect2(west, z - w * 0.5, east - west, w)
		else:
			var x := inner.get_center().x
			var north := outer.position.y + float(_segment_on("z", outer.position.y, outer.position.x, outer.end.x).get("half", 0.0))
			var south := outer.end.y - float(_segment_on("z", outer.end.y, outer.position.x, outer.end.x).get("half", 0.0))
			alley["axis"] = "x"
			alley["rect"] = Rect2(x - w * 0.5, inner.position.y, w, inner.size.y)
			alley["curb_rect"] = Rect2(x - w * 0.5, north, w, south - north)
		alleys.append(alley)
		block["alley"] = alleys.size() - 1


const IMPORTANCE := {"boulevard": 4, "perimeter": 3, "avenue": 3, "one_way": 2, "street": 1}


func _rank(axis: String, at: float, lo: float, hi: float) -> int:
	return int(IMPORTANCE.get(_segment_on(axis, at, lo, hi).get("profile", ""), 0))


# Tronçon de la rue `axis` = `at` qui borde [lo, hi] (le premier trouvé), {} s'il n'y en a pas.
func _segment_on(axis: String, at: float, lo: float, hi: float) -> Dictionary:
	for s: Dictionary in segments:
		if s["axis"] == axis and absf(float(s["at"]) - at) < 0.01 and float(s["to"]) > lo + 0.01 and float(s["from"]) < hi - 0.01:
			return s
	return {}


# --- bilans -----------------------------------------------------------------------------------------------------------

func stats() -> Dictionary:
	var by_profile := {}
	var km := {}
	for s: Dictionary in segments:
		by_profile[s["profile"]] = int(by_profile.get(s["profile"], 0)) + 1
		km[s["profile"]] = float(km.get(s["profile"], 0.0)) + (float(s["to"]) - float(s["from"])) / 1000.0
	var zones := {}
	for block: Dictionary in blocks:
		zones[block["zone"]] = int(zones.get(block["zone"], 0)) + 1
	var lit := 0
	var tees := 0
	for node: Dictionary in nodes:
		lit += 1 if node["lit"] else 0
		tees += 1 if (node["arms"] as Dictionary).size() == 3 else 0
	return {"segments": by_profile, "km": km, "nodes": nodes.size(), "lit": lit, "tees": tees, "blocks": blocks.size(),
			"zones": zones, "alleys": alleys.size()}
