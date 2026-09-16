"""
Agence immobilière « City Realty » : devanture de bureau de centre-ville / strip mall US, échelle réelle.

Site mesuré dans World.tscn (repère de l'ancien Building_Small_1_154) : voisins à X ±7,0, trottoir à
Y -7,8 (dessus à 0,408 m), ancien fond à Y +7,3. Bureau de plain-pied 13 x 12,5 m, plafond à 3,4 m,
fausse façade en brique jusqu'à 5,8 m : allège brique, vitrines alu avec panneaux d'annonces (maisons),
porte vitrée décalée à droite, bandeau vert à lettres dorées, store banne bordeaux, chevalet « OPEN
HOUSE » sur le parvis. Intérieur : comptoir au fond (repère), panneau d'annonces, chaises d'attente.
Toit (dalle + clim) exporté à part.
"""

import math

from mathutils import Matrix

import dl_common as dl
import shop_common as sc
from dl_common import MeshBuilder, col_box, socket
from shop_common import FLOOR_Z, T

X0, X1 = -6.5, 6.5
Y0, Y1 = -6.0, 6.5
FORE_Y = -7.75
LOT = {"x": (-6.8, 6.8), "y": (-7.8, 7.3)}
CEIL = FLOOR_Z + 3.4
ROOF_T = 0.25
PARAPET = FLOOR_Z + 4.1
FRONT_TOP = FLOOR_Z + 5.8
BULK, WIN_TOP = FLOOR_Z + 0.55, FLOOR_Z + 2.5
SIGN_Z0, SIGN_Z1 = FLOOR_Z + 2.85, FLOOR_Z + 3.95
DOOR_X, DOOR_W, DOOR_H = 3.6, 1.30, 2.30
PIL = 0.6
COUNTER = (-1.5, 4.9)
LIGHTS = [(-2.5, 0.0), (2.5, 0.0), (0.0, 4.0)]
BOARD_X = [-5.1, -4.3, -3.5, -2.2, -1.4, -0.6, 0.8, 1.6, 2.4]
BOARD_Z = [FLOOR_Z + 1.15, FLOOR_Z + 1.95]
(CARPET, CONC, BRICK, INT, GREEN, ALU, GLASS, GOLD, AWN, WHITE, BLUE, RED, CORK, DARK, CHAIR) = range(15)


def _mats():
    return [
        dl.mat("AG_Carpet", (0.22, 0.25, 0.30), 0.95),
        dl.mat("SH_Concrete", (0.36, 0.36, 0.34), 0.9),
        dl.mat("AG_Brick", (0.42, 0.18, 0.12), 0.9),
        dl.mat("AG_Wall_Int", (0.78, 0.74, 0.66), 0.9),
        dl.mat("AG_Sign_Green", (0.02, 0.20, 0.10), 0.5),
        dl.mat("SH_Aluminum", (0.55, 0.57, 0.60), 0.35, metallic=0.8),
        sc.glass("SH_Glass", (0.45, 0.60, 0.70), 0.28),
        dl.mat("AG_Letters_Gold", (0.85, 0.65, 0.20), 0.3, metallic=0.6, emission=(0.85, 0.65, 0.2), strength=0.6),
        dl.mat("AG_Awning", (0.40, 0.03, 0.05), 0.8),
        dl.mat("AG_Board_White", (0.92, 0.92, 0.90), 0.7),
        dl.mat("AG_House_Blue", (0.10, 0.30, 0.65), 0.6),
        dl.mat("AG_House_Red", (0.65, 0.12, 0.08), 0.6),
        dl.mat("AG_Cork", (0.45, 0.30, 0.16), 0.9),
        dl.mat("SH_Trim_Dark", (0.05, 0.05, 0.06), 0.6),
        dl.mat("AG_Chair", (0.12, 0.12, 0.14), 0.7),
    ]


