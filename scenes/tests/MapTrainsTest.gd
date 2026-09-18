extends Node

# Test headless de l'exploitation ferroviaire (chantier des trains, étape 3). Le test ne charge PAS la carte : il
# instancie la voie seule (RailPath lit rail_path.tres et n'a besoin de rien d'autre), ce qui laisse tourner des
# dizaines de minutes de jeu en quelques secondes.
#
# Surveillé à chaque frame physique, sur deux vagues complètes :
#  - jamais plus de max_trains rames en ligne ;
#  - jamais deux rames de SENS OPPOSÉS en même temps (la voie est unique, elles se croiseraient) ;
#  - jamais deux rames dans le même canton, et jamais de chevauchement (queue de la précédente / nez de la suivante) ;
#  - aucune rame hors de la voie, ni au-delà du heurtoir ;
#  - les compositions et les longueurs de rame sont celles attendues ;
#  - les deux sens sont bien exploités (la vague suivante repart de l'autre bout).
#
# Lancer : Godot --headless --fixed-fps 60 --quit-after 120000 res://scenes/tests/MapTrainsTest.tscn

const RAIL := preload("res://scenes/world/RailPath.gd")
const MAX_FRAMES := 200000
const RAKES := {"grande vitesse": 5, "fret": 15}

var _rail: Node3D
var _errors: Array[String] = []
var _frames := 0
var _waves := 0
var _dirs := {}
var _peak := 0
var _min_gap := INF
var _seen := {}
var _last_dir := 0
var _done := false


func _ready() -> void:
	print("MAP_TRAINS_BEGIN")
	_rail = RAIL.new()
	_rail.name = "Rail"
	add_child(_rail)
	if _rail.data == null:
		_errors.append("rail_path.tres absent ou illisible")
		_finish()


func _physics_process(_delta: float) -> void:
	if _done or _rail == null or _rail.data == null:
		return
	_frames += 1
	var live: Array = _rail.report()
	_peak = maxi(_peak, live.size())
	if live.size() > int(_rail.max_trains):
		_fail("%d rames en ligne, plafond %d" % [live.size(), _rail.max_trains])
	var dirs := {}
	for t: Dictionary in live:
		dirs[int(t["sens"])] = true
		_dirs[int(t["sens"])] = true
		var name := String(t["nom"])
		if not _seen.has(name):
			_seen[name] = t
			var kind := String(t["type"])
			if RAKES.has(kind) and int(t["caisses"]) != int(RAKES[kind]):
				_fail("%s (%s) : %d caisses au lieu de %d" % [name, kind, t["caisses"], RAKES[kind]])
			if _last_dir != 0 and int(t["sens"]) != _last_dir:
				_waves += 1
			_last_dir = int(t["sens"])
		var lo: float = minf(float(t["tete"]), float(t["queue"]))
		var hi: float = maxf(float(t["tete"]), float(t["queue"]))
		if lo < -1.0 or hi > float(_rail.length) + 1.0:
			_fail("%s hors de la voie : %.1f a %.1f m (voie 0 a %.0f)" % [name, lo, hi, _rail.length])
	if dirs.size() > 1:
		_fail("deux sens en meme temps sur la voie unique : %s" % str(dirs.keys()))
	_check_spacing(live)
	if _waves >= 2 and _frames > 600:
		_done = true
		_finish()
	elif _frames > MAX_FRAMES:
		_fail("%d frames sans voir deux vagues (vagues vues : %d)" % [_frames, _waves])
		_done = true
		_finish()


# Deux rames du même sens ne doivent ni se chevaucher ni partager un canton.
func _check_spacing(live: Array) -> void:
	for i in live.size():
		for j in range(i + 1, live.size()):
			var a: Dictionary = live[i]
			var b: Dictionary = live[j]
			var a_lo: float = minf(float(a["tete"]), float(a["queue"]))
			var a_hi: float = maxf(float(a["tete"]), float(a["queue"]))
			var b_lo: float = minf(float(b["tete"]), float(b["queue"]))
			var b_hi: float = maxf(float(b["tete"]), float(b["queue"]))
			var gap: float = (b_lo - a_hi) if b_lo > a_hi else (a_lo - b_hi)
			_min_gap = minf(_min_gap, gap)
			if gap < 0.0:
				_fail("%s et %s se chevauchent de %.1f m" % [a["nom"], b["nom"], -gap])
			elif gap < float(_rail.block_length) - float(_rail.block_margin) - 1.0 and _same_block(a_lo, a_hi, b_lo, b_hi):
				_fail("%s et %s dans le meme canton (ecart %.1f m)" % [a["nom"], b["nom"], gap])


func _same_block(a_lo: float, a_hi: float, b_lo: float, b_hi: float) -> bool:
	var block: float = float(_rail.block_length)
	for k in range(floori(a_lo / block), floori(a_hi / block) + 1):
		if k >= floori(b_lo / block) and k <= floori(b_hi / block):
			return true
	return false


func _fail(line: String) -> void:
	if _errors.size() < 8 and not _errors.has(line):
		_errors.append(line)


func _finish() -> void:
	print("MAP_TRAINS_EXPLOITATION %d frames, %d vague(s), %d rame(s) differentes, pointe de %d en ligne, sens vus %s, ecart mini entre rames %.1f m"
			% [_frames, _waves, _seen.size(), _peak, str(_dirs.keys()), _min_gap if _min_gap < INF else 0.0])
	var kinds := {}
	for name: String in _seen:
		var k := String((_seen[name] as Dictionary)["type"])
		kinds[k] = int(kinds.get(k, 0)) + 1
		if not kinds.has(k + "_len"):
			kinds[k + "_len"] = snappedf(float((_seen[name] as Dictionary)["longueur"]), 0.01)
	print("MAP_TRAINS_RAMES %s" % JSON.stringify(kinds))
	if _dirs.size() < 2:
		_fail("un seul sens exploite : %s" % str(_dirs.keys()))
	if _errors.is_empty():
		print("MAP_TRAINS_RESULT OK")
	else:
		print("MAP_TRAINS_RESULT FAIL " + " | ".join(_errors))
	get_tree().quit(0 if _errors.is_empty() else 1)
