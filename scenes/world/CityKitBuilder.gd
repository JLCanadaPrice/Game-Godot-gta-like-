@tool
extends Node3D

## Génère le réseau routier à partir des modules city_kit et neutralise les
## routes-placeholder (boîtes) de World.tscn.
##
## @tool + bake_now : outil TEMPORAIRE. On coche "Bake Now" UNE FOIS dans
## l'éditeur -> les tuiles route/trottoir deviennent de vrais enfants de ce
## node (sauvés dans World.tscn au Ctrl+S) et les routes placeholder sont
## désactivées en dur. Ensuite (validation joueur) la génération runtime est
## retirée : plus aucune (re)génération au lancement.
##
## Paramétrique : tout est piloté par les constantes ci-dessous. Un module mal
## calé = UNE constante à corriger, pas 200 lignes de .tscn.
##
## 1re PASSE : routes + trottoirs uniquement. Les bâtiments (modèles city_kit +
## re-disposition en blocs 2x2) sont volontairement laissés pour la passe
## suivante, une fois le calage des routes validé.
##
## Réversible : retirer le node "CityKit" de World.tscn restaure le monde
## placeholder (les anciennes routes ne sont que désactivées, pas supprimées).

# Seuls 3 modules du kit sont réellement utilisés (routes + trottoir). Ils ont
# été isolés dans models_active/ avec leurs 7 textures ; le reste du kit
# (~150 .gltf + 22 textures 2K jamais instanciés, la « passe bâtiments » n'a
# jamais été faite) reste dans models/ marqué .gdignore -> non importé.
const M := "res://assets/city_kit/models_active/"
# Street_4Lane (relevé mesh) : asphalte X[-3,3] Z[-6,6] -> route de 12 m de
# LARGE (4 voies, sur Z local) et 6 m de LONG par tuile (sur X local). Le
# MI_Trim (trottoirs) étend la largeur à Z[-9,9] = 18. Origine centrée,
# asphalte à y = -0.15 (cf. MESH_SLAB).
const STREET_STRAIGHT := M + "Street_4Lane.gltf"
# Street_Curve_4LaneShort : virage à 90°. Emprise locale [0,18]² (jusqu'à la
# bordure), ORIGINE = CENTRE de l'arc (coin intérieur du virage). Asphalte en
# quart d'anneau, axe médian à rayon CURVE_RADIUS (13). Le modèle inclut DÉJÀ
# son trottoir/bordure -> on ne pose PAS de trottoir en plus.
const STREET_CURVE := M + "Street_Curve_4LaneShort.gltf"

const RING_X := 70.0          # |x| des bords Est/Ouest (ligne médiane de la route) = corners du CircuitPath
const RING_Z := 80.0          # |z| des bords Nord/Sud
const STRAIGHT_LEN := 6.0     # LONGUEUR native d'une tuile Street_4Lane (sur son X local) -> pas de trou entre tuiles
const ROAD_W := 12.0          # LARGEUR de l'asphalte 4 voies (sur son Z local) = largeur de la boîte de collision
# Rayon de l'axe médian de la route dans le virage Street_Curve_4LaneShort.
# Relevé sur le mesh : asphalte en quart d'anneau, rayon extérieur 16, largeur
# de voie 6 -> rayon intérieur 10 -> AXE MÉDIAN à (10+16)/2 = 13. Les droites
# doivent finir à ±(RING - 13) pour tomber pile sur l'ouverture du virage.
const CURVE_RADIUS := 13.0
const CURVE_TILE := 18.0      # emprise locale du virage (carré, jusqu'à la bordure)
const RIVER_HALF_Z := 24.0    # bande de rivière sur les bords E/O : les ponts EXISTANTS portent la route
const COLL_H := 0.6           # épaisseur des boîtes de collision
# Le sol/herbe a son DESSUS à y = 0.0. Les petits nudges précédents (0.02, 0.04)
# n'ont pas suffi -> la vraie surface roulable des tuiles city_kit est ~0.15
# SOUS l'origine de la tuile (le slab de 15 cm est modélisé sous le point
# d'origine). MESH_SLAB compense ça ; SURFACE_Y est la hauteur voulue de la
# surface roulable AU-DESSUS de l'herbe.
#   - Si les routes flottent après ça -> mets MESH_SLAB à 0.0.
#   - Si elles ont encore l'air enterrées -> monte SURFACE_Y (0.10, 0.15...).
const MESH_SLAB := 0.15
# Avec MESH_SLAB qui compense correctement le slab, l'asphalte se retrouve
# exactement à SURFACE_Y au-dessus de l'herbe. 0.18 -> route visiblement en
# l'air (on voyait la tranche). 0.05 = juste au-dessus du sol, assez de marge
# pour éviter le z-fighting (qui n'apparaît que sous ~1 cm). Garder
# Car.ROAD_TOP_Y égal.
const SURFACE_Y := 0.05
const COLL_LAYER := 1         # calque du décor statique (voitures mask=5, joueur mask=7)

