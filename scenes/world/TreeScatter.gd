@tool
extends Node3D

# Disperse des arbres RÉELS (assets/nature_kit/) au hasard sur la carte en
# évitant les routes, la rivière et l'emprise des quartiers de bâtiments.
# Purement visuel (les arbres n'ont pas de collision).
#
# @tool + bake_now : outil TEMPORAIRE de génération FIGÉE. On coche "Bake Now"
# UNE FOIS dans l'éditeur -> les arbres deviennent de vrais enfants de ce node,
# sauvés dans World.tscn au Ctrl+S. Ensuite (validation joueur) on retire la
# génération runtime : plus aucune randomisation au lancement.

# Pool RESTREINT aux arbres verts. Les TwistedTree_1..5 (feuillage rouge/automne
# vérifié : Leaves_TwistedTree_C.png ≈ R167 G23 B23) sont RETIRÉS. Pas de
# DeadTree dans le kit isolé. Textures dans nature_kit/trees/ ; le reste du kit
# est .gdignore -> non importé (VRAM).
const LEAFY_TREES := [                      # grands feuillus verts (Leaves_NormalTree_C, vert)
	"res://assets/nature_kit/trees/CommonTree_1.gltf",
	"res://assets/nature_kit/trees/CommonTree_2.gltf",
	"res://assets/nature_kit/trees/CommonTree_3.gltf",
	"res://assets/nature_kit/trees/CommonTree_4.gltf",
	"res://assets/nature_kit/trees/CommonTree_5.gltf",
]
const CONIFER_TREES := [                    # pins / sapins verts (Leaf_Pine_C, vert foncé)
	"res://assets/nature_kit/trees/Pine_1.gltf",
	"res://assets/nature_kit/trees/Pine_2.gltf",
	"res://assets/nature_kit/trees/Pine_3.gltf",
	"res://assets/nature_kit/trees/Pine_4.gltf",
	"res://assets/nature_kit/trees/Pine_5.gltf",
]

@export var count: int = 60   # densité "parc" sans murer la circulation (arbres sans collision)
@export var area_half_x: float = 105.0
@export var area_half_z: float = 105.0
@export var keepout_points: Array[Vector3] = []   # ex: emplacements des immeubles
@export var keepout_radius: float = 9.0
# Les .gltf nature_kit font déjà ~7-9 m de haut en natif -> échelle de base ~1.0
# (multipliée ensuite par une variation aléatoire). À régler à l'œil.
@export var model_scale: float = 1.0
@export var model_y: float = 0.0                  # décalage vertical si l'origine du modèle n'est pas au pied
# Part de conifères (pins) dans le tirage ; le reste = grands feuillus.
# 0.35 -> ~1 pin pour 2 feuillus (feuillu dominant, comme la capture voulue).
@export_range(0.0, 1.0) var conifer_ratio: float = 0.35

# Coche cette case dans l'Inspecteur (node "Trees") pour générer les arbres UNE
# FOIS dans l'éditeur, puis Ctrl+S. Se décoche toute seule (bouton).
@export var bake_now := false:
	set(value):
		if not value:
			return
		bake_now = false
		# on DIFFÈRE : ajouter/supprimer des nodes depuis un setter d'inspecteur
		# est bloqué/repoussé par l'éditeur -> _bake() silencieusement sans effet.
		if Engine.is_editor_hint():
			call_deferred("_bake")

func _ready() -> void:
	# En éditeur : rien d'automatique, seulement via bake_now.
	if Engine.is_editor_hint():
		return
	# Déjà figé dans la scène (des arbres sauvés) -> pas de régénération runtime.
	if get_child_count() > 0:
		return
	_scatter(null)

# Génère les arbres sous ce node. `save_owner` != null -> les nodes sont
# rattachés à la scène éditée pour être sauvegardés (bake).
func _scatter(save_owner: Node) -> void:
	var leafy := _load_pool(LEAFY_TREES)
	var conifer := _load_pool(CONIFER_TREES)
	print("[TreeScatter] modèles chargés : %d feuillus + %d conifères" % [leafy.size(), conifer.size()])
	if leafy.is_empty() and conifer.is_empty():
		push_error("[TreeScatter] aucun modèle chargé -> abandon")
		return

	var placed := 0
	var blocked := 0
	var attempts := 0
	while placed < count and attempts < count * 30:
		attempts += 1
		var p := Vector3(
			randf_range(-area_half_x, area_half_x),
			0.0,
			randf_range(-area_half_z, area_half_z))
		if _blocked(p):
			blocked += 1
			continue
		# tirage pondéré feuillu / conifère
		var pool: Array = conifer if (randf() < conifer_ratio and not conifer.is_empty()) else leafy
		if pool.is_empty():
			pool = conifer if leafy.is_empty() else leafy
		var tree_scene: PackedScene = pool[randi() % pool.size()]
		if tree_scene == null:
			continue
		var t := tree_scene.instantiate() as Node3D
		add_child(t)
		t.position = p + Vector3(0.0, model_y, 0.0)
		t.rotate_y(randf() * TAU)
		t.scale *= model_scale * randf_range(0.8, 1.4)
		if save_owner != null:
			t.owner = save_owner
		placed += 1
	print("[TreeScatter] _scatter : %d posés (%d tentatives, %d bloquées)" % [placed, attempts, blocked])

func _load_pool(paths: Array) -> Array:
	var out: Array = []
	for path in paths:
		var res: Resource = load(str(path))
		if res == null:
			push_error("[TreeScatter] échec load : " + str(path))
		else:
			out.append(res)
	return out

func _bake() -> void:
	print("[TreeScatter] _bake() lancé. edited_scene_root = ", get_tree().edited_scene_root)
	for c in get_children():
		c.free()
	_scatter(get_tree().edited_scene_root)
	print("[TreeScatter] BAKE TERMINÉ : %d arbres enfants de 'Trees' — fais Ctrl+S pour sauver." % get_child_count())

func _blocked(p: Vector3) -> bool:
	# emplacements réservés (immeubles, etc.)
	for k in keepout_points:
		if Vector2(p.x - k.x, p.z - k.z).length() < keepout_radius:
			return true
	# rivière (canal z in [-18,18], marge)
	if absf(p.z) < 24.0:
		return true
	# légs verticaux du circuit (x = +-70) et horizontaux (z = +-80), + marge
	if absf(absf(p.x) - 70.0) < 10.0 and absf(p.z) < 90.0:
		return true
	if absf(absf(p.z) - 80.0) < 10.0 and absf(p.x) < 82.0:
		return true
	# emprises des deux quartiers denses (à l'intérieur de la boucle)
	if absf(p.x) < 60.0 and p.z > -76.0 and p.z < -24.0:
		return true
	if absf(p.x) < 60.0 and p.z > 24.0 and p.z < 76.0:
		return true
	return false
