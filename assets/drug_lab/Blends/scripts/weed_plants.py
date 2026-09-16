"""
Lot 2 drug_lab : plant de weed stylisé en 4 stades (échelle du perso, S_HUMAN).

Silhouettes bas-poly sans détail botanique : tige, touffes de feuillage, feuilles en
éventail, têtes plus claires aux stades 3 et 4. Géométrie en mètres réels, l'échelle est
appliquée par build_props.py. Origine au pied de la tige : le plant se pose sur le
PlantSocket de Weed_Pot (terre à 0,656 m, pot x2).
"""

import math
import random

from mathutils import Vector

from dl_common import MeshBuilder, cyl_between, ico, leaf_fan, mat, orient

STAGES = [
    # nom, hauteur (m), envergure (m), étages de branches, branches par étage, têtes, graine
    ("Weed_Plant_Stage1_Seedling", 0.15, 0.12, 0, 0, None, 11),
    ("Weed_Plant_Stage2_Vegetative", 0.50, 0.45, 3, 3, None, 12),
    ("Weed_Plant_Stage3_Flowering", 0.90, 0.70, 4, 4, "young", 13),
    ("Weed_Plant_Stage4_Mature", 1.20, 0.85, 5, 4, "ripe", 14),
]

# Plages de contrôle avant export (m ; axes Blender : x/y envergure, z hauteur)
EXPECT = {
    "Weed_Plant_Stage1_Seedling": {"x": (0.04, 0.22), "y": (0.04, 0.22), "z": (0.12, 0.21)},
    "Weed_Plant_Stage2_Vegetative": {"x": (0.28, 0.60), "y": (0.28, 0.60), "z": (0.42, 0.60)},
    "Weed_Plant_Stage3_Flowering": {"x": (0.45, 0.85), "y": (0.45, 0.85), "z": (0.80, 1.02)},
    "Weed_Plant_Stage4_Mature": {"x": (0.60, 1.00), "y": (0.60, 1.00), "z": (1.08, 1.32)},
}

STEM, FOLIAGE, LEAF, BUD, BUD_RIPE = range(5)


def _mats():
    return [
        mat("WD_Stem", (0.06, 0.12, 0.03), 0.8),
        mat("WD_Foliage", (0.02, 0.09, 0.02), 0.8),
        mat("WD_Leaf", (0.035, 0.16, 0.03), 0.7, double_sided=True),
        mat("WD_Bud", (0.14, 0.26, 0.06), 0.8),
        mat("WD_Bud_Ripe", (0.30, 0.36, 0.22), 0.8),
    ]


def _seedling(b, h):
    top = h * 0.8
    cyl_between(b, (0, 0, 0), (0, 0, top), 0.006, 0.004, segments=5, mi=STEM)
    for a in (0.0, math.pi):  # cotylédons
        leaf_fan(b, orient((0, 0, top), (math.cos(a), math.sin(a), 0.35)), 0.045, 0.025, blades=1, mi=LEAF)
    for k in range(3):  # premières feuilles
        a = 0.5 + k * 2.0 * math.pi / 3.0
        leaf_fan(b, orient((0, 0, h * 0.92), (math.cos(a), math.sin(a), 0.8)), 0.06, 0.018,
                 blades=3, spread=40.0, mi=LEAF)


def _bushy(b, h, spread, tiers, per_tier, buds, rng):
    cyl_between(b, (0, 0, 0), (0, 0, h * 0.9), 0.006 + 0.012 * h, 0.003 + 0.004 * h, segments=6, mi=STEM)
    bud_mi = BUD_RIPE if buds == "ripe" else BUD
    for i in range(tiers):
        t = i / (tiers - 1) if tiers > 1 else 0.0
        z = h * (0.22 + 0.58 * t)           # étages du bas vers le haut
        reach = spread / 2.0 * (1.0 - 0.55 * t)  # silhouette conique
        for j in range(per_tier):
            a = j * 2.0 * math.pi / per_tier + i * 0.6 + rng.uniform(-0.25, 0.25)
            d = Vector((math.cos(a), math.sin(a), 0.0))
            base = Vector((0.0, 0.0, z))
            tip = base + d * (reach * 0.45) + Vector((0.0, 0.0, reach * 0.30))
            cyl_between(b, base, tip, 0.004 + 0.004 * h, 0.003, segments=4, mi=STEM)
            puff = reach * 0.20  # touffe réduite : la feuille en éventail porte la silhouette
            ico(b, tip, puff, scale=(1.0, 1.0, 0.65), rot_z=rng.uniform(0.0, math.pi), mi=FOLIAGE)
            leaf_fan(b, orient(tip, d + Vector((0.0, 0.0, 0.5))), reach * 0.62, reach * 0.16,
                     blades=7, spread=80.0, mi=LEAF)
            if buds:
                ico(b, tip + Vector((0.0, 0.0, puff * 0.55)), reach * 0.12, scale=(1.0, 1.0, 1.4), mi=bud_mi)

    top = Vector((0.0, 0.0, h * 0.9))
    ico(b, top, h * 0.07, scale=(1.0, 1.0, 1.1), mi=FOLIAGE)
    for k in range(3):
        a = 0.3 + k * 2.0 * math.pi / 3.0
        leaf_fan(b, orient(top, (math.cos(a), math.sin(a), 1.5)), h * 0.16, h * 0.045,
                 blades=7, spread=70.0, mi=LEAF)
    if buds:
        ico(b, top + Vector((0.0, 0.0, h * 0.05)), h * 0.055, scale=(1.0, 1.0, 2.0), mi=bud_mi)


def build_plant(coll, name, h, spread, tiers, per_tier, buds, seed):
    b = MeshBuilder(name, _mats())
    if tiers == 0:
        _seedling(b, h)
    else:
        _bushy(b, h, spread, tiers, per_tier, buds, random.Random(seed))
    return b.finish(coll)


def builders():
    """(nom, fonction de build) pour build_props.py."""
    return [(s[0], (lambda coll, s=s: build_plant(coll, *s))) for s in STAGES]
