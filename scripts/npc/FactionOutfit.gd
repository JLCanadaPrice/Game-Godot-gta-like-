extends RefCounted

# Tenue et équipement visuel des factions de PNJ (aucun comportement de combat ici).
#   civil       : skins civils de NPC.gd, inchangés
#   police      : Casual_2 bleu marine + casquette (os Head) + insigne (os Chest)
#   police_riot : Swat bleu marine + bouclier anti-émeute
# Les accessoires (assets/faction_gear/police/*.glb) ont leur origine au point d'ancrage mesuré dans
# le repère du modèle Quaternius, en pose de repos. On les pose sur un BoneAttachment3D en
# compensant la pose de repos de l'os : au repos ils tombent pile sur l'ancrage, puis ils suivent
# l'animation.

const CIVIL := &"civil"
const POLICE := &"police"
const POLICE_RIOT := &"police_riot"

const GEAR_DIR := "res://assets/faction_gear/police/"

const MODELS := {
	&"police": "res://assets/npc_models/Casual_2.gltf",
	&"police_riot": "res://assets/npc_models/Swat.gltf",
}

# [accessoire, os porteur, ancrage] ; ancrage = noms d'os (tête de l'os au repos, ou milieu de
# plusieurs têtes) ou point fixe Vector3 dans le repère du modèle.
const GEAR := {
	&"police": [
		["Police_Cap.glb", "Head", ["Head"]],
		["Police_Badge.glb", "Chest", ["Chest"]],
	],
	# Bouclier porté au torse, droit devant le corps. Accroché à l'avant-bras (ancrage mesuré
	# LowerArm.L / Wrist.L), il basculait jusqu'à 54,5° pendant l'anim Walk (bras ballants), contre
	# 8,9° au torse (FactionGearTest). À repasser sur l'avant-bras avec une future anim de garde.
	&"police_riot": [
		["Police_RiotShield.glb", "Chest", Vector3(0.22, 1.02, 0.32)],
	],
}

# Couleurs linéaires (comme les baseColorFactor glTF), converties en sRGB pour albedo_color.
const NAVY := Color(0.015, 0.02, 0.06)
const NAVY_DARK := Color(0.008, 0.01, 0.03)
const NAVY_GREY := Color(0.05, 0.06, 0.09)
const BLACK := Color(0.01, 0.01, 0.012)
const PART_COLORS := {&"police": {"body": NAVY, "legs": NAVY_DARK, "feet": BLACK}}  # mot-clé du mesh
const MATERIAL_COLORS := {&"police_riot": {"swat": NAVY, "swat_black": NAVY_DARK, "grey": NAVY_GREY, "black": BLACK}}
const KEPT_MATERIALS := ["skin", "eye", "hair", "moustache", "earring", "visor"]

static var _tinted_cache := {}  # un seul matériau teinté par (matériau source, couleur), partagé entre PNJ


static func model_path(faction: StringName, civil_paths: Array) -> String:
	if MODELS.has(faction):
		return MODELS[faction]
	return civil_paths[randi() % civil_paths.size()]


static func apply(model: Node3D, faction: StringName, layers: int) -> void:
	_recolor(model, PART_COLORS.get(faction, {}), MATERIAL_COLORS.get(faction, {}))
	for g in GEAR.get(faction, []):
		attach(model, GEAR_DIR + g[0], g[1], g[2], layers)


static func attach(model: Node3D, gear_path: String, bone_name: String, anchor: Variant, layers: int) -> Node3D:
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return null
	var skel := skels[0] as Skeleton3D
	var bone := skel.find_bone(bone_name)
	var scene := load(gear_path) as PackedScene
	if bone == -1 or scene == null:
		push_warning("FactionOutfit : os '%s' ou accessoire '%s' introuvable" % [bone_name, gear_path])
		return null

	var skel_in_model := _relative_transform(skel, model)
	var anchor_model := _anchor_point(skel, skel_in_model, anchor)

	var att := BoneAttachment3D.new()
	att.name = "Gear_" + gear_path.get_file().get_basename()
	skel.add_child(att)
	att.bone_name = bone_name
	var gear := scene.instantiate() as Node3D
	att.add_child(gear)
	# au repos : attachement = skel_in_model * rest ; l'accessoire doit valoir (axes du modèle, ancrage)
	gear.transform = skel.get_bone_global_rest(bone).affine_inverse() * skel_in_model.affine_inverse() \
		* Transform3D(Basis.IDENTITY, anchor_model)
	for mi in gear.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = layers
	return gear


# Point d'ancrage dans le repère du modèle (pose de repos).
static func anchor_in_model(model: Node3D, anchor: Variant) -> Vector3:
	var skel := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	return _anchor_point(skel, _relative_transform(skel, model), anchor)


static func _anchor_point(skel: Skeleton3D, skel_in_model: Transform3D, anchor: Variant) -> Vector3:
	if anchor is Vector3:
		return anchor
	var sum := Vector3.ZERO
	for bone_name in anchor:
		sum += skel_in_model * skel.get_bone_global_rest(skel.find_bone(bone_name)).origin
	return sum / float(anchor.size())


static func _relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != ancestor:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


static func _recolor(model: Node3D, by_part: Dictionary, by_mat: Dictionary) -> void:
	if by_part.is_empty() and by_mat.is_empty():
		return
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var part_color := Color(0, 0, 0, 0)  # alpha 0 = aucune couleur de partie
		for key in by_part:
			if String(mi.name).to_lower().contains(key):
				part_color = by_part[key]
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i)
			if src == null:
				continue
			var mat_name := src.resource_name.to_lower()
			var color: Color = by_mat.get(mat_name, Color(0, 0, 0, 0))
			if color.a == 0.0 and part_color.a > 0.0 and not KEPT_MATERIALS.any(func(k): return mat_name.contains(k)):
				color = part_color
			if color.a > 0.0:
				mi.set_surface_override_material(i, _tinted(src, color))


static func _tinted(src: Material, color: Color) -> Material:
	var key := "%d|%s" % [src.get_instance_id(), color.to_html()]
	if not _tinted_cache.has(key):
		var dup := src.duplicate() as Material
		if dup is BaseMaterial3D:
			(dup as BaseMaterial3D).albedo_color = color.linear_to_srgb()
		_tinted_cache[key] = dup
	return _tinted_cache[key]
