extends SceneTree

# Chantier centre-ville, étape D2 : installe le centre-ville reconstruit dans World.tscn.
#  - première installation (World a encore ses 4 districts) : nœud Downtown ; quais (District/Quay, Quay2) déplacés
#    dessous à l'identique ; boutiques visitables (Liberty Motors, City Realty) déplacées dans Downtown/Shops avec tout
#    leur contenu (intérieur, comptoir, repères, place de livraison) et abaissées de SHOP_DROP m : leur sol (0,41 m,
#    calé sur les anciens trottoirs) arrive au niveau des nouveaux trottoirs (0,20 m) ; puis les 4 districts et leurs
#    carrefours de couture (tuiles de route, trottoirs, 1049 bâtiments du kit, sols) sont retirés ;
#  - à chaque passage : scène des rues (generated/Streets.tscn) instanciée dans Downtown si absente, données du Circuit
#    (nœuds, arêtes et voies, distances d'arrêt aux passages piétons) et du PedGraph remplacées par celles du plan
#    (DowntownTraffic : mêmes indices que les feux de Streets.tscn), points d'apparition des spawners.
# Sauvegarde, puis renumérotation des unique_id en double éventuels.
#
# Lancer : Godot --headless --path <projet> --script res://scenes/world/downtown/tools/DowntownInstall.gd

const Traffic := preload("res://scenes/world/downtown/DowntownTraffic.gd")
const WORLD_PATH := "res://scenes/world/World.tscn"
const STREETS := "res://scenes/world/downtown/generated/Streets.tscn"
const OLD := ["District", "District_W", "District_N", "District_NW", "DistrictSeams"]
const SHOPS := ["Dealership_Building", "Agency_Building"]
const SHOP_DROP := 0.21

var _report := {}


func _initialize() -> void:
	var root := (load(WORLD_PATH) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
	var problems: Array[String] = []
	var downtown := root.get_node_or_null("Downtown") as Node3D
	if downtown == null:
		downtown = Node3D.new()
		downtown.name = "Downtown"
		root.add_child(downtown)
		downtown.owner = root
		var old := root.get_node_or_null("District")
		if old != null:
			root.move_child(downtown, old.get_index())
	var main := root.get_node_or_null("District")
	if main != null:
		for quay_name in ["Quay", "Quay2"]:
			var quay := main.get_node_or_null(quay_name) as Node3D
			if quay != null:
				quay.reparent(downtown, false)   # District, Buildings, Downtown et Shops sans transformation : pose identique
		var shops := downtown.get_node_or_null("Shops") as Node3D
		if shops == null:
			shops = Node3D.new()
			shops.name = "Shops"
			downtown.add_child(shops)
			shops.owner = root
		for shop_name in SHOPS:
			var shop := main.get_node_or_null("Buildings/" + shop_name) as Node3D
			if shop == null:
				problems.append("%s introuvable" % shop_name)
				continue
			var before := shop.position
			shop.reparent(shops, false)
			shop.position.y -= SHOP_DROP
			_report[shop_name] = {"avant": str(before), "après": str(shop.position), "propriétaire": shop.owner == root}
		if problems.is_empty():
			var removed := 0
			for old_name in OLD:
				var node := root.get_node_or_null(old_name)
				if node != null:
					removed += node.find_children("*", "", true, false).size() + 1
					root.remove_child(node)
					node.free()
			_report["noeuds_retires"] = removed
	if not downtown.has_node("Streets"):
		var streets := (load(STREETS) as PackedScene).instantiate()
		streets.name = "Streets"
		downtown.add_child(streets)
		streets.owner = root
		downtown.move_child(streets, 0)
	var traffic := Traffic.new()
	var circuit := root.get_node("Circuit") as CircuitPath
	circuit.nodes = traffic.nodes
	circuit.edges = traffic.edges
	circuit.roundabout_nodes = []
	circuit.unlit_nodes = []
	circuit.yield_approaches = {}
	circuit.crosswalk_stop_dist = traffic.crosswalk_stop_dist
	var ped := root.get_node("PedGraph") as PathGraph
	ped.nodes = traffic.ped_nodes
	ped.edges = traffic.ped_edges
	for pair: Array in [["CarSpawner", traffic.nodes.size()], ["NpcSpawner", traffic.ped_nodes.size()]]:
		var spawner := root.get_node(pair[0])
		var points: Array[int] = []
		for i in int(pair[1]):
			points.append(i)
		spawner.set("spawn_nodes", points)
	_report["circulation"] = traffic.stats()
	var err := FAILED
	if problems.is_empty():
		var packed := PackedScene.new()
		err = packed.pack(root)
		if err == OK:
			err = ResourceSaver.save(packed, WORLD_PATH)
		if err == OK:
			_report["unique_id_renumerotes"] = _renumber_duplicate_ids(WORLD_PATH)
		_report["sauvegarde"] = error_string(err)
	else:
		_report["sauvegarde"] = "ANNULEE : " + " | ".join(problems)
	print("DOWNTOWN_INSTALL " + JSON.stringify(_report))
	root.free()
	quit(0 if err == OK else 1)


# Identifiants de nœuds propres (hors enfants d'instance éditable, en-tête avec index="…") en double : chaque doublon
# reçoit un identifiant libre dans le fichier enregistré (cf. CityExpansionBake).
func _renumber_duplicate_ids(path: String) -> int:
	var text := FileAccess.get_file_as_string(path)
	var re := RegEx.create_from_string("\\[node [^\\]]*unique_id=(\\d+)[^\\]]*\\]")
	var used := {}
	for m in re.search_all(text):
		used[m.get_string(1)] = true
	var seen := {}
	var parts := PackedStringArray()
	var last := 0
	for m in re.search_all(text):
		if m.get_string(0).contains(" index=\""):
			continue
		var id := m.get_string(1)
		if seen.has(id):
			var fresh := str(randi_range(1, 2147483646))
			while used.has(fresh):
				fresh = str(randi_range(1, 2147483646))
			used[fresh] = true
			parts.append(text.substr(last, m.get_start(1) - last))
			parts.append(fresh)
			last = m.get_end(1)
		seen[id] = true
	if parts.is_empty():
		return 0
	parts.append(text.substr(last))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("".join(parts))
	f.close()
	return parts.size() / 2
