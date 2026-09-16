"""
Lot « boutiques » : concessionnaire Liberty Motors et agence City Realty, bâtiments complets (coquille avec
intérieur réel, collisions, repères) et toits séparés masquables. Module pour run_lot.py
(assets/drug_lab/Blends/scripts), même méthode que le labo : échelle réelle, contrôles avant export.

Garde-fous (extra_checks) : emprise dans le lot mesuré dans World.tscn, porte franchissable au gabarit du
perso sans collision, murs fermés partout ailleurs, hauteur intérieure, comptoir / voitures exposées /
livraison dégagés, toit sans collision couvrant tout l'intérieur.
"""

import os
import sys

import bpy
from mathutils import Matrix, Vector

import dl_common as dl
import shop_agency as agency
import shop_common as sc
import shop_dealership as dealer
from dl_common import MeshBuilder, mat

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))  # assets/shops
BLEND = "Shop_Buildings.blend"
APT_SCRIPTS = os.path.normpath(os.path.join(ROOT, "..", "apartments", "Blends", "scripts"))
CAR_DIR = os.path.normpath(os.path.join(ROOT, "..", "vehicle_models_extra", "lowpoly_cars_free_cc0"))
STAGE_AGENCY_X = 50.0

ASSETS = [
    ("Dealership_Shell", "dealership", dealer.build_shell),
    ("Dealership_Roof", "dealership", dealer.build_roof),
    ("Agency_Shell", "agency", agency.build_shell),
    ("Agency_Roof", "agency", agency.build_roof),
]
EXPECT = {
    "Dealership_Shell": {"x": (21.70, 21.80), "y": (16.30, 16.45), "z": (7.76, 7.86)},
    "Dealership_Roof": {"x": (17.85, 17.95), "y": (13.75, 13.85), "z": (1.35, 1.45)},
    "Agency_Shell": {"x": (13.15, 13.25), "y": (14.20, 14.30), "z": (6.16, 6.26)},
    "Agency_Roof": {"x": (12.35, 12.45), "y": (11.85, 11.95), "z": (1.10, 1.20)},
}
SPECS = {
    "Dealership_Shell": dict(mod=dealer, roof="Dealership_Roof", min_height=5.0, cars=2),
    "Agency_Shell": dict(mod=agency, roof="Agency_Roof", min_height=3.3, cars=0),
}
CAR_RADIUS = 2.95  # demi-diagonale d'une voiture de 5,4 x 2,6 m


def _aabb(obj):
    pts = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    return Vector([min(p[i] for p in pts) for i in range(3)]), Vector([max(p[i] for p in pts) for i in range(3)])


def _hits(lo, hi, boxes):
    return [n for n, (a, b) in boxes if all(lo[i] < b[i] - 1e-4 and hi[i] > a[i] + 1e-4 for i in range(3))]


