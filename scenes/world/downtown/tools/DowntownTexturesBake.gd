extends SceneTree

# Chantier centre-ville, étape D2 : textures des rues, dans la palette des routes de la carte (RoadTexturesBake :
# enrobé plus sombre sur les bords, lignes jaunes et blanches).
#  - streets_atlas.png (4096 x 512) : une colonne par surface d'enrobé ; u = travers de la chaussée (largeur de la
#    colonne en m), v = long de la rue sur TEX_LENGTH m. Colonnes : chaussées par profil (voies, axe double jaune,
#    stationnement), demi-chaussée de boulevard (ligne jaune côté terre-plein), enrobé nu (carrefours), passage piéton
#    (bandes), ligne d'arrêt, terre-plein planté, ruelle, bateau (entrée de ruelle).
#  - paving.png (512 x 512 = PAVING_TILE m de côté) : dalles des trottoirs et des sols d'îlot, UV en coordonnées monde.
# Réglages d'import écrits avec (compression VRAM, mipmaps).
#
# Lancer : Godot --headless --path <projet> --script res://scenes/world/downtown/tools/DowntownTexturesBake.gd

const DIR := "res://scenes/world/downtown/generated/textures"
const TEX_LENGTH := 12.0
const PX_PER_M := 36.0
const PAVING_TILE := 3.0
const GUTTER := 4
const ASPHALT_EDGE := Color8(0x72, 0x71, 0x71)
const ASPHALT_MID := Color8(0x8C, 0x8C, 0x8F)
const ALLEY_DARK := Color8(0x5f, 0x5d, 0x5b)
const ALLEY_LIGHT := Color8(0x7a, 0x78, 0x75)
const YELLOW := Color8(0xE3, 0xA6, 0x00)
const WHITE := Color8(0xE8, 0xE8, 0xE4)
const WALK_DARK := Color8(0x9a, 0x9a, 0x9b)
const WALK_LIGHT := Color8(0xb4, 0xb3, 0xb0)
const CONCRETE := Color8(0xa9, 0xa6, 0xa0)
const GRASS_DARK := Color8(0x4b, 0x63, 0x34)
const GRASS_LIGHT := Color8(0x6c, 0x86, 0x45)
# [nom, largeur m, lignes [début m, fin m, couleur, tirets]] ; bornes u relevées dans columns.json pour la cuisson
const COLUMNS := [
	["avenue", 14.0, [[3.45, 3.55, "white", true], [6.85, 6.95, "yellow", false], [7.05, 7.15, "yellow", false], [10.45, 10.55, "white", true]]],
	["boulevard_half", 7.0, [[0.2, 0.32, "yellow", false], [3.45, 3.55, "white", true]]],
	["street", 11.0, [[1.95, 2.05, "white", false], [5.35, 5.45, "yellow", false], [5.55, 5.65, "yellow", false], [8.95, 9.05, "white", false]]],
	["one_way", 10.0, [[1.45, 1.55, "white", false], [4.95, 5.05, "white", true], [8.45, 8.55, "white", false]]],
	["plain", 16.0, []],
	["crosswalk", 16.0, []],
	["stop", 1.0, []],
	["median", 2.0, []],
	["alley", 6.0, []],
	["driveway", 6.0, []],
]
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
	grain.seed = 11
	grain.frequency = 0.08
	var patches := FastNoiseLite.new()
	patches.seed = 23
	patches.frequency = 0.012
	var atlas := Image.create(4096, 512, false, Image.FORMAT_RGB8)
	atlas.fill(ASPHALT_EDGE)
	var bounds := {}
	var x0 := 0
	for column: Array in COLUMNS:
		var kind: String = column[0]
		var width: float = column[1]
		var px := roundi(width * PX_PER_M)
		for y in 512:
			var along := (y + 0.5) / 512.0 * TEX_LENGTH
			for x in px:
				var across := (x + 0.5) / px * width
				var noise := grain.get_noise_2d(x0 + x, y)
				var c := _base_color(kind, across, width, along, noise, patches.get_noise_2d(x0 + x, y))
				for line: Array in column[2]:
					if across >= line[0] and across <= line[1] and (not line[3] or fposmod(along, 12.0) < 3.0):
						c = (YELLOW if line[2] == "yellow" else WHITE).darkened(maxf(0.0, noise) * 0.08)
				atlas.set_pixel(x0 + x, y, c)
		# bornes en u rentrées d'un demi-texel : pas de fuite de la colonne voisine au filtrage
		bounds[kind] = {"u0": (x0 + 0.5) / 4096.0, "u1": (x0 + px - 0.5) / 4096.0, "width": width}
		print("DOWNTOWN_TEXTURE colonne %s : x %d à %d (%.1f m)" % [kind, x0, x0 + px, width])
		x0 += px + GUTTER
	if x0 > 4096:
		push_error("atlas trop étroit : %d px" % x0)
		quit(1)
		return
	_save(atlas, "streets_atlas")
	var f := FileAccess.open(DIR.path_join("columns.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"tex_length": TEX_LENGTH, "columns": bounds}, "  "))
	f.close()
	var paving := Image.create(512, 512, false, Image.FORMAT_RGB8)
	var slab := 512.0 / PAVING_TILE * 1.5       # dalles de 1,5 m
	for y in 512:
		for x in 512:
			var v := 0.5 + grain.get_noise_2d(x * 1.5, y * 1.5) * 0.5
			var c := WALK_LIGHT.lerp(WALK_DARK, clampf(v * 0.7 + patches.get_noise_2d(x, y) * 0.3, 0.0, 1.0))
			if fposmod(x, slab) < 2.0 or fposmod(y, slab) < 2.0:
				c = c.darkened(0.18)
			paving.set_pixel(x, y, c)
	_save(paving, "paving")
	quit(0)


func _base_color(kind: String, across: float, width: float, along: float, noise: float, patch: float) -> Color:
	match kind:
		"crosswalk":
			var base := ASPHALT_MID.darkened(noise * 0.05)
			return WHITE.darkened(maxf(0.0, noise) * 0.1) if fposmod(across, 1.2) < 0.6 else base
		"stop":
			return WHITE.darkened(maxf(0.0, noise) * 0.1)
		"median":
			if across < 0.12 or across > width - 0.12:
				return CONCRETE.darkened(noise * 0.08)
			return GRASS_LIGHT.lerp(GRASS_DARK, clampf(0.5 + noise * 0.9, 0.0, 1.0))
		"alley":
			var c := ALLEY_LIGHT.lerp(ALLEY_DARK, clampf(0.5 + noise * 0.6 + patch * 0.8, 0.0, 1.0))
			return c.darkened(0.12) if absf(across - width * 0.5) < 0.25 else c   # rigole centrale
		"driveway":
			return CONCRETE.darkened(clampf(noise * 0.08 + patch * 0.06, 0.0, 0.2))
		"plain":
			return ASPHALT_MID.lerp(ASPHALT_EDGE, clampf(0.35 + patch * 0.5, 0.0, 1.0)).darkened(noise * 0.04)
		_:
			var shade := 1.0 - absf(across / width - 0.5) * 2.0
			return ASPHALT_EDGE.lerp(ASPHALT_MID, smoothstep(0.0, 0.8, shade)).darkened(noise * 0.04)


func _save(img: Image, tex_name: String) -> void:
	var path := DIR.path_join(tex_name + ".png")
	img.save_png(path)
	var f := FileAccess.open(path + ".import", FileAccess.WRITE)
	f.store_string(IMPORT_TEMPLATE % path)
	f.close()
	print("DOWNTOWN_TEXTURE %s" % path)