def _rule(ext, inner):
    cx, cy = (X0 + X1) / 2.0, (Y0 + Y1) / 2.0

    def fn(f):
        c, n = f.calc_center_median(), f.normal
        inside = X0 + T - 1e-3 <= c.x <= X1 - T + 1e-3 and Y0 + T - 1e-3 <= c.y <= Y1 - T + 1e-3
        return inner if inside and abs(n.z) < 0.5 and n.x * (cx - c.x) + n.y * (cy - c.y) > 0.0 else ext
    return fn


def _house(b, x, z, mi):
    """Annonce : panneau blanc, maison stylisée (corps + toit triangulaire) et bandeau prix, face -Y."""
    y = Y0 + T + 0.25
    b.box((x - 0.275, y - 0.02, z - 0.35), (x + 0.275, y, z + 0.35), mi=WHITE)
    b.box((x - 0.14, y - 0.04, z - 0.22), (x + 0.14, y - 0.02, z + 0.02), mi=mi)
    dl.poly(b, [(x - 0.19, y - 0.04, z + 0.02), (x + 0.19, y - 0.04, z + 0.02), (x, y - 0.04, z + 0.20)], mi=mi)
    b.box((x - 0.20, y - 0.03, z - 0.31), (x + 0.20, y - 0.02, z - 0.26), mi=DARK)


