"""
Lot B : coquilles d'appartement vides aux empreintes réelles des bâtiments city_kit. Module pour run_lot.py.

Empreintes = ligne des murs mesurée entre 1 et 2,5 m de haut dans les modèles (sans corniches) :
Building_Small_1 12,08 x 14,35 m, Building_Medium_2_001 14,31 x 12,34 m, Building_Large_2 20,50 x 16,50 m.
Hauteur = pas d'étage mesuré (3,0 m) : sol fini 0,00, plafond 2,80, dalles de 0,20 m. Murs de 0,20 m
(épaisseur des modules de mur city_kit). Porte d'entrée 1,2 x 2,2 m (capsule du joueur Ø 0,8 m) au
centre du mur avant (-Y Blender = +Z Godot). Fenêtres dépolies : allège 0,9 m, 1,2 x 1,5 m, ~3 m.
Plafond exporté à part (masquable, sans collision). Origine : centre de l'emprise, au sol fini.

Correspondance ApartmentData : studio -> Small, apt_2pieces -> Medium, loft et penthouse -> Large.
"""

import os

import apt_props
import dl_common as dl
from dl_common import MeshBuilder, col_box, mat, socket
from wh_shell import _to3d, _wall_boxes  # découpe des murs autour des ouvertures, comme l'entrepôt

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))  # assets/apartments
BLEND = "Apartment_Shells.blend"

SHELLS = [("Small", 12.08, 14.35), ("Medium", 14.31, 12.34), ("Large", 20.50, 16.50)]
T, CEIL, SLAB = 0.20, 2.80, 0.20
DOOR_W, DOOR_H = 1.20, 2.20
WIN_W, WIN_SILL, WIN_TOP, WIN_STEP, WIN_MARGIN = 1.20, 0.90, 2.40, 3.0, 0.80
BASE_H, BASE_T = 0.08, 0.012
ENTRANCE_DEPTH, TABLE_FROM_WALL = 0.80, 0.45


def _mats():
    return dict(
        int=mat("AP_Wall_Int", (0.55, 0.53, 0.49), 0.9),
        ext=mat("AP_Wall_Ext", (0.30, 0.28, 0.26), 0.9),
        trim=mat("AP_Trim", (0.10, 0.09, 0.08), 0.6),
        glass=mat("AP_Glass_Frosted", (0.70, 0.76, 0.80), 0.3, emission=(0.55, 0.62, 0.68), strength=0.6),
        floor=mat("AP_Floor", (0.28, 0.19, 0.11), 0.7),
        ceiling=mat("AP_Ceiling", (0.62, 0.62, 0.60), 0.9),
    )


