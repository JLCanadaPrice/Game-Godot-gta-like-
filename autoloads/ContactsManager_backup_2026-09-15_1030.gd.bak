extends Node

# Listes de contacts du joueur, 4 catégories distinctes. État runtime propre
# à la partie en cours (comme GameManager.money), pas du contenu pré-conçu
# -> Dictionary/Array simples plutôt que des Resource .tres, pour rester
# facilement sérialisable en JSON le jour où SaveSystem sera implémenté.
# Vide pour l'instant, structure prête à recevoir de vrais personnages.

signal contacts_changed

const CATEGORIES := ["flic", "mafieux", "rival", "indic"]

# category (String) -> Array[Dictionary], chaque entrée :
# {"name": String, "trust": int, "note": String}
var contacts: Dictionary = {
	"flic": [],
	"mafieux": [],
	"rival": [],
	"indic": [],
}

func add_contact(category: String, contact_name: String, trust: int = 0, note: String = "") -> void:
	if not CATEGORIES.has(category):
		push_warning("Catégorie de contact inconnue : %s" % category)
		return
	(contacts[category] as Array).append({"name": contact_name, "trust": trust, "note": note})
	contacts_changed.emit()

func remove_contact(category: String, contact_name: String) -> void:
	if not CATEGORIES.has(category):
		return
	var list: Array = contacts[category]
	for i in list.size():
		if list[i]["name"] == contact_name:
			list.remove_at(i)
			contacts_changed.emit()
			return

func set_trust(category: String, contact_name: String, trust: int) -> void:
	if not CATEGORIES.has(category):
		return
	for entry in (contacts[category] as Array):
		if entry["name"] == contact_name:
			entry["trust"] = trust
			contacts_changed.emit()
			return

func get_contacts(category: String) -> Array:
	return contacts.get(category, [])
