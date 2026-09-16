@tool
extends Node3D

# Remplace le BoxMesh placeholder des 14 bâtiments par les vrais modèles du
# pack Quaternius building_pack (CC0), un modèle DIFFÉRENT par bâtiment
# (assigné explicitement par nom de noeud, pas par palier de prix). Le modèle +
# une collision solide englobante + la zone d'achat élargie sont FIGÉS dans
# World.tscn (owner = racine). Le code d'achat (Building.gd / BuildingData /
# Area3D) n'est PAS touché.
#
# Coche "Bake Now" dans l'Inspecteur (node "BuildingKit"), puis Ctrl+S, puis
# Scène > Recharger la scène pour vérifier la persistance.
#
# NB : une fois bake, TowerBuilding._apply_height() détecte la présence de
# "KitModel" et n'étire plus le mesh/collision au runtime (le nombre d'étages
# du modèle choisi remplace le stretch — voir TowerBuilding.gd).

const M := "res://assets/building_pack/"

# Assignation explicite : un modèle par bâtiment (nom du noeud dans ../Buildings).
# Paliers : bon marché -> 1Story_*/2Story_* simples ; moyen -> 2Story_* travaillés
# ou 3Story_* ; cher/tours -> 4Story_* et 6Story_Stack (le plus haut du pack).
const BUILDING_MODEL := {
	"Warehouse": "1Story_Mat",
	"Bar": "1Story_Sign_Mat",
	"Laundromat": "1Story_GableRoof_Mat",
	"Nightclub": "2Story_Columns_Mat",
	"Casino": "3Story_Balcony_Mat",
	"DocksWarehouse": "4Story_Mat",
	"ShippingOffice": "4Story_Wide_2Doors_Mat",
	"CustomsHouse": "4Story_Center_Mat",
	"AptSmall": "2Story_Sidehouse_Mat",
	"AptMid": "2Story_Double_Mat",
	"OfficeLowrise": "3Story_Small_Mat",
	"OfficeHighrise": "3Story_Slim_Mat",
	"TowerMeridian": "4Story_Wide_2Doors_Roof_Mat",
	"TowerBlackwood": "6Story_Stack_Mat",
}

const ZONE_MARGIN := 5.0       # marge autour de l'empreinte pour la zone d'achat Area3D
const KIT_NAME := "KitModel"

@export var bake_now := false:
	set(value):
		if not value:
			return
		bake_now = false
		if Engine.is_editor_hint():
			call_deferred("_bake")

func _ready() -> void:
	pass   # aucune génération runtime : le baker ne sert qu'en éditeur

func _bake() -> void:
	var root: Node = owner
	if root == null:
		root = get_tree().edited_scene_root
	if root == null:
		push_error("[BuildingKit] racine de scène introuvable")
		return
	var buildings := get_node_or_null("../Buildings")
	if buildings == null:
		push_error("[BuildingKit] node ../Buildings introuvable")
		return

	var done := 0
	var owned := 0
	for b in buildings.get_children():
		var b3 := b as Node3D
		if b3 == null:
			continue
		if _bake_one(b3, root):
			done += 1
			if b3.get_node(KIT_NAME).owner == root:
				owned += 1
	print("[BuildingKit] BAKE : %d/%d bâtiments équipés (%d modèles ownés par la racine). " % [done, buildings.get_child_count(), owned]
		+ "Ctrl+S puis Scène > Recharger la scène.")

func _bake_one(b: Node3D, root: Node) -> bool:
	# re-bake propre
	var old := b.get_node_or_null(KIT_NAME)
	if old != null:
		old.free()

	var model_name: String = BUILDING_MODEL.get(b.name, "")
	if model_name == "":
		push_error("[BuildingKit] pas de modèle assigné pour : " + str(b.name))
		return false
	var path := M + model_name + ".fbx"

	var scene := load(path) as PackedScene
	if scene == null:
		push_error("[BuildingKit] modèle introuvable : " + path)
		return false
	var model := scene.instantiate() as Node3D
	model.name = KIT_NAME
	b.add_child(model)

	# AABB du modèle dans le repère du bâtiment
	var aabb := _model_aabb(model)
	# empreinte re-centrée sur l'origine du bâtiment ; base du modèle -> y monde ≈ 0
	model.position = Vector3(
		-aabb.get_center().x,
		-b.position.y - aabb.position.y,
		-aabb.get_center().z)
	model.owner = root

	# masque le cube placeholder (override d'instance)
	var box := b.get_node_or_null("MeshInstance3D") as Node3D
	if box != null:
		box.visible = false

	# collision solide englobante : BoxShape3D NEUVE (pas de mutation de ressource partagée)
	var solid := b.get_node_or_null("StaticBody3D/CollisionShape3D") as CollisionShape3D
	if solid != null:
		var sh := BoxShape3D.new()
		sh.size = aabb.size
		solid.shape = sh
		solid.scale = Vector3.ONE
		solid.position = Vector3(0.0, -b.position.y + aabb.size.y * 0.5, 0.0)

	# zone d'achat Area3D élargie (sinon injoignable sur un grand bâtiment)
	var zone := b.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if zone != null:
		var zsh := BoxShape3D.new()
		zsh.size = Vector3(aabb.size.x + ZONE_MARGIN * 2.0, 6.0, aabb.size.z + ZONE_MARGIN * 2.0)
		zone.shape = zsh
		zone.scale = Vector3.ONE
		zone.position = Vector3(0.0, -b.position.y + 3.0, 0.0)
	return true

func _model_aabb(model: Node3D) -> AABB:
	var to_local := model.global_transform.affine_inverse()
	var acc := AABB()
	var has := false
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var bb := (to_local * mi.global_transform) * mi.mesh.get_aabb()
		if has:
			acc = acc.merge(bb)
		else:
			acc = bb
			has = true
	return acc if has else AABB(Vector3(-6, 0, -6), Vector3(12, 12, 12))
