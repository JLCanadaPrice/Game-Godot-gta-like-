extends Resource

# RÉGLAGES GLOBAUX DE LA CONDUITE (2026-09-24, CLAUDE.md §14 et §15). Ils s'appliquent à TOUTES les fiches
# (resources/vehicle_physics/fiches_vehicules.csv) sans toucher à leurs 72 lignes : les écarts entre modèles sont gardés.
# Le fichier à modifier est resources/vehicle_physics/reglages_conduite.tres : dans l'éditeur, un double-clic l'ouvre dans
# l'inspecteur ; à la main, c'est trois lignes de texte. Relu au lancement du jeu (FichesVehicules).
# (Un ancien réglage, glissement_avant_max, bornait la direction du châssis réel, par une limite à nous ; il a disparu avec
# lui le 2026-09-24 au soir. Depuis le 2026-09-25, la direction est réduite avec la vitesse par la courbe de GTA V, que règle
# reduction_braquage.)

## Freins : fBrakeForce et fHandBrakeForce de chaque fiche x ce nombre. 1,0 = les fiches telles quelles.
@export_range(0.5, 2.0, 0.05) var multiplicateur_freinage := 1.0
## Pneus : fTractionCurveMax et fTractionCurveMin de chaque fiche x ce nombre. Le véhicule reste sur ses roues quoi qu'il
## arrive : le centre de roulis suit l'adhérence (FichesVehicules.SSF_MIN). 1,0 = les fiches telles quelles.
@export_range(0.5, 2.0, 0.05) var multiplicateur_adherence := 1.0
## Direction : réduction du braquage avec la vitesse, celle de GTA V (ChassisGTA.reduction_gta, 2026-09-25). C'est le
## réglage « Steering reduction » du code d'ikt32 d'où vient la courbe : 1,0 = la courbe de GTA V telle quelle ; 0 = aucune
## réduction (la butée à toute vitesse) ; au-dessus de 1, plus de réduction (au-delà de 1,18, elle tombe à zéro aux plus
## grandes vitesses : plus de direction du tout). ikt32 le met à 0,9 par défaut dans son mod, et le conseille plus haut pour
## un pneu au pic bas (fTractionCurveLateral petit), plus bas pour un pneu au pic haut.
@export_range(0.0, 2.0, 0.05) var reduction_braquage := 1.0
