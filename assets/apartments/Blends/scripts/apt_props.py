"""
Lot C : props de départ des appartements, à l'échelle du perso (S_HUMAN). Module pour run_lot.py.

- Apt_Table : bureau 1,40 x 0,70 m, plateau à 0,75 m (14 cm sous le bassin mesuré à 0,894 m).
  Socket_PC sur le plateau, légèrement en retrait.
- Apt_Computer : écran plat, clavier, souris, tour ; côté utilisateur vers -Y Blender (= +Z Godot).
  L'écran est un nœud séparé « Screen » avec UV 0-1 et son propre matériau (PC_Screen) : le futur
  chantier d'affichage y branchera une ViewportTexture sans ré-export.
"""

import os

import bpy

import dl_common as dl
from dl_common import MeshBuilder, col_box, mat, socket

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))  # assets/apartments
BLEND = "Apartment_Props.blend"
TABLE_TOP = 0.75

EXPECT = {
    "Apt_Table": {"x": (1.38, 1.42), "y": (0.68, 0.72), "z": (0.74, 0.76)},
    "Apt_Computer": {"x": (0.87, 0.91), "y": (0.48, 0.52), "z": (0.44, 0.46)},
}


def build_table(coll):
    b = MeshBuilder("Apt_Table", [mat("AP_Wood", (0.30, 0.20, 0.10), 0.7), mat("AP_Metal_Dark", (0.05, 0.05, 0.055), 0.6)])
    WOOD, METAL = range(2)
    w, d, h, t = 1.40, 0.70, TABLE_TOP, 0.04
    b.box((-w / 2, -d / 2, h - t), (w / 2, d / 2, h), mi=WOOD)  # plateau
    b.box((-w / 2 + 0.03, -d / 2 + 0.03, h - t - 0.06), (w / 2 - 0.03, d / 2 - 0.03, h - t), mi=METAL)  # ceinture
    for x in (-w / 2 + 0.065, w / 2 - 0.065):
        for y in (-d / 2 + 0.065, d / 2 - 0.065):
            b.box((x - 0.025, y - 0.025, 0.0), (x + 0.025, y + 0.025, h - t - 0.06), mi=METAL)
    table = b.finish(coll)
    col_box("Col_Table", (-w / 2, -d / 2, 0.0), (w / 2, d / 2, h), table)
    socket("Socket_PC", (0.0, 0.05, h), table)
    return table


def _screen(parent, x0, x1, y, z0, z1):
    """Dalle d'affichage : quad face -Y, UV 0-1 (bas-gauche -> haut-droite vu de face)."""
    me = bpy.data.meshes.new("Screen")
    me.from_pydata([(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)], [], [(0, 1, 2, 3)])
    uv = me.uv_layers.new(name="UVMap")
    for loop, coord in zip(me.loops, ((0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0))):
        uv.data[loop.index].uv = coord
    me.update()
    me.materials.append(mat("PC_Screen", (0.02, 0.03, 0.04), 0.1))
    obj = bpy.data.objects.new("Screen", me)
    parent.users_collection[0].objects.link(obj)
    obj.parent = parent
    return obj


def build_computer(coll):
    led = mat("AP_LED", (0.2, 0.5, 1.0), 0.5, emission=(0.2, 0.5, 1.0), strength=3.0)
    b = MeshBuilder("Apt_Computer", [mat("AP_Plastic_Dark", (0.02, 0.02, 0.025), 0.5),
                                     mat("AP_Plastic_Grey", (0.12, 0.12, 0.13), 0.5), led])
    DARK, GREY, LED = range(3)
    b.box((-0.11, 0.02, 0.0), (0.11, 0.18, 0.015), mi=DARK)       # pied de l'écran
    b.box((-0.02, 0.08, 0.015), (0.02, 0.11, 0.13), mi=DARK)       # cou
    b.box((-0.28, 0.05, 0.11), (0.28, 0.08, 0.45), mi=DARK)        # dalle 0,56 x 0,34
    b.box((-0.22, -0.25, 0.0), (0.22, -0.11, 0.025), mi=GREY)      # clavier 0,44 x 0,14
    b.box((0.27, -0.23, 0.0), (0.33, -0.13, 0.03), mi=GREY)        # souris
    b.box((0.43, -0.15, 0.0), (0.61, 0.25, 0.42), mi=DARK)         # tour 0,18 x 0,40 x 0,42
    b.box((0.505, -0.153, 0.36), (0.535, -0.149, 0.39), mi=LED)    # voyant
    pc = b.finish(coll)
    _screen(pc, -0.265, 0.265, 0.048, 0.125, 0.435)
    return pc


ASSETS = [
    ("Apt_Table", "props", build_table),
    ("Apt_Computer", "props", build_computer),
]


def place_desk(roots, coll, at, name):
    """Table + PC posés sur Socket_PC (positions lues sur les vrais repères). Utilisé aussi par apt_shells."""
    base = dl.Vector(at)
    dl.instance(roots["Apt_Table"], name + "_Table", base, coll)
    sock = next(c for c in roots["Apt_Table"].children if c.name.startswith("Socket_PC"))
    pc_at = base + sock.location
    dl.instance(roots["Apt_Computer"], name + "_Computer", pc_at, coll)
    screen = next(c for c in roots["Apt_Computer"].children if c.name.startswith("Screen"))
    dl.instance(screen, name + "_Screen", pc_at, coll)


def stage(roots, coll):
    ground = MeshBuilder("Stage_Ground", [mat("Stage_Ground", (0.30, 0.30, 0.30), 0.9)])
    ground.box((-3.0, -3.0, -0.05), (3.0, 3.0, 0.0))
    ground.finish(coll)
    place_desk(roots, coll, (0.0, 0.0, 0.0), "Stage")
    dl.mannequin(coll, (-0.2, -0.75, 0.0))
    return [
        {"file": "Lot_C_desk_3q.png", "loc": (1.6, -2.4, 1.7), "target": (0.1, 0.0, 0.7), "lens": 35.0},
        {"file": "Lot_C_desk_front.png", "type": 'ORTHO', "ortho_scale": 2.8, "loc": (0.3, -8.0, 0.95),
         "target": (0.3, 0.0, 0.95), "res": (1400, 1000)},
    ]
