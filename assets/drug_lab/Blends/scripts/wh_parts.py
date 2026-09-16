"""
Entrepôt drug_lab : pièces à instancier aux sockets de Warehouse_Walls
(pilier, lampe suspendue, grande porte de chargement, porte piétonne).

Origine de chaque pièce = son point d'ancrage : base au niveau du sol fini,
ou point de fixation au plafond pour la lampe (elle pend vers le bas).
"""

from dl_common import S_HUMAN, MeshBuilder, col_box, mat
from dl_common import S_SHELL as S  # pilier, lampe, grande porte : coque ; porte piétonne : S_HUMAN
from wh_shell import CEIL_Z, FLOOR_TOP, LOADING_DOOR, PED_DOOR


def _trim():
    return mat("WH_Trim", (0.06, 0.06, 0.065), 0.6)


def build_pillar(coll):
    concrete = mat("WH_Pillar", (0.25, 0.25, 0.24), 0.9)
    yellow = mat("WH_Line_Yellow", (0.60, 0.42, 0.02), 0.7)
    b = MeshBuilder("Warehouse_Pillar", [concrete, yellow, _trim()])
    h = CEIL_Z - FLOOR_TOP

    def square(half, z0, z1, mi):
        b.box((-half, -half, z0), (half, half, z1), mi=mi)

    square(0.300 * S, 0.0, 0.08 * S, 2)          # platine
    square(0.200 * S, 0.0, h, 0)                 # fût 0,4 x 0,4 (plan)
    square(0.275 * S, h - 0.12 * S, h, 2)        # chapiteau
    square(0.210 * S, 0.15 * S, 1.10 * S, 1)     # bande de sécurité jaune
    square(0.215 * S, 0.55 * S, 0.70 * S, 2)     # bande noire
    pillar = b.finish(coll)
    col_box("Col_Pillar", (-0.30 * S, -0.30 * S, 0.0), (0.30 * S, 0.30 * S, h), pillar)
    return pillar


def build_ceiling_light(coll):
    shade = mat("WH_Lamp_Shade", (0.02, 0.06, 0.035), 0.4)
    light = mat("WH_Lamp_Light", (1.0, 0.85, 0.6), 0.5, emission=(1.0, 0.8, 0.55), strength=4.0)
    b = MeshBuilder("Warehouse_CeilingLight", [shade, light, _trim()])
    b.cone((0, 0, -0.04 * S), 0.10 * S, 0.10 * S, 0.04 * S, segments=8, mi=2)     # rosace au plafond
    b.box((-0.015 * S, -0.015 * S, -1.04 * S), (0.015 * S, 0.015 * S, -0.04 * S), mi=2)  # câble
    b.cone((0, 0, -1.16 * S), 0.08 * S, 0.08 * S, 0.12 * S, segments=8, mi=2)     # douille
    b.cone((0, 0, -1.51 * S), 0.30 * S, 0.10 * S, 0.35 * S, segments=12, mi=0)    # abat-jour Ø 0,6 (plan)
    b.cone((0, 0, -1.52 * S), 0.27 * S, 0.27 * S, 0.01 * S, segments=12, mi=1)    # disque émissif
    return b.finish(coll)


def build_loading_door(coll):
    rust = mat("WH_Door_Rust", (0.28, 0.07, 0.03), 0.6)
    rust_dark = mat("WH_Door_Rust_Dark", (0.18, 0.045, 0.02), 0.6)
    b = MeshBuilder("Warehouse_LoadingDoor", [rust, rust_dark, _trim()])
    w, h = LOADING_DOOR["w"], LOADING_DOOR["h"] - FLOOR_TOP
    b.box((-w / 2, -0.05 * S, 0.05 * S), (w / 2, 0.05 * S, h), mi=0)       # tablier
    b.box((-w / 2, -0.06 * S, 0.0), (w / 2, 0.06 * S, 0.05 * S), mi=2)     # joint bas
    for k in range(1, 6):                                                # nervures entre sections
        zc = h * k / 6.0
        b.box((-w / 2 + 0.05 * S, -0.07 * S, zc - 0.03 * S), (w / 2 - 0.05 * S, 0.07 * S, zc + 0.03 * S), mi=1)
    door = b.finish(coll)
    col_box("Col_LoadingDoor", (-w / 2, -0.07 * S, 0.0), (w / 2, 0.07 * S, h), door)
    return door


def build_door(coll):
    S = S_HUMAN  # porte piétonne : cadre, battant et poignée à l'échelle du perso
    steel = mat("WH_Door_Steel", (0.05, 0.07, 0.09), 0.5)
    metal = mat("WH_Metal", (0.18, 0.19, 0.20), 0.5)
    w, h = PED_DOOR["w"], PED_DOOR["h"] - FLOOR_TOP
    jamb, depth = 0.06 * S, 0.09 * S

    f = MeshBuilder("Warehouse_Door", [_trim()])
    f.box((-w / 2, -depth, 0.0), (-w / 2 + jamb, depth, h))
    f.box((w / 2 - jamb, -depth, 0.0), (w / 2, depth, h))
    f.box((-w / 2 + jamb, -depth, h - jamb), (w / 2 - jamb, depth, h))
    frame = f.finish(coll)

    gap = 0.005 * S
    leaf_w = w - 2 * jamb - 2 * gap
    leaf_h = h - jamb - gap - 0.01 * S
    lb = MeshBuilder("Door_Leaf", [steel, metal])
    lb.box((0.0, -0.03 * S, 0.01 * S), (leaf_w, 0.03 * S, 0.01 * S + leaf_h), mi=0)
    lb.box((leaf_w - 0.20 * S, -0.06 * S, 0.98 * S), (leaf_w - 0.08 * S, 0.06 * S, 1.02 * S), mi=1)  # poignée
    leaf = lb.finish(coll, frame)
    leaf.location = (-w / 2 + jamb + gap, 0.0, 0.0)  # origine du battant = axe des gonds (rotation en Z)
    col_box("Col_DoorLeaf", (0.0, -0.03 * S, 0.0), (leaf_w, 0.03 * S, leaf_h), leaf)
    return frame
