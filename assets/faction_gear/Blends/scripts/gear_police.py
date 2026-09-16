"""
Lot A : équipement de faction police, à l'échelle du perso (S_HUMAN). Module pour run_lot.py.

- Police_RiotShield : plaque incurvée 0,58 x 1,05 m, sangle d'avant-bras et poignée au dos.
  Origine = ArmPoint (sangle) : X le long de l'avant-bras (coude -> poignet), Z vers le haut,
  face avant vers -Y Blender (= +Z Godot, l'avant des personnages).
- Police_Cap / Police_Badge : ajustés à la vraie tête et au vrai torse de Casual_2, mesurés à la
  construction dans npc_models/Casual_2.gltf. Origines = positions de repos des os Head / Chest.
"""

import math
import os

import bmesh
import bpy
from mathutils import Vector

import dl_common as dl
from dl_common import MeshBuilder, box_m, mat, poly, socket

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))  # assets/faction_gear
NPC_DIR = os.path.normpath(os.path.join(ROOT, "..", "npc_models"))
BLEND = "Faction_Gear.blend"

EXPECT = {
    "Police_RiotShield": {"x": (0.56, 0.62), "y": (0.16, 0.20), "z": (1.04, 1.07)},  # plaque à 11 cm + sangle
    "Police_Cap": {"x": (0.20, 0.30), "y": (0.28, 0.42), "z": (0.13, 0.17)},  # calée sur la calotte, visière comprise
    "Police_Badge": {"x": (0.045, 0.055), "y": (0.005, 0.008), "z": (0.06, 0.07)},
}

_FIT = {}


def _m():
    return dict(
        plate=mat("GP_Shield_Plate", (0.06, 0.08, 0.10), 0.2),
        rim=mat("GP_Shield_Rim", (0.01, 0.01, 0.012), 0.5),
        band=mat("GP_Shield_Band", (0.55, 0.57, 0.60), 0.4),
        strap=mat("GP_Strap", (0.02, 0.02, 0.022), 0.7),
        cap=mat("GP_Cap_Navy", (0.015, 0.02, 0.06), 0.7),
        visor=mat("GP_Cap_Visor", (0.01, 0.01, 0.012), 0.3),
        gold=mat("GP_Gold", (0.55, 0.40, 0.10), 0.35),
    )


