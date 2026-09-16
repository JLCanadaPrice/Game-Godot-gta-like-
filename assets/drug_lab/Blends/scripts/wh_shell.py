"""
Entrepôt drug_lab : murs (ouvertures, collisions, sockets), sol, toit.

Coque x S_SHELL, porte piétonne x S_HUMAN (cf. dl_common). Origine commune : centre de
l'emprise, au sol. Façade principale côté -Y dans Blender (= +Z dans Godot).
"""

from dl_common import S_HUMAN, MeshBuilder, col_box, mat, socket
from dl_common import S_SHELL as S

# Plan x1 : emprise 16 x 24 m, épaisseur 0,25 m. Murs abaissés à 5,5 m plan (11 m) au lieu de 7 :
# le plus bas qui garde la grande porte de 9 m sous le plafond (9,4 m) avec un linteau.
W, D, H, T = 16.0 * S, 24.0 * S, 5.5 * S, 0.25 * S
FLOOR_TOP, FLOOR_BOTTOM, APRON = 0.05 * S, -0.15 * S, 0.30 * S
CEIL_Z, ROOF_TOP = 4.7 * S, 5.0 * S
CAP_H, CAP_OUT = 0.15 * S, 0.05 * S

LOADING_DOOR = dict(u=3.0 * S, w=4.0 * S, h=4.5 * S)
# Porte piétonne à l'échelle du perso, élargie à 1,2 m : la capsule du Player fait Ø 0,8 m
PED_DOOR = dict(u=-4.5 * S, w=1.2 * S_HUMAN, h=2.2 * S_HUMAN)
SIDE_WINDOWS_U = [c * S for c in (-9.0, -3.0, 3.0, 9.0)]
WINDOW_W, WINDOW_Z0, WINDOW_Z1 = 2.0 * S, 3.4 * S, 4.4 * S  # 6,8 -> 8,8 m, sous le plafond de 9,4 m

PILLARS = [(x * S, y * S) for x in (-4.0, 4.0) for y in (-4.0, 4.0)]
LIGHTS = [(x * S, y * S) for x in (-4.0, 4.0) for y in (-8.0, 0.0, 8.0)]


def _wall_boxes(span, height, openings):
    """Découpe un mur en boîtes (u0, u1, z0, z1) autour des ouvertures (u, w, z0, z1)."""
    boxes, cursor = [], span[0]
    for u, w, z0, z1 in sorted(openings):
        a, b = u - w / 2.0, u + w / 2.0
        if a > cursor:
            boxes.append((cursor, a, 0.0, height))
        if z0 > 0.0:
            boxes.append((a, b, 0.0, z0))
        if z1 < height:
            boxes.append((a, b, z1, height))
        cursor = b
    if span[1] > cursor:
        boxes.append((cursor, span[1], 0.0, height))
    return boxes


def _to3d(axis, u0, u1, v0, v1, z0, z1):
    if axis == 'x':
        return (u0, v0, z0), (u1, v1, z1)
    return (v0, u0, z0), (v1, u1, z1)


