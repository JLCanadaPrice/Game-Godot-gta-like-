"""
Aides communes du lot « boutiques » (concessionnaire, agence immobilière) : Blender 5.1 en --background,
1 unité = 1 m, échelle réelle (S_HUMAN = 1). Repère de chaque bâtiment = repère du site dans World.tscn :
origine de l'ancien bâtiment city_kit, -Y Blender = rue principale (= +Z Godot), +X Blender = +X Godot.
Mesures relevées dans World.tscn : terrain du District à 0,000 m, dessus des trottoirs à 0,408 m.
"""

import math

import bpy
from mathutils import Matrix, Vector

import dl_common as dl

FLOOR_Z = 0.41                   # sol fini et parvis au niveau des trottoirs (0,408 m) : on entre sans marche
T = 0.30                         # épaisseur des murs
PLAYER_W, PLAYER_H = 0.90, 1.90  # gabarit de passage : capsule Ø 0,8 m, perso 1,86 m


def glass(name, rgb, alpha):
    """Vitrage transparent (glTF alphaMode BLEND) : on voit l'intérieur depuis la rue."""
    m = dl.mat(name, rgb, 0.05, metallic=0.1)
    bsdf = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Alpha'].default_value = alpha
    if hasattr(m, "surface_render_method"):
        m.surface_render_method = 'BLENDED'
    m.diffuse_color = (*rgb, alpha)
    return m


def split_span(u0, u1, z0, z1, openings):
    """Découpe un pan (u0..u1, z0..z1) autour d'ouvertures (centre, largeur, bas, haut)."""
    boxes, cur = [], u0
    for c, w, oz0, oz1 in sorted(openings):
        a, b = c - w / 2.0, c + w / 2.0
        if a > cur:
            boxes.append((cur, a, z0, z1))
        if oz0 > z0:
            boxes.append((a, b, z0, oz0))
        if oz1 < z1:
            boxes.append((a, b, oz1, z1))
        cur = b
    if cur < u1:
        boxes.append((cur, u1, z0, z1))
    return boxes


def along(axis, u0, u1, v0, v1, z0, z1):
    """Coins (lo, hi) d'un pan courant le long de X (v = Y) ou le long de Y (v = X)."""
    if axis == 'x':
        return (u0, v0, z0), (u1, v1, z1)
    return (v0, u0, z0), (v1, u1, z1)


def facing(center, side):
    """Repère d'un panneau posé en center, face visible vers '-Y', '+Y', '+X' ou '-X' (texte lisible de face)."""
    stand = Matrix.Rotation(math.radians(90), 4, 'X')  # plan XY debout, face vers -Y
    turn = {'-Y': 0.0, '+X': 90.0, '+Y': 180.0, '-X': -90.0}[side]
    return Matrix.Translation(Vector(center)) @ Matrix.Rotation(math.radians(turn), 4, 'Z') @ stand


def add_text(b, body, max_w, max_h, matrix, mi, depth=0.05):
    """Lettres extrudées bas-poly (police intégrée), centrées et réduites pour tenir dans max_w x max_h,
    posées en saillie sur la face +Z locale de matrix."""
    cu = bpy.data.curves.new("TXT", 'FONT')
    cu.body = body
    cu.size = 1.0
    cu.extrude = depth / 2.0
    cu.align_x = 'CENTER'
    cu.align_y = 'CENTER'
    cu.resolution_u = 2
    obj = bpy.data.objects.new("TXT", cu)
    bpy.context.scene.collection.objects.link(obj)
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    xs = [v.co.x for v in me.vertices]
    ys = [v.co.y for v in me.vertices]
    k = min(max_w / (max(xs) - min(xs)), max_h / (max(ys) - min(ys)))
    cx, cy = (max(xs) + min(xs)) / 2.0, (max(ys) + min(ys)) / 2.0
    me.transform(matrix @ Matrix.Diagonal((k, k, 1.0, 1.0)) @ Matrix.Translation((-cx, -cy, depth / 2.0)))
    start = len(b.bm.faces)
    b.bm.from_mesh(me)
    for f in list(b.bm.faces)[start:]:
        f.material_index = mi
    bpy.data.objects.remove(obj)
    bpy.data.curves.remove(cu)
    bpy.data.meshes.remove(me)


def rotated_socket(name, loc, parent, yaw_deg, tag=""):
    """Repère orienté : l'avant Godot (-Z) suit +Y Blender tourné de yaw_deg autour de Z."""
    s = dl.socket(name, loc, parent, tag)
    s.rotation_euler = (0.0, 0.0, math.radians(yaw_deg))
    return s