def _import(name):
    """Importe un PNJ en pose de repos : c'est dans ce repère que Head / Chest / LowerArm sont mesurés
    et que les accessoires sont calés (en jeu, BoneAttachment3D suit ensuite l'os dans toute pose)."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(NPC_DIR, name + ".gltf"))
    objs = [o for o in bpy.data.objects if o not in before]
    for o in objs:
        if o.type == 'ARMATURE':
            o.data.pose_position = 'REST'
    bpy.context.view_layer.update()
    return objs


def _bones(objs):
    arm = next(o for o in objs if o.type == 'ARMATURE')
    return {b.name: arm.matrix_world @ b.head_local for b in arm.data.bones}


def _casual_fit():
    """Mesure tête et torse de Casual_2 (pose de repos), puis retire le modèle importé."""
    if not _FIT:
        objs = _import("Casual_2")
        bones = _bones(objs)
        head = next(o for o in objs if o.type == 'MESH' and o.name.lower().endswith("head"))
        body = next(o for o in objs if o.type == 'MESH' and o.name.lower().endswith("body"))
        hv = [head.matrix_world @ v.co for v in head.data.vertices]
        bv = [body.matrix_world @ v.co for v in body.data.vertices]
        _FIT["head_point"] = bones["Head"].copy()
        _FIT["chest_point"] = bones["Chest"].copy()
        _FIT["head_min"] = Vector([min(p[i] for p in hv) for i in range(3)])
        _FIT["head_max"] = Vector([max(p[i] for p in hv) for i in range(3)])
        skull = [p for p in hv if p.z >= _FIT["head_max"].z - 0.10]  # calotte : sans la queue de cheval, plus bas
        _FIT["skull_min"] = Vector([min(p[i] for p in skull) for i in range(3)])
        _FIT["skull_max"] = Vector([max(p[i] for p in skull) for i in range(3)])
        _FIT["chest_front_y"] = min(p.y for p in bv if 1.30 <= p.z <= 1.42 and 0.03 <= p.x <= 0.14)
        for o in objs:
            bpy.data.objects.remove(o, do_unlink=True)
    return _FIT


def _band(b, cx, cy, z0, z1, rx0, ry0, rx1, ry1, mi, seg=14, cap_top=False):
    """Tronc de cône elliptique ouvert en bas (normales vers l'extérieur)."""
    def ring(rx, ry, z):
        return [Vector((cx + rx * math.cos(2 * math.pi * i / seg), cy + ry * math.sin(2 * math.pi * i / seg), z))
                for i in range(seg)]
    r0, r1 = ring(rx0, ry0, z0), ring(rx1, ry1, z1)
    for i in range(seg):
        j = (i + 1) % seg
        poly(b, (r0[i], r0[j], r1[j], r1[i]), mi)
    if cap_top:
        poly(b, r1, mi)


def build_shield(coll):
    m = _m()
    b = MeshBuilder("Police_RiotShield", [m["plate"], m["rim"], m["band"], m["strap"]])
    PLATE, RIM, BAND, STRAP = range(4)
    # apex à 11 cm devant l'avant-bras : la courbure de la plaque ne touche pas la main côté poignet
    w, z0, z1, t, apex, r, seg = 0.58, -0.55, 0.50, 0.012, -0.11, 0.85, 8
    half = math.asin((w / 2) / r)

    def pt(radius, a, z):
        return Vector((radius * math.sin(a), apex + r - radius * math.cos(a), z))

    def ang(i, a0=-half, a1=half, n=seg):
        return a0 + (a1 - a0) * i / n

    for i in range(seg):  # plaque : face avant (-Y), dos (+Y), tranches haute/basse
        a, c = ang(i), ang(i + 1)
        poly(b, (pt(r, a, z0), pt(r, c, z0), pt(r, c, z1), pt(r, a, z1)), PLATE)
        poly(b, (pt(r - t, a, z1), pt(r - t, c, z1), pt(r - t, c, z0), pt(r - t, a, z0)), PLATE)
        poly(b, (pt(r, a, z1), pt(r, c, z1), pt(r - t, c, z1), pt(r - t, a, z1)), RIM)
        poly(b, (pt(r - t, a, z0), pt(r - t, c, z0), pt(r, c, z0), pt(r, a, z0)), RIM)
    poly(b, (pt(r, -half, z0), pt(r, -half, z1), pt(r - t, -half, z1), pt(r - t, -half, z0)), RIM)
    poly(b, (pt(r, half, z0), pt(r - t, half, z0), pt(r - t, half, z1), pt(r, half, z1)), RIM)

    def strip(a0, a1, za, zb, mi, n, lift):
        for i in range(n):
            a, c = ang(i, a0, a1, n), ang(i + 1, a0, a1, n)
            poly(b, (pt(r + lift, a, za), pt(r + lift, c, za), pt(r + lift, c, zb), pt(r + lift, a, zb)), mi)

    d = 0.025 / r  # bordure noire de 2,5 cm, bande claire horizontale
    strip(-half, half, z1 - 0.025, z1, RIM, seg, 0.003)
    strip(-half, half, z0, z0 + 0.025, RIM, seg, 0.003)
    strip(-half, -half + d, z0 + 0.025, z1 - 0.025, RIM, 1, 0.003)
    strip(half - d, half, z0 + 0.025, z1 - 0.025, RIM, 1, 0.003)
    strip(-half + d, half - d, 0.12, 0.20, BAND, seg, 0.002)

    # dos : sangle d'avant-bras autour de l'origine (avant-bras le long de X) et poignée côté poignet
    back = apex + t  # dos de la plaque au centre
    b.box((-0.03, back, 0.045), (0.03, 0.07, 0.065), mi=STRAP)
    b.box((-0.03, back, -0.065), (0.03, 0.07, -0.045), mi=STRAP)
    b.box((-0.03, 0.05, -0.065), (0.03, 0.07, 0.065), mi=STRAP)
    for z in (0.07, -0.09):
        b.box((0.13, back + 0.01, z), (0.16, -0.005, z + 0.02), mi=STRAP)
    b.box((0.13, -0.02, -0.09), (0.16, 0.0, 0.09), mi=STRAP)

    shield = b.finish(coll)
    socket("ArmPoint", (0.0, 0.0, 0.0), shield)
    return shield


def build_cap(coll):
    fit = _casual_fit()
    m = _m()
    b = MeshBuilder("Police_Cap", [m["cap"], m["visor"], m["gold"]])
    CAP, VISOR, GOLD = range(3)
    lo, hi = fit["skull_min"], fit["skull_max"]  # calotte mesurée (10 cm du haut), sans la queue de cheval
    cx, cy, top = (lo.x + hi.x) / 2.0, (lo.y + hi.y) / 2.0, fit["head_max"].z
    rx, ry = (hi.x - lo.x) / 2.0 + 0.008, (hi.y - lo.y) / 2.0 + 0.008
    band0, band1 = top - 0.11, top - 0.06
    _band(b, cx, cy, band0, band1, rx, ry, rx, ry, CAP)  # bandeau posé sur le front
    _band(b, cx, cy, band1, top + 0.02, rx, ry, rx + 0.012, ry + 0.010, CAP, cap_top=True)  # calotte basse

    zv, drop, n = band0 + 0.004, math.tan(math.radians(15.0)), 8  # visière vers -Y, inclinée de 15°
    a0, a1 = math.radians(200.0), math.radians(340.0)
    inner, outer = [], []
    for i in range(n + 1):
        a = a0 + (a1 - a0) * i / n
        p = Vector((cx + rx * math.cos(a), cy + ry * math.sin(a), zv))
        reach = 0.06 * max(-math.sin(a), 0.0)
        radial = Vector((math.cos(a), math.sin(a), 0.0))
        inner.append(p)
        outer.append(p + radial * reach - Vector((0.0, 0.0, reach * drop)))
    for i in range(n):
        poly(b, (inner[i], outer[i], outer[i + 1], inner[i + 1]), VISOR)
        low = Vector((0.0, 0.0, 0.008))
        poly(b, (inner[i] - low, inner[i + 1] - low, outer[i + 1] - low, outer[i] - low), VISOR)
    box_m(b, dl.Matrix.Translation((cx, cy - ry - 0.012, band1 + 0.03)), (0.035, 0.008, 0.035), mi=GOLD)  # écusson

    bmesh.ops.translate(b.bm, vec=-fit["head_point"], verts=b.bm.verts[:])
    cap = b.finish(coll)
    socket("HeadPoint", (0.0, 0.0, 0.0), cap)
    return cap


def build_badge(coll):
    fit = _casual_fit()
    m = _m()
    b = MeshBuilder("Police_Badge", [m["gold"]])
    xc, zc, yf = 0.085, 1.36, fit["chest_front_y"] - 0.004
    shape = [(-0.025, 0.028), (-0.025, -0.008), (0.0, -0.037), (0.025, -0.008), (0.025, 0.028)]
    front = [Vector((xc + x, yf - 0.003, zc + z)) for x, z in shape]
    back = [Vector((xc + x, yf + 0.003, zc + z)) for x, z in shape]
    poly(b, front, 0)
    poly(b, list(reversed(back)), 0)
    for i in range(len(shape)):
        j = (i + 1) % len(shape)
        poly(b, (front[i], back[i], back[j], front[j]), 0)
    bmesh.ops.translate(b.bm, vec=-fit["chest_point"], verts=b.bm.verts[:])
    badge = b.finish(coll)
    socket("ChestPoint", (0.0, 0.0, 0.0), badge)
    return badge


ASSETS = [
    ("Police_RiotShield", "police", build_shield),
    ("Police_Cap", "police", build_cap),
    ("Police_Badge", "police", build_badge),
]

# --- Aperçus ------------------------------------------------------------------

KEEP = ("skin", "eye", "hair", "moustache", "earring", "visor")
NAVY, NAVY_DARK, BLACK = (0.015, 0.02, 0.06), (0.008, 0.01, 0.03), (0.01, 0.01, 0.012)


def _police_look(objs, x_offset, by_part, by_mat):
    for o in objs:
        if o.parent is None:
            o.location.x += x_offset
        if o.type != 'MESH':
            continue
        if "pistol" in o.name.lower():
            o.hide_render = True
            continue
        part = next((c for k, c in by_part.items() if k in o.name.lower()), None)
        for slot in o.material_slots:
            if slot.material is None:
                continue
            name = slot.material.name.lower().split(".")[0]
            color = by_mat.get(name)
            if color is None and part is not None and not any(k in name for k in KEEP):
                color = part
            if color is not None:
                slot.material = slot.material.copy()
                slot.material.diffuse_color = (*color, 1.0)


def stage(roots, coll):
    fit = _casual_fit()
    ground = MeshBuilder("Stage_Ground", [mat("Stage_Ground", (0.30, 0.30, 0.30), 0.9)])
    ground.box((-2.0, -3.0, -0.05), (5.0, 3.0, 0.0))
    ground.finish(coll)

    casual = _import("Casual_2")
    _police_look(casual, 0.0, {"body": NAVY, "legs": NAVY_DARK, "feet": BLACK}, {})
    dl.instance(roots["Police_Cap"], "Stage_Cap", fit["head_point"], coll)
    dl.instance(roots["Police_Badge"], "Stage_Badge", fit["chest_point"], coll)

    swat_mats = {"swat": NAVY, "swat_black": NAVY_DARK, "grey": (0.05, 0.06, 0.09), "black": BLACK}
    for x in (1.3, 2.7):
        swat = _import("Swat")
        bones = _bones(swat)
        _police_look(swat, x, {}, swat_mats)
        if x < 2.0:  # repère d'accroche réel : milieu de l'avant-bras gauche en pose de repos
            mid = (bones["LowerArm.L"] + bones["Wrist.L"]) / 2.0
            dl.instance(roots["Police_RiotShield"], "Stage_Shield_Arm", mid + Vector((x, 0.0, 0.0)), coll)
        else:  # position « tenue » approximative devant le corps, pour juger la taille
            dl.instance(roots["Police_RiotShield"], "Stage_Shield_Held", (x + 0.22, -0.32, 1.02), coll)

    head = fit["head_point"]
    return [
        {"file": "Lot_A_police_front.png", "loc": (1.4, -4.6, 1.5), "target": (1.4, 0.0, 1.1), "lens": 35.0},
        {"file": "Lot_A_cap_close.png", "loc": (head.x + 0.55, -0.80, 1.90), "target": (head.x, head.y, 1.74),
         "lens": 50.0, "res": (1200, 900)},
        {"file": "Lot_A_cap_side.png", "loc": (head.x - 0.95, head.y + 0.05, 1.80), "target": (head.x, head.y, 1.74),
         "lens": 50.0, "res": (1200, 900)},
        {"file": "Lot_A_shield_back.png", "loc": (3.3, 1.5, 1.5), "target": (2.92, -0.32, 1.0), "lens": 35.0,
         "res": (1200, 900)},
    ]