# TEST FREEZE : passe à true pour générer la ville normalement, false pour tout
# sauter (aucune tuile route/trottoir instanciée). Le log dit clairement lequel
# des deux a tourné -> plus d'ambiguïté sur l'état actif.
const CITYKIT_ENABLED := true

# Coche cette case dans l'Inspecteur (node "CityKit") pour générer les tuiles
# route/trottoir UNE FOIS dans l'éditeur + désactiver les routes placeholder,
# puis Ctrl+S. Se décoche toute seule (bouton).
@export var bake_now := false:
	set(value):
		if not value:
			return
		bake_now = false
		# différé : manipuler l'arbre de nodes depuis un setter d'inspecteur
		# peut être bloqué/repoussé par l'éditeur.
		if Engine.is_editor_hint():
			call_deferred("_bake")

# != null pendant un bake -> chaque node généré est rattaché à la scène éditée
# pour être sauvegardé.
var _bake_owner: Node = null

func _ready() -> void:
	if Engine.is_editor_hint():
		return   # en éditeur : rien d'automatique, seulement via bake_now
	if not CITYKIT_ENABLED:
		print("[CityKitBuilder] *** DÉSACTIVÉ (test freeze) *** — aucune tuile générée")
		return
	if get_child_count() > 0:
		print("[CityKitBuilder] déjà figé dans la scène — pas de régénération runtime")
		return
	print("[CityKitBuilder] ACTIF — génération routes (trottoirs inclus dans les modèles)")
	_disable_placeholder_roads()
	_build_ring_roads()

func _bake() -> void:
	# racine de scène FIABLE : owner du node CityKit lui-même (garanti = racine
	# du .tscn), sinon edited_scene_root. Un node sans owner correct n'est PAS
	# écrit dans le .tscn (existe en mémoire, disparaît au rechargement).
	var root: Node = owner
	if root == null:
		root = get_tree().edited_scene_root
	if root == null:
		push_error("[CityKitBuilder] BAKE ANNULÉ : impossible de trouver la racine de scène")
		return

	# EFFACE l'ancien résultat avant de régénérer -> aucun doublon même si on
	# bake plusieurs fois de suite. get_children() est un snapshot, free() est
	# immédiat.
	var cleared := 0
	for c in get_children():
		c.free()
		cleared += 1
	print("[CityKitBuilder] BAKE : %d anciens nodes effacés." % cleared)
	_bake_owner = root
	_disable_placeholder_roads()          # modifie les nodes Roads/* existants (sauvés au Ctrl+S)
	_build_ring_roads()                   # trottoirs INCLUS dans les modèles Street_* -> pas de _build_inner_sidewalks
	_bake_owner = null

	# passe d'ownership RÉCURSIVE : chaque node généré doit être owned par `root`.
	# On NE descend PAS dans les sous-scènes instanciées (scene_file_path
	# renseigné -> elles se sauvent comme instance, enfants internes non re-ownés).
	var res := _own_recursive(self, root)
	print("[CityKitBuilder] BAKE : %d nodes à sauver, %d ownés par la racine (doivent être égaux). " % [res[1], res[0]]
		+ "Ctrl+S PUIS Scène > Recharger la scène pour vérifier la persistance.")

