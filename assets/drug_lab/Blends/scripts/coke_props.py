"""
Lot 3 drug_lab : props coke génériques et stylisés, à l'échelle du perso (S_HUMAN) :
table, tas, sachets, briques, presse, balance. Formes simples de décor, sans détail de
préparation. Géométrie en mètres réels, origine au sol ; l'échelle est appliquée par
build_props.py.
"""

import math
import random

from mathutils import Matrix, Vector

from dl_common import MeshBuilder, box_m, col_box, cyl_between, ico, mat, poly

# Plages de contrôle avant export (m ; axes Blender : x largeur, y profondeur, z hauteur)
EXPECT = {
    "Coke_Table": {"x": (1.90, 2.10), "y": (0.90, 1.10), "z": (0.85, 0.95)},
    "Coke_Pile": {"x": (0.30, 0.40), "y": (0.30, 0.40), "z": (0.10, 0.14)},
    "Coke_Bag": {"x": (0.11, 0.13), "y": (0.07, 0.09), "z": (0.02, 0.04)},
    "Coke_Bags_Stack": {"x": (0.20, 0.45), "y": (0.15, 0.40), "z": (0.05, 0.14)},
    "Coke_Brick": {"x": (0.29, 0.31), "y": (0.17, 0.19), "z": (0.06, 0.08)},
    "Coke_Bricks_Stack": {"x": (0.60, 0.70), "y": (0.34, 0.42), "z": (0.20, 0.24)},
    "Coke_Press": {"x": (0.50, 0.70), "y": (0.40, 0.60), "z": (1.00, 1.20)},
    "Coke_Scale": {"x": (0.24, 0.27), "y": (0.19, 0.22), "z": (0.06, 0.10)},
}


def _m():
    return dict(
        steel=mat("CK_Steel", (0.45, 0.46, 0.47), 0.35),
        metal=mat("CK_Metal_Dark", (0.05, 0.05, 0.055), 0.6),
        powder=mat("CK_Powder", (0.80, 0.80, 0.78), 0.95),
        bag=mat("CK_Bag", (0.70, 0.72, 0.72), 0.3),
        seal=mat("CK_Bag_Seal", (0.35, 0.03, 0.02), 0.5),
        wrap=mat("CK_Wrap", (0.36, 0.26, 0.13), 0.7),
        tape=mat("CK_Tape", (0.12, 0.09, 0.05), 0.6),
        emblem=mat("CK_Emblem", (0.40, 0.02, 0.02), 0.5),
        paint=mat("CK_Paint_Red", (0.35, 0.03, 0.02), 0.5),
        plastic=mat("CK_Plastic_Black", (0.02, 0.02, 0.025), 0.5),
        display=mat("CK_Display", (0.2, 0.9, 0.5), 0.5, emission=(0.2, 0.9, 0.5), strength=2.0),
    )