def build_shell(coll):
    b = MeshBuilder("Agency_Shell", _mats())
    wall = _rule(BRICK, INT)
    b.box((X0, Y0, 0.0), (X1, Y1, FLOOR_Z), mat_fn=lambda f: CARPET if f.normal.z > 0.9 else CONC)
    b.box((X0, FORE_Y, 0.0), (X1, Y0, FLOOR_Z), mi=CONC)
    b.box((X0, Y0 + T, 0.0), (X0 + T, Y1, PARAPET), mat_fn=wall)
    b.box((X1 - T, Y0 + T, 0.0), (X1, Y1, PARAPET), mat_fn=wall)
    b.box((X0 + T, Y1 - T, 0.0), (X1 - T, Y1, PARAPET), mat_fn=wall)

    u0, u1, vm = X0 + PIL, X1 - PIL, Y0 + T / 2.0
    for xa, xb in ((X0, u0), (u1, X1)):  # pilastres
        b.box((xa, Y0, 0.0), (xb, Y0 + T, FRONT_TOP - 0.2), mi=BRICK)
    for a, c, z0, z1 in sc.split_span(u0, u1, 0.0, BULK, [(DOOR_X, DOOR_W, 0.0, BULK + 1.0)]):
        b.box((a, Y0, z0), (c, Y0 + T, z1), mat_fn=wall)
    for a, c, z0, z1 in sc.split_span(u0, u1, BULK, WIN_TOP, [(DOOR_X, DOOR_W, BULK - 1.0, FLOOR_Z + DOOR_H)]):
        b.box((a, vm - 0.03, z0), (c, vm + 0.03, z1), mi=GLASS)
    for p in (u0, -3.0, 0.0, DOOR_X - DOOR_W / 2.0, DOOR_X + DOOR_W / 2.0, u1):
        z0 = FLOOR_Z if abs(abs(p - DOOR_X) - DOOR_W / 2.0) < 1e-6 else BULK
        b.box((p - 0.05, Y0 + 0.05, z0), (p + 0.05, Y0 + T - 0.05, WIN_TOP), mi=ALU)
    b.box((u0, Y0 + 0.05, WIN_TOP), (u1, Y0 + T - 0.05, WIN_TOP + 0.08), mi=ALU)
    b.box((DOOR_X - DOOR_W / 2.0, Y0 + 0.05, FLOOR_Z + DOOR_H), (DOOR_X + DOOR_W / 2.0, Y0 + T - 0.05, FLOOR_Z + DOOR_H + 0.08), mi=ALU)
    hinge = DOOR_X + DOOR_W / 2.0 - 0.08  # vantail vitré ouvert vers l'intérieur, rabattu contre la vitrine
    b.box((hinge - 0.03, Y0 + T + 0.02, FLOOR_Z + 0.02), (hinge + 0.03, Y0 + T + 1.24, FLOOR_Z + DOOR_H - 0.05), mi=GLASS)
    for z0 in (FLOOR_Z + 0.02, FLOOR_Z + DOOR_H - 0.15):
        b.box((hinge - 0.04, Y0 + T + 0.02, z0), (hinge + 0.04, Y0 + T + 1.24, z0 + 0.1), mi=ALU)

    b.box((u0, Y0, WIN_TOP + 0.08), (u1, Y0 + T, SIGN_Z0), mat_fn=_rule(DARK, INT))
    b.box((u0, Y0 - 0.06, SIGN_Z0), (u1, Y0 + T, SIGN_Z1), mat_fn=_rule(GREEN, INT))
    sc.add_text(b, "CITY REALTY", 8.5, 0.7, sc.facing((0.0, Y0 - 0.06, (SIGN_Z0 + SIGN_Z1) / 2.0), '-Y'), GOLD)
    b.box((u0 - 0.05, Y0 - 0.12, SIGN_Z1), (u1 + 0.05, Y0 + 0.05, SIGN_Z1 + 0.1), mi=DARK)
    b.box((u0, Y0, SIGN_Z1), (u1, Y0 + T, FRONT_TOP - 0.2), mi=BRICK)
    b.box((X0 - 0.1, Y0 - 0.25, FRONT_TOP - 0.2), (X1 + 0.1, Y0 + T + 0.05, FRONT_TOP), mi=DARK)
    sc.add_text(b, "EST. 1962", 2.0, 0.28, sc.facing((0.0, Y0, FRONT_TOP - 0.75), '-Y'), GOLD)

    slope = math.atan2(0.4, 1.4)  # store banne : 1,4 m de saillie, 40 cm de pente
    dl.box_m(b, Matrix.Translation((0.0, Y0 - 0.7, SIGN_Z0 - 0.28)) @ Matrix.Rotation(slope, 4, 'X'), (11.6, 1.46, 0.05), mi=AWN)
    b.box((-5.8, Y0 - 1.45, FLOOR_Z + 2.17), (5.8, Y0 - 1.38, FLOOR_Z + 2.39), mi=AWN)
    b.box((-5.8, Y0 - 1.46, FLOOR_Z + 2.11), (5.8, Y0 - 1.37, FLOOR_Z + 2.17), mi=WHITE)

    for i, x in enumerate(BOARD_X):  # annonces derrière les vitrines
        for j, z in enumerate(BOARD_Z):
            _house(b, x, z, BLUE if (i + j) % 2 == 0 else RED)
    for xa, xb in ((-5.45, -3.15), (-2.55, -0.25), (0.45, 2.75)):
        b.box((xa, Y0 + T + 0.22, BOARD_Z[1] + 0.40), (xb, Y0 + T + 0.26, BOARD_Z[1] + 0.44), mi=ALU)

    for tilt, dy in ((-12.0, -0.09), (12.0, 0.09)):  # chevalet « OPEN HOUSE »
        panel = Matrix.Translation((2.0, -7.15 + dy, FLOOR_Z + 0.42)) @ Matrix.Rotation(math.radians(tilt), 4, 'X')
        dl.box_m(b, panel, (0.6, 0.03, 0.85), mi=WHITE)
        if tilt < 0.0:
            for word, dz in (("OPEN", 0.12), ("HOUSE", -0.1)):
                sc.add_text(b, word, 0.5, 0.17, panel @ Matrix.Translation((0.0, -0.016, dz)) @ Matrix.Rotation(math.radians(90), 4, 'X'), RED, depth=0.01)

    yb = Y1 - T
    b.box((-5.0, yb - 0.05, FLOOR_Z + 1.0), (1.0, yb, FLOOR_Z + 2.3), mi=CORK)  # panneau d'annonces intérieur
    for x in [-4.5 + 0.8 * k for k in range(7)]:
        for z in (1.3, 1.65, 2.0):
            b.box((x - 0.15, yb - 0.06, FLOOR_Z + z - 0.14), (x + 0.15, yb - 0.05, FLOOR_Z + z + 0.14), mi=WHITE)
    sc.add_text(b, "FIND YOUR HOME", 5.0, 0.35, sc.facing((-2.0, yb, FLOOR_Z + 2.7), '-Y'), GREEN)
    for y in (-3.1, -2.5):  # chaises d'attente, dos au mur droit
        b.box((5.15, y - 0.25, FLOOR_Z + 0.42), (5.65, y + 0.25, FLOOR_Z + 0.48), mi=CHAIR)
        b.box((5.60, y - 0.25, FLOOR_Z + 0.48), (5.68, y + 0.25, FLOOR_Z + 0.95), mi=CHAIR)
        for lx in (5.2, 5.6):
            for ly in (y - 0.2, y + 0.2):
                b.box((lx - 0.02, ly - 0.02, FLOOR_Z), (lx + 0.02, ly + 0.02, FLOOR_Z + 0.42), mi=CHAIR)
    shell = b.finish(coll)

    front_l, front_r = DOOR_X - DOOR_W / 2.0, DOOR_X + DOOR_W / 2.0
    cols = {
        "Col_Floor": ((X0, FORE_Y, 0.0), (X1, Y1, FLOOR_Z)),
        "Col_Wall_Left": ((X0, Y0 + T, FLOOR_Z), (X0 + T, Y1, PARAPET)),
        "Col_Wall_Right": ((X1 - T, Y0 + T, FLOOR_Z), (X1, Y1, PARAPET)),
        "Col_Wall_Back": ((X0 + T, Y1 - T, FLOOR_Z), (X1 - T, Y1, PARAPET)),
        "Col_Wall_Front_L": ((X0, Y0, FLOOR_Z), (front_l, Y0 + T, FRONT_TOP)),
        "Col_Wall_Front_R": ((front_r, Y0, FLOOR_Z), (X1, Y0 + T, FRONT_TOP)),
        "Col_Wall_Front_Top": ((front_l, Y0, FLOOR_Z + DOOR_H), (front_r, Y0 + T, FRONT_TOP)),
        "Col_AFrame": ((1.65, -7.45, FLOOR_Z), (2.35, -6.85, FLOOR_Z + 0.9)),
        "Col_Chairs": ((5.1, -3.4, FLOOR_Z), (5.7, -2.2, FLOOR_Z + 0.95)),
    }
    tag = "Agency"  # mêmes noms que les collisions et repères du concessionnaire : « @tag » retiré à l'export
    for name, (lo, hi) in cols.items():
        col_box(name, lo, hi, shell, tag=tag)
    sc.rotated_socket("Socket_Counter", (COUNTER[0], COUNTER[1], FLOOR_Z), shell, 0.0, tag)
    socket("Socket_DoorOutside", (DOOR_X, FORE_Y + 0.55, FLOOR_Z), shell, tag)
    socket("Socket_DoorInside", (DOOR_X, Y0 + 2.3, FLOOR_Z), shell, tag)
    socket("Socket_InteriorMin", (X0 + T, Y0 + T, FLOOR_Z), shell, tag)
    socket("Socket_InteriorMax", (X1 - T, Y1 - T, CEIL), shell, tag)
    for i, (lx, ly) in enumerate(LIGHTS, 1):
        socket("Socket_Light_%d" % i, (lx, ly, CEIL - 0.4), shell, tag)
    return shell


def build_roof(coll):
    b = MeshBuilder("Agency_Roof", [dl.mat("SH_Ceiling", (0.85, 0.85, 0.83), 0.9),
                                    dl.mat("SH_Roof_Membrane", (0.30, 0.30, 0.31), 0.95),
                                    dl.mat("SH_HVAC", (0.55, 0.56, 0.56), 0.6)])
    b.box((X0 + T, Y0 + T, CEIL), (X1 - T, Y1 - T, CEIL + ROOF_T), mat_fn=lambda f: 0 if f.normal.z < -0.9 else 1)
    b.box((-1.5, 2.0, CEIL + ROOF_T), (0.1, 3.2, CEIL + ROOF_T + 0.9), mi=2)
    return b.finish(coll)