def build_walls(coll):
    mats = [
        mat("WH_Wall_Ext", (0.28, 0.24, 0.19), 0.8),
        mat("WH_Wall_Int", (0.30, 0.30, 0.29), 0.9),
        mat("WH_Trim", (0.06, 0.06, 0.065), 0.6),
        mat("WH_Glass", (0.05, 0.08, 0.10), 0.2),
    ]
    EXT, INT, TRIM, GLASS = range(4)
    b = MeshBuilder("Warehouse_Walls", mats)
    hw, hd = W / 2.0, D / 2.0
    windows = [(u, WINDOW_W, WINDOW_Z0, WINDOW_Z1) for u in SIDE_WINDOWS_U]
    walls = [
        # nom, axe u, (v0, v1) épaisseur, sens extérieur, (u0, u1), ouvertures
        ("Front", 'x', (-hd, -hd + T), -1, (-hw, hw),
         [(LOADING_DOOR["u"], LOADING_DOOR["w"], 0.0, LOADING_DOOR["h"]),
          (PED_DOOR["u"], PED_DOOR["w"], 0.0, PED_DOOR["h"])]),
        ("Back", 'x', (hd - T, hd), 1, (-hw, hw), []),
        ("Left", 'y', (-hw, -hw + T), -1, (-hd + T, hd - T), windows),
        ("Right", 'y', (hw - T, hw), 1, (-hd + T, hd - T), windows),
    ]

    col_boxes = []
    for name, axis, (v0, v1), sign, span, openings in walls:
        vi = 1 if axis == 'x' else 0
        outer, inner = (v0, v1) if sign < 0 else (v1, v0)

        def rule(f, vi=vi, sign=sign, outer=outer, inner=inner):
            n, c = f.normal, f.calc_center_median()
            if n[vi] * sign > 0.9 and abs(c[vi] - outer) < 1e-4:
                return EXT
            if n[vi] * sign < -0.9 and abs(c[vi] - inner) < 1e-4:
                return INT
            return TRIM

        for u0, u1, z0, z1 in _wall_boxes(span, H, openings):
            lo, hi = _to3d(axis, u0, u1, v0, v1, z0, z1)
            b.box(lo, hi, mat_fn=rule)
            if name == "Front":  # la façade garde ses ouvertures de porte franchissables
                col_boxes.append((name, lo, hi))
        if name != "Front":
            col_boxes.append((name, *_to3d(axis, span[0], span[1], v0, v1, 0.0, H)))

        vm = (v0 + v1) / 2.0
        for u, w, z0, z1 in openings:
            if z0 <= 0.0:
                continue  # porte : pas de vitre
            b.box(*_to3d(axis, u - w / 2, u + w / 2, vm - 0.02 * S, vm + 0.02 * S, z0, z1), mi=GLASS)
            b.box(*_to3d(axis, u - 0.04 * S, u + 0.04 * S, vm - 0.05 * S, vm + 0.05 * S, z0, z1), mi=TRIM)

        grow = CAP_OUT if axis == 'x' else -CAP_OUT  # façades débordent, pignons s'arrêtent entre elles
        b.box(*_to3d(axis, span[0] - grow, span[1] + grow, v0 - CAP_OUT, v1 + CAP_OUT, H, H + CAP_H), mi=TRIM)

    walls_obj = b.finish(coll)
    for i, (name, lo, hi) in enumerate(col_boxes):
        col_box("Col_Wall_%s_%02d" % (name, i), lo, hi, walls_obj)

    front_mid = -hd + T / 2.0
    socket("Socket_LoadingDoor", (LOADING_DOOR["u"], front_mid, FLOOR_TOP), walls_obj)
    socket("Socket_Door", (PED_DOOR["u"], front_mid, FLOOR_TOP), walls_obj)
    for i, (x, y) in enumerate(PILLARS, 1):
        socket("Socket_Pillar_%02d" % i, (x, y, FLOOR_TOP), walls_obj)
    for i, (x, y) in enumerate(LIGHTS, 1):
        socket("Socket_Light_%02d" % i, (x, y, CEIL_Z), walls_obj)
    return walls_obj


def build_floor(coll):
    concrete = mat("WH_Floor", (0.20, 0.20, 0.19), 0.9)
    yellow = mat("WH_Line_Yellow", (0.60, 0.42, 0.02), 0.7)
    b = MeshBuilder("Warehouse_Floor", [concrete, yellow])
    # Dalle + trottoir : déborde des murs (APRON) pour éviter les faces coplanaires avec eux
    lo = (-W / 2 - APRON, -D / 2 - APRON, FLOOR_BOTTOM)
    hi = (W / 2 + APRON, D / 2 + APRON, FLOOR_TOP)
    b.box(lo, hi, mi=0)

    # Zone de chargement peinte derrière la grande porte
    x0, x1 = LOADING_DOOR["u"] - 2.25 * S, LOADING_DOOR["u"] + 2.25 * S
    y0 = -D / 2 + T + 0.3 * S
    y1 = y0 + 5.0 * S
    lw, z0, z1 = 0.12 * S, FLOOR_TOP, FLOOR_TOP + 0.006 * S
    for a, c in (((x0, y0, z0), (x1, y0 + lw, z1)), ((x0, y1 - lw, z0), (x1, y1, z1)),
                 ((x0, y0 + lw, z0), (x0 + lw, y1 - lw, z1)), ((x1 - lw, y0 + lw, z0), (x1, y1 - lw, z1))):
        b.box(a, c, mi=1)

    floor = b.finish(coll)
    col_box("Col_Floor", lo, hi, floor)
    return floor


def build_roof(coll):
    mats = [
        mat("WH_Roof_Top", (0.04, 0.04, 0.045), 0.9),
        mat("WH_Ceiling", (0.12, 0.12, 0.12), 0.9),
        mat("WH_Metal", (0.18, 0.19, 0.20), 0.5),
    ]
    b = MeshBuilder("Warehouse_Roof", mats)
    b.box((-W / 2 + T, -D / 2 + T, CEIL_Z), (W / 2 - T, D / 2 - T, ROOF_TOP),
          mat_fn=lambda f: 0 if f.normal.z > 0.9 else 1)
    for x, y in ((-3.0 * S, 4.0 * S), (3.0 * S, -5.0 * S)):  # aérateurs de toit
        h = 0.6 * S
        b.box((x - 0.6 * S, y - 0.6 * S, ROOF_TOP), (x + 0.6 * S, y + 0.6 * S, ROOF_TOP + h), mi=2)
        b.box((x - 0.7 * S, y - 0.7 * S, ROOF_TOP + h), (x + 0.7 * S, y + 0.7 * S, ROOF_TOP + h + 0.1 * S), mi=2)
    return b.finish(coll)
