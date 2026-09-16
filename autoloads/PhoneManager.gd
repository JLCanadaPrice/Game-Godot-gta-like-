extends Node

# Téléphone du joueur : pivot pour appeler les contacts (ContactsManager,
# 4 catégories) et, plus tard, des services génériques joignables par
# téléphone mais qui ne sont pas des contacts nommés (concessionnaire,
# agence immo) -- d'où le champ "service" optionnel dès maintenant dans
# chaque entrée du journal, même si aucun composeur/numéroto n'appelle
# encore call_service() : ça évite de retravailler cette structure une
# deuxième fois quand ces systèmes arriveront.
#
# État runtime propre à la partie en cours (comme ContactsManager.contacts)
# -> Array de Dictionary, pas de Resource .tres.

signal call_log_changed
signal incoming_call(entry: Dictionary)

# Chaque entrée : {"name": String, "category": String, "service": String,
# "direction": "sortant"/"entrant", "note": String}
# - appel à un contact nommé (une des 4 catégories) : "category" rempli, "service" vide
# - appel à un service générique (concessionnaire, agence immo...) : "service" rempli, "category" vide
var call_log: Array[Dictionary] = []

func call_contact(category: String, contact_name: String) -> void:
	_log_call({
		"name": contact_name,
		"category": category,
		"service": "",
		"direction": "sortant",
		"note": "",
	})

func call_service(service_id: String, display_name: String = "") -> void:
	_log_call({
		"name": display_name if display_name != "" else service_id,
		"category": "",
		"service": service_id,
		"direction": "sortant",
		"note": "",
	})

func trigger_incoming_call(caller_name: String, category: String = "", service_id: String = "", note: String = "") -> void:
	var entry := {
		"name": caller_name,
		"category": category,
		"service": service_id,
		"direction": "entrant",
		"note": note,
	}
	call_log.append(entry)
	incoming_call.emit(entry)
	call_log_changed.emit()

func _log_call(entry: Dictionary) -> void:
	call_log.append(entry)
	call_log_changed.emit()
