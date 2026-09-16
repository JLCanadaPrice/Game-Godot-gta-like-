"""
Fonctions communes aux scripts de build drug_lab (Blender 5.1, lancés en --background).

1 unité = 1 m. Les dimensions « plan » (échelle réelle) sont multipliées par une échelle
validée en jeu, intégrée à la géométrie exportée (jamais via Node3D.scale dans Godot) :
  S_SHELL : coque et volume des bâtiments (murs, structure, toiture, éclairage en hauteur)
  S_HUMAN : ce que le perso utilise à sa hauteur (porte piétonne, tables, plants, props)
"""

import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

S_SHELL = 2.0
S_HUMAN = 1.0

_MATS = {}


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0  # pas de .blend1 à chaque rebuild
    _MATS.clear()
    scene = bpy.context.scene
    scene.unit_settings.system = 'METRIC'
    scene.unit_settings.scale_length = 1.0
    return scene


def mat(name, rgb, roughness=0.5, metallic=0.0, emission=None, strength=0.0, double_sided=False):
    """Matériau couleur unie, réutilisé par nom (couleurs linéaires comme Suit.gltf).

    Faces arrière masquées par défaut : l'export glTF écrit doubleSided=false (sinon Godot
    désactive le culling). double_sided=True seulement pour les surfaces sans épaisseur (feuilles).
    """
    if name in _MATS:
        return _MATS[name]
    m = bpy.data.materials.new(name)
    m.use_backface_culling = not double_sided
    if m.node_tree is None:
        m.use_nodes = True  # Blender < 5 uniquement
    nodes = m.node_tree.nodes
    bsdf = next((n for n in nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if bsdf is None:
        bsdf = nodes.new('ShaderNodeBsdfPrincipled')
        out = next((n for n in nodes if n.type == 'OUTPUT_MATERIAL'), None) or nodes.new('ShaderNodeOutputMaterial')
        m.node_tree.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    bsdf.inputs['Base Color'].default_value = (*rgb, 1.0)
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = metallic
    if emission is not None:
        bsdf.inputs['Emission Color'].default_value = (*emission, 1.0)
        bsdf.inputs['Emission Strength'].default_value = strength
    m.diffuse_color = (*(emission if emission is not None else rgb), 1.0)
    _MATS[name] = m
    return m


def collection(name):
    col = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(col)
    return col


class MeshBuilder:
    """Accumule des primitives bmesh ; chaque face reçoit un index de matériau."""

    def __init__(self, name, materials):
        self.name = name
        self.materials = list(materials)
        self.bm = bmesh.new()

    def _assign(self, verts, mi, mat_fn):
        faces = {f for v in verts for f in v.link_faces}
        for f in faces:
            f.normal_update()
            f.material_index = mi if mat_fn is None else mat_fn(f)
        return faces

    def box(self, lo, hi, mi=0, mat_fn=None):
        """Boîte alignée sur les axes, coin lo -> coin hi (mètres finaux)."""
        lo, hi = Vector(lo), Vector(hi)
        size = hi - lo
        m = Matrix.Translation((lo + hi) / 2.0) @ Matrix.Diagonal((size.x, size.y, size.z, 1.0))
        res = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)
        return self._assign(res['verts'], mi, mat_fn)

    def cone(self, base_center, r_bottom, r_top, depth, segments=12, mi=0, cap=True):
        """Cylindre / tronc de cône posé sur base_center, axe Z."""
        m = Matrix.Translation(Vector(base_center) + Vector((0.0, 0.0, depth / 2.0)))
        res = bmesh.ops.create_cone(self.bm, cap_ends=cap, cap_tris=False, segments=segments,
                                    radius1=r_bottom, radius2=r_top, depth=depth, matrix=m)
        return self._assign(res['verts'], mi, None)

    def finish(self, coll, parent=None):
        for f in self.bm.faces:
            f.smooth = False  # bas-poly : ombrage plat
        self.bm.normal_update()
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.materials:
            me.materials.append(m)
        obj = bpy.data.objects.new(self.name, me)
        coll.objects.link(obj)
        obj.parent = parent
        return obj


def base_name(obj):
    """Nom exporté. Ce qui suit « @ » ne sert qu'à garder les noms uniques dans Blender quand
    plusieurs assets d'une même scène ont les mêmes nœuds (collisions, sockets) ; retiré à l'export."""
    return obj.name.split("@")[0]


def _tagged(name, tag):
    return name + ("@" + tag if tag else "")


def col_box(name, lo, hi, parent, tag=""):
    """Boîte de collision : suffixe Godot -convcolonly (StaticBody3D + forme convexe, invisible)."""
    b = MeshBuilder(_tagged(name + "-convcolonly", tag), [])
    b.box(lo, hi)
    obj = b.finish(parent.users_collection[0], parent)
    obj.display_type = 'WIRE'
    return obj


def socket(name, loc, parent, tag=""):
    """Empty exporté en Node3D : point d'ancrage pour instancier une pièce dans Godot."""
    e = bpy.data.objects.new(_tagged(name, tag), None)
    e.empty_display_type = 'ARROWS'
    e.empty_display_size = 0.5 * S_SHELL
    e.location = loc
    parent.users_collection[0].objects.link(e)
    e.parent = parent
    return e


def visual_meshes(objs):
    return [o for o in objs if o.type == 'MESH' and not base_name(o).endswith("colonly")]


def stats(root):
    objs = [root] + list(root.children_recursive)
    meshes = visual_meshes(objs)
    tris = sum(len(p.vertices) - 2 for o in meshes for p in o.data.polygons)
    pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    lo = [min(p[i] for p in pts) for i in range(3)]
    hi = [max(p[i] for p in pts) for i in range(3)]
    return {
        "triangles": tris,
        "size_xyz_m": [round(hi[i] - lo[i], 3) for i in range(3)],
        "z_range_m": [round(lo[2], 3), round(hi[2], 3)],
        "collisions": sum(1 for o in objs if base_name(o).endswith("colonly")),
        "sockets": sum(1 for o in objs if o.type == 'EMPTY'),
        "materials": sorted({m.name for o in meshes for m in o.data.materials}),
    }


def export_glb(root, path):
    """Exporte root + descendants (collisions, sockets) en .glb Y-up, sous leurs noms de base (sans « @tag »)."""
    objs = [root] + list(root.children_recursive)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = root
    props = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    wanted = dict(filepath=path, export_format='GLB', use_selection=True, export_apply=True,
                  export_yup=True, export_cameras=False, export_lights=False,
                  export_animations=False, export_extras=False, export_materials='EXPORT')
    tagged = [(o, o.name) for o in objs if "@" in o.name]
    try:
        for o, full in tagged:
            o.name = base_name(o)
            if o.name != full.split("@")[0]:  # Blender aurait suffixé « .001 » : nom Godot faussé
                raise RuntimeError("Nom exporté déjà pris dans la scène : " + full)
        bpy.ops.export_scene.gltf(**{k: v for k, v in wanted.items() if k in props})
    finally:
        for o, full in tagged:
            o.name = full
    return stats(root)


def instance(src, name, loc, coll, rot_z=0.0):
    """Copie liée (même mesh) pour l'assemblage de prévisualisation."""
    obj = bpy.data.objects.new(name, src.data)
    obj.location = loc
    obj.rotation_euler = (0.0, 0.0, rot_z)
    coll.objects.link(obj)
    return obj


# --- Prévisualisation ---------------------------------------------------------

def mannequin(coll, loc):
    """Perso de référence 1,86 m : taille réelle de Suit en jeu, jamais mise à l'échelle."""
    b = MeshBuilder("REF_Mannequin_1m86", [mat("REF_Mannequin", (0.10, 0.20, 0.45))])
    b.cone((0.0, 0.0, 0.0), 0.20, 0.20, 1.50, segments=12)
    ico = bmesh.ops.create_icosphere(b.bm, subdivisions=2, radius=0.13, matrix=Matrix.Translation((0, 0, 1.73)))
    b._assign(ico['verts'], 0, None)
    obj = b.finish(coll)
    obj.location = loc
    return obj


def setup_workbench(scene, res=1000):
    world = bpy.data.worlds.new("Preview")
    world.color = (0.62, 0.66, 0.70)
    scene.world = world
    scene.view_settings.view_transform = 'Standard'
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    sh = scene.display.shading
    sh.light = 'STUDIO'
    sh.color_type = 'MATERIAL'
    sh.show_shadows = True
    sh.show_cavity = True
    sh.show_object_outline = True
    sh.show_backface_culling = True  # révèle les normales inversées (culling actif à l'export)
    cam = bpy.data.objects.new("PreviewCam", bpy.data.cameras.new("PreviewCam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    return cam


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()


def shoot(scene, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


def deg(a):
    return math.radians(a)


# --- Primitives libres et contrôles (lots 2 et 3) ---------------------------------

def poly(b, points, mi=0):
    """Une face à partir de points monde (ordre anti-horaire vu du côté de la normale)."""
    f = b.bm.faces.new([b.bm.verts.new(Vector(p)) for p in points])
    f.material_index = mi
    return f


def ico(b, center, radius, scale=(1.0, 1.0, 1.0), rot_z=0.0, mi=0, subdivisions=1):
    m = (Matrix.Translation(Vector(center)) @ Matrix.Rotation(rot_z, 4, 'Z')
         @ Matrix.Diagonal((scale[0], scale[1], scale[2], 1.0)))
    res = bmesh.ops.create_icosphere(b.bm, subdivisions=subdivisions, radius=radius, matrix=m)
    return b._assign(res['verts'], mi, None)


def cyl_between(b, p0, p1, r0, r1, segments=6, mi=0, cap=True):
    """Cylindre / cône de p0 (rayon r0) à p1 (rayon r1)."""
    p0, p1 = Vector(p0), Vector(p1)
    axis = p1 - p0
    rot = axis.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    m = Matrix.Translation(p0) @ rot @ Matrix.Translation((0.0, 0.0, axis.length / 2.0))
    res = bmesh.ops.create_cone(b.bm, cap_ends=cap, cap_tris=False, segments=segments,
                                radius1=r0, radius2=r1, depth=axis.length, matrix=m)
    return b._assign(res['verts'], mi, None)


def box_m(b, matrix, size, mi=0):
    """Boîte de dimensions size, centrée sur l'origine locale de matrix (rotation libre)."""
    m = matrix @ Matrix.Diagonal((size[0], size[1], size[2], 1.0))
    res = bmesh.ops.create_cube(b.bm, size=1.0, matrix=m)
    return b._assign(res['verts'], mi, None)


def orient(origin, direction):
    """Repère local : Y suit direction, X horizontal, Z = dessus (feuilles, plateaux)."""
    y = Vector(direction).normalized()
    x = y.cross(Vector((0.0, 0.0, 1.0)))
    if x.length < 1e-6:
        x = Vector((1.0, 0.0, 0.0))
    x.normalize()
    z = x.cross(y)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = Vector(origin)
    return m


def leaf_fan(b, matrix, length, width, blades=5, spread=70.0, mi=0):
    """Feuille stylisée : lames en losange rayonnant dans le plan XY local, vers +Y."""
    half = (blades - 1) / 2.0
    faces = []
    for k in range(blades):
        off = (k - half) / half if half else 0.0
        ang = math.radians(-off * spread)
        lk = length * (1.0 - 0.45 * abs(off))
        ca, sa = math.cos(ang), math.sin(ang)
        pts = [matrix @ Vector((x * ca - y * sa, x * sa + y * ca, 0.0))
               for x, y in ((0.0, 0.0), (width / 2.0, 0.35 * lk), (0.0, lk), (-width / 2.0, 0.35 * lk))]
        faces.append(poly(b, pts, mi))
    return faces


def bake_scale(root, factor):
    """Échelle appliquée aux sommets et aux positions des enfants : aucun scale sur les nœuds."""
    if factor != 1.0:
        for o in [root] + list(root.children_recursive):
            if o.type == 'MESH':
                o.data.transform(Matrix.Scale(factor, 4))
            if o is not root:
                o.location = o.location * factor
    return root


def check_dims(root, expect):
    """Compare les dimensions visibles (m) aux plages attendues ; renvoie la liste des écarts."""
    size = stats(root)["size_xyz_m"]
    errors = []
    for i, axis in enumerate("xyz"):
        if axis in expect:
            lo, hi = expect[axis]
            if not lo <= size[i] <= hi:
                errors.append("%s : %s = %.3f m hors [%.2f ; %.2f]" % (root.name, axis, size[i], lo, hi))
    return errors
