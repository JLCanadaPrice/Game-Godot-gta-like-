extends Control

# Panneau de contacts : ouvert/fermé par la touche C (toggle_contacts).
# 4 catégories distinctes (flics/mafieux/rivaux/indics) en onglets. Ne met
# pas le jeu en pause. Vide pour l'instant -- la structure de données
# (ContactsManager) est prête à recevoir de vrais personnages plus tard.

const CATEGORY_TAB_NAMES := {
	"flic": "Flics",
	"mafieux": "Mafieux",
	"rival": "Rivaux",
	"indic": "Indics",
}

@onready var tab_container: TabContainer = $Panel/VBoxContainer/TabContainer
@onready var close_button: Button = $Panel/VBoxContainer/CloseButton

var _lists: Dictionary = {}        # category -> VBoxContainer
var _empty_labels: Dictionary = {} # category -> Label

func _ready() -> void:
	add_to_group("contacts_panel")
	visible = false
	close_button.pressed.connect(_on_close_pressed)
	for category in ContactsManager.CATEGORIES:
		var tab_name: String = CATEGORY_TAB_NAMES[category]
		_lists[category] = tab_container.get_node(
			NodePath(tab_name + "/ScrollContainer/ItemsList"))
		_empty_labels[category] = tab_container.get_node(
			NodePath(tab_name + "/EmptyLabel"))
	ContactsManager.contacts_changed.connect(_refresh)
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_contacts"):
		toggle()

func toggle() -> void:
	if visible:
		hide_ui()
	else:
		show_ui()

func show_ui() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()

func hide_ui() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_close_pressed() -> void:
	hide_ui()

func _refresh() -> void:
	for category in ContactsManager.CATEGORIES:
		var list: VBoxContainer = _lists[category]
		for child in list.get_children():
			child.queue_free()
		var entries: Array = ContactsManager.get_contacts(category)
		(_empty_labels[category] as Label).visible = entries.is_empty()
		for entry in entries:
			var label := Label.new()
			var note: String = entry.get("note", "")
			var note_suffix: String = "  (%s)" % note if note != "" else ""
			label.text = "%s -- confiance %d%s" % [entry["name"], entry["trust"], note_suffix]
			list.add_child(label)
