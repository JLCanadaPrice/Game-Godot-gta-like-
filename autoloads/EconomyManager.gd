extends Node

# Économie criminelle stylisée façon Tulsa King : gestion de stock, demande,
# revenu par cycle. Volontairement abstrait — aucune mécanique réaliste de trafic,
# juste une boucle tycoon (stocker -> attendre -> encaisser -> re-stocker).

signal business_income_generated(business_id: String, amount: int)
signal business_stock_changed(business_id: String, new_stock: int)
signal cycle_completed

const CYCLE_SECONDS := 30.0          # durée d'un "jour" de jeu
const BASE_SALES_PER_CYCLE := 20     # unités écoulées par cycle si le stock suit
const RESTOCK_COST_RATIO := 0.4      # coût de réappro à l'unité = base_price * ce ratio

var all_businesses: Array[BusinessData] = []

var _cycle_timer: Timer

func _ready() -> void:
	_load_all_businesses()
	_cycle_timer = Timer.new()
	_cycle_timer.wait_time = CYCLE_SECONDS
	_cycle_timer.one_shot = false
	_cycle_timer.autostart = true
	_cycle_timer.timeout.connect(_on_cycle_timeout)
	add_child(_cycle_timer)

func _load_all_businesses() -> void:
	var dir := DirAccess.open("res://resources/businesses/")
	if dir == null:
		push_warning("Dossier resources/businesses/ introuvable")
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var data: BusinessData = load("res://resources/businesses/" + file_name)
			if data != null:
				# Copie runtime : on ne veut pas muter la ressource sur disque.
				var runtime_copy := data.duplicate() as BusinessData
				all_businesses.append(runtime_copy)
		file_name = dir.get_next()
	dir.list_dir_end()

# --- Accès ---------------------------------------------------------------

func get_business(id: String) -> BusinessData:
	for b in all_businesses:
		if b.id == id:
			return b
	return null

func get_business_for_building(building_id: String) -> BusinessData:
	for b in all_businesses:
		if b.linked_building_id == building_id:
			return b
	return null

func is_business_active(b: BusinessData) -> bool:
	return b != null and GameManager.owns_building(b.linked_building_id)

# Estimation du revenu du prochain cycle (pour l'UI).
func get_cycle_income(b: BusinessData) -> int:
	if b == null:
		return 0
	var units := mini(b.current_stock, BASE_SALES_PER_CYCLE)
	var sales_income := int(round(units * b.base_price * b.demand_factor))
	return sales_income + _linked_passive_income(b)

func get_restock_unit_cost(b: BusinessData) -> int:
	return maxi(1, int(round(b.base_price * RESTOCK_COST_RATIO)))

# Coût pour remplir jusqu'à max_stock.
func get_restock_cost(b: BusinessData) -> int:
	if b == null:
		return 0
	return maxi(0, b.max_stock - b.current_stock) * get_restock_unit_cost(b)

# --- Cycle de temps ----------------------------------------------------

func _on_cycle_timeout() -> void:
	for b in all_businesses:
		if is_business_active(b):
			_process_business(b)
	cycle_completed.emit()

func _process_business(b: BusinessData) -> void:
	var units := mini(b.current_stock, BASE_SALES_PER_CYCLE)
	var sales_income := int(round(units * b.base_price * b.demand_factor))
	var total := sales_income + _linked_passive_income(b)

	if units > 0:
		b.current_stock -= units
		business_stock_changed.emit(b.id, b.current_stock)
		# Seules les ventes réelles attirent la police.
		PoliceManager.register_criminal_activity(b.risk_factor)

	if total > 0:
		GameManager.add_money(total)
		business_income_generated.emit(b.id, total)

func _linked_passive_income(b: BusinessData) -> int:
	var bld := BuildingRegistry.get_building(b.linked_building_id)
	return bld.passive_income if bld != null else 0

# --- Réapprovisionnement (déclenché par l'UI) -------------------------

func restock(business_id: String) -> bool:
	var b := get_business(business_id)
	if b == null:
		return false
	var missing := b.max_stock - b.current_stock
	if missing <= 0:
		return false

	var unit_cost := get_restock_unit_cost(b)
	var units_to_buy := missing
	var cost := units_to_buy * unit_cost

	# Achat partiel si le joueur n'a pas de quoi remplir complètement.
	if cost > GameManager.money:
		units_to_buy = int(float(GameManager.money) / unit_cost)   # division flottante -> floor voulu
		cost = units_to_buy * unit_cost

	if units_to_buy <= 0:
		return false
	if not GameManager.remove_money(cost):
		return false

	b.current_stock += units_to_buy
	business_stock_changed.emit(b.id, b.current_stock)
	return true
