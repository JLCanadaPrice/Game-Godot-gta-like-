"""
Lot 2 drug_lab : props de culture à l'échelle du perso (S_HUMAN) : séchoir, table de tri,
bocal, lampe de culture. Géométrie en mètres réels, origine au sol (au point d'accroche
pour la lampe, qui pend vers le bas) ; l'échelle est appliquée par build_props.py.
"""

import random

from dl_common import MeshBuilder, col_box, cyl_between, ico, mat

# Plages de contrôle avant export (m ; axes Blender : x largeur, y profondeur, z hauteur)
EXPECT = {
    "Weed_DryingRack": {"x": (1.90, 2.10), "y": (0.50, 0.70), "z": (1.90, 2.10)},
    "Weed_TrimTable": {"x": (1.70, 1.90), "y": (0.80, 1.00), "z": (1.05, 1.18)},  # plateau 0,9 + bocaux
    "Weed_Jar": {"x": (0.10, 0.14), "y": (0.10, 0.14), "z": (0.19, 0.23)},  # Ø 0,114 : 0,108 entre plats (10 côtés)
    "Weed_GrowLamp": {"x": (1.15, 1.25), "y": (0.55, 0.65), "z": (0.55, 0.70)},
}


def _m():
    return dict(
        metal=mat("WD_Metal_Dark", (0.05, 0.05, 0.055), 0.6),
        wood=mat("WD_Wood", (0.30, 0.20, 0.10), 0.8),
        tray=mat("WD_Tray", (0.03, 0.03, 0.035), 0.6),
        bud=mat("WD_Bud", (0.14, 0.26, 0.06), 0.8),
        dried=mat("WD_Dried", (0.07, 0.08, 0.025), 0.9),
        string=mat("WD_String", (0.35, 0.33, 0.28), 0.9),
        glass=mat("WD_Glass", (0.30, 0.40, 0.40), 0.1),
        lid=mat("WD_Lid", (0.04, 0.04, 0.045), 0.5),
        label=mat("WD_Label", (0.60, 0.58, 0.50), 0.8),
        housing=mat("WD_Lamp_Housing", (0.10, 0.10, 0.11), 0.5),
        light=mat("WD_Grow_Light", (1.0, 0.55, 0.95), 0.5, emission=(1.0, 0.55, 0.95), strength=3.0),
    )


def _jar(b, x, y, z, glass, lid, label):
    """Bocal Ø 0,114 x 0,20 m posé en (x, y, z)."""
    cyl_between(b, (x, y, z), (x, y, z + 0.160), 0.055, 0.055, segments=10, mi=glass)
    cyl_between(b, (x, y, z + 0.160), (x, y, z + 0.175), 0.045, 0.045, segments=10, mi=glass)
    cyl_between(b, (x, y, z + 0.175), (x, y, z + 0.200), 0.050, 0.050, segments=10, mi=lid)
    cyl_between(b, (x, y, z + 0.050), (x, y, z + 0.110), 0.057, 0.057, segments=10, mi=label, cap=False)


def build_drying_rack(coll):
    m = _m()
    b = MeshBuilder("Weed_DryingRack", [m["metal"], m["dried"], m["string"]])
    METAL, DRIED, STRING = range(3)
    w, d, h, p = 2.0, 0.6, 2.0, 0.04
    for x in (-w / 2 + p / 2, w / 2 - p / 2):
        for y in (-d / 2 + p / 2, d / 2 - p / 2):
            b.box((x - p / 2, y - p / 2, 0.0), (x + p / 2, y + p / 2, h), mi=METAL)  # montants
        for zt in (0.08, 1.29, 1.89, h - p):  # traverses des extrémités
            b.box((x - p / 2, -d / 2, zt), (x + p / 2, d / 2, zt + p), mi=METAL)
    rng = random.Random(21)
    for z in (1.91, 1.31):
        for y in (-0.15, 0.15):
            b.box((-w / 2 + p, y - 0.01, z - 0.01), (w / 2 - p, y + 0.01, z + 0.01), mi=METAL)  # tringle
            for k in range(5):
                x = -0.75 + k * 0.375 + rng.uniform(-0.04, 0.04)
                knot = z - 0.01 - rng.uniform(0.04, 0.08)
                cyl_between(b, (x, y, z - 0.01), (x, y, knot), 0.003, 0.003, segments=3, mi=STRING)
                cyl_between(b, (x, y, knot - rng.uniform(0.28, 0.36)), (x, y, knot), 0.015, 0.075,
                            segments=6, mi=DRIED)  # grappe tête en bas
    rack = b.finish(coll)
    col_box("Col_DryingRack", (-w / 2, -d / 2, 0.0), (w / 2, d / 2, h), rack)
    return rack