def _window_centers(u0, u1, avoid=None):
    lo, hi = u0 + WIN_MARGIN + WIN_W / 2.0, u1 - WIN_MARGIN - WIN_W / 2.0
    if hi < lo:
        return []
    n = int((hi - lo) // WIN_STEP) + 1
    mid = (lo + hi) / 2.0
    us = [mid + (k - (n - 1) / 2.0) * WIN_STEP for k in range(n)]
    if avoid is not None:
        us = [u for u in us if abs(u - avoid) >= DOOR_W / 2.0 + WIN_W / 2.0 + 0.6]
    return us


def build_shell(coll, size, w, d):
    m = _mats()
    INT, EXT, TRIM, GLASS, FLOOR = range(5)
    b = MeshBuilder("Apartment_%s_Shell" % size, [m["int"], m["ext"], m["trim"], m["glass"], m["floor"]])
    hw, hd = w / 2.0, d / 2.0
    door = (0.0, DOOR_W, 0.0, DOOR_H)
    walls = [
        # nom, axe u, (v0, v1) épaisseur, sens extérieur, (u0, u1)
        ("Front", 'x', (-hd, -hd + T), -1, (-hw, hw)),
        ("Back", 'x', (hd - T, hd), 1, (-hw, hw)),
        ("Left", 'y', (-hw, -hw + T), -1, (-hd + T, hd - T)),
        ("Right", 'y', (hw - T, hw), 1, (-hd + T, hd - T)),
    ]
    cols = []
    for name, axis, (v0, v1), sign, span in walls:
        room_span = (-hw + T, hw - T) if axis == 'x' else span
        openings = [(u, WIN_W, WIN_SILL, WIN_TOP) for u in _window_centers(*room_span, avoid=0.0 if name == "Front" else None)]
        if name == "Front":
            openings.append(door)
        vi = 1 if axis == 'x' else 0
        outer, inner = (v0, v1) if sign < 0 else (v1, v0)

        def rule(f, vi=vi, sign=sign, outer=outer, inner=inner):
            n, c = f.normal, f.calc_center_median()
            if n[vi] * sign > 0.9 and abs(c[vi] - outer) < 1e-4:
                return EXT
            if n[vi] * sign < -0.9 and abs(c[vi] - inner) < 1e-4:
                return INT
            return TRIM

        for u0, u1, z0, z1 in _wall_boxes(span, CEIL, openings):
            b.box(*_to3d(axis, u0, u1, v0, v1, z0, z1), mat_fn=rule)
        vm = (v0 + v1) / 2.0
        for u, ow, z0, z1 in openings:
            if z0 > 0.0:  # fenêtre : vitre dépolie + meneau
                b.box(*_to3d(axis, u - ow / 2, u + ow / 2, vm - 0.01, vm + 0.01, z0, z1), mi=GLASS)
                b.box(*_to3d(axis, u - 0.02, u + 0.02, vm - 0.03, vm + 0.03, z0, z1), mi=TRIM)

        pv = sorted((inner, inner - sign * BASE_T))  # plinthe côté pièce, interrompue par la porte
        base_span = room_span if axis == 'x' else (span[0] + BASE_T, span[1] - BASE_T)
        for u0, u1, _z0, _z1 in _wall_boxes(base_span, BASE_H, [door] if name == "Front" else []):
            b.box(*_to3d(axis, u0, u1, pv[0], pv[1], 0.0, BASE_H), mi=TRIM)

        wall_cols = _wall_boxes(span, CEIL, [door]) if name == "Front" else [(span[0], span[1], 0.0, CEIL)]
        cols += [("%s_%d" % (name, i), _to3d(axis, u0, u1, v0, v1, z0, z1)) for i, (u0, u1, z0, z1) in enumerate(wall_cols)]

    b.box((-hw, -hd, -SLAB), (hw, hd, 0.0), mi=FLOOR)
    shell = b.finish(coll)
    # tag=size : les 3 coquilles partagent ces noms dans la scène Blender ; exportés sans « @size »
    for cname, (lo, hi) in cols:
        col_box("Col_Wall_" + cname, lo, hi, shell, tag=size)
    col_box("Col_Floor", (-hw, -hd, -SLAB), (hw, hd, 0.0), shell, tag=size)
    # Repères sans rotation : l'avant Godot (-Z) regarde vers l'intérieur de la pièce, porte dans le dos
    socket("Socket_Entrance", (0.0, -hd + T + ENTRANCE_DEPTH, 0.0), shell, tag=size)
    socket("Socket_Table", (0.0, hd - T - TABLE_FROM_WALL, 0.0), shell, tag=size)
    return shell


def build_ceiling(coll, size, w, d):
    m = _mats()
    b = MeshBuilder("Apartment_%s_Ceiling" % size, [m["ceiling"], m["ext"]])
    b.box((-w / 2, -d / 2, CEIL), (w / 2, d / 2, CEIL + SLAB), mat_fn=lambda f: 0 if f.normal.z < -0.9 else 1)
    return b.finish(coll)


ASSETS, EXPECT = [], {}
for _size, _w, _d in SHELLS:
    ASSETS.append(("Apartment_%s_Shell" % _size, "shells", lambda c, s=_size, w=_w, d=_d: build_shell(c, s, w, d)))
    ASSETS.append(("Apartment_%s_Ceiling" % _size, "shells", lambda c, s=_size, w=_w, d=_d: build_ceiling(c, s, w, d)))
    EXPECT["Apartment_%s_Shell" % _size] = {"x": (_w - 0.01, _w + 0.01), "y": (_d - 0.01, _d + 0.01), "z": (2.99, 3.01)}
    EXPECT["Apartment_%s_Ceiling" % _size] = {"x": (_w - 0.01, _w + 0.01), "y": (_d - 0.01, _d + 0.01), "z": (0.19, 0.21)}


def stage(roots, coll):
    desk = {"Apt_Table": apt_props.build_table(coll), "Apt_Computer": apt_props.build_computer(coll)}
    for r in desk.values():  # sources du bureau à l'origine : cachées, seules les copies posées s'affichent
        for o in [r] + list(r.children_recursive):
            o.hide_render = True
    ground = MeshBuilder("Stage_Ground", [mat("Stage_Ground", (0.30, 0.30, 0.30), 0.9)])
    ground.box((-12.0, -14.0, -0.30), (62.0, 14.0, -0.21))
    ground.finish(coll)

    xs, x, ceilings = {}, 0.0, []
    for size, w, d in SHELLS:
        x += w / 2.0 if not xs else 0.0
        xs[size] = x
        shell = roots["Apartment_%s_Shell" % size]
        dl.instance(shell, "Stage_%s_Shell" % size, (x, 0.0, 0.0), coll)
        dl.instance(roots["Apartment_%s_Ceiling" % size], "Stage_%s_Ceiling" % size, (x, 0.0, 0.0), coll)
        ceilings.append("Stage_%s_Ceiling" % size)
        socks = {dl.base_name(c): c.location for c in shell.children if c.name.startswith("Socket_")}
        apt_props.place_desk(desk, coll, dl.Vector((x, 0.0, 0.0)) + socks["Socket_Table"], "Stage_%s" % size)
        entrance = socks["Socket_Entrance"]
        dl.mannequin(coll, (x + entrance.x, entrance.y, 0.0))
        x += w / 2.0 + 4.0 + (next((sw for s, sw, _ in SHELLS[SHELLS.index((size, w, d)) + 1:]), 0.0) / 2.0)

    total = x
    s_hd, m_hd = SHELLS[0][2] / 2.0, SHELLS[1][2] / 2.0
    xl = xs["Large"]
    return [
        {"file": "Lot_B_plan.png", "type": 'ORTHO', "ortho_scale": total + 6.0, "loc": (total / 2.0 - 3.0, 0.0, 80.0),
         "target": (total / 2.0 - 3.0, 0.0, 0.0), "res": (2000, 800), "hide": ceilings},
        {"file": "Lot_B_small_interior.png", "loc": (xs["Small"] + 0.3, -s_hd + T + 0.35, 1.65),
         "target": (xs["Small"], s_hd - 1.2, 1.0), "lens": 16.0},
        {"file": "Lot_B_medium_desk.png", "loc": (xs["Medium"] + 1.4, m_hd - T - 2.8, 1.6),
         "target": (xs["Medium"], m_hd - T - TABLE_FROM_WALL, 0.9), "lens": 24.0},
        {"file": "Lot_B_large_exterior.png", "loc": (xl + 18.0, -24.0, 12.0), "target": (xl, 0.0, 1.4), "lens": 35.0},
    ]
