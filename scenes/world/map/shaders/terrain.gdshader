shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Sol de la carte 3D : 4 matières (herbe, terre, roche, sable) mélangées par poids de sommet (COLOR RGBA),
// plaquées en coordonnées monde (aucun UV), avec une variation à grande échelle contre la répétition.
// Coût fixe de 6 lectures de texture par pixel, sans branche : pensé pour un GPU intégré.

uniform sampler2D tex_grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_dirt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_sand : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_size = 6.5;
uniform float macro_size = 210.0;

varying vec3 world_pos;
varying vec4 weights;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	weights = COLOR;
}

void fragment() {
	vec2 uv = world_pos.xz / tile_size;
	vec3 grass = mix(texture(tex_grass, uv).rgb, texture(tex_grass, uv * 0.27 + 0.31).rgb, 0.45);
	vec3 dirt = texture(tex_dirt, uv * 0.9).rgb;
	vec3 rock = texture(tex_rock, uv * 0.6).rgb;
	vec3 sand = texture(tex_sand, uv).rgb;
	vec4 w = weights / max(weights.r + weights.g + weights.b + weights.a, 0.001);
	vec3 color = grass * w.r + dirt * w.g + rock * w.b + sand * w.a;
	float macro = texture(tex_dirt, world_pos.xz / macro_size).r;
	color *= mix(0.82, 1.12, macro);
	ALBEDO = color;
	ROUGHNESS = 0.94;
	SPECULAR = 0.25;
}
