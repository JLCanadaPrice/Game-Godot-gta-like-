"""
Exécuteur générique des lots Blender (faction_gear, apartments...) : construit les assets d'un
module de lot, applique S_HUMAN aux sommets, contrôle les dimensions (EXPECT du module), rend les
aperçus en situation (module.stage), puis exporte les .glb et sauvegarde le .blend seulement avec
--export ET si tous les contrôles passent.

Un module de lot définit : ROOT (dossier assets du lot), BLEND (nom du .blend dans ROOT/Blends),
ASSETS = [(nom, sous-dossier, fonction de build)], EXPECT = {nom: plages} et stage(roots, coll)
qui met en scène les aperçus et renvoie la liste des prises de vue.

Usage : blender --background --factory-startup --python run_lot.py -- <module.py> <preview_dir> [--export]
"""

import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402

import dl_common as dl  # noqa: E402

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
MODULE_PATH, PREVIEW_DIR, EXPORT = os.path.abspath(ARGV[0]), ARGV[1], "--export" in ARGV
sys.path.insert(0, os.path.dirname(MODULE_PATH))
_spec = importlib.util.spec_from_file_location("lot", MODULE_PATH)
lot = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(lot)


def render(scene, shots):
    for o in bpy.data.objects:
        if dl.base_name(o).endswith("colonly"):
            o.hide_render = True
    bpy.data.collections["Parts"].hide_render = True
    cam = dl.setup_workbench(scene, 1600)
    cam.data.clip_end = 500.0
    out = []
    for s in shots:
        scene.render.resolution_x, scene.render.resolution_y = s.get("res", (1600, 900))
        hidden = [o for o in bpy.data.objects if o.name in s.get("hide", ())]
        for o in hidden:
            o.hide_render = True
        cam.data.type = s.get("type", 'PERSP')
        if cam.data.type == 'ORTHO':
            cam.data.ortho_scale = s["ortho_scale"]
        else:
            cam.data.lens = s.get("lens", 35.0)
        cam.location = s["loc"]
        dl.look_at(cam, s["target"])
        out.append(dl.shoot(scene, os.path.join(PREVIEW_DIR, s["file"])))
        for o in hidden:
            o.hide_render = False
    return out


def main():
    scene = dl.reset_scene()
    parts = dl.collection("Parts")
    roots = {name: dl.bake_scale(build(parts), dl.S_HUMAN) for name, _sub, build in lot.ASSETS}
    bpy.context.view_layer.update()

    errors, report = [], {"module": os.path.basename(MODULE_PATH), "S_HUMAN": dl.S_HUMAN, "assets": {}}
    for name, root in roots.items():
        errs = dl.check_dims(root, lot.EXPECT[name])
        errors += errs
        report["assets"][name] = dict(dl.stats(root), ok=not errs)
    report["scale_errors"] = list(errors)
    if hasattr(lot, "extra_checks"):  # garde-fous propres au lot (passages, emprise, repères...)
        extra = lot.extra_checks(roots)
        errors += extra
        report["extra_errors"] = extra

    exported = EXPORT and not errors
    if exported:
        for name, sub, _build in lot.ASSETS:
            dl.export_glb(roots[name], os.path.join(lot.ROOT, sub, name + ".glb"))
    report["exported"] = exported

    report["previews"] = render(scene, lot.stage(roots, dl.collection("Stage")))
    if exported:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(lot.ROOT, "Blends", lot.BLEND), check_existing=False)
    print("BUILD_REPORT " + json.dumps(report))
    if errors:
        raise RuntimeError("Contrôle en échec, rien n'a été exporté : " + " | ".join(errors))


main()
