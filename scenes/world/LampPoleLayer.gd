extends Node3D

# Place le mesh du poteau de lampadaire (lamp_1.glb) sur le meme calque
# visuel dedie (2) que TrafficLight.gd utilise pour son propre modele : le
# poteau touche presque son propre SpotLight3D (a peine ~6.2m, dans un cone
# de 44 et une portee de 8.8), qui le surexposait en blanc. Le
# light_cull_mask des 98 spots exclut deja ce calque ; le soleil
# (DirectionalLight3D, cull_mask par defaut = tous calques) continue de
# l'eclairer normalement.
#
# Fait exprès en script (comme TrafficLight.gd) plutot qu'en modifiant la
# propriete "layers" directement dans World.tscn sur ce noeud interne de
# l'instance .glb : une tentative precedente de forcer un owner sur ce
# noeud interne pour sauvegarder l'override a corrompu la structure
# d'instanciation (duplication du mesh). Un changement au runtime, ici,
# n'a pas ce probleme puisqu'il n'est jamais serialise dans la scene.

# Copie non metallique du materiau importe, UNE pour tous les poteaux
# (materiau importe -> copie). Une copie par poteau donnait 378 materiaux
# distincts, donc 378 appels de dessin que rien ne pouvait regrouper
# (l'instanciation automatique du moteur comme les MultiMesh de
# CityRenderOptimizer exigent le meme materiau). La copie n'est plus jamais
# modifiee ensuite : la partager ne change rien a l'image.
static var _non_metal := {}

func _ready() -> void:
	for c in get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			mi.layers = 2
			# Cause reelle trouvee : le materiau importe du glb est
			# metallic=1.0 (roughness=1.0), contrairement a la tete du feu
			# (metallic=0.0). Un metal pur n'a quasiment pas de reponse
			# diffuse, sa teinte vient presque entierement de la lumiere
			# ambiante/environnante reflechie (non filtree par
			# light_cull_mask, qui n'agit que sur les Light3D explicites) ;
			# avec albedo blanc pur, ca lave facilement la surface vers du
			# blanc. Duplique (comme TrafficLight.gd) pour ne jamais muter
			# le materiau partage de l'asset importe ; copie commune a tous
			# les poteaux (cf. _non_metal).
			var base := mi.get_active_material(0) as StandardMaterial3D
			if base != null:
				if not _non_metal.has(base):
					var mat := base.duplicate() as StandardMaterial3D
					mat.metallic = 0.0
					_non_metal[base] = mat
				mi.set_surface_override_material(0, _non_metal[base])