def build_trim_table(coll):
    m = _m()
    b = MeshBuilder("Weed_TrimTable", [m["metal"], m["wood"], m["tray"], m["bud"], m["glass"], m["lid"], m["label"]])
    METAL, WOOD, TRAY, BUD, GLASS, LID, LABEL = range(7)
    w, d, h, t = 1.8, 0.9, 0.9, 0.04
    b.box((-w / 2, -d / 2, h - t), (w / 2, d / 2, h), mi=WOOD)  # plateau à 0,9 m
    for x in (-w / 2 + 0.06, w / 2 - 0.06):
        for y in (-d / 2 + 0.06, d / 2 - 0.06):
            b.box((x - 0.025, y - 0.025, 0.0), (x + 0.025, y + 0.025, h - t), mi=METAL)
    b.box((-w / 2 + 0.06, -d / 2 + 0.06, 0.15), (w / 2 - 0.06, d / 2 - 0.06, 0.17), mi=METAL)  # tablette basse
    b.box((-0.70, -0.25, h), (-0.10, 0.15, h + 0.03), mi=TRAY)  # bac de tri
    rng = random.Random(31)
    for _ in range(9):
        ico(b, (rng.uniform(-0.65, -0.15), rng.uniform(-0.20, 0.10), h + 0.04), rng.uniform(0.018, 0.026),
            scale=(1.0, 1.0, 0.7), rot_z=rng.uniform(0.0, 3.14), mi=BUD)
    for x in (0.15, 0.32, 0.49):
        for y in (-0.12, 0.10):
            _jar(b, x, y, h, GLASS, LID, LABEL)
    table = b.finish(coll)
    col_box("Col_TrimTable", (-w / 2, -d / 2, 0.0), (w / 2, d / 2, h), table)
    return table


def build_jar(coll):
    m = _m()
    b = MeshBuilder("Weed_Jar", [m["glass"], m["lid"], m["label"]])
    _jar(b, 0.0, 0.0, 0.0, 0, 1, 2)
    return b.finish(coll)


def build_grow_lamp(coll):
    m = _m()
    b = MeshBuilder("Weed_GrowLamp", [m["housing"], m["light"], m["metal"]])
    HOUSING, LIGHT, METAL = range(3)
    w, d, t, hang = 1.2, 0.6, 0.10, 0.50
    b.box((-w / 2, -d / 2, -hang - t), (w / 2, d / 2, -hang), mi=HOUSING)
    b.box((-w / 2 + 0.04, -d / 2 + 0.04, -hang - t - 0.01), (w / 2 - 0.04, d / 2 - 0.04, -hang - t), mi=LIGHT)
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            cyl_between(b, (sx * (w / 2 - 0.08), sy * (d / 2 - 0.08), -hang), (sx * 0.05, 0.0, -0.02),
                        0.004, 0.004, segments=3, mi=METAL)
    b.box((-0.08, -0.02, -0.02), (0.08, 0.02, 0.0), mi=METAL)  # barre d'accroche = origine
    return b.finish(coll)


def builders():
    """(nom, fonction de build) pour build_props.py."""
    return [
        ("Weed_DryingRack", build_drying_rack),
        ("Weed_TrimTable", build_trim_table),
        ("Weed_Jar", build_jar),
        ("Weed_GrowLamp", build_grow_lamp),
    ]
