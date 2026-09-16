shader_type spatial;
render_mode cull_back, specular_disabled, shadows_disabled;

// Arbres lointains de la carte 3D (VegetationBake) : silhouettes en couleurs de sommet, instanciées par blocs.
// Chaque instance plus proche que `near_hide` m de la caméra est repliée sur elle-même (aucun fragment) : l'arbre
// détaillé de la cellule voisine prend le relais, sans trou ni doublon visible.

uniform float near_hide = 290.0;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	// silhouette d'une autre espèce que celle de l'instance, ou instance proche : repliée
	if (abs(UV.x - INSTANCE_CUSTOM.r) > 0.25 || distance(origin, CAMERA_POSITION_WORLD) < near_hide) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2));   // couleurs de sommet saisies en sRGB
	ROUGHNESS = 1.0;
}
