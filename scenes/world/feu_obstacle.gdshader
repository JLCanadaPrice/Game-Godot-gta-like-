// FEU D'OBSTACLE (2026-09-23) : la copie allumée de la boule rouge au sommet de Mk1 (cf. DowntownBuildingsBake,
// _feu_obstacle). Le maillage est la géométrie du modèle, recentrée sur la boule et ramenée à un rayon de 1 ; le nœud
// est posé au centre de la boule et mis à l'échelle de son vrai rayon.
//
// De près, elle garde exactement sa taille. De loin, elle GROSSIT autour de son centre pour ne jamais paraître plus
// petite que ANGLE_MIN radians de rayon : une boule de 1,1 m de rayon tombait sous le pixel à 1,3 km en 800x450 (vu à
// l'image, zéro pixel rouge, allumée ou non), alors qu'un vrai feu d'obstacle se voit à des kilomètres parce qu'il
// éblouit. Pas de boîte ni d'image ajoutée : ce sont les mêmes triangles.
shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled, cull_back;

// Sous 1,0 : l'ACES délave un rouge posé à 1,0 en saumon (CLAUDE.md §6).
uniform vec3 couleur : source_color = vec3(0.62, 0.0, 0.0);
// 0,004 rad : environ 3 px de rayon en 1920x1080, 1,5 px en 800x450, pour le champ de la caméra du jeu.
uniform float angle_min = 0.004;

void vertex() {
	float rayon = length(MODELVIEW_MATRIX[0].xyz);        // l'échelle du nœud : le vrai rayon de la boule
	float distance_camera = length(MODELVIEW_MATRIX[3].xyz);
	VERTEX *= max(1.0, distance_camera * angle_min / max(rayon, 0.001));
}

void fragment() {
	ALBEDO = couleur;
}
