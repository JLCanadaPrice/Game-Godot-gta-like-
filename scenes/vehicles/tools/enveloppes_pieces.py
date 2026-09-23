# ENVELOPPES PAR PIÈCE des camions, bus et pick-up (2026-09-23, CLAUDE.md §12).
#
# Une enveloppe convexe unique relie le toit de la cabine au bout de la benne d'un pick-up, ou le haut d'une cabine de
# camion au plateau qui la suit : c'est une rampe de vide que la voiture emporte avec elle. Ce script coupe la caisse
# aux MARCHES de son profil (lu au rayon, du dessus, tous les PAS) et fait une enveloppe par tronçon, une par roue et une
# par pièce séparée (tourelle). Mêmes deux retouches que l'enveloppe unique de Car.gd : les rétroviseurs ramenés à la
# largeur du tronçon sous la ceinture, et sous les pare-chocs avant et arrière une face VERTICALE jusqu'au sol (les
# bordures de 0,15 m s'y appuient : _try_step_up du joueur, arrêt de la circulation, CarKerbTest).
# Rend aussi une image par modèle (Cycles, processeur) : le modèle en gris, ses enveloppes en couleur, pour REGARDER.
#
# Entrée : l'export de EnveloppesExport.gd (triangles par pièce, repère de la voiture Godot : y en haut, -z à l'avant).
# Lancer :
#   blender -b --factory-startup --python scenes/vehicles/tools/enveloppes_pieces.py -- --entree=<export.json>
#       --sortie=<projet>/scenes/vehicles/enveloppes_pieces.json --images=<dossier hors du dépôt>

import bpy, bmesh, json, sys, os, math
from mathutils import Vector
from mathutils.bvhtree import BVHTree

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
opt = dict(a[2:].split("=", 1) for a in args if a.startswith("--") and "=" in a)
ENTREE, SORTIE, IMAGES = opt["entree"], opt["sortie"], opt.get("images", "")

PAS = 0.10          # m : tranches du profil le long de la voiture
MARCHE = 0.35       # m : saut de hauteur du dessus qui sépare deux pièces (cabine / benne, cabine / caisse)
TRONCON_MIN = 0.8   # m : un tronçon plus court est rendu à son voisin
CEINTURE = 0.55     # largeur de référence d'un tronçon : sous 55 % de sa hauteur (ni rétroviseur ni galerie)
JUPE = 0.35         # bande basse (fraction de la hauteur) qui donne l'aplomb des pare-chocs


def g2b(x, y, z):
    return Vector((x, -z, y))           # Godot -> Blender : z en haut, +y vers l'avant


def b2g(v):
    return [round(v.x, 4), round(v.z, 4), round(-v.y, 4)]


def triangles(plat):
    s = [g2b(plat[i], plat[i + 1], plat[i + 2]) for i in range(0, len(plat), 3)]
    return [s[i:i + 3] for i in range(0, len(s) - 2, 3)]


def bm_depuis(tris):
    bm = bmesh.new()
    index = {}
    for t in tris:
        vs = []
        for v in t:
            k = (round(v.x, 4), round(v.y, 4), round(v.z, 4))
            if k not in index:
                index[k] = bm.verts.new(v)
            vs.append(index[k])
        if len({id(x) for x in vs}) == 3:
            try:
                bm.faces.new(vs)
            except ValueError:
                pass    # face déjà là (doublon du modèle)
    bm.verts.ensure_lookup_table()
    return bm


def enveloppe(points):
    """Sommets de l'enveloppe convexe d'un nuage de points (Blender), ou [] si elle est plate."""
    if len(points) < 4:
        return []
    bm = bmesh.new()
    for p in points:
        bm.verts.new(p)
    r = bmesh.ops.convex_hull(bm, input=bm.verts[:])
    for v in r["geom_interior"] + r["geom_unused"]:
        if isinstance(v, bmesh.types.BMVert) and v.is_valid:
            bm.verts.remove(v)
    pts = [v.co.copy() for v in bm.verts if v.is_valid and v.link_faces]
    bm.free()
    if len(pts) < 4:
        return []
    # volume nul (pièce plate) : Jolt n'en veut pas
    c = sum(pts, Vector()) / len(pts)
    etendue = [max(abs((p - c)[i]) for p in pts) for i in range(3)]
    return pts if min(etendue) > 0.01 else []