# renvoie [nb_ownés, nb_total] pour les nodes qui DOIVENT être sauvés
func _own_recursive(n: Node, root: Node) -> Array:
	var owned := 0
	var total := 0
	for c in n.get_children():
		total += 1
		c.owner = root
		if c.owner == root:
			owned += 1
		if c.scene_file_path == "":     # pas une instance -> on descend
			var sub := _own_recursive(c, root)
			owned += sub[0]
			total += sub[1]
	return [owned, total]

# rattache un node généré à la scène éditée (redondant avec _own_recursive,
# gardé pour que l'ownership soit posé au plus tôt).
func _own(n: Node) -> void:
	if _bake_owner != null:
		n.owner = _bake_owner

# --- neutralise les routes-boîtes de World.tscn (Roads/*), réversible ---
func _disable_placeholder_roads() -> void:
	var roads := get_node_or_null("../Roads")
	if roads == null:
		return
	for c in roads.get_children():
		var n3 := c as Node3D
		if n3 != null:
			n3.visible = false          # cache le mesh placeholder (l'ancien sol gris)
		if c is StaticBody3D:
			(c as StaticBody3D).collision_layer = 0
			(c as StaticBody3D).collision_mask = 0

# --- routes ---------------------------------------------------------
func _build_ring_roads() -> void:
	var straight := load(STREET_STRAIGHT) as PackedScene
	var curve := load(STREET_CURVE) as PackedScene
	if straight == null or curve == null:
		push_error("CityKitBuilder : modules de route introuvables")
		return

	# 4 virages d'angle (un yaw différent par coin pour raccorder les 2 droites)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_place_corner_curve(curve, sx, sz)

	# bords Nord/Sud : route le long de X, jusqu'au point où le virage prend le relais
	for sz: float in [-1.0, 1.0]:
		_run_road(straight, true, sz * RING_Z, -(RING_X - CURVE_RADIUS), RING_X - CURVE_RADIUS, [])
	# bords Ouest/Est : route le long de Z, on saute la bande de rivière (ponts existants)
	for sx: float in [-1.0, 1.0]:
		_run_road(straight, false, sx * RING_X, -(RING_Z - CURVE_RADIUS), RING_Z - CURVE_RADIUS,
			[-RIVER_HALF_Z, RIVER_HALF_Z])

# Centre de l'arc du virage au coin (sx, sz) : intersection des deux médianes de
# route, décalée de CURVE_RADIUS vers l'intérieur de l'anneau.
func _corner_arc_center(sx: float, sz: float) -> Vector3:
	return Vector3(sx * (RING_X - CURVE_RADIUS), 0.0, sz * (RING_Z - CURVE_RADIUS))

# Yaw du virage par coin. Le module relie son ouverture "z=0 local" (flux Z) à
# son ouverture "x=0 local" (flux X) ; il faut donc l'orienter pour que ces deux
# ouvertures tombent sur les deux droites perpendiculaires du coin.
#   (sx,sz) = (+,+) -> 0°   (+,-) -> 90°   (-,-) -> 180°   (-,+) -> 270°
func _corner_yaw(sx: float, sz: float) -> float:
	if sx > 0.0:
		return 0.0 if sz > 0.0 else 90.0
	return 270.0 if sz > 0.0 else 180.0

func _place_corner_curve(scene: PackedScene, sx: float, sz: float) -> void:
	var c := _corner_arc_center(sx, sz)
	var yaw := _corner_yaw(sx, sz)
	# empreinte : la tuile locale [0,18]² pivote autour de son origine (le centre
	# d'arc) -> le centre de l'empreinte est à Ry(yaw) * (9,0,9) depuis c.
	var half := CURVE_TILE * 0.5
	var footprint_off := Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(half, 0.0, half)
	_place(scene, c, yaw, 1.0,
		Vector3(CURVE_TILE + 1.0, COLL_H, CURVE_TILE + 1.0), footprint_off)

