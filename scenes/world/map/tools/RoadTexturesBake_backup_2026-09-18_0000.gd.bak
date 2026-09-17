extends SceneTree

# Étapes 2a, 2b et 4b (puis chantier des routes, étape 1) : textures des routes de la carte 3D, dans la palette des
# routes du centre-ville (assets/modular_roads : enrobé gris plus sombre sur les bords, lignes jaunes), plateforme
# ballastée de la voie ferrée, et colonnes de marquage des carrefours et des bretelles. Atlas roads.png
# (4096 x 512) : une colonne par type de ruban ou de marquage,
# u = travers de la chaussée (bord gauche du sens de marche -> bord droit), v = long de la route sur TEX_LENGTH m ;
# concrete.png pour les ouvrages. Réglages d'import écrits avec (compression VRAM, mipmaps) : lancer avant l'import
# puis RoadBake.
#
# Lancer : Godot --headless --path <projet> --script res://scenes/world/map/tools/RoadTexturesBake.gd

const DIR := "res://scenes/world/map/roads/textures"
const TEX_LENGTH := 12.0             # m couverts par la hauteur de texture (tiret 3 m, intervalle 9 m)
const PX_PER_M := 512.0 / 10.7
const ASPHALT_EDGE := Color8(0x72, 0x71, 0x71)
const ASPHALT_MID := Color8(0x8C, 0x8C, 0x8F)
const YELLOW := Color8(0xE3, 0xA6, 0x00)
const WHITE := Color8(0xE8, 0xE8, 0xE4)
const CONCRETE_DARK := Color8(0x93, 0x92, 0x8E)
const CONCRETE_LIGHT := Color8(0xAE, 0xAD, 0xA8)
# colonnes de l'atlas : [nom, première colonne px, largeur m, lignes [début m, fin m, couleur, tirets]]
# (RoadBake.ATLAS reprend les bornes en u)
const ATLAS_WIDTH := 4096
const COLUMNS := [
	["highway", 0, 10.7, [[0.35, 0.5, "yellow", false], [5.28, 5.43, "white", true], [10.2, 10.35, "white", false]]],
	["ramp", 512, 7.0, [[0.35, 0.5, "yellow", false], [6.5, 6.65, "white", false]]],
	["median", 848, 3.0, []],
	["urban", 1024, 10.5, [[0.55, 0.7, "yellow", false], [5.08, 5.18, "yellow", false], [5.32, 5.42, "yellow", false], [9.8, 9.95, "yellow", false]]],
	["arterial", 1536, 9.0, [[0.4, 0.55, "white", false], [4.43, 4.57, "yellow", true], [8.45, 8.6, "white", false]]],
	["access", 2000, 6.5, [[0.35, 0.48, "white", false], [6.02, 6.15, "white", false]]],
	["dirt", 2344, 5.0, []],
	["sidewalk", 2616, 3.0, []],
	["rail", 2800, 5.0, []],
	# Chantier des routes, étape 1 : colonnes de marquage posées dans les pixels libres après "rail" (qui finit à 3039).
	# Les 9 colonnes ci-dessus gardent exactement leurs bornes u : ni leur x0 ni la largeur de l'atlas ne changent, et
	# le grain est tiré sur les coordonnées absolues (x0 + x), donc leurs pixels sont identiques au texel près.
	# Motifs dessinés par _base_color ; largeurs choisies pour que le marquage se pose à l'échelle 1:1 en mètres.
	["junction", 3048, 3.5, []],     # enrobé nu des plateaux (carrefours, culs-de-sac, anneau)
	["crosswalk", 3222, 11.0, []],   # bandes piétonnes, plus large que la plus large chaussée (10,7 m)
	["stop", 3754, 1.0, []],         # ligne d'arrêt
	["yield", 3808, 2.0, []],        # cédez-le-passage : triangles puis ligne pointillée
	["chevron", 3910, 2.5, []],      # museau de divergence (colonne retournée en u de l'autre côté)
	["dashed", 4036, 1.0, []],       # ligne pointillée de séparation (3 m de trait, 9 m d'intervalle)
]
const BALLAST_DARK := Color8(0x57, 0x53, 0x4f)
const BALLAST_LIGHT := Color8(0x8b, 0x85, 0x7d)
const SLEEPER := Color8(0x4d, 0x41, 0x36)
const RAIL_SHADOW := Color8(0x33, 0x30, 0x2d)
const DIRT_DARK := Color8(0x6b, 0x55, 0x3d)
const DIRT_LIGHT := Color8(0x8f, 0x76, 0x57)
const WALK_DARK := Color8(0x9a, 0x9a, 0x9b)
const WALK_LIGHT := Color8(0xa8, 0xa8, 0xa9)
const IMPORT_TEMPLATE := """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="%s"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var grain := FastNoiseLite.new()
	grain.seed = 5
	grain.frequency = 0.08
	var atlas := Image.create(ATLAS_WIDTH, 512, false, Image.FORMAT_RGB8)
	atlas.fill(ASPHALT_EDGE)
	for column: Array in COLUMNS:
		var x0: int = column[1]
		var width: float = column[2]
		var lines: Array = column[3]
		var px := roundi(width * PX_PER_M)
		for y in 512:
			var along := (y + 0.5) / 512.0 * TEX_LENGTH
			for x in px:
				var across := (x + 0.5) / px * width
				var c := _base_color(String(column[0]), across, width, along, grain.get_noise_2d(x0 + x, y))
				for line: Array in lines:
					if across >= line[0] and across <= line[1] and (not line[3] or fposmod(along, 12.0) < 3.0):
						c = YELLOW if line[2] == "yellow" else WHITE
				atlas.set_pixel(x0 + x, y, c)
		print("ROAD_TEXTURE colonne %s : u %.6f à %.6f" % [column[0], x0 / float(ATLAS_WIDTH), (x0 + px) / float(ATLAS_WIDTH)])
	_save(atlas, "roads")
	var concrete := Image.create(256, 256, false, Image.FORMAT_RGB8)
	for y in 256:
		for x in 256:
			var v := 0.5 + grain.get_noise_2d(x * 2.0, y * 2.0) * 0.5
			var c := CONCRETE_DARK.lerp(CONCRETE_LIGHT, clampf(v, 0.0, 1.0))
			if y % 64 == 0:
				c = c.darkened(0.12)   # joints de coffrage
			concrete.set_pixel(x, y, c)
	_save(concrete, "concrete")
	quit(0)


# Fond d'une colonne : enrobé (dégradé du centre-ville), terre battue avec ornières, dalles de trottoir.
func _base_color(kind: String, across: float, width: float, along: float, noise: float) -> Color:
	match kind:
		"dirt":
			var rut := absf(absf(across - width * 0.5) - 1.0)
			var c := DIRT_LIGHT.lerp(DIRT_DARK, clampf(1.0 - rut * 2.5, 0.0, 1.0) * 0.8)
			return c.darkened(noise * 0.12)
		"sidewalk":
			var joint := fposmod(along, 3.0) < 0.04 or across < 0.08
			var c := WALK_LIGHT.lerp(WALK_DARK, 0.5 + noise * 0.5)
			return c.darkened(0.15) if joint else c
		"rail":
			# ballast moucheté, traverses de 2,6 m tous les 0,6 m (20 par longueur de texture), ombre sous les rails
			var speck := fposmod(sin(across * 917.3 + along * 571.9) * 43758.5, 1.0)
			var c := BALLAST_LIGHT.lerp(BALLAST_DARK, clampf(0.5 + noise * 0.8 + (speck - 0.5) * 0.6, 0.0, 1.0))
			if absf(across - width * 0.5) < 1.3 and fposmod(along, 0.6) < 0.24:
				c = SLEEPER.darkened(clampf(noise * 0.3 + speck * 0.1, 0.0, 0.4))
			if absf(absf(across - width * 0.5) - 0.7175) < 0.06:
				c = RAIL_SHADOW
			return c
		"junction":
			# enrobé nu, sans dégradé transversal (les plateaux se raccordent à des chaussées dans tous les sens) :
			# teinte entre le milieu et le bord d'une chaussée, pour que le plateau ne tranche pas avec elles
			return ASPHALT_EDGE.lerp(ASPHALT_MID, 0.72).darkened(noise * 0.05)
		"crosswalk":
			# bandes de 0,5 m tous les mètres en travers de la route, constantes le long de la route
			return _paint(noise) if fposmod(across, 1.0) < 0.5 else ASPHALT_MID.darkened(noise * 0.05)
		"stop":
			return _paint(noise)
		"yield":
			# triangles de 0,6 x 0,7 m tous les mètres, puis ligne pointillée : le marquage couvre 2 m de long
			if along <= 0.7 and absf(fposmod(across, 1.0) - 0.5) < 0.3 * (1.0 - along / 0.7):
				return _paint(noise)
			if along >= 0.9 and along <= 1.4 and fposmod(across, 1.0) < 0.5:
				return _paint(noise)
			return ASPHALT_MID.darkened(noise * 0.05)
		"chevron":
			# chevrons à 45°, un tous les 2,4 m le long de la route
			return _paint(noise) if fposmod(along - across, 2.4) < 0.5 else ASPHALT_MID.darkened(noise * 0.05)
		"dashed":
			if absf(across - width * 0.5) < 0.075 and fposmod(along, 12.0) < 3.0:
				return _paint(noise)
			return ASPHALT_MID.darkened(noise * 0.05)
		_:
			var shade := 1.0 - absf(across / width - 0.5) * 2.0
			return ASPHALT_EDGE.lerp(ASPHALT_MID, smoothstep(0.0, 0.8, shade)).darkened(noise * 0.04)


# Peinture blanche des colonnes de marquage, à peine grenue comme les lignes des colonnes de chaussée.
func _paint(noise: float) -> Color:
	return WHITE.darkened(maxf(0.0, noise) * 0.08)


func _save(img: Image, tex_name: String) -> void:
	var path := DIR.path_join(tex_name + ".png")
	img.save_png(path)
	var f := FileAccess.open(path + ".import", FileAccess.WRITE)
	f.store_string(IMPORT_TEMPLATE % path)
	f.close()
	print("ROAD_TEXTURE %s" % path)
