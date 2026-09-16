"""
Weed_Pot : lot 0 (test d'échelle) du chantier drug_lab.

Construit le pot de culture bas-poly (1 unité = 1 m, comme Suit.gltf / city_kit),
l'exporte en .glb (Y-up), sauvegarde la source .blend, puis rend deux aperçus :
  - échelle : pot à côté d'un mannequin de 1,86 m (taille de Suit) et d'une porte 1 x 2,2 m (Door_1)
  - gros plan : le pot seul, vu de 3/4 pour voir la terre

Usage :
  blender --background --factory-startup --python build_weed_pot.py -- <out.glb> <out.blend> <preview_dir>
"""

import json
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) < 3:
    raise SystemExit("usage: -- <out.glb> <out.blend> <preview_dir>")
OUT_GLB, OUT_BLEND, PREVIEW_DIR = argv[0], argv[1], argv[2]

# --- Dimensions (mètres) ------------------------------------------------------
# Profil dessiné à l'échelle réelle, puis toute la géométrie est multipliée par SCALE,
# intégré au mesh (aucun scale sur le nœud exporté). x2 : validé en jeu, décision définitive.
SCALE = 2.0
SEG = 16          # segments du cylindre : rond lisible de près, facettes visibles
SOIL_Z = 0.310    # niveau de la terre (4 cm sous le haut du rebord), avant SCALE

# Profil extérieur -> intérieur, (rayon, hauteur), tourné autour de Z
PROFILE = [
    (0.140, 0.000),   # arête du fond (petit chanfrein)
    (0.150, 0.012),
    (0.195, 0.312),   # haut de la paroi conique (Ø 0,30 en bas -> 0,40 en haut)
    (0.212, 0.318),   # dessous du rebord
    (0.212, 0.350),   # dessus du rebord (hauteur totale 0,35)
    (0.198, 0.350),   # lèvre intérieure
    (0.184, SOIL_Z),  # paroi intérieure jusqu'à la terre
]

# Hauteur du centre de la terre = point d'ancrage des plants (PlantSocket)
SOIL_CENTER_Z = 0.328

# --- Couleurs (linéaires, comme baseColorFactor de Suit.gltf) -----------------
COL_PLASTIC = (0.035, 0.035, 0.038)   # plastique sombre (pot de pépinière)
COL_SOIL = (0.060, 0.034, 0.018)      # terre brun foncé
COL_CLOD = (0.105, 0.064, 0.036)      # mottes plus claires (relief lisible sans texture)

MAT_PLASTIC, MAT_SOIL, MAT_CLOD = 0, 1, 2


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # Pas de sauvegarde .blend1 à côté de la source à chaque rebuild
    bpy.context.preferences.filepaths.save_version = 0
    scene = bpy.context.scene
    scene.unit_settings.system = 'METRIC'
    scene.unit_settings.scale_length = 1.0
    return scene


