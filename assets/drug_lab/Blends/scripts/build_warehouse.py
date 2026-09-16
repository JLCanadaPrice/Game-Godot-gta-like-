"""
Lot 1 drug_lab : entrepôt (coque x S_SHELL, porte piétonne x S_HUMAN, cf. dl_common).

Exporte 7 .glb dans assets/drug_lab/warehouse/, sauvegarde Blends/Warehouse.blend
(assemblage complet, pièces sources masquées), puis rend 3 aperçus avec un
mannequin de 1,86 m (taille réelle du perso) et le Weed_Pot tel qu'exporté.

Usage :
  blender --background --factory-startup --python build_warehouse.py -- <preview_dir>
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402

import dl_common as dl  # noqa: E402
import wh_parts  # noqa: E402
import wh_shell  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))  # assets/drug_lab
OUT_DIR = os.path.join(ROOT, "warehouse")
BLEND = os.path.join(ROOT, "Blends", "Warehouse.blend")
ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PREVIEW_DIR = ARGV[0] if ARGV else os.path.join(HERE, "previews")


def assemble(objs):
    """Copies liées des pièces aux sockets des murs (pour le .blend et les aperçus)."""
    asm = dl.collection("Assembly")
    walls = objs["Warehouse_Walls"]
    for sock in (c for c in walls.children if c.type == 'EMPTY'):
        loc = sock.matrix_world.translation.copy()
        name = sock.name.replace("Socket_", "")
        if name.startswith("Pillar"):
            dl.instance(objs["Warehouse_Pillar"], name, loc, asm)
        elif name.startswith("Light"):
            dl.instance(objs["Warehouse_CeilingLight"], name, loc, asm)
        elif name == "LoadingDoor":
            dl.instance(objs["Warehouse_LoadingDoor"], name, loc, asm)
        elif name == "Door":
            frame = objs["Warehouse_Door"]
            dl.instance(frame, name, loc, asm)
            leaf = next(c for c in frame.children if c.type == 'MESH' and not c.name.endswith("colonly"))
            dl.instance(leaf, "Door_Leaf", loc + leaf.location, asm)
    return asm


def render_previews(scene, objs):
    for o in bpy.data.objects:
        if o.name.endswith("colonly"):
            o.hide_render = True
    cam = dl.setup_workbench(scene, 1000)
    cam.data.clip_end = 1000.0
    refs = dl.collection("REF")

    ground = dl.MeshBuilder("REF_Ground", [dl.mat("REF_Ground", (0.09, 0.10, 0.09), 0.9)])
    ground.box((-80.0, -80.0, -0.5), (80.0, 80.0, 0.0))
    ground.finish(refs)

    front_y = -wh_shell.D / 2.0
    man_x = wh_shell.PED_DOOR["u"] + 2.5
    dl.mannequin(refs, (man_x, front_y - 1.5, 0.0))

    pot_path = os.path.join(ROOT, "weed", "Weed_Pot.glb")
    if os.path.exists(pot_path):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=pot_path)
        for o in set(bpy.data.objects) - before:
            if o.parent is None:
                o.location = (man_x + 1.2, front_y - 1.5, 0.0)  # échelle du .glb, sans retouche

    out = {}
    cam.data.lens = 30.0
    cam.location = (-48.0, -78.0, 26.0)
    dl.look_at(cam, (0.0, 0.0, 5.0))
    out["exterior"] = dl.shoot(scene, os.path.join(PREVIEW_DIR, "Warehouse_preview_exterior.png"))

    mid_x = (wh_shell.PED_DOOR["u"] + wh_shell.LOADING_DOOR["u"]) / 2.0  # cadré entre les deux portes
    cam.data.lens = 28.0
    cam.location = (mid_x, front_y - 24.0, 3.0)
    dl.look_at(cam, (mid_x, front_y, 4.0))
    out["entrance"] = dl.shoot(scene, os.path.join(PREVIEW_DIR, "Warehouse_preview_entrance.png"))

    objs["Warehouse_Roof"].hide_render = True
    cam.data.lens = 24.0
    cam.location = (0.0, front_y - 14.0, 48.0)
    dl.look_at(cam, (0.0, 2.0, 0.0))
    out["interior"] = dl.shoot(scene, os.path.join(PREVIEW_DIR, "Warehouse_preview_interior.png"))
    return out


def main():
    scene = dl.reset_scene()
    shell = dl.collection("Warehouse")
    parts = dl.collection("Parts")
    objs = {
        "Warehouse_Walls": wh_shell.build_walls(shell),
        "Warehouse_Floor": wh_shell.build_floor(shell),
        "Warehouse_Roof": wh_shell.build_roof(shell),
        "Warehouse_Pillar": wh_parts.build_pillar(parts),
        "Warehouse_CeilingLight": wh_parts.build_ceiling_light(parts),
        "Warehouse_LoadingDoor": wh_parts.build_loading_door(parts),
        "Warehouse_Door": wh_parts.build_door(parts),
    }
    bpy.context.view_layer.update()

    report = {"S_SHELL": dl.S_SHELL, "S_HUMAN": dl.S_HUMAN, "exports": {}}
    for name, obj in objs.items():
        report["exports"][name] = dl.export_glb(obj, os.path.join(OUT_DIR, name + ".glb"))

    assemble(objs)
    parts.hide_viewport = True
    parts.hide_render = True
    os.makedirs(os.path.dirname(BLEND), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND, check_existing=False)

    report["previews"] = render_previews(scene, objs)
    print("BUILD_REPORT " + json.dumps(report))


main()