def profil_dessus(tris, y0, y1, x0, x1):
    bvh = BVHTree.FromPolygons([v for t in tris for v in t], [(3 * i, 3 * i + 1, 3 * i + 2) for i in range(len(tris))])
    n = max(int((y1 - y0) / PAS), 1)
    haut = []
    for i in range(n):
        y = y0 + (i + 0.5) * PAS
        h = None
        for k in range(9):
            x = x0 + (x1 - x0) * (0.1 + 0.8 * k / 8)
            hit = bvh.ray_cast(Vector((x, y, 50.0)), Vector((0, 0, -1)))
            if hit[0] is not None:
                h = hit[0].z if h is None else max(h, hit[0].z)
        haut.append(h)
    # tranches sans rien dessous (vide entre deux pièces) : la hauteur de la voisine
    for i in range(n):
        if haut[i] is None:
            voisines = [haut[j] for j in range(max(0, i - 3), min(n, i + 4)) if haut[j] is not None]
            haut[i] = max(voisines) if voisines else 0.0
    return haut


def troncons(haut, y0, y1):
    coupes = [y0 + (i + 1) * PAS for i in range(len(haut) - 1) if abs(haut[i + 1] - haut[i]) > MARCHE]
    bornes = [y0]
    for c in coupes:
        if c - bornes[-1] >= TRONCON_MIN and y1 - c >= TRONCON_MIN:
            bornes.append(c)
    bornes.append(y1)
    return [(bornes[i], bornes[i + 1]) for i in range(len(bornes) - 1)]


def morceau(tris, ya, yb):
    """Sommets de la caisse entre les plans y = ya et y = yb (coupés proprement, bisect)."""
    bm = bm_depuis(tris)
    g = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=g, dist=0.0001, plane_co=(0, ya, 0), plane_no=(0, 1, 0), clear_inner=True)
    g = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=g, dist=0.0001, plane_co=(0, yb, 0), plane_no=(0, 1, 0), clear_outer=True)
    pts = [v.co.copy() for v in bm.verts if v.is_valid]
    bm.free()
    return pts


def enveloppes_du_modele(m):
    pieces = m["pieces"]
    non_roues = [p for p in pieces if not p["roue"]]
    corps = max(non_roues, key=lambda p: len(p["sommets"]))
    tc = triangles(corps["sommets"])
    tous = [v for t in tc for v in t]
    roues = [triangles(p["sommets"]) for p in pieces if p["roue"]]
    sol = min([v.z for r in roues for t in r for v in t] + [v.z for v in tous])
    y0, y1 = min(v.y for v in tous), max(v.y for v in tous)
    x0, x1 = min(v.x for v in tous), max(v.x for v in tous)
    h_tot = max(v.z for v in tous) - sol
    haut = profil_dessus(tc, y0, y1, x0, x1)
    parts = troncons(haut, y0, y1)
    bas = [v for v in tous if v.z <= sol + JUPE * h_tot]
    y_avant = max(v.y for v in bas) if bas else y1
    y_arriere = min(v.y for v in bas) if bas else y0
    sortie = []
    for i, (ya, yb) in enumerate(parts):
        pts = morceau(tc, ya, yb)
        if len(pts) < 4:
            continue
        top = max(p.z for p in pts)
        ref = max([abs(p.x) for p in pts if p.z <= sol + CEINTURE * (top - sol)] or [max(abs(p.x) for p in pts)])
        pts = [Vector((max(-ref, min(ref, p.x)), p.y, p.z)) for p in pts]
        if yb >= y1 - 1e-6:    # tronçon avant : aplomb du pare-chocs avant jusqu'au sol
            pts += [Vector((-ref, y_avant, sol)), Vector((ref, y_avant, sol))]
        if ya <= y0 + 1e-6:    # tronçon arrière
            pts += [Vector((-ref, y_arriere, sol)), Vector((ref, y_arriere, sol))]
        env = enveloppe(pts)
        if env:
            sortie.append(("caisse %d" % i, env))
    for p in non_roues:
        if p is corps:
            continue
        env = enveloppe([v for t in triangles(p["sommets"]) for v in t])
        if env:
            sortie.append((p["nom"], env))
    for k, r in enumerate(roues):
        env = enveloppe([v for t in r for v in t])
        if env:
            sortie.append(("roue %d" % k, env))
    return sortie, parts, tc, roues, [triangles(p["sommets"]) for p in non_roues if p is not corps]


