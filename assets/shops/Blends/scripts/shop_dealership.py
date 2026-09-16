"""
Concessionnaire « Liberty Motors » : showroom d'angle façon concession US (CarMax / Ford), échelle réelle.

Site mesuré dans World.tscn (repère de l'ancien Building_Medium_2_001_102) : voisin gauche à X -8,3,
bâtiment d'angle arrière à Y +9,7, trottoir de la rue principale à Y -7,0 et trottoir de la rue
transversale à X +13,8 (dessus à 0,408 m). Le bâtiment d'angle Building_Small_1_152, qui chevauchait
l'ancien lot sur 9 x 10 m, est retiré de la carte pour laisser place au showroom.

Showroom 18,5 x 14,4 m, plafond à 5,2 m : baies vitrées sur les deux rues, bandeau de marque bleu,
portail d'entrée plus haut que l'acrotère avec auvent, pylône d'enseigne à 45° au coin, deux podiums
de voitures, comptoir au fond devant un mur de marque. Toit (dalle + groupes de clim) exporté à part.
"""

import math

from mathutils import Matrix

import dl_common as dl
import shop_common as sc
from dl_common import MeshBuilder, col_box, socket
from shop_common import FLOOR_Z, T

X0, X1 = -8.0, 10.5           # emprise du bâtiment
Y0, Y1 = -5.0, 9.4            # façade vitrée (rue principale) / mur du fond
FORE_Y, FORE_X = -6.95, 13.75  # parvis jusqu'aux trottoirs
LOT = {"x": (-8.3, 13.8), "y": (-7.0, 9.7)}
CEIL = FLOOR_Z + 5.2
ROOF_T = 0.30
PARAPET = FLOOR_Z + 6.2
SILL = FLOOR_Z + 0.30
GLASS_TOP = FLOOR_Z + 4.2
DOOR_X, DOOR_W, DOOR_H = 1.25, 2.40, 2.60   # portes coulissantes ouvertes
PORTAL_HALF, BLADE_W, BLADE_D = 1.9, 0.35, 1.2
PORTAL_TOP = FLOOR_Z + 7.2
CANOPY_Z0, CANOPY_Z1, CANOPY_D = FLOOR_Z + 3.0, FLOOR_Z + 3.2, 1.8
PYLON = (12.3, -5.7)
MULLION_STEP = 2.3
CARS = [(-3.0, 1.2, -30.0), (6.0, 1.8, 25.0)]   # x, y, cap : le .glb posé sur le repère a l'avant vers la rue
COUNTER = (-4.0, 7.6)
DELIVERY = (12.2, 2.6, 180.0)                   # parvis latéral, avant vers la rue principale
LIGHTS = [(-3.0, 2.0), (5.5, 2.0), (-3.5, 7.0), (5.5, 7.0)]
FLOOR, CONC, EXT, INT, BLUE, ALU, GLASS, SIGN, DARK, LIGHT = range(10)


def _mats():
    return [
        dl.mat("SH_Floor_Tile", (0.62, 0.63, 0.64), 0.15),
        dl.mat("SH_Concrete", (0.36, 0.36, 0.34), 0.9),
        dl.mat("DL_Panel_Ext", (0.72, 0.73, 0.74), 0.6),
        dl.mat("DL_Wall_Int", (0.80, 0.80, 0.78), 0.9),
        dl.mat("DL_Brand_Blue", (0.02, 0.10, 0.42), 0.4),
        dl.mat("SH_Aluminum", (0.55, 0.57, 0.60), 0.35, metallic=0.8),
        sc.glass("SH_Glass", (0.45, 0.60, 0.70), 0.28),
        dl.mat("DL_Sign_White", (0.95, 0.95, 0.95), 0.4, emission=(0.90, 0.92, 1.0), strength=1.5),
        dl.mat("SH_Trim_Dark", (0.05, 0.05, 0.06), 0.6),
        dl.mat("DL_Canopy_Light", (0.90, 0.90, 0.85), 0.5, emission=(1.0, 0.95, 0.85), strength=2.0),
    ]


