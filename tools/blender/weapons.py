"""Low-poly medieval weapons held by the player: sword, spear, bow, and the arrow it shoots.

    blender -b --factory-startup --python tools/blender/weapons.py -- <sword|spear|bow|arrow> <out.glb>

Origin at the grip (the arrow: at its nock). The weapon points along +Z in Blender, which is
+Y in Godot; the game turns that axis to the character's front. Limbs of the bow lie along Y.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

STEEL = (0.72, 0.74, 0.78)
WOOD = (0.45, 0.30, 0.17)
LEATHER = (0.28, 0.17, 0.10)
BRASS = (0.72, 0.58, 0.28)
STRING = (0.88, 0.85, 0.76)
FEATHER = (0.85, 0.82, 0.78)


def sword():
    steel = common.flat_material("steel", STEEL)
    leather = common.flat_material("leather", LEATHER)
    brass = common.flat_material("brass", BRASS)
    return [
        common.box("grip", (0.035, 0.035, 0.16), (0, 0, 0), leather, "w"),
        common.box("pommel", (0.06, 0.06, 0.05), (0, 0, -0.1), brass, "w"),
        common.box("guard", (0.22, 0.04, 0.035), (0, 0, 0.09), brass, "w"),
        common.box("blade", (0.06, 0.015, 0.72), (0, 0, 0.465), steel, "w", top_scale=0.35),
    ]


def spear():
    wood = common.flat_material("wood", WOOD)
    steel = common.flat_material("steel", STEEL)
    return [
        common.box("shaft", (0.035, 0.035, 1.7), (0, 0, 0.35), wood, "w"),
        common.box("socket", (0.05, 0.05, 0.08), (0, 0, 1.2), steel, "w"),
        common.box("head", (0.08, 0.02, 0.26), (0, 0, 1.37), steel, "w", top_scale=0.1),
    ]


def bow():
    wood = common.flat_material("wood", WOOD)
    leather = common.flat_material("leather", LEATHER)
    string = common.flat_material("string", STRING)
    parts = [common.box("grip", (0.045, 0.05, 0.05), (0, 0, 0), leather, "w")]
    half, depth, segments = 0.6, 0.15, 6
    # Arc in the YZ plane: belly at the grip, tips bent back toward -Z.
    def z_at(y):
        return -depth * (y / half) ** 2

    step = half * 2 / segments
    for i in range(segments):
        y0 = -half + i * step
        y1 = y0 + step
        z0, z1 = z_at(y0), z_at(y1)
        seg = common.box(f"limb{i}", (0.03, math.hypot(step, z1 - z0) + 0.01, 0.035),
                         (0, (y0 + y1) / 2, (z0 + z1) / 2), wood, "w")
        seg.rotation_euler = (math.atan2(z1 - z0, step), 0, 0)
        parts.append(seg)
    parts.append(common.box("string", (0.008, half * 2, 0.008), (0, 0, -depth), string, "w"))
    return parts


def arrow():
    wood = common.flat_material("wood", WOOD)
    steel = common.flat_material("steel", STEEL)
    feather = common.flat_material("feather", FEATHER)
    return [
        common.box("shaft", (0.015, 0.015, 0.7), (0, 0, 0.35), wood, "w"),
        common.box("head", (0.045, 0.012, 0.08), (0, 0, 0.73), steel, "w", top_scale=0.1),
        common.box("fletch_a", (0.004, 0.06, 0.1), (0, 0, 0.07), feather, "w"),
        common.box("fletch_b", (0.06, 0.004, 0.1), (0, 0, 0.07), feather, "w"),
    ]


BUILDERS = {"sword": sword, "spear": spear, "bow": bow, "arrow": arrow}

argv = sys.argv[sys.argv.index("--") + 1:]
if len(argv) != 2 or argv[0] not in BUILDERS:
    raise SystemExit("usage: weapons.py -- <%s> <out.glb>" % "|".join(BUILDERS))
kind, out = argv
common.reset_scene()
common.join(BUILDERS[kind](), kind)
common.export_glb(out)
print("EXPORTED", out)
