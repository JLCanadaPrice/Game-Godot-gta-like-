shader_type spatial;
render_mode cull_back;

// Facade procedurale : grain beton (bruit valeur calcule dans le shader) +
// grille de fenetres dessinee dans le fragment a partir des UV de face.
// Aucun noeud par fenetre, aucune boucle, aucune texture externe.
// Coordonnees en espace-modele -> insensible a la rotation / echelle du noeud.

uniform vec3 facade_color : source_color = vec3(0.6, 0.6, 0.58);
uniform vec3 window_color : source_color = vec3(0.11, 0.14, 0.19);
uniform vec3 window_lit_color : source_color = vec3(1.0, 0.77, 0.43);

uniform vec2 window_count = vec2(4.0, 6.0);
uniform float lit_ratio : hint_range(0.0, 1.0) = 0.15;
uniform float window_fill : hint_range(0.3, 0.95) = 0.68;
uniform float emission_strength : hint_range(0.0, 3.0) = 0.6;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.85;
uniform float noise_scale = 3.0;
uniform vec3 mesh_obj_size = vec3(4.0);
uniform float lit_seed = 0.0;

varying vec3 v_obj;
varying vec3 v_n;

void vertex() {
	v_obj = VERTEX;
	v_n = NORMAL;
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec3 s = max(mesh_obj_size, vec3(0.001));
	vec3 p01 = clamp(v_obj / s + 0.5, 0.0, 1.0);
	vec3 n = abs(normalize(v_n));
	bool is_roof = n.y > 0.7;

	vec2 fuv;
	float face_id;
	if (n.x > n.z) {
		fuv = vec2(p01.z, p01.y);
		face_id = 0.0;
	} else {
		fuv = vec2(p01.x, p01.y);
		face_id = 2.0;
	}

	float grain = vnoise(fuv * noise_scale * 6.0) * 0.6 + vnoise(fuv * noise_scale * 22.0) * 0.4;
	vec3 concrete = facade_color * (0.82 + 0.36 * grain);
	float rough = clamp(roughness_base * (0.85 + 0.3 * grain), 0.05, 1.0);

	vec3 albedo = concrete;
	vec3 emis = vec3(0.0);
	float metal = 0.0;

	if (is_roof) {
		albedo = concrete * 0.68;
		rough = 0.95;
	} else {
		vec2 gc = fuv * window_count;
		vec2 cell = fract(gc);
		vec2 idx = floor(gc);
		float hf = window_fill * 0.5;
		vec2 dd = abs(cell - 0.5);
		float win = step(dd.x, hf) * step(dd.y, hf);
		if (win > 0.5) {
			float r = hash21(idx + vec2(face_id * 17.0, lit_seed));
			float lit = step(r, lit_ratio);
			albedo = mix(window_color, window_lit_color, lit);
			rough = mix(0.12, 0.25, lit);
			metal = 0.35;
			emis = window_lit_color * emission_strength * lit;
		}
	}

	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emis;
}
