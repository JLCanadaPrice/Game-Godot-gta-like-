extends Node

# Rond-point d'Echo Circle : la circulation ne doit JAMAIS s'y figer (2026-09-21).
#
# Quatre interblocages y ont été trouvés et corrigés le même jour, chacun permanent une fois formé
# (cf. CLAUDE.md, « Rond-point d'Echo Circle ») :
#  1. la voiture qui attendait à une entrée cédait à toute voiture de l'anneau à moins de 14 m, même
#     arrêtée, et la voiture de l'anneau freinait pour elle (son couloir d'obstacles, droit, filait
#     tangent à l'anneau jusqu'aux entrées) : chacune attendait l'autre ;
#  2. au bout d'une branche, la voiture de tête cédait sa PRIORITÉ DE VIRAGE à la voiture qui la suivait ;
#  3. plus généralement, une voiture cédait sa priorité à une voiture ARRÊTÉE DERRIÈRE UNE AUTRE, qui ne
#     pouvait pas passer avant — cycles au bout des branches et aux carrefours voisins, dont les files
#     remontaient jusque sur l'anneau ;
#  4. quatre voitures engagées dans un carrefour, chacune arrêtée derrière la suivante, en rond.
# Le test laisse rouler la vraie circulation, joueur posé sur l'îlot central (anneau entier à moins de
# 50 m : rien n'y est gelé par SimulationCuller), et échoue si une file se fige : au moins
# BLOQUEES_MAX voitures de la zone arrêtées depuis ARRET_MAX s. Il vérifie aussi que les deux voies de
# l'anneau servent et que les voitures en sortent. En cas d'échec, il imprime la chaîne « X attend Y »
# lue sur Car.diag_raison, c'est-à-dire sur les vraies règles.
#
# Lancer : Godot --headless --fixed-fps 60 res://scenes/tests/RoundaboutTrafficTest.tscn

const WORLD := preload("res://scenes/world/World.tscn")
const CENTRE := Vector3(110, 0, -316)
const ZONE := 60.0
const DUREE := 300.0
const ARRET := 0.3
const ARRET_MAX := 40.0
const BLOQUEES_MAX := 3
const SORTIES_MIN := 20

var _t := 0.0
var _pas := 0.0
var _arret := {}
var _sur_anneau := {}
var _sorties := 0
var _voies := {"interieure": 0, "exterieure": 0}
var _pire := 0
var _fautes: Array[String] = []
var _trace_faite := false


func _ready() -> void:
	add_child(WORLD.instantiate())
	await get_tree().physics_frame
	await get_tree().physics_frame
	var joueur := get_tree().get_first_node_in_group("player") as Node3D
	if joueur != null:
		joueur.global_position = CENTRE + Vector3(0, 2.5, 0)


func _physics_process(delta: float) -> void:
	_t += delta
	_pas -= delta
	if _pas > 0.0:
		return
	_pas = 1.0
	var bloquees: Array = []
	for v in get_tree().get_nodes_in_group(&"vehicle"):
		var c := v as Node3D
		if c == null or not c.has_method("is_on_ring") or c.get("driven_by_player") == true:
			continue
		if Vector2(c.global_position.x - CENTRE.x, c.global_position.z - CENTRE.z).length() > ZONE:
			_arret.erase(c.get_instance_id())
			continue
		var id := c.get_instance_id()
		var sur := bool(c.call("is_on_ring"))
		if sur:
			var r := Vector2(c.global_position.x - CENTRE.x, c.global_position.z - CENTRE.z).length()
			if r < 29.2:
				_voies["interieure"] += 1
			elif r > 30.8:
				_voies["exterieure"] += 1
		elif _sur_anneau.get(id, false):
			_sorties += 1
		_sur_anneau[id] = sur
		if float(c.get("_ai_speed")) < ARRET:
			_arret[id] = float(_arret.get(id, 0.0)) + 1.0
			if float(_arret[id]) >= ARRET_MAX:
				bloquees.append(c)
		else:
			_arret.erase(id)
	_pire = maxi(_pire, bloquees.size())
	if bloquees.size() >= BLOQUEES_MAX and not _trace_faite:
		_trace_faite = true
		_fautes.append("%d voitures figees depuis %d s pres de l'anneau a t = %.0f s" % [bloquees.size(), int(ARRET_MAX), _t])
		for c: Node3D in bloquees:
			var o = c.get("diag_objet")
			print("ROUNDABOUT_TRAFFIC_TRACE %s en (%.1f, %.1f) : %s %s" % [String(c.get("model_path")).get_file(),
					c.global_position.x, c.global_position.z, String(c.get("diag_raison")),
					String(o.get("model_path")).get_file() if o != null and is_instance_valid(o) else ""])
	if _t >= DUREE:
		_verdict()


func _verdict() -> void:
	set_physics_process(false)
	if _sorties < SORTIES_MIN:
		_fautes.append("%d sorties de l'anneau en %.0f s, il en faut au moins %d" % [_sorties, DUREE, SORTIES_MIN])
	if _voies["interieure"] == 0 or _voies["exterieure"] == 0:
		_fautes.append("une voie de l'anneau ne sert jamais : %s" % str(_voies))
	print("ROUNDABOUT_TRAFFIC %.0f s : %d sorties, au plus %d voiture(s) figee(s) %d s, echantillons voie interieure %d / exterieure %d"
			% [DUREE, _sorties, _pire, int(ARRET_MAX), _voies["interieure"], _voies["exterieure"]])
	if _fautes.is_empty():
		print("ROUNDABOUT_TRAFFIC_RESULT OK")
	else:
		for f in _fautes:
			print("ROUNDABOUT_TRAFFIC_FAUTE %s" % f)
		print("ROUNDABOUT_TRAFFIC_RESULT FAIL %d faute(s)" % _fautes.size())
	get_tree().quit(0)
