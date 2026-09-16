extends SceneTree

# Étape 2a : textures des routes de la carte 3D, dans la palette des routes du centre-ville (assets/modular_roads :
# enrobé gris plus sombre sur les bords, lignes jaunes). Atlas roads.png (1024 x 512) : une colonne par type de ruban,
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
const COLUMNS := [
	["highway", 0, 10.7, [[0.35, 0.5, "yellow", false], [5.28, 5.43, "white", true], [10.2, 10.35, "white", false]]],
	["ramp", 512, 7.0, [[0.35, 0.5, "yellow", false], [6.5, 6.65, "white", false]]],
	["median", 848, 3.0, []],
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
	grain.seed = 5
	grain.frequency = 0.08
	var atlas := Image.create(1024, 512, false, Image.FORMAT_RGB8)
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
				# dégradé des routes du centre-ville : bords plus sombres, léger grain
				var shade := 1.0 - absf(across / width - 0.5) * 2.0
				var c := ASPHALT_EDGE.lerp(ASPHALT_MID, smoothstep(0.0, 0.8, shade))
				c = c.darkened(grain.get_noise_2d(x0 + x, y) * 0.04)
				for line: Array in lines:
					if across >= line[0] and across <= line[1] and (not line[3] or fposmod(along, 12.0) < 3.0):
						c = YELLOW if line[2] == "yellow" else WHITE
				atlas.set_pixel(x0 + x, y, c)
		print("ROAD_TEXTURE colonne %s : u %.6f à %.6f" % [column[0], x0 / 1024.0, (x0 + px) / 1024.0])
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


func _save(img: Image, tex_name: String) -> void:
	var path := DIR.path_join(tex_name + ".png")
	img.save_png(path)
	var f := FileAccess.open(path + ".import", FileAccess.WRITE)
	f.store_string(IMPORT_TEMPLATE % path)
	f.close()
	print("ROAD_TEXTURE %s" % path)
