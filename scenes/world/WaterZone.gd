extends Area3D

# Zone de détection de nage : AJOUTÉE en plus de la collision solide déjà
# existante sur les plans d'eau (StaticBody3D "Water"/"Lake", inchangée),
# pas un remplacement. Prévient le joueur (notify_water_entered/exited,
# même principe que notify_car_in_range côté véhicules) quand il entre/sort
# de ce volume ; c'est Player.gd qui décide ensuite du comportement (état
# de nage). collision_layer=0 (rien ne doit détecter CETTE zone), mask=1
# (calque par défaut du joueur).

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and body.has_method("notify_water_entered"):
		body.notify_water_entered(self)

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player") and body.has_method("notify_water_exited"):
		body.notify_water_exited(self)
