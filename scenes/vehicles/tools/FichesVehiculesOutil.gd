extends Node

# OUTIL DES FICHES DE VÉHICULES (2026-09-24, CLAUDE.md §14). Remplit, dans resources/vehicle_physics/fiches_vehicules.csv,
# les colonnes CALCULÉES de chaque modèle — cdg_m, raideur_av_nmm, raideur_ar_nmm, amort_av_nsm, amort_ar_nsm — à partir
# de ses autres colonnes (masse, répartition, fréquence, amortissement, adhérence) et de ses MESURES (voie, hauteur,
# roues par essieu, relevées sur le modèle chargé comme en jeu : Car._mesures_chassis). Les mêmes formules que le jeu
# (FichesVehicules.calculees) : une case remplie à la main est gardée telle quelle, une case vide est calculée. Recopie
# aussi longueur, largeur et hauteur mesurées (colonnes pour information).
# Rien d'autre du fichier ne change : commentaires, ordre des lignes et des colonnes, autres cases.
# Scène, pas script : Car a besoin des autoloads.
#   Godot --headless --path <projet> res://scenes/vehicles/tools/FichesVehiculesOutil.tscn [-- --recalculer]
# --recalculer : recalcule AUSSI les cases déjà remplies (après un changement de formule, ou de masse sur tout le parc).

const CAR := preload("res://scenes/vehicles/Car.tscn")
const CALCULEES := ["cdg_m", "raideur_av_nmm", "raideur_ar_nmm", "amort_av_nsm", "amort_ar_nsm"]
const DECIMALES := {"cdg_m": 3, "raideur_av_nmm": 1, "raideur_ar_nmm": 1, "amort_av_nsm": 0, "amort_ar_nsm": 0,
		"longueur_m": 2, "largeur_m": 2, "hauteur_m": 2}


func _ready() -> void:
	var recalculer := OS.get_cmdline_user_args().has("--recalculer")
	var texte := FileAccess.get_file_as_string(FichesVehicules.CHEMIN)
	var lignes := texte.split("\n")
	var entete := PackedStringArray()
	var changees := 0
	var absents: Array[String] = []
	for i in lignes.size():
		var ligne := lignes[i]
		if ligne.strip_edges().is_empty() or ligne.begins_with("#"):
			continue
		var cases := ligne.split(";")
		if entete.is_empty():
			entete = cases
			continue
		var id := cases[0].strip_edges()
		var mesures := _mesurer(id)
		if mesures.is_empty():
			absents.append(id)
			continue
		var f := FichesVehicules.fiche(id).duplicate()
		if recalculer:
			for cle in CALCULEES:
				f[cle] = NAN
		var calc := FichesVehicules.calculees(f, mesures["voie"], mesures["hauteur"], mesures["n_av"], mesures["n_ar"])
		for cle in CALCULEES:
			var k := entete.find(cle)
			if k >= 0 and (recalculer or cases[k].strip_edges().is_empty()):
				cases[k] = _nombre(float(calc[cle]), DECIMALES[cle])
		for cle in ["longueur_m", "largeur_m", "hauteur_m"]:
			var k := entete.find(cle)
			if k >= 0:
				cases[k] = _nombre(float(mesures[cle]), DECIMALES[cle])
		var nouvelle := ";".join(cases)
		if nouvelle != ligne:
			changees += 1
		lignes[i] = nouvelle
		print("FICHES_OUTIL %s : voie %.2f m, %d + %d roues, cdg %s m, ressorts %s / %s N/mm, amortisseurs %s / %s N.s/m" % [id,
				mesures["voie"], mesures["n_av"], mesures["n_ar"], cases[entete.find("cdg_m")],
				cases[entete.find("raideur_av_nmm")], cases[entete.find("raideur_ar_nmm")],
				cases[entete.find("amort_av_nsm")], cases[entete.find("amort_ar_nsm")]])
	var sortie := FileAccess.open(FichesVehicules.CHEMIN, FileAccess.WRITE)
	sortie.store_string("\n".join(lignes))
	sortie.close()
	FichesVehicules.recharger()
	print("FICHES_OUTIL_FIN %d ligne(s) changée(s)%s" % [changees, "" if absents.is_empty() else ", sans modèle : " + ", ".join(absents)])
	get_tree().quit()


# Mesures du modèle `id`, chargé comme en jeu : voie (roues avant), hauteur, roues physiques par essieu (Car._mesures_chassis),
# longueur et largeur de sa boîte.
func _mesurer(id: String) -> Dictionary:
	var data = load("res://resources/vehicle_models/%s.tres" % id)
	if data == null or data.model_paths.is_empty():
		return {}
	var car := CAR.instantiate()
	car.set("forced_model_path", String(data.model_paths[0]))
	add_child(car)
	var m: Dictionary = car.call("_mesures_chassis")
	var boite: AABB = car.call("boite_caisse")
	car.process_mode = Node.PROCESS_MODE_DISABLED   # gardée jusqu'à la fin : son premier passage différé l'attend dans l'arbre
	car.visible = false
	if m.is_empty():
		return {}
	var n_av := 0
	var n_ar := 0
	for r: Dictionary in m["roues"]:
		if bool(r["avant"]):
			n_av += 1
		else:
			n_ar += 1
	return {"voie": float(m["voie"]), "hauteur": float(m["hauteur"]), "n_av": n_av, "n_ar": n_ar,
			"longueur_m": boite.size.z - 0.04, "largeur_m": boite.size.x - 0.04, "hauteur_m": boite.size.y - 0.04}


static func _nombre(v: float, decimales: int) -> String:
	return ("%." + str(decimales) + "f") % v if decimales > 0 else str(roundi(v))