def extra_checks(roots):
    errors = []
    for name, spec in SPECS.items():
        mod, shell = spec["mod"], roots[name]
        objs = [shell] + list(shell.children_recursive)
        cols = [(dl.base_name(o), _aabb(o)) for o in objs if dl.base_name(o).endswith("colonly")]
        walls = [c for c in cols if not c[0].startswith("Col_Floor")]
        socks = {dl.base_name(o): o.matrix_world.translation for o in objs if o.type == 'EMPTY'}
        mn, mx = socks["Socket_InteriorMin"], socks["Socket_InteriorMax"]

        for o in objs:  # 1. emprise du lot
            if o.type == 'MESH':
                lo, hi = _aabb(o)
                if lo.x < mod.LOT["x"][0] - 0.01 or hi.x > mod.LOT["x"][1] + 0.01 or lo.y < mod.LOT["y"][0] - 0.01 or hi.y > mod.LOT["y"][1] + 0.01:
                    errors.append("%s : %s déborde du lot (%s -> %s)" % (name, o.name, tuple(round(v, 2) for v in lo), tuple(round(v, 2) for v in hi)))

        out, inside = socks["Socket_DoorOutside"], socks["Socket_DoorInside"]  # 2. porte franchissable
        if mod.DOOR_W < 1.2 or mod.DOOR_H < 2.2:
            errors.append("%s : porte %.2f x %.2f m sous le gabarit humain" % (name, mod.DOOR_W, mod.DOOR_H))
        sweep = _hits(Vector((mod.DOOR_X - sc.PLAYER_W / 2, out.y, sc.FLOOR_Z + 0.05)),
                      Vector((mod.DOOR_X + sc.PLAYER_W / 2, inside.y, sc.FLOOR_Z + sc.PLAYER_H)), walls)
        if sweep:
            errors.append("%s : passage de la porte bloqué par %s" % (name, sweep))
        if not (mn.y < inside.y < mx.y and out.y < mn.y):
            errors.append("%s : repères de porte mal placés" % name)

        z, gaps = sc.FLOOR_Z + 1.0, []  # 3. murs fermés hors porte

        def probe(x, y, run_x):
            d = Vector((0.03, 0.2, 0.05)) if run_x else Vector((0.2, 0.03, 0.05))
            return _hits(Vector((x, y, z)) - d, Vector((x, y, z)) + d, walls)
        x = mn.x + 0.1
        while x < mx.x - 0.1:
            if not probe(x, mx.y, True):
                gaps.append("fond x=%.2f" % x)
            if abs(x - mod.DOOR_X) > mod.DOOR_W / 2.0 + 0.1 and not probe(x, mn.y, True):
                gaps.append("façade x=%.2f" % x)
            x += 0.25
        y = mn.y + 0.1
        while y < mx.y - 0.1:
            for side, xx in (("gauche", mn.x), ("droite", mx.x)):
                if not probe(xx, y, False):
                    gaps.append("%s y=%.2f" % (side, y))
            y += 0.25
        if gaps:
            errors.append("%s : murs ouverts hors porte (%d points, ex. %s)" % (name, len(gaps), gaps[:3]))

        if mx.z - mn.z < spec["min_height"]:  # 4. volume intérieur
            errors.append("%s : hauteur intérieure %.2f m < %.2f" % (name, mx.z - mn.z, spec["min_height"]))

        counter = socks["Socket_Counter"]  # 5. comptoir dégagé
        if not (mn.x + 0.9 <= counter.x <= mx.x - 0.9 and mn.y + 0.9 <= counter.y <= mx.y - 0.9) \
                or _hits(counter + Vector((-0.8, -1.0, 0.05)), counter + Vector((0.8, 1.0, 1.5)), walls):
            errors.append("%s : comptoir contre un mur ou hors de la pièce" % name)

        cars = [socks["Socket_Car_%d" % i] for i in range(1, spec["cars"] + 1)]  # 6. voitures exposées
        for i, c in enumerate(cars, 1):
            if not (mn.x + CAR_RADIUS <= c.x <= mx.x - CAR_RADIUS and mn.y + CAR_RADIUS <= c.y <= mx.y - CAR_RADIUS):
                errors.append("%s : voiture %d contre un mur" % (name, i))
            if (c - counter).xy.length < CAR_RADIUS + 1.2 or (c - inside).xy.length < CAR_RADIUS + 0.8:
                errors.append("%s : voiture %d gêne le comptoir ou l'entrée" % (name, i))
        if len(cars) == 2 and (cars[0] - cars[1]).xy.length < 2 * CAR_RADIUS:
            errors.append("%s : les deux voitures se chevauchent" % name)

        if "Socket_Delivery" in socks:  # 7. livraison sur le parvis, hors bâtiment
            d = socks["Socket_Delivery"]
            lo, hi = d + Vector((-1.1, -2.5, 0.05)), d + Vector((1.1, 2.5, 1.5))
            if _hits(lo, hi, walls) or (mn.x <= d.x <= mx.x and mn.y <= d.y <= mx.y) \
                    or lo.x < mod.LOT["x"][0] or hi.x > mod.LOT["x"][1] or lo.y < mod.LOT["y"][0] or hi.y > mod.LOT["y"][1]:
                errors.append("%s : place de livraison encombrée ou hors parvis" % name)

        roof = roots[spec["roof"]]  # 8. toit masquable
        rlo, rhi = _aabb(roof)
        if any(dl.base_name(o).endswith("colonly") for o in roof.children_recursive):
            errors.append("%s : le toit ne doit pas avoir de collision" % spec["roof"])
        if rlo.x > mn.x + 0.05 or rhi.x < mx.x - 0.05 or rlo.y > mn.y + 0.05 or rhi.y < mx.y - 0.05 or abs(rlo.z - mx.z) > 0.01:
            errors.append("%s : le toit ne couvre pas l'intérieur" % spec["roof"])
    return errors