def _rule(ext, inner):
    """Face intérieure (dans l'emprise, tournée vers le centre) -> inner ; le reste -> ext."""
    cx, cy = (X0 + X1) / 2.0, (Y0 + Y1) / 2.0

    def fn(f):
        c, n = f.calc_center_median(), f.normal
        inside = X0 + T - 1e-3 <= c.x <= X1 - T + 1e-3 and Y0 + T - 1e-3 <= c.y <= Y1 - T + 1e-3
        toward = n.x * (cx - c.x) + n.y * (cy - c.y) > 0.0
        return inner if inside and abs(n.z) < 0.5 and toward else ext
    return fn


def _glass_wall(b, axis, u0, u1, v0, v1, openings):
    """Allège alu, baies vitrées, meneaux, imposte au-dessus des portes, bandeau bleu jusqu'à l'acrotère."""
    vm = (v0 + v1) / 2.0
    for a, c, z0, z1 in sc.split_span(u0, u1, 0.0, SILL, [(o[0], o[1], 0.0, SILL + 1.0) for o in openings]):
        b.box(*sc.along(axis, a, c, v0, v1, z0, z1), mi=ALU)
    for a, c, z0, z1 in sc.split_span(u0, u1, SILL, GLASS_TOP, [(o[0], o[1], SILL - 1.0, o[3]) for o in openings]):
        b.box(*sc.along(axis, a, c, vm - 0.03, vm + 0.03, z0, z1), mi=GLASS)
    n = max(1, round((u1 - u0) / MULLION_STEP))
    posts = [u0 + (u1 - u0) * k / n for k in range(n + 1)]
    for o in openings:
        posts = [p for p in posts if abs(p - o[0]) > o[1] / 2.0 + 0.3] + [o[0] - o[1] / 2.0, o[0] + o[1] / 2.0]
        b.box(*sc.along(axis, o[0] - o[1] / 2.0, o[0] + o[1] / 2.0, v0 + 0.05, v1 - 0.05, o[3], o[3] + 0.12), mi=ALU)
        for sgn in (-1, 1):  # vantaux coulissants rangés derrière les baies fixes
            lo_u, hi_u = sorted((o[0] + sgn * o[1] / 2.0, o[0] + sgn * o[1]))
            b.box(*sc.along(axis, lo_u, hi_u, v1 + 0.04, v1 + 0.08, FLOOR_Z, o[3]), mi=GLASS)
    for p in posts:
        b.box(*sc.along(axis, p - 0.05, p + 0.05, v0 + 0.05, v1 - 0.05, SILL, GLASS_TOP), mi=ALU)
    b.box(*sc.along(axis, u0, u1, v0, v1, GLASS_TOP, PARAPET), mat_fn=_rule(BLUE, INT))


