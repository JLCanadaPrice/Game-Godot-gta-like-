extends Resource

# RÉGLAGES GLOBAUX DE LA CONDUITE RÉALISTE (2026-09-24, CLAUDE.md §14). Ils s'appliquent à TOUTES les fiches
# (resources/vehicle_physics/fiches_vehicules.csv) sans toucher à leurs 72 lignes : les écarts entre modèles sont gardés.
# Le fichier à modifier est resources/vehicle_physics/reglages_conduite.tres : dans l'éditeur, un double-clic l'ouvre dans
# l'inspecteur ; à la main, c'est trois lignes de texte. Relu au lancement du jeu (FichesVehicules).

## Freins : la décélération maximale de chaque fiche (freinage_ms2) et son frein à main (frein_main_ms2) x ce nombre.
## 1,0 = les fiches telles quelles.
@export_range(0.5, 2.0, 0.05) var multiplicateur_freinage := 1.0
## Pneus : l'adhérence de chaque fiche (adherence) x ce nombre, et la raideur du pneu avec elle, pour qu'il ne glisse pas
## davantage avant de décrocher. S'il le faut, le centre de gravité est rabaissé d'autant : aucun véhicule ne peut se
## coucher (FichesVehicules.SSF_MIN). 1,0 = les fiches telles quelles.
@export_range(0.5, 2.0, 0.05) var multiplicateur_adherence := 1.0
## Direction, à vitesse : braquage à fond (clavier), les roues avant tournent au plus de l'angle du virage que tiennent
## les pneus, plus ce glissement du pneu avant, en degrés. Plus il est grand, plus la voiture tourne serré et glisse à la
## limite ; plus il est petit, plus elle reste droite et sous-vire. 0 = pas de borne (le braquage du pack seul, qui au
## clavier demandait jusqu'à dix fois ce que tiennent les pneus, à 110 km/h). Levée tant que le frein à main bloque les
## roues arrière : c'est le geste pour faire pivoter la voiture.
@export_range(0.0, 15.0, 0.5) var glissement_avant_max := 0.0
