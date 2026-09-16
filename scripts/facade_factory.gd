extends RefCounted

# Fabrique un ShaderMaterial de facade randomise (couleur, densite de fenetres,
# ratio de fenetres allumees). AUCUN preload : le shader est charge
# paresseusement via load(), avec garde-fou -> une erreur de shader ne casse
# plus le parsing des scripts qui utilisent cette fabrique. Le grain de beton
# est genere dans le shader, pas de texture externe.

const SHADER_PATH := "res://shaders/building_facade.gdshader"

# Palette de facades realistes : beton, beton chaud, gris pierre, brique,
# gres, verre bleute, moderne sombre.
const PALETTE := [
	Color(0.62, 0.62, 0.60),
	Color(0.78, 0.72, 0.58),
	Color(0.55, 0.53, 0.50),
	Color(0.55, 0.30, 0.24),
	Color(0.72, 0.63, 0.48),
	Color(0.42, 0.48, 0.55),
	Color(0.34, 0.35, 0.38),
]

static var _shader = null

# mesh_size  : taille du BoxMesh de base (espace modele, ex. Vector3(4,4,4))
# world_scale: echelle monde accumulee du MeshInstance3D (root * local)
static func build(mesh_size: Vector3, world_scale: Vector3) -> ShaderMaterial:
	if _shader == null:
		_shader = load(SHADER_PATH)
	if _shader == null:
		return null

	var world_w: float = maxf(mesh_size.x * world_scale.x, 1.0)
	var world_h: float = maxf(mesh_size.y * world_scale.y, 1.0)

	# ~1 travee toutes les ~3 m, ~1 rangee par etage (~3.3 m)
	# => plus le batiment est haut, plus il a de rangees de fenetres.
	var cols: int = maxi(2, roundi(world_w / randf_range(2.6, 3.4)))
	var rows: int = maxi(1, roundi(world_h / randf_range(3.0, 3.7)))

	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("facade_color", PALETTE[randi() % PALETTE.size()])
	mat.set_shader_parameter("window_color", Color(0.11, 0.14, 0.19))
	mat.set_shader_parameter("window_lit_color", Color(1.0, 0.77, 0.43))
	mat.set_shader_parameter("window_count", Vector2(cols, rows))
	mat.set_shader_parameter("lit_ratio", randf_range(0.05, 0.30))
	mat.set_shader_parameter("window_fill", randf_range(0.60, 0.78))
	mat.set_shader_parameter("emission_strength", randf_range(0.40, 0.90))
	mat.set_shader_parameter("roughness_base", randf_range(0.75, 0.95))
	mat.set_shader_parameter("noise_scale", randf_range(2.0, 4.0))
	mat.set_shader_parameter("mesh_obj_size", mesh_size)
	mat.set_shader_parameter("lit_seed", randf() * 1000.0)
	return mat
