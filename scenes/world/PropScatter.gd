@tool
extends Node3D

# Instancie une grille de bâtiments décoratifs (PropBuilding).
#
# @tool + bake_now : on coche "Bake Now" UNE FOIS dans l'éditeur -> les props
# deviennent de vrais enfants figés (transform + matériau de façade), sauvés
# dans World.tscn au Ctrl+S. Plus de génération/randomisation au lancement.

const PROP := preload("res://scenes/world/PropBuilding.tscn")

@export var rows_z: Array[float] = []
@export var cols_x: Array[float] = []

# Coche dans l'Inspecteur (nodes DistrictNorth / DistrictSouth) pour figer.
@export var bake_now := false:
	set(value):
		if not value:
			return
		bake_now = false
		if Engine.is_editor_hint():
			call_deferred("_bake")

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if get_child_count() > 0:
		return   # déjà figé dans la scène -> pas de régénération runtime
	_generate(null)

func _generate(root: Node) -> void:
	for z in rows_z:
		for x in cols_x:
			var p := PROP.instantiate()
			add_child(p)
			p.position = Vector3(x, 0.0, z)
			if root != null:
				p.randomize_and_face()   # pose les valeurs random MAINTENANT
				p.baked = true            # -> ne se re-randomisera pas au runtime

func _bake() -> void:
	var root: Node = owner
	if root == null:
		root = get_tree().edited_scene_root
	if root == null:
		push_error("[PropScatter] BAKE ANNULÉ : racine de scène introuvable")
		return
	for c in get_children():
		c.free()
	_generate(root)
	var res := _own_recursive(self, root)
	print("[PropScatter/%s] BAKE : %d props, %d/%d ownés. Ctrl+S puis recharger la scène." % [name, get_child_count(), res[0], res[1]])

func _own_recursive(n: Node, root: Node) -> Array:
	var owned := 0
	var total := 0
	for c in n.get_children():
		total += 1
		c.owner = root
		if c.owner == root:
			owned += 1
		if c.scene_file_path == "":
			var sub := _own_recursive(c, root)
			owned += sub[0]
			total += sub[1]
	return [owned, total]
