extends Resource

# RÉGLAGES GLOBAUX DE LA CONDUITE (2026-09-24, CLAUDE.md §14 et §15). Ils s'appliquent à TOUTES les fiches
# (resources/vehicle_physics/fiches_vehicules.csv) sans toucher à leurs 72 lignes : les écarts entre modèles sont gardés.
# Le fichier à modifier est resources/vehicle_physics/reglages_conduite.tres : dans l'éditeur, un double-clic l'ouvre dans
# l'inspecteur ; à la main, c'est deux lignes de texte. Relu au lancement du jeu (FichesVehicules).
# (Le troisième réglage, glissement_avant_max, bornait la direction du châssis réel ; la conduite façon GTA V, qui l'a
# remplacé le 2026-09-24 au soir, borne sa direction d'elle-même par le pneu avant : il a disparu.)

## Freins : fBrakeForce et fHandBrakeForce de chaque fiche x ce nombre. 1,0 = les fiches telles quelles.
@export_range(0.5, 2.0, 0.05) var multiplicateur_freinage := 1.0
## Pneus : fTractionCurveMax et fTractionCurveMin de chaque fiche x ce nombre. Le véhicule reste sur ses roues quoi qu'il
## arrive : le centre de roulis suit l'adhérence (FichesVehicules.SSF_MIN). 1,0 = les fiches telles quelles.
@export_range(0.5, 2.0, 0.05) var multiplicateur_adherence := 1.0
