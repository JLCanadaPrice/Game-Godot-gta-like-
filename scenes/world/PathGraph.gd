extends Node3D
class_name PathGraph

# Graphe de cheminement piéton : noeuds (positions monde, y ignoré) + arêtes
# non orientées. Les PNJ marchent de noeud en noeud et tirent une arête au
# hasard à chaque carrefour (sans faire demi-tour si une autre option existe).
#
# Les VOITURES n'utilisent PAS ce graphe : elles restent sur CircuitPath.
# Ce graphe couvre : l'anneau des trottoirs de la route + les allées devant
# les bâtiments + les entrées de chaque bâtiment.

@export var nodes: Array[Vector3] = []
@export var edges: Array[Vector2i] = []   # (a, b) : indices dans `nodes`

var _adj: Array = []   # _adj[i] = PackedInt32Array des voisins de i

func _ready() -> void:
	rebuild()

func rebuild() -> void:
	_adj.clear()
	for i in nodes.size():
		_adj.append(PackedInt32Array())
	for e in edges:
		var a := int(e.x)
		var b := int(e.y)
		if a >= 0 and a < nodes.size() and b >= 0 and b < nodes.size():
			_adj[a].append(b)
			_adj[b].append(a)

func neighbors(i: int) -> PackedInt32Array:
	if i < 0 or i >= _adj.size():
		return PackedInt32Array()
	return _adj[i]

func node_pos(i: int) -> Vector3:
	return nodes[i] if i >= 0 and i < nodes.size() else global_position

func node_count() -> int:
	return nodes.size()

# Voisin au hasard de `node`, en évitant `avoid` (le noeud d'où l'on vient)
# tant qu'il reste au moins une autre possibilité.
func pick_next(node: int, avoid: int) -> int:
	var nb := neighbors(node)
	if nb.is_empty():
		return node
	var options: Array[int] = []
	for n in nb:
		if n != avoid:
			options.append(n)
	if options.is_empty():
		return nb[randi() % nb.size()]
	return options[randi() % options.size()]
