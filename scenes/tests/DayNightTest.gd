extends Node3D

# Cycle jour/nuit, vérifié dans le monde réel (World.tscn instanciée), pas sur les constantes.
#
# Ce que le test couvre à cette étape, et pourquoi :
#  - l'heure avance, et le facteur nuit suit ses charnières et son crépuscule (sinon rien d'autre
#    n'a de sens : c'est lui qui pilotera les lampadaires) ;
#  - le soleil est au-dessus de l'horizon à midi et en dessous à minuit ;
#  - SES OMBRES SONT COUPÉES la nuit, et la lune éclaire moins que le soleil. Les ombres ne sont pas
#    un détail esthétique : la passe d'ombre directionnelle est le plus gros poste d'appels de dessin
#    de la scène, et c'est elle qui paiera l'éclairage nocturne à l'étape suivante. Une régression
#    là passerait inaperçue à l'œil et se verrait seulement sur l'UHD 750.

const WORLD := preload("res://scenes/world/World.tscn")

var _fautes: Array[String] = []


func _ready() -> void:
	var world := WORLD.instantiate()
	add_child(world)
	for spawner_name in ["CarSpawner", "NpcSpawner"]:
		var s := world.get_node_or_null(spawner_name)
		if s != null:
			s.set_process(false)
	for k in 4:
		await get_tree().physics_frame
	var cycle := world.get_node_or_null("DayNight")
	if cycle == null:
		_fautes.append("DayNight absent de World.tscn")
		_verdict()
		return
	cycle.set("paused", true)
	await _heure_et_nuit(cycle)
	await _soleil(cycle)
	_verdict()


func _heure_et_nuit(cycle: Node) -> void:
	for essai: Array in [[12.0, 0.0], [1.0, 1.0], [23.5, 1.0], [4.0, 1.0], [8.0, 0.0], [18.0, 0.0]]:
		cycle.call("set_hour", essai[0])
		var n: float = cycle.call("night_factor")
		if not is_equal_approx(n, float(essai[1])):
			_fautes.append("à %.1f h, facteur nuit %.2f au lieu de %.2f" % [essai[0], n, essai[1]])
	# crépuscule : strictement entre 0 et 1, et croissant
	var avant := -1.0
	for h: float in [19.2, 19.6, 20.0, 20.4, 20.8]:
		cycle.call("set_hour", h)
		var n: float = cycle.call("night_factor")
		if n <= 0.0 or n >= 1.0:
			_fautes.append("crépuscule %.1f h : facteur nuit %.2f, attendu strictement entre 0 et 1" % [h, n])
		if n <= avant:
			_fautes.append("crépuscule %.1f h : facteur nuit %.2f ne croît pas (précédent %.2f)" % [h, n, avant])
		avant = n
	# l'heure avance toute seule quand le cycle n'est pas figé
	cycle.set("paused", false)
	cycle.call("set_hour", 10.0)
	for k in 12:
		await get_tree().process_frame
	var apres: float = cycle.get("hour")
	if apres <= 10.0:
		_fautes.append("cycle non figé : l'heure n'a pas avancé (%.4f)" % apres)
	cycle.set("paused", true)
	print("DAY_NIGHT_HEURE charnières et crépuscule conformes, heure avance jusqu'à %.4f h" % apres)


func _soleil(cycle: Node) -> void:
	var sun := _premier_soleil(self)
	if sun == null:
		_fautes.append("DirectionalLight3D introuvable")
		return
	cycle.call("set_hour", 12.0)
	await get_tree().process_frame
	var midi: Vector3 = cycle.call("sun_direction")
	var ombre_midi := sun.shadow_enabled
	var energie_midi := sun.light_energy
	cycle.call("set_hour", 1.0)
	await get_tree().process_frame
	var minuit: Vector3 = cycle.call("sun_direction")
	var ombre_minuit := sun.shadow_enabled
	var energie_minuit := sun.light_energy
	if midi.y <= 0.0:
		_fautes.append("à midi le soleil est sous l'horizon (y = %.3f)" % midi.y)
	if minuit.y >= 0.0:
		_fautes.append("à 1 h le soleil est au-dessus de l'horizon (y = %.3f)" % minuit.y)
	if not ombre_midi:
		_fautes.append("ombres du soleil coupées à midi")
	if ombre_minuit:
		_fautes.append("ombres encore actives la nuit : c'est le poste GPU le plus lourd de la scène")
	if energie_minuit >= energie_midi:
		_fautes.append("la lune (%.3f) éclaire autant que le soleil (%.3f)" % [energie_minuit, energie_midi])
	print("DAY_NIGHT_SOLEIL midi élévation %.1f°, énergie %.2f, ombres %s | 1 h élévation %.1f°, énergie %.3f, ombres %s"
			% [rad_to_deg(asin(midi.y)), energie_midi, str(ombre_midi),
			rad_to_deg(asin(minuit.y)), energie_minuit, str(ombre_minuit)])


func _premier_soleil(n: Node) -> DirectionalLight3D:
	if n is DirectionalLight3D:
		return n as DirectionalLight3D
	for c in n.get_children():
		var r := _premier_soleil(c)
		if r != null:
			return r
	return null


func _verdict() -> void:
	if _fautes.is_empty():
		print("DAY_NIGHT_RESULT OK")
	else:
		for f in _fautes:
			print("DAY_NIGHT_FAUTE %s" % f)
		print("DAY_NIGHT_RESULT FAIL %d faute(s)" % _fautes.size())
	get_tree().quit(0)