def build_shell(coll):
    b = MeshBuilder("Dealership_Shell", _mats())
    b.box((X0, Y0, 0.0), (X1, Y1, FLOOR_Z), mat_fn=lambda f: FLOOR if f.normal.z > 0.9 else CONC)
    b.box((X0, FORE_Y, 0.0), (FORE_X, Y0, FLOOR_Z), mi=CONC)
    b.box((X1, Y0, 0.0), (FORE_X, Y1, FLOOR_Z), mi=CONC)
    b.box((X0, Y0, 0.0), (X0 + T, Y1, PARAPET), mat_fn=_rule(EXT, INT))
    b.box((X0 + T, Y1 - T, 0.0), (X1, Y1, PARAPET), mat_fn=_rule(EXT, INT))
    _glass_wall(b, 'x', X0 + T, X1 - T, Y0, Y0 + T, [(DOOR_X, DOOR_W, FLOOR_Z, FLOOR_Z + DOOR_H)])
    _glass_wall(b, 'y', Y0 + T, Y1 - T, X1 - T, X1, [])
    b.box((X1 - T, Y0, 0.0), (X1, Y0 + T, PARAPET), mi=ALU)  # poteau d'angle

    for sgn in (-1, 1):  # portail d'entrée + auvent
        x = DOOR_X + sgn * PORTAL_HALF
        b.box((x - BLADE_W / 2, Y0 - BLADE_D, 0.0), (x + BLADE_W / 2, Y0, PORTAL_TOP), mi=BLUE)
    hx = PORTAL_HALF + BLADE_W / 2
    b.box((DOOR_X - hx, Y0 - BLADE_D, PORTAL_TOP - 0.8), (DOOR_X + hx, Y0, PORTAL_TOP), mi=BLUE)
    b.box((DOOR_X - PORTAL_HALF + BLADE_W / 2, Y0 - CANOPY_D, CANOPY_Z0), (DOOR_X + PORTAL_HALF - BLADE_W / 2, Y0, CANOPY_Z1),
          mat_fn=lambda f: LIGHT if f.normal.z < -0.9 else BLUE)

    zc = (GLASS_TOP + PARAPET) / 2.0
    sc.add_text(b, "LIBERTY MOTORS", 2 * PORTAL_HALF - 0.2, 0.5, sc.facing((DOOR_X, Y0 - BLADE_D, PORTAL_TOP - 0.4), '-Y'), SIGN)
    sc.add_text(b, "NEW & PRE-OWNED", 5.6, 0.55, sc.facing(((X0 + T + DOOR_X - hx) / 2.0, Y0, zc), '-Y'), SIGN)
    sc.add_text(b, "SALES - SERVICE", 5.6, 0.55, sc.facing(((DOOR_X + hx + X1) / 2.0, Y0, zc), '-Y'), SIGN)
    sc.add_text(b, "LIBERTY MOTORS", 11.0, 0.9, sc.facing((X1, (Y0 + Y1) / 2.0, zc), '+X'), SIGN)

    rot = Matrix.Translation((PYLON[0], PYLON[1], 0.0)) @ Matrix.Rotation(math.radians(45.0), 4, 'Z')
    dl.box_m(b, rot @ Matrix.Translation((0.0, 0.0, FLOOR_Z + 0.15)), (1.0, 1.0, 0.3), mi=CONC)
    dl.box_m(b, rot @ Matrix.Translation((0.0, 0.0, FLOOR_Z + 2.85)), (0.35, 0.35, 5.1), mi=ALU)
    dl.box_m(b, rot @ Matrix.Translation((0.0, 0.0, FLOOR_Z + 6.4)), (3.0, 0.45, 2.0), mi=BLUE)
    for line, dz in (("LIBERTY", 0.45), ("MOTORS", -0.45)):
        for turn, dy in ((0.0, -0.225), (180.0, 0.225)):
            face = (rot @ Matrix.Translation((0.0, dy, FLOOR_Z + 6.4 + dz)) @ Matrix.Rotation(math.radians(turn), 4, 'Z')
                    @ Matrix.Rotation(math.radians(90.0), 4, 'X'))
            sc.add_text(b, line, 2.6, 0.6, face, SIGN)

    b.box((X0 + T + 0.5, Y1 - T - 0.04, FLOOR_Z), (X0 + T + 6.5, Y1 - T, CEIL), mi=BLUE)  # mur de marque
    sc.add_text(b, "LIBERTY MOTORS", 5.2, 0.45, sc.facing((X0 + T + 3.5, Y1 - T - 0.04, FLOOR_Z + 3.3), '-Y'), SIGN)
    for cx, cy, _yaw in CARS:  # podiums
        b.cone((cx, cy, FLOOR_Z), 3.0, 3.0, 0.02, segments=24, mi=DARK)
    shell = b.finish(coll)

    front_l, front_r = DOOR_X - DOOR_W / 2.0, DOOR_X + DOOR_W / 2.0
    cols = {
        "Col_Floor": ((X0, FORE_Y, 0.0), (FORE_X, Y1, FLOOR_Z)),
        "Col_Wall_Left": ((X0, Y0, FLOOR_Z), (X0 + T, Y1, PARAPET)),
        "Col_Wall_Back": ((X0 + T, Y1 - T, FLOOR_Z), (X1, Y1, PARAPET)),
        "Col_Wall_Right": ((X1 - T, Y0, FLOOR_Z), (X1, Y1 - T, PARAPET)),
        "Col_Wall_Front_L": ((X0 + T, Y0, FLOOR_Z), (front_l, Y0 + T, PARAPET)),
        "Col_Wall_Front_R": ((front_r, Y0, FLOOR_Z), (X1 - T, Y0 + T, PARAPET)),
        "Col_Wall_Front_Top": ((front_l, Y0, FLOOR_Z + DOOR_H), (front_r, Y0 + T, PARAPET)),
        "Col_Portal_L": ((DOOR_X - hx, Y0 - BLADE_D, FLOOR_Z), (DOOR_X - PORTAL_HALF + BLADE_W / 2, Y0, PORTAL_TOP)),
        "Col_Portal_R": ((DOOR_X + PORTAL_HALF - BLADE_W / 2, Y0 - BLADE_D, FLOOR_Z), (DOOR_X + hx, Y0, PORTAL_TOP)),
        "Col_Pylon": ((PYLON[0] - 0.75, PYLON[1] - 0.75, FLOOR_Z), (PYLON[0] + 0.75, PYLON[1] + 0.75, FLOOR_Z + 2.0)),
    }
    tag = "Dealership"  # collisions et repères portent les mêmes noms que ceux de l'agence : « @tag » retiré à l'export
    for name, (lo, hi) in cols.items():
        col_box(name, lo, hi, shell, tag=tag)
    sc.rotated_socket("Socket_Counter", (COUNTER[0], COUNTER[1], FLOOR_Z), shell, 0.0, tag)
    for i, (cx, cy, yaw) in enumerate(CARS, 1):
        sc.rotated_socket("Socket_Car_%d" % i, (cx, cy, FLOOR_Z), shell, yaw, tag)
    sc.rotated_socket("Socket_Delivery", (DELIVERY[0], DELIVERY[1], FLOOR_Z), shell, DELIVERY[2], tag)
    socket("Socket_DoorOutside", (DOOR_X, FORE_Y + 0.7, FLOOR_Z), shell, tag)
    socket("Socket_DoorInside", (DOOR_X, Y0 + 2.2, FLOOR_Z), shell, tag)
    socket("Socket_InteriorMin", (X0 + T, Y0 + T, FLOOR_Z), shell, tag)
    socket("Socket_InteriorMax", (X1 - T, Y1 - T, CEIL), shell, tag)
    for i, (lx, ly) in enumerate(LIGHTS, 1):
        socket("Socket_Light_%d" % i, (lx, ly, CEIL - 0.5), shell, tag)
    return shell


def build_roof(coll):
    b = MeshBuilder("Dealership_Roof", [dl.mat("SH_Ceiling", (0.85, 0.85, 0.83), 0.9),
                                        dl.mat("SH_Roof_Membrane", (0.30, 0.30, 0.31), 0.95),
                                        dl.mat("SH_HVAC", (0.55, 0.56, 0.56), 0.6)])
    b.box((X0 + T, Y0 + T, CEIL), (X1 - T, Y1 - T, CEIL + ROOF_T), mat_fn=lambda f: 0 if f.normal.z < -0.9 else 1)
    for hx, hy in ((-2.0, 4.0), (4.0, 5.5)):
        b.box((hx - 1.0, hy - 0.7, CEIL + ROOF_T), (hx + 1.0, hy + 0.7, CEIL + ROOF_T + 1.1), mi=2)
    return b.finish(coll)
