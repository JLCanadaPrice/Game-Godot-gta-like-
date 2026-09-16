extends SceneTree

# Garde-fou de chargement : charge sans les instancier tous les scripts, shaders, ressources et scènes du jeu. Une
# erreur de syntaxe, un script invalide ou une dépendance cassée fait échouer l'étape en cours.
#
# Lancer : Godot --headless --path <projet> --script res://scenes/world/map/tools/ProjectLoadCheck.gd

const ROOTS := ["res://scenes", "res://scripts", "res://resources", "res://shaders"]
const EXTENSIONS := ["gd", "gdshader", "tres", "tscn"]


func _initialize() -> void:
	var files: PackedStringArray = []
	for root in ROOTS:
		if DirAccess.dir_exists_absolute(root):
			_collect(root, files)
	var failed: PackedStringArray = []
	for path in files:
		var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
		if res == null:
			failed.append(path)
		elif res is GDScript and not (res as GDScript).can_instantiate():
			failed.append(path + " (script invalide)")
	print("LOADCHECK %d fichiers chargés, %d échec(s) %s" % [files.size(), failed.size(), ", ".join(failed)])
	quit(0 if failed.is_empty() else 1)


func _collect(dir_path: String, out: PackedStringArray) -> void:
	for sub in DirAccess.get_directories_at(dir_path):
		if not sub.begins_with("."):
			_collect(dir_path.path_join(sub), out)
	for file in DirAccess.get_files_at(dir_path):
		if file.get_extension() in EXTENSIONS and not file.contains("_backup"):   # anciennes copies de sauvegarde, hors jeu
			out.append(dir_path.path_join(file))
