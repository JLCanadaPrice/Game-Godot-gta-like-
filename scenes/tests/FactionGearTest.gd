extends Node3D

# Harnais de test automatisé (headless) des tenues de faction des PNJ : modèle par faction, Swat
# retiré des civils, recoloration bleu marine, accessoires présents et calés au repos (écart à
# l'ancrage mesuré), puis orientation du bouclier pendant la marche selon l'os porteur.
#
# Lancer : Godot --headless --fixed-fps 60 res://scenes/tests/FactionGearTest.tscn

const NPC_SCENE := preload("res://scenes/npc/NPC.tscn")
const FactionOutfit := preload("res://scripts/npc/FactionOutfit.gd")
const CHEST_SHIELD_ANCHOR := Vector3(0.22, 1.02, 0.32)  # bouclier « tenu » devant le corps, repère modèle
const WALK_FRAMES := 90

var _errors: Array[String] = []


func _ready() -> void:
	print("FACTION_TEST_BEGIN")
	await _run()
	print("FACTION_TEST_RESULT %s %s" % ["OK" if _errors.is_empty() else "FAIL", " | ".join(_errors)])
	get_tree().quit(0 if _errors.is_empty() else 1)


func _run() -> void:
	var civil := _spawn(&"civil", Vector3(0, 0, 0))
	var police := _spawn(&"police", Vector3(2, 0, 0))
	var riot := _spawn(&"police_riot", Vector3(4, 0, 0))
	var civils: Array[Node3D] = []
	for i in 20:
		civils.append(_spawn(&"civil", Vector3(i * 1.5, 0, 6)))
	for i in 3:
		await get_tree().process_frame

	_check_outfit(civil, 0, "")
	_check_outfit(police, 2, "Casual2_Body")
	_check_outfit(riot, 1, "Swat_Body")
	for c in civils:
		if _model(c).find_child("Swat_Body", true, false) != null:
			_errors.append("un civil utilise encore le skin Swat")
			break
	_check_tint(police, "Casual2_Body", FactionOutfit.NAVY)
	_check_tint(riot, "Swat_Body", FactionOutfit.NAVY)

	await _check_rest_alignment(police)
	await _check_rest_alignment(riot)

	var forearm := await _shield_walk_deviation(_spawn(&"police_riot", Vector3(6, 0, 0)), "LowerArm.L", ["LowerArm.L", "Wrist.L"])
	var chest := await _shield_walk_deviation(_spawn(&"police_riot", Vector3(8, 0, 0)), "Chest", CHEST_SHIELD_ANCHOR)
	print("SHIELD_WALK_MAX_TILT avant_bras=%.1f deg torse=%.1f deg" % [forearm, chest])


func _spawn(faction: StringName, pos: Vector3) -> Node3D:
	var npc := NPC_SCENE.instantiate() as Node3D
	npc.faction = faction
	add_child(npc)
	npc.global_position = pos
	return npc


func _model(npc: Node3D) -> Node3D:
	for c in npc.get_children():
		if c is Node3D and not c is MeshInstance3D and not c is CollisionShape3D \
				and not c.find_children("*", "Skeleton3D", true, false).is_empty():
			return c
	return null


func _check_outfit(npc: Node3D, gear_count: int, body_mesh: String) -> void:
	var model := _model(npc)
	if model == null:
		_errors.append("%s : modèle absent" % npc.faction)
		return
	var gears := model.find_children("Gear_*", "BoneAttachment3D", true, false)
	print("  %-12s accessoires=%d %s" % [npc.faction, gears.size(), body_mesh])
	if gears.size() != gear_count:
		_errors.append("%s : %d accessoire(s) au lieu de %d" % [npc.faction, gears.size(), gear_count])
	if body_mesh != "" and model.find_child(body_mesh, true, false) == null:
		_errors.append("%s : skin attendu %s absent" % [npc.faction, body_mesh])


func _check_tint(npc: Node3D, mesh_name: String, linear_color: Color) -> void:
	var mi := _model(npc).find_child(mesh_name, true, false) as MeshInstance3D
	var expected := linear_color.linear_to_srgb()
	for i in mi.mesh.get_surface_count():
		var mat := mi.get_surface_override_material(i) as BaseMaterial3D
		if mat != null and mat.albedo_color.is_equal_approx(expected):
			return
	_errors.append("%s : aucune surface recolorée en bleu marine sur %s" % [npc.faction, mesh_name])


func _check_rest_alignment(npc: Node3D) -> void:
	var model := _model(npc)
	(model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer).stop()
	(model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D).reset_bone_poses()
	await get_tree().process_frame
	await get_tree().process_frame
	for entry in FactionOutfit.GEAR[npc.faction]:
		var att := model.find_child("Gear_" + String(entry[0]).get_basename(), true, false) as BoneAttachment3D
		var gear := att.get_child(0) as Node3D
		var expected := model.global_transform * FactionOutfit.anchor_in_model(model, entry[2])
		var dist := gear.global_position.distance_to(expected)
		var tilt := rad_to_deg(gear.global_basis.y.normalized().angle_to(model.global_basis.y.normalized()))
		print("  repos %-22s écart=%.4f m inclinaison=%.2f deg" % [entry[0], dist, tilt])
		if dist > 0.01 or tilt > 1.0:
			_errors.append("%s mal calé au repos (%.3f m, %.1f deg)" % [entry[0], dist, tilt])


func _shield_walk_deviation(npc: Node3D, bone: String, anchor: Variant) -> float:
	await get_tree().process_frame
	var model := _model(npc)
	for g in model.find_children("Gear_*", "BoneAttachment3D", true, false):
		g.free()
	var gear := FactionOutfit.attach(model, FactionOutfit.GEAR_DIR + "Police_RiotShield.glb", bone, anchor, 4)
	(model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer).play("Walk")
	var worst := 0.0
	for i in WALK_FRAMES:
		await get_tree().process_frame
		worst = maxf(worst, rad_to_deg(gear.global_basis.y.normalized().angle_to(model.global_basis.y.normalized())))
	return worst