def _pillow(b, matrix, sx, sy, sz, inset, mi):
    """Coussin bas-poly : ceinture pleine taille, dessus et dessous rentrés."""
    levels = [[matrix @ Vector((cx * sx / 2.0 * k, cy * sy / 2.0 * k, z))
               for cx, cy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
              for z, k in ((0.0, inset), (sz / 2.0, 1.0), (sz, inset))]
    poly(b, list(reversed(levels[0])), mi)
    for lo, hi in ((levels[0], levels[1]), (levels[1], levels[2])):
        for i in range(4):
            j = (i + 1) % 4
            poly(b, (lo[i], lo[j], hi[j], hi[i]), mi)
    poly(b, levels[2], mi)


def _bag(b, matrix, bag, seal):
    """Sachet 0,12 x 0,08 x 0,03 m avec bande de fermeture."""
    _pillow(b, matrix, 0.12, 0.08, 0.03, 0.85, bag)
    box_m(b, matrix @ Matrix.Translation((0.047, 0.0, 0.0225)), (0.01, 0.072, 0.019), mi=seal)


def _brick(b, matrix, wrap, tape, emblem):
    """Brique emballée 0,30 x 0,18 x 0,07 m : deux bandes d'adhésif et un losange sur le dessus."""
    sz = 0.07
    _pillow(b, matrix, 0.30, 0.18, sz, 0.94, wrap)
    for x in (-0.08, 0.08):
        box_m(b, matrix @ Matrix.Translation((x, 0.0, sz / 2.0)), (0.03, 0.184, sz + 0.004), mi=tape)
    poly(b, [matrix @ Vector((px, py, sz + 0.0015)) for px, py in ((0.02, 0.0), (0.0, 0.03), (-0.02, 0.0), (0.0, -0.03))],
         emblem)


def build_table(coll):
    m = _m()
    b = MeshBuilder("Coke_Table", [m["steel"], m["metal"]])
    STEEL, METAL = range(2)
    w, d, h, t = 2.0, 1.0, 0.9, 0.03
    b.box((-w / 2, -d / 2, h - t), (w / 2, d / 2, h), mi=STEEL)  # plateau inox à 0,9 m
    b.box((-w / 2 + 0.03, -d / 2 + 0.03, h - t - 0.07), (w / 2 - 0.03, d / 2 - 0.03, h - t), mi=METAL)  # ceinture
    for x in (-w / 2 + 0.07, w / 2 - 0.07):
        for y in (-d / 2 + 0.07, d / 2 - 0.07):
            b.box((x - 0.025, y - 0.025, 0.0), (x + 0.025, y + 0.025, h - t - 0.07), mi=METAL)
    b.box((-w / 2 + 0.07, -d / 2 + 0.07, 0.18), (w / 2 - 0.07, d / 2 - 0.07, 0.20), mi=STEEL)  # étagère basse
    table = b.finish(coll)
    col_box("Col_CokeTable", (-w / 2, -d / 2, 0.0), (w / 2, d / 2, h), table)
    return table


def build_pile(coll):
    m = _m()
    b = MeshBuilder("Coke_Pile", [m["powder"]])
    rng = random.Random(41)
    seg = 12
    profile = [(0.175, 0.000), (0.150, 0.025), (0.105, 0.065), (0.050, 0.100)]
    rings = []
    for k, (r, z) in enumerate(profile):
        jr, jz = (0.08, 0.006) if k else (0.0, 0.0)
        rings.append([Vector((r * (1.0 + rng.uniform(-jr, jr)) * math.cos((i + 0.5 * k) * 2.0 * math.pi / seg),
                              r * (1.0 + rng.uniform(-jr, jr)) * math.sin((i + 0.5 * k) * 2.0 * math.pi / seg),
                              z + rng.uniform(-jz, jz)))
                      for i in range(seg)])
    for lo, hi in zip(rings, rings[1:]):
        for i in range(seg):
            j = (i + 1) % seg
            poly(b, (lo[i], lo[j], hi[i]))
            poly(b, (hi[i], lo[j], hi[j]))
    top = Vector((0.0, 0.0, 0.12))
    for i in range(seg):
        poly(b, (rings[-1][i], rings[-1][(i + 1) % seg], top))
    poly(b, list(reversed(rings[0])))  # dessous
    return b.finish(coll)


def build_bag(coll):
    m = _m()
    b = MeshBuilder("Coke_Bag", [m["bag"], m["seal"]])
    _bag(b, Matrix.Identity(4), 0, 1)
    return b.finish(coll)


def build_bags_stack(coll):
    m = _m()
    b = MeshBuilder("Coke_Bags_Stack", [m["bag"], m["seal"]])
    rng = random.Random(43)
    layout = [(0.000, [(-0.065, -0.045), (0.065, -0.045), (-0.065, 0.045), (0.065, 0.045)]),
              (0.027, [(-0.03, -0.02), (0.07, 0.01), (-0.05, 0.05)]),
              (0.054, [(0.0, 0.0), (0.04, 0.04)])]
    for z, spots in layout:
        for x, y in spots:
            _bag(b, Matrix.Translation((x, y, z)) @ Matrix.Rotation(rng.uniform(-0.35, 0.35), 4, 'Z'), 0, 1)
    return b.finish(coll)


def build_brick(coll):
    m = _m()
    b = MeshBuilder("Coke_Brick", [m["wrap"], m["tape"], m["emblem"]])
    _brick(b, Matrix.Identity(4), 0, 1, 2)
    return b.finish(coll)


def build_bricks_stack(coll):
    m = _m()
    b = MeshBuilder("Coke_Bricks_Stack", [m["wrap"], m["tape"], m["emblem"]])
    rng = random.Random(47)
    for layer in range(3):
        for x in (-0.151, 0.151):
            for y in (-0.091, 0.091):
                mtx = (Matrix.Translation((x + rng.uniform(-0.008, 0.008), y + rng.uniform(-0.006, 0.006), layer * 0.072))
                       @ Matrix.Rotation(rng.uniform(-0.03, 0.03), 4, 'Z'))
                _brick(b, mtx, 0, 1, 2)
    return b.finish(coll)


def build_press(coll):
    m = _m()
    b = MeshBuilder("Coke_Press", [m["metal"], m["paint"], m["steel"]])
    METAL, PAINT, STEEL = range(3)
    b.box((-0.30, -0.25, 0.0), (0.30, 0.25, 0.06), mi=METAL)  # socle
    for x in (-0.24, 0.24):
        cyl_between(b, (x, 0.0, 0.06), (x, 0.0, 0.95), 0.03, 0.03, segments=8, mi=STEEL)  # colonnes
    b.box((-0.30, -0.06, 0.95), (0.30, 0.06, 1.03), mi=PAINT)  # traverse haute
    b.box((-0.27, -0.20, 0.70), (0.27, 0.20, 0.76), mi=PAINT)  # plateau de travail
    b.box((-0.16, -0.10, 0.76), (0.16, 0.10, 0.86), mi=STEEL)  # moule
    b.box((-0.15, -0.09, 0.87), (0.15, 0.09, 0.90), mi=METAL)  # plaque de pression
    cyl_between(b, (0.0, 0.0, 0.90), (0.0, 0.0, 1.08), 0.025, 0.025, segments=8, mi=STEEL)  # vis
    cyl_between(b, (-0.20, 0.0, 1.08), (0.20, 0.0, 1.08), 0.012, 0.012, segments=6, mi=METAL)  # manette
    for x in (-0.20, 0.20):
        ico(b, (x, 0.0, 1.08), 0.03, mi=PAINT)
    press = b.finish(coll)
    col_box("Col_Press", (-0.30, -0.25, 0.0), (0.30, 0.25, 1.03), press)
    return press


def build_scale(coll):
    m = _m()
    b = MeshBuilder("Coke_Scale", [m["plastic"], m["steel"], m["display"]])
    PLASTIC, STEEL, DISPLAY = range(3)
    b.box((-0.125, -0.10, 0.0), (0.125, 0.10, 0.05), mi=PLASTIC)  # corps
    b.box((-0.10, -0.065, 0.05), (0.10, 0.095, 0.06), mi=STEEL)  # plateau
    b.box((-0.06, -0.10, 0.05), (0.06, -0.07, 0.075), mi=PLASTIC)  # bloc écran
    poly(b, ((-0.045, -0.095, 0.0755), (0.045, -0.095, 0.0755), (0.045, -0.075, 0.0755), (-0.045, -0.075, 0.0755)),
         DISPLAY)
    return b.finish(coll)


def builders():
    """(nom, fonction de build) pour build_props.py."""
    return [
        ("Coke_Table", build_table),
        ("Coke_Pile", build_pile),
        ("Coke_Bag", build_bag),
        ("Coke_Bags_Stack", build_bags_stack),
        ("Coke_Brick", build_brick),
        ("Coke_Bricks_Stack", build_bricks_stack),
        ("Coke_Press", build_press),
        ("Coke_Scale", build_scale),
    ]