# --- image de contrôle ----------------------------------------------------------------------------------------------
def objet(nom, tris, couleur, alpha):
    me = bpy.data.meshes.new(nom)
    verts = [v for t in tris for v in t]
    me.from_pydata(verts, [], [(3 * i, 3 * i + 1, 3 * i + 2) for i in range(len(tris))])
    ob = bpy.data.objects.new(nom, me)
    bpy.context.scene.collection.objects.link(ob)
    mat = bpy.data.materials.new(nom)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = couleur
    bsdf.inputs["Alpha"].default_value = alpha
    me.materials.append(mat)
    return ob


def tris_enveloppe(points):
    bm = bmesh.new()
    for p in points:
        bm.verts.new(p)
    bmesh.ops.convex_hull(bm, input=bm.verts[:])
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    t = [[v.co.copy() for v in f.verts] for f in bm.faces]
    bm.free()
    return t


def rendre(mid, envs, tc, roues, autres, chemin):
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob)
    objet("caisse", tc, (0.55, 0.55, 0.55, 1.0), 1.0)
    for r in roues + autres:
        objet("piece", r, (0.2, 0.2, 0.2, 1.0), 1.0)
    couleurs = [(0.95, 0.35, 0.1, 1), (0.1, 0.55, 0.95, 1), (0.2, 0.8, 0.3, 1), (0.9, 0.8, 0.1, 1), (0.8, 0.2, 0.8, 1)]
    for i, (nom, pts) in enumerate(envs):
        objet("env_%d" % i, tris_enveloppe(pts), couleurs[i % len(couleurs)] if nom.startswith("caisse") else (0.9, 0.9, 0.9, 1), 0.35)
    tous = [v for t in tc for v in t]
    c = sum(tous, Vector()) / len(tous)
    longueur = max(v.y for v in tous) - min(v.y for v in tous)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 16
    scene.render.resolution_x, scene.render.resolution_y = 800, 450
    if scene.world is None:
        scene.world = bpy.data.worlds.new("monde")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (1, 1, 1, 1)
    soleil = bpy.data.objects.new("soleil", bpy.data.lights.new("soleil", "SUN"))
    soleil.data.energy = 3.0
    soleil.rotation_euler = (math.radians(50), 0, math.radians(30))
    scene.collection.objects.link(soleil)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    for vue, pos in (("profil", Vector((longueur * 1.6, 0, 0.3))), ("trois_quarts", Vector((longueur * 0.9, longueur * 0.9, longueur * 0.5)))):
        cam.location = c + pos
        direction = c - cam.location
        cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        cam.data.lens = 50
        scene.render.filepath = os.path.join(chemin, "%s_%s.png" % (mid, vue))
        bpy.ops.render.render(write_still=True)


donnees = json.load(open(ENTREE, encoding="utf-8"))
resultat = {}
for mid in sorted(donnees):
    envs, parts, tc, roues, autres = enveloppes_du_modele(donnees[mid])
    resultat[mid] = [[b2g(p) for p in pts] for (_, pts) in envs]
    print("ENVELOPPES_PIECES %-20s %-7s : %d troncon(s) de caisse %s, %d enveloppes en tout (%s)" % (
        mid, donnees[mid]["famille"], len(parts), ["%.2f..%.2f" % (-b, -a) for (a, b) in parts], len(envs),
        ", ".join("%s %d pts" % (n, len(p)) for (n, p) in envs)))
    if IMAGES:
        os.makedirs(IMAGES, exist_ok=True)
        rendre(mid, envs, tc, roues, autres, IMAGES)
with open(SORTIE, "w", encoding="utf-8") as f:
    json.dump(resultat, f, separators=(",", ":"))
print("ENVELOPPES_PIECES_FIN %d modeles -> %s" % (len(resultat), SORTIE))
