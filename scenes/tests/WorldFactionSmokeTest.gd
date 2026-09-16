extends Node

# Test fumée (headless) des factions dans la vraie carte : charge World.tscn, laisse tourner les
# spawners 30 s de jeu, puis compte les PNJ par faction et vérifie leurs accessoires (police : 2,
# anti-émeute : 1, civil : 0) et qu'aucun civil ne porte le skin Swat.
#
# Lancer : Godot --headless --fixed-fps 60 --quit-after 4000 res://scenes/tests/WorldFactionSmokeTest.tscn

const WORLD := preload("res://scenes/world/World.tscn")
const GAME_SECONDS := 30.0
const EXPECTED_GEAR := {&"civil": 0, &"police": 2, &"police_riot": 1}


func _ready() -> void:
	print("WORLD_FACTION_BEGIN")
	add_child(WORLD.instantiate())
	await get_tree().create_timer(GAME_SECONDS).timeout
	var counts := {}
	var errors: Array[String] = []
	for npc in get_tree().get_nodes_in_group("npc"):
		var faction: StringName = npc.get("faction")
		counts[faction] = int(counts.get(faction, 0)) + 1
		var gear_count: int = npc.find_children("Gear_*", "BoneAttachment3D", true, false).size()
		if gear_count != int(EXPECTED_GEAR.get(faction, 0)):
			errors.append("%s avec %d accessoire(s)" % [faction, gear_count])
		if faction == &"civil" and npc.find_child("Swat_Body", true, false) != null:
			errors.append("civil en skin Swat")
	print("WORLD_FACTION_COUNTS %s" % counts)
	print("WORLD_FACTION_RESULT %s %s" % ["OK" if errors.is_empty() else "FAIL", " | ".join(errors)])
	get_tree().quit(0 if errors.is_empty() else 1)
