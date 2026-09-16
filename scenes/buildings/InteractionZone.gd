extends Area3D

# Zone d'interaction [E] réutilisable (porte de boutique, comptoir, sortie) : affiche une invite quand le
# joueur est dedans, à pied et sans panneau UI ouvert, et émet `interacted` à l'appui sur "interact".
# L'événement est alors consommé : le Player ne tente pas en même temps de monter dans une voiture garée
# à côté (les zones sont après le Player dans l'arbre, elles reçoivent l'entrée avant lui).

signal interacted(player: Node3D)

@export var prompt_text := "[E]"
@export var zone_size := Vector3(2.0, 2.4, 2.0)

var _player: Node3D = null
var _prompt: Label3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1   # le Player est sur le calque 1
	var box := BoxShape3D.new()
	box.size = zone_size
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = Vector3(0.0, zone_size.y / 2.0, 0.0)
	add_child(shape)
	_prompt = Label3D.new()   # même style que l'invite des voitures (Car.tscn/EnterPrompt)
	_prompt.text = prompt_text
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.font_size = 48
	_prompt.outline_size = 12
	_prompt.position = Vector3(0.0, zone_size.y + 0.2, 0.0)
	_prompt.visible = false
	add_child(_prompt)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# Rien à faire tant que le joueur n'est pas dans la zone : _process et
	# _unhandled_input ne sont réarmés qu'à son entrée (cf. _on_body_entered).
	# La carte compte ~1045 zones de bâtiment ; les laisser toutes actives
	# coûtait 1045 appels de script par frame rendue, et faisait traverser
	# 1045 nœuds à chaque événement d'entrée, pour un seul joueur.
	set_process(false)
	set_process_unhandled_input(false)


func _process(_delta: float) -> void:
	_prompt.visible = _player != null and _can_interact(_player)


func _unhandled_input(event: InputEvent) -> void:
	if _player == null or not event.is_action_pressed("interact") or not _can_interact(_player):
		return
	get_viewport().set_input_as_handled()
	interacted.emit(_player)


# À pied et sans panneau qui pilote la souris (même règle que Player._ui_owns_mouse).
func _can_interact(player: Node3D) -> bool:
	if bool(player.get("_driving")):
		return false
	return not (player.has_method("_ui_owns_mouse") and player.call("_ui_owns_mouse"))


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player = body
		set_process(true)
		set_process_unhandled_input(true)


func _on_body_exited(body: Node3D) -> void:
	if body == _player:
		_player = null
		# état de sortie identique à ce que _process aurait posé (_player null
		# -> invite masquée), donc rien ne change visuellement en se mettant en veille
		_prompt.visible = false
		set_process(false)
		set_process_unhandled_input(false)
