"""
Lots 2 (weed) et 3 (coke) drug_lab : props à l'échelle du perso (S_HUMAN).

1) Construit chaque asset, applique l'échelle aux sommets et contrôle ses dimensions
   contre les plages attendues du module (EXPECT).
2) Rend des aperçus en situation : mannequins de 1,86 m, plants posés sur le Weed_Pot x2
   (hauteur lue sur son PlantSocket), petits props posés sur la table de leur lot.
3) Exporte les .glb et sauvegarde le .blend seulement avec --export ET si tous les
   contrôles passent ; sinon rien n'est écrit dans le projet.

Usage :
  blender --background --factory-startup --python build_props.py -- <weed|coke> <preview_dir> [--export]
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import coke_props  # noqa: E402
import dl_common as dl  # noqa: E402
import weed_plants  # noqa: E402
import weed_props  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))  # assets/drug_lab
ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
LOT, PREVIEW_DIR, EXPORT = ARGV[0], ARGV[1], "--export" in ARGV

LOTS = {
    "weed": dict(folder="weed", blend="Weed_Props.blend",
                 builders=weed_plants.builders() + weed_props.builders(),
                 expect={**weed_plants.EXPECT, **weed_props.EXPECT}, table="Weed_TrimTable"),
    "coke": dict(folder="coke", blend="Coke_Props.blend",
                 builders=coke_props.builders(), expect=coke_props.EXPECT, table="Coke_Table"),
}

# Mise en scène des aperçus : (x, y, z) ; z = "pot" (sur le PlantSocket), "table" (sur le plateau), "lamp"
STAGING = {
    "weed": {
        "Weed_Plant_Stage1_Seedling": (0.0, 0.0, "pot"),
        "Weed_Plant_Stage2_Vegetative": (1.0, 0.0, "pot"),
        "Weed_Plant_Stage3_Flowering": (2.0, 0.0, "pot"),
        "Weed_Plant_Stage4_Mature": (3.0, 0.0, "pot"),
        "Weed_GrowLamp": (3.0, 0.0, "lamp"),
        "Weed_DryingRack": (5.0, 0.0, 0.0),
        "Weed_TrimTable": (8.0, 0.0, 0.0),
        "Weed_Jar": (8.72, 0.0, "table"),
    },
    "coke": {
        "Coke_Table": (1.0, 0.0, 0.0),
        "Coke_Pile": (0.35, 0.15, "table"),
        "Coke_Scale": (0.35, -0.30, "table"),
        "Coke_Bags_Stack": (0.85, -0.15, "table"),
        "Coke_Bag": (0.95, 0.25, "table"),
        "Coke_Brick": (1.45, -0.20, "table"),
        "Coke_Bricks_Stack": (1.55, 0.20, "table"),
        "Coke_Press": (2.9, 0.0, 0.0),
    },
}
MANNEQUINS = {"weed": [(-0.8, 0.0), (9.4, 0.0)], "coke": [(-0.8, 0.0), (3.8, 0.0)]}
CLOSEUP = {"weed": ((1.5, -3.4, 1.7), (1.5, 0.0, 0.9)), "coke": ((1.0, -1.7, 1.8), (1.0, 0.0, 0.9))}


def _collision_top(root):
    col = next(c for c in root.children if c.name.endswith("colonly"))
    return max((col.matrix_world @ Vector(v)).z for v in col.bound_box)


def render_lineup(scene, roots):
    for o in bpy.data.objects:
        if o.name.endswith("colonly"):
            o.hide_render = True
    bpy.data.collections["Parts"].hide_render = True
    refs = dl.collection("Lineup")
    ground = dl.MeshBuilder("REF_Ground", [dl.mat("REF_Ground", (0.30, 0.30, 0.30), 0.9)])
    ground.box((-3.0, -3.0, -0.2), (12.0, 3.0, 0.0))
    ground.finish(refs)
    for x, y in MANNEQUINS[LOT]:
        dl.mannequin(refs, (x, y, 0.0))

    heights = {"table": _collision_top(roots[LOTS[LOT]["table"]])}
    pot = None
    if LOT == "weed":
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "weed", "Weed_Pot.glb"))
        new = set(bpy.data.objects) - before
        pot = next(o for o in new if o.type == 'MESH')
        heights["pot"] = next(o for o in new if o.type == 'EMPTY').matrix_world.translation.z  # PlantSocket réel
        pot.hide_render = True
        heights["lamp"] = (heights["pot"] + dl.stats(roots["Weed_Plant_Stage4_Mature"])["size_xyz_m"][2]
                           + 0.35 + dl.stats(roots["Weed_GrowLamp"])["size_xyz_m"][2])

    for name, (x, y, z) in STAGING[LOT].items():
        if z == "pot":
            dl.instance(pot, "Pot_" + name, (x, y, 0.0), refs)
        dl.instance(roots[name], "Lineup_" + name, (x, y, heights.get(z, z)), refs)

    cam = dl.setup_workbench(scene, 2000)
    scene.render.resolution_y = 800
    cam.data.clip_end = 200.0
    xs = [p[0] for p in STAGING[LOT].values()] + [m[0] for m in MANNEQUINS[LOT]]
    x0, x1 = min(xs) - 1.2, max(xs) + 1.2
    cx = (x0 + x1) / 2.0
    out = {}
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = x1 - x0
    cam.location = (cx, -20.0, (x1 - x0) * 0.2 - 0.3)
    cam.rotation_euler = (dl.deg(90.0), 0.0, 0.0)
    out["front"] = dl.shoot(scene, os.path.join(PREVIEW_DIR, "Lot_%s_front.png" % LOT))

    cam.data.type = 'PERSP'
    cam.data.lens = 24.0
    cam.location = (cx, -5.5 - 0.25 * (x1 - x0), 2.6)
    dl.look_at(cam, (cx, 0.0, 0.8))
    out["overview"] = dl.shoot(scene, os.path.join(PREVIEW_DIR, "Lot_%s_overview.png" % LOT))

    cam.data.lens = 35.0
    cam.location = CLOSEUP[LOT][0]
    dl.look_at(cam, CLOSEUP[LOT][1])
    out["closeup"] = dl.shoot(scene, os.path.join(PREVIEW_DIR, "Lot_%s_closeup.png" % LOT))
    return out


def main():
    cfg = LOTS[LOT]
    scene = dl.reset_scene()
    parts = dl.collection("Parts")
    roots = {name: dl.bake_scale(build(parts), dl.S_HUMAN) for name, build in cfg["builders"]}
    bpy.context.view_layer.update()

    errors, report = [], {"lot": LOT, "S_HUMAN": dl.S_HUMAN, "assets": {}}
    for name, root in roots.items():
        errs = dl.check_dims(root, cfg["expect"][name])
        errors += errs
        report["assets"][name] = dict(dl.stats(root), ok=not errs)
    report["scale_errors"] = errors

    exported = EXPORT and not errors
    if exported:
        for name, root in roots.items():
            dl.export_glb(root, os.path.join(ROOT, cfg["folder"], name + ".glb"))
    report["exported"] = exported

    report["previews"] = render_lineup(scene, roots)
    if exported:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "Blends", cfg["blend"]), check_existing=False)
    print("BUILD_REPORT " + json.dumps(report))
    if errors:
        raise RuntimeError("Contrôle d'échelle en échec, rien n'a été exporté : " + " | ".join(errors))


main()