def make_mat(name, rgb, roughness=0.5, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_backface_culling = True  # export glTF doubleSided=false : culling actif dans Godot
    if mat.node_tree is None:
        mat.use_nodes = True  # Blender < 5 uniquement (déprécié en 5.x, node tree toujours présent)
    if mat.node_tree is None:
        raise RuntimeError("material %s has no node tree" % name)
    nodes = mat.node_tree.nodes
    bsdf = next((n for n in nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if bsdf is None:
        bsdf = nodes.new('ShaderNodeBsdfPrincipled')
        out = next((n for n in nodes if n.type == 'OUTPUT_MATERIAL'), None) or nodes.new('ShaderNodeOutputMaterial')
        mat.node_tree.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    bsdf.inputs['Base Color'].default_value = (*rgb, 1.0)
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = metallic
    mat.diffuse_color = (*rgb, 1.0)  # couleur viewport / Workbench
    return mat


def soil_height(r):
    """Hauteur approximative de la surface de terre au rayon r (léger dôme)."""
    if r <= 0.055:
        return SOIL_CENTER_Z - (SOIL_CENTER_Z - 0.324) * (r / 0.055)
    if r <= 0.120:
        return 0.324 - (0.324 - 0.317) * ((r - 0.055) / 0.065)
    return 0.317 - (0.317 - SOIL_Z) * ((r - 0.120) / 0.064)


def build_pot_mesh():
    bm = bmesh.new()
    rng = random.Random(7)  # graine fixe : le relief est identique à chaque build

    def ring(r, z, n=SEG, offset=0.0, jitter=None):
        verts = []
        for i in range(n):
            a = (i + offset) * 2.0 * math.pi / n
            zz = z if jitter is None else z + jitter()
            verts.append(bm.verts.new((r * math.cos(a), r * math.sin(a), zz)))
        return verts

    def face(verts, mat):
        f = bm.faces.new(verts)
        f.material_index = mat
        return f

    # Paroi (extérieur, rebord, intérieur)
    rings = [ring(r, z) for r, z in PROFILE]
    for k in range(len(rings) - 1):
        a, b = rings[k], rings[k + 1]
        for i in range(SEG):
            j = (i + 1) % SEG
            face((a[i], a[j], b[j], b[i]), MAT_PLASTIC)
    face(list(reversed(rings[0])), MAT_PLASTIC)  # fond

    # Terre : anneaux décalés d'un demi-pas + hauteurs jitterées -> facettes irrégulières
    edge = rings[-1]
    s_a = ring(0.120, 0.317, SEG, offset=0.5, jitter=lambda: rng.uniform(-0.004, 0.005))
    s_b = ring(0.055, 0.324, SEG // 2, offset=0.5, jitter=lambda: rng.uniform(-0.003, 0.004))
    center = bm.verts.new((0.0, 0.0, SOIL_CENTER_Z))

    for i in range(SEG):
        j = (i + 1) % SEG
        face((edge[i], edge[j], s_a[i]), MAT_SOIL)
        face((s_a[i], edge[j], s_a[j]), MAT_SOIL)
    half = SEG // 2
    for jb in range(half):
        k0, k1, k2 = 2 * jb, (2 * jb + 1) % SEG, (2 * jb + 2) % SEG
        jn = (jb + 1) % half
        face((s_a[k0], s_a[k1], s_b[jb]), MAT_SOIL)
        face((s_b[jb], s_a[k1], s_a[k2]), MAT_SOIL)
        face((s_b[jb], s_a[k2], s_b[jn]), MAT_SOIL)
        face((s_b[jb], s_b[jn], center), MAT_SOIL)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])

    # Mottes : icosaèdres aplatis posés sur la terre
    clods = [  # (rayon polaire, angle, taille)
        (0.085, 0.4, 0.024),
        (0.060, 2.3, 0.019),
        (0.125, 3.7, 0.021),
        (0.030, 5.1, 0.016),
    ]
    for rp, ang, size in clods:
        x, y = rp * math.cos(ang), rp * math.sin(ang)
        z = soil_height(rp) + size * 0.12
        m = (Matrix.Translation((x, y, z))
             @ Matrix.Rotation(rng.uniform(0.0, 2.0 * math.pi), 4, 'Z')
             @ Matrix.Diagonal((1.0, 0.85, 0.55, 1.0)))
        res = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=size, matrix=m, calc_uvs=False)
        vset = set(res['verts'])
        for f in bm.faces:
            if all(v in vset for v in f.verts):
                f.material_index = MAT_CLOD
                f.smooth = False

    for f in bm.faces:
        f.smooth = False  # bas-poly : ombrage plat

    bmesh.ops.scale(bm, vec=(SCALE, SCALE, SCALE), verts=bm.verts[:])
    bm.normal_update()
    me = bpy.data.meshes.new("Weed_Pot")
    bm.to_mesh(me)
    bm.free()
    me.validate(clean_customdata=False)
    return me


def export_glb(objs, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    props = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    wanted = dict(
        filepath=path,
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_cameras=False,
        export_lights=False,
        export_animations=False,
        export_extras=False,
        export_materials='EXPORT',
    )
    skipped = sorted(k for k in wanted if k not in props)
    bpy.ops.export_scene.gltf(**{k: v for k, v in wanted.items() if k in props})
    return skipped


def add_ref_mesh(name, build, color, loc=(0, 0, 0)):
    bm = bmesh.new()
    build(bm)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    obj.location = loc
    me.materials.append(make_mat("REF_" + name, color))
    bpy.context.scene.collection.objects.link(obj)
    return obj


def look_at(obj, target):
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()


def render_previews(scene, pot):
    os.makedirs(PREVIEW_DIR, exist_ok=True)

    ground = add_ref_mesh(
        "Ground",
        lambda bm: bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=2.0),
        (0.30, 0.30, 0.30))
    # Mannequin 1,86 m (taille mesurée de Suit.gltf)
    mannequin = add_ref_mesh(
        "Mannequin_1m86",
        lambda bm: (
            bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=12,
                                  radius1=0.20, radius2=0.20, depth=1.50,
                                  matrix=Matrix.Translation((0, 0, 0.75))),
            bmesh.ops.create_icosphere(bm, subdivisions=2, radius=0.13,
                                       matrix=Matrix.Translation((0, 0, 1.73))),
        ),
        (0.10, 0.20, 0.45), loc=(0.75, 0.0, 0.0))
    # Porte 1 x 2,2 m (Door_1 de city_kit)
    door = add_ref_mesh(
        "Door_1x2m2",
        lambda bm: bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Diagonal((1.0, 0.05, 2.2, 1.0))),
        (0.25, 0.14, 0.07), loc=(-0.95, 0.30, 1.10))

    world = bpy.data.worlds.new("Preview")
    world.color = (0.62, 0.66, 0.70)
    scene.world = world
    scene.view_settings.view_transform = 'Standard'
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.film_transparent = False
    shading = scene.display.shading
    shading.light = 'STUDIO'
    shading.color_type = 'MATERIAL'
    shading.show_shadows = True
    shading.show_cavity = True
    shading.show_object_outline = True

    cam_data = bpy.data.cameras.new("PreviewCam")
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam

    outputs = {}

    def shoot(filename):
        path = os.path.join(PREVIEW_DIR, filename)
        scene.render.filepath = path
        try:
            bpy.ops.render.render(write_still=True)
        except RuntimeError:
            scene.render.engine = 'CYCLES'
            scene.cycles.samples = 16
            scene.cycles.device = 'CPU'
            bpy.ops.render.render(write_still=True)
        outputs[filename] = path

    # 1) Échelle : vue de face orthographique
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = 3.0
    cam.location = (0.0, -6.0, 1.05)
    cam.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    shoot("Weed_Pot_preview_scale.png")

    # 2) Gros plan 3/4 plongeant, pot seul
    for o in (mannequin, door):
        o.hide_render = True
    cam_data.type = 'PERSP'
    cam_data.lens = 50.0
    cam.location = (0.80 * SCALE, -1.00 * SCALE, 1.00 * SCALE)
    look_at(cam, (0.0, 0.0, 0.20 * SCALE))
    shoot("Weed_Pot_preview_close.png")

    return outputs, scene.render.engine


