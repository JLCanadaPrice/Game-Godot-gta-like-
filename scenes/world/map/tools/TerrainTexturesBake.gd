extends SceneTree

# Étape 1 : textures de sol de la carte 3D générées par bruit (aucune licence tierce) : herbe, terre, roche, sable,
# 512 px, raccordables. Réglages d'import écrits avec : compression VRAM et mipmaps (usage 3D), à lancer avant
# l'import puis TerrainBake.
#
# Lancer : Godot --headless --path <projet> --script res://scenes/world/map/tools/TerrainTexturesBake.gd

const DIR := "res://scenes/world/map/terrain/textures"
const SIZE := 512
# [couleur sombre, couleur claire, fréquence, graine, part du détail fin]
const MATERIALS := {
	"grass": [Color(0.22, 0.32, 0.13), Color(0.41, 0.52, 0.22), 0.045, 11, 0.35],
	"dirt": [Color(0.34, 0.27, 0.18), Color(0.53, 0.43, 0.30), 0.055, 23, 0.30],
	"rock": [Color(0.36, 0.36, 0.34), Color(0.61, 0.60, 0.56), 0.035, 37, 0.45],
	"sand": [Color(0.60, 0.54, 0.40), Color(0.79, 0.73, 0.58), 0.07, 41, 0.25],
}
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
	for tex_name: String in MATERIALS:
		var spec: Array = MATERIALS[tex_name]
		var base := FastNoiseLite.new()
		base.seed = spec[3]
		base.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		base.frequency = spec[2]
		base.fractal_octaves = 5
		var fine := FastNoiseLite.new()
		fine.seed = spec[3] + 101
		fine.noise_type = FastNoiseLite.TYPE_CELLULAR if tex_name == "rock" else FastNoiseLite.TYPE_SIMPLEX
		fine.frequency = spec[2] * 7.0
		var a := base.get_seamless_image(SIZE, SIZE, false, false, 0.1, true)
		var b := fine.get_seamless_image(SIZE, SIZE, false, false, 0.1, true)
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
		var dark: Color = spec[0]
		var light: Color = spec[1]
		for y in SIZE:
			for x in SIZE:
				var v: float = a.get_pixel(x, y).r * (1.0 - spec[4]) + b.get_pixel(x, y).r * spec[4]
				img.set_pixel(x, y, dark.lerp(light, clampf(v, 0.0, 1.0)))
		var path := DIR.path_join(tex_name + ".png")
		img.save_png(path)
		var f := FileAccess.open(path + ".import", FileAccess.WRITE)
		f.store_string(IMPORT_TEMPLATE % path)
		f.close()
		print("TERRAIN_TEXTURE %s" % path)
	quit(0)
