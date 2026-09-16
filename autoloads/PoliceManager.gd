extends Node

# Recherche policière façon GTA (étoiles). Alimentée par EconomyManager :
# chaque cycle de ventes a une probabilité (= risk_factor du business) de faire
# monter d'une étoile. Sans activité criminelle pendant COOLDOWN_SECONDS, on
# redescend d'une étoile, puis encore une, etc.

signal wanted_level_changed(new_level: int)

const MAX_WANTED := 5
const COOLDOWN_SECONDS := 45.0  # inactivité (aucune vente) avant de perdre une étoile

var wanted_level: int = 0  # 0 à 5

var _cooldown_timer: Timer

func _ready() -> void:
	_cooldown_timer = Timer.new()
	_cooldown_timer.wait_time = COOLDOWN_SECONDS
	_cooldown_timer.one_shot = false
	_cooldown_timer.autostart = true
	_cooldown_timer.timeout.connect(_on_cooldown_tick)
	add_child(_cooldown_timer)

# Appelé par EconomyManager à chaque cycle où un business a réellement vendu.
func register_criminal_activity(risk_factor: float) -> void:
	_cooldown_timer.start()  # relance le compte à rebours d'inactivité
	if randf() < clampf(risk_factor, 0.0, 1.0):
		_set_wanted(wanted_level + 1)

func _on_cooldown_tick() -> void:
	# N'arrive que si aucune activité n'a relancé le timer entre-temps.
	if wanted_level > 0:
		_set_wanted(wanted_level - 1)

func _set_wanted(value: int) -> void:
	var new_level := clampi(value, 0, MAX_WANTED)
	if new_level == wanted_level:
		return
	wanted_level = new_level
	wanted_level_changed.emit(wanted_level)