def main():
    scene = reset_scene()

    mats = [
        make_mat("Plastic_Dark", COL_PLASTIC, roughness=0.5),
        make_mat("Soil_Dark", COL_SOIL, roughness=0.9),
        make_mat("Soil_Clod", COL_CLOD, roughness=0.9),
    ]
    me = build_pot_mesh()
    for m in mats:
        me.materials.append(m)
    pot = bpy.data.objects.new("Weed_Pot", me)
    scene.collection.objects.link(pot)

    socket = bpy.data.objects.new("PlantSocket", None)
    socket.empty_display_type = 'ARROWS'
    socket.empty_display_size = 0.1
    socket.location = (0.0, 0.0, SOIL_CENTER_Z * SCALE)
    socket.parent = pot
    scene.collection.objects.link(socket)

    bpy.context.view_layer.update()
    corners = [pot.matrix_world @ Vector(c) for c in pot.bound_box]
    dims = [max(c[i] for c in corners) - min(c[i] for c in corners) for i in range(3)]
    report = {
        "object": pot.name,
        "scale": SCALE,
        "dims_blender_xyz_m": [round(d, 4) for d in dims],
        "min_z": round(min(c[2] for c in corners), 4),
        "triangles": sum(len(p.vertices) - 2 for p in me.polygons),
        "vertices": len(me.vertices),
        "materials": [m.name for m in me.materials],
        "plant_socket_z": round(SOIL_CENTER_Z * SCALE, 4),
    }

    report["export_skipped_params"] = export_glb([pot, socket], OUT_GLB)
    os.makedirs(os.path.dirname(OUT_BLEND), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND, check_existing=False)

    previews, engine = render_previews(scene, pot)
    report["previews"] = previews
    report["render_engine"] = engine
    report["glb"] = OUT_GLB
    report["blend"] = OUT_BLEND
    print("BUILD_REPORT " + json.dumps(report))


main()
