extends Node3D

# ROUE DU CHÂSSIS FAÇON GTA V (ChassisGTA, CLAUDE.md §15) : ses réglages et son état, sans calcul — c'est le châssis qui
# sonde le sol, pousse les ressorts et fait travailler les pneus, roue par roue, dans un seul script (un appel par pas au
# lieu de cinq).
# Posée au centre de la roue du modèle AU REPOS (repère du châssis) ; son enfant « animation » descend et monte avec la
# suspension, et sa rotation autour de Y est son braquage (+ : à gauche). C'est ce que lit Car._visuels_chassis, avec
# `wv` et `w_size` (noms repris du pack VitaVehicle, que lisait aussi la voiture) : la roue du modèle roule à wv x w_size.

# --- réglages (ChassisGTA.configurer) ---
var avant := false
var gauche := false
var motrice := false
var jumelle: Node3D = null        # l'autre roue de l'essieu (barre anti-roulis)
var rayon := 0.3                  # m, relevé sur le modèle
var repos := Vector3.ZERO         # centre au repos, repère du châssis
var charge_statique := 0.0        # N
var l0 := 0.1                     # m : détente, sous le repos, où le ressort ne pousse plus (1 / (4 x fSuspensionForce))
var detente_max := 0.16           # m : course de détente sous le repos, jusqu'où la roue cherche le sol (au moins l0)
var raideur := 0.0                # N/m
var raideur_barre := 0.0          # N/m : barre anti-roulis, sur l'écart de compression avec la jumelle
var amort_comp := 0.0             # N.s/m
var amort_detente := 0.0          # N.s/m
var adherence := 1.0              # adhérence maximale (g) : fTractionCurveMax converti, multiplicateur global compris
var adherence_glisse := 0.9       # adhérence en glisse franche (g) : fTractionCurveMin converti
var part_frein := 0.0             # part de la force du frein au pied
var part_moteur := 0.0            # part de la force motrice
var part_frein_main := 0.0        # part de la force du frein à main (roues arrière)

# --- état (ChassisGTA._physics_process) ---
var au_sol := false
var detente := 0.0                # m : centre de la roue SOUS sa position de repos (négatif : comprimée)
var detente_avant := 0.0          # celle du pas précédent (vitesse de l'amortisseur)
var charge := 0.0                 # N : effort du ressort (ressort, amortisseur, butée, barre), ce que porte le pneu
var normale := Vector3.UP         # normale du sol sous la roue (monde)
var contact := Vector3.ZERO       # point bas de la roue, sur le sol (monde)
var braquage := 0.0               # rad, + à gauche
var patinage := 0.0               # m/s : excès de vitesse du pneu sur le sol, roue motrice qui patine
var bloquee := false              # bloquée par le frein à main
var wv := 0.0                     # rad/s, + en avant : vitesse de rotation (nom du pack, lu par Car._visuels_chassis)
var w_size := 0.3                 # rayon du pneu en m (idem ; LengthScale du châssis vaut 1)
var compress := 0.0               # m : compression depuis le repos (+ comprimée), pour les traces des tests
var glisse := 0.0                 # m/s : vitesse du pneu moins celle du sol, le long de la roue (traces)
var derive_pneu := 0.0            # rad : angle de glissement du pneu (traces)
# forces du pneu de ce pas (N), calculées pour toutes les roues sur le même état du corps, puis appliquées ensemble
var fx := 0.0                     # le long de la roue (+ vers l'avant)
var fy := 0.0                     # en travers (+ vers la gauche)
var dir_av := Vector3.FORWARD
var dir_lat := Vector3.LEFT
var point_lat := Vector3.ZERO     # où s'applique fy (monde) : au centre de roulis
var point_lon := Vector3.ZERO     # où s'applique fx : au centre de tangage


func is_colliding() -> bool:
	return au_sol
