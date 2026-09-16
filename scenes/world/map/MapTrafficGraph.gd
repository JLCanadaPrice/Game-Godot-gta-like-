class_name MapTrafficGraph
extends Resource

# Graphe de circulation de la carte 3D (autoroutes, bretelles, artères), écrit par RoadBake et fusionné au Circuit du
# monde par MapTraffic. Mêmes conventions que CircuitPath : y des noeuds = surface de chaussée - 0,05.

@export var nodes := PackedVector3Array()
@export var edges: Array[Dictionary] = []          # {"a", "b", "points": PackedVector3Array, "one_way", "lanes": PackedFloat32Array}
@export var roundabout := PackedInt32Array()       # noeuds d'anneau (cédez-le-passage à l'entrée, priorité sur l'anneau)
@export var unlit := PackedInt32Array()            # noeuds sans feu tricolore
@export var grid := PackedInt32Array()             # noeuds confondus avec la grille du centre-ville (déjà dans le Circuit)
@export var yields := {}                           # "%d_%d" % [arête, noeud] : approche qui cède le passage