func _run_road(scene: PackedScene, along_x: bool, fixed: float, a: float, b: float, skip: Array) -> void:
	for seg in _segments(a, b, skip):
		var span: float = seg[1] - seg[0]
		var n := maxi(1, int(round(span / STRAIGHT_LEN)))
		var tl := span / float(n)
		for i in n:
			# c avance de tl à CHAQUE itération, tuile centrée dessus -> bout à
			# bout, aucune marge ajoutée.
			var c: float = seg[0] + tl * (float(i) + 0.5)
			var pos := Vector3(c, 0.0, fixed) if along_x else Vector3(fixed, 0.0, c)
			# La LONGUEUR de tuile de Street_4Lane est sur son X local (6 m natif,
			# étiré à tl par len_scale). yaw : 0° bords N/S (X local -> X monde),
			# 90° bords E/O (X local -> Z monde). La boîte suit :
			#   yaw 0  -> longue (tl) sur X monde, large (ROAD_W) sur Z
			#   yaw 90 -> longue (tl) sur Z monde, large (ROAD_W) sur X
			var yaw := 0.0 if along_x else 90.0
			var box := Vector3(tl, COLL_H, ROAD_W) if along_x else Vector3(ROAD_W, COLL_H, tl)
			_place(scene, pos, yaw, tl / STRAIGHT_LEN, box)

# NB : plus de _build_inner_sidewalks() — les modèles Street_4Lane et
# Street_Curve_4LaneShort embarquent DÉJÀ leur trottoir/bordure (mesh
# MI_Trim_MetalConcrete). En poser en plus faisait double.

# --- utilitaires ---------------------------------------------------

# découpe [a,b] en retirant la bande centrale skip=[lo,hi] si fournie
func _segments(a: float, b: float, skip: Array) -> Array:
	var out := []
	if skip.is_empty():
		if b - a > 0.5:
			out.append([a, b])
		return out
	if skip[0] - a > 0.5:
		out.append([a, skip[0]])
	if b - skip[1] > 0.5:
		out.append([skip[1], b])
	return out

# instancie `scene` sous un StaticBody3D à `pos` (remonté de SURFACE_Y au-dessus
# de l'herbe), visuel tourné de `yaw_deg` et étiré de `len_scale` sur son X
# local (= sens de la longueur des tuiles Street_4Lane), + une BoxShape3D
# `box_world` (repère MONDE, AXIS-ALIGNED, appliquée APRÈS le yaw) dont le
# dessus est calé sur la surface. `box_off_xz` décale la boîte en XZ quand
# l'origine de la tuile n'est pas au centre de son empreinte (cas du virage).
func _place(scene: PackedScene, pos: Vector3, yaw_deg: float, len_scale: float,
		box_world: Vector3, box_off_xz := Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = COLL_LAYER
	body.collision_mask = 0
	# origine de la tuile relevée pour que sa surface roulable (≈ MESH_SLAB sous
	# l'origine) se retrouve à SURFACE_Y au-dessus de l'herbe
	body.position = Vector3(pos.x, SURFACE_Y + MESH_SLAB, pos.z)
	add_child(body)
	_own(body)

	var vis := scene.instantiate() as Node3D
	vis.rotation_degrees.y = yaw_deg
	if not is_equal_approx(len_scale, 1.0):
		vis.scale = Vector3(vis.scale.x * len_scale, vis.scale.y, vis.scale.z)
	body.add_child(vis)
	_own(vis)

	var cs := CollisionShape3D.new()
	var shp := BoxShape3D.new()
	shp.size = box_world
	cs.shape = shp
	# dessus de la boîte calé sur la surface roulable (MESH_SLAB sous l'origine du body)
	cs.position = Vector3(box_off_xz.x, -MESH_SLAB - box_world.y * 0.5, box_off_xz.z)
	body.add_child(cs)
	_own(cs)
