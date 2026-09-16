extends Node

signal money_changed(new_amount: int)
signal reputation_changed(new_amount: int)
signal building_purchased(building_id: String)
signal vehicle_purchased(vehicle_id: String)
signal apartment_purchased(apartment_id: String)

var money: int = 5000
var reputation: int = 0
var owned_buildings: Array[String] = []  # stocke les IDs des bâtiments possédés
var owned_vehicles: Array[String] = []   # stocke les IDs des modèles de voiture possédés (concessionnaire)
var owned_apartments: Array[String] = [] # stocke les IDs des appartements possédés (agence immobilière)

func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)

func remove_money(amount: int) -> bool:
	if amount > money:
		return false
	money -= amount
	money_changed.emit(money)
	return true

func add_reputation(amount: int) -> void:
	reputation = clamp(reputation + amount, -100, 100)
	reputation_changed.emit(reputation)

func own_building(building_id: String) -> void:
	if not owned_buildings.has(building_id):
		owned_buildings.append(building_id)
		building_purchased.emit(building_id)

func owns_building(building_id: String) -> bool:
	return owned_buildings.has(building_id)

func own_vehicle(vehicle_id: String) -> void:
	if not owned_vehicles.has(vehicle_id):
		owned_vehicles.append(vehicle_id)
		vehicle_purchased.emit(vehicle_id)

func owns_vehicle(vehicle_id: String) -> bool:
	return owned_vehicles.has(vehicle_id)

func own_apartment(apartment_id: String) -> void:
	if not owned_apartments.has(apartment_id):
		owned_apartments.append(apartment_id)
		apartment_purchased.emit(apartment_id)

func owns_apartment(apartment_id: String) -> bool:
	return owned_apartments.has(apartment_id)