def _import_car(path, coll, loc, yaw):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        for c in list(o.users_collection):
            c.objects.unlink(o)
        coll.objects.link(o)
    for o in new:
        if o.parent is None:
            o.matrix_world = Matrix.Translation(loc) @ Matrix.Rotation(yaw, 4, 'Z') @ o.matrix_world


def stage(roots, coll):
    sys.path.insert(0, APT_SCRIPTS)
    import apt_props
    desk = {"Apt_Table": apt_props.build_table(coll), "Apt_Computer": apt_props.build_computer(coll)}
    for r in desk.values():
        for o in [r] + list(r.children_recursive):
            o.hide_render = True
    ax = STAGE_AGENCY_X
    g = MeshBuilder("Stage_Ground", [mat("Stage_Grass", (0.20, 0.26, 0.16), 0.9),
                                     mat("Stage_Sidewalk", (0.50, 0.50, 0.48), 0.9), mat("Stage_Road", (0.08, 0.08, 0.09), 0.9)])
    g.box((-40.0, -40.0, -0.05), (ax + 30.0, 40.0, 0.0), mi=0)
    g.box((-30.0, -10.0, 0.0), (16.8, -7.0, 0.408), mi=1)  # trottoirs et chaussées mesurés autour du concessionnaire
    g.box((-30.0, -22.0, 0.0), (28.8, -10.0, 0.2), mi=2)
    g.box((13.8, -10.0, 0.0), (16.8, 30.0, 0.408), mi=1)
    g.box((16.8, -22.0, 0.0), (28.8, 30.0, 0.2), mi=2)
    g.box((ax - 20.0, -10.8, 0.0), (ax + 20.0, -7.8, 0.408), mi=1)  # idem devant l'agence
    g.box((ax - 20.0, -22.8, 0.0), (ax + 20.0, -10.8, 0.2), mi=2)
    g.finish(coll)

    roofs = []
    for key, origin in (("Dealership", Vector((0.0, 0.0, 0.0))), ("Agency", Vector((ax, 0.0, 0.0)))):
        shell = roots[key + "_Shell"]
        dl.instance(shell, "Stage_%s_Shell" % key, origin, coll)
        dl.instance(roots[key + "_Roof"], "Stage_%s_Roof" % key, origin, coll)
        roofs.append("Stage_%s_Roof" % key)
        socks = {dl.base_name(c): c for c in shell.children if c.type == 'EMPTY'}
        apt_props.place_desk(desk, coll, origin + socks["Socket_Counter"].location, "Stage_" + key)
        dl.mannequin(coll, origin + socks["Socket_DoorOutside"].location)
        if key == "Dealership":
            for i, fname in enumerate(("italia.glb", "kamaro.glb"), 1):
                s = socks["Socket_Car_%d" % i]
                _import_car(os.path.join(CAR_DIR, fname), coll, s.location, s.rotation_euler.z)
    return [
        {"file": "Shops_dealership_street.png", "loc": (26.0, -32.0, 7.0), "target": (2.0, 0.0, 3.0), "lens": 30.0},
        {"file": "Shops_dealership_front.png", "loc": (1.25, -21.0, 2.2), "target": (1.25, 0.0, 3.4), "lens": 26.0},
        {"file": "Shops_dealership_interior.png", "loc": (1.25, -4.2, 1.7), "target": (-2.5, 7.0, 1.0), "lens": 16.0, "hide": roofs},
        {"file": "Shops_agency_street.png", "loc": (ax + 9.0, -24.0, 3.2), "target": (ax, -5.0, 2.8), "lens": 30.0},
        {"file": "Shops_agency_interior.png", "loc": (ax + 3.6, -4.6, 1.7), "target": (ax - 2.0, 5.5, 1.0), "lens": 16.0, "hide": roofs},
        {"file": "Shops_plan.png", "type": 'ORTHO', "ortho_scale": 90.0, "loc": (25.0, 0.0, 90.0), "target": (25.0, 0.0, 0.0),
         "res": (2000, 1000), "hide": roofs},
    ]
