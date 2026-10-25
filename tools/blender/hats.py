"""Headwear by trade (the look of a villager tells the trade): straw hat (farmer), iron helmet (guard),
hood (woodcutter, gatherer), cap (mason, builder) and a feathered cap (merchant).

    blender -b --factory-startup --python tools/blender/hats.py -- <straw|helmet|hood|cap|feather_cap> <out.glb>

Origin at the crown of the head (the top of the villager's hair); the face looks to -Y in Blender. The game
puts the hat on the head bone.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

STRAW = (0.86, 0.72, 0.38)
STRAW_BAND = (0.55, 0.22, 0.14)
IRON = (0.55, 0.57, 0.60)
IRON_DARK = (0.36, 0.37, 0.40)
HOOD = (0.30, 0.36, 0.22)
LEATHER = (0.36, 0.24, 0.14)
FELT = (0.22, 0.30, 0.52)
FEATHER = (0.92, 0.88, 0.80)


def straw():
    s, band = common.flat_material("straw", STRAW), common.flat_material("band", STRAW_BAND)
    return [
        common.box("brim", (0.48, 0.48, 0.025), (0, 0, -0.025), s, "w"),
        common.box("crown", (0.25, 0.26, 0.13), (0, 0, 0.045), s, "w", top_scale=0.8),
        common.box("band", (0.255, 0.265, 0.03), (0, 0, 0.0), band, "w"),
    ]


def helmet():
    iron, dark = common.flat_material("iron", IRON), common.flat_material("iron_dark", IRON_DARK)
    return [
        common.box("dome", (0.28, 0.29, 0.17), (0, 0.0, -0.04), iron, "w", top_scale=0.7),
        common.box("rim", (0.3, 0.31, 0.035), (0, 0.0, -0.12), dark, "w"),
        common.box("nasal", (0.035, 0.03, 0.11), (0, -0.155, -0.17), dark, "w"),
    ]


def hood():
    cloth = common.flat_material("hood", HOOD)
    return [
        common.box("top", (0.29, 0.3, 0.06), (0, 0.01, -0.01), cloth, "w"),
        common.box("back", (0.29, 0.06, 0.3), (0, 0.135, -0.14), cloth, "w"),
        common.box("side.L", (0.04, 0.28, 0.26), (0.135, 0.01, -0.12), cloth, "w"),
        common.box("side.R", (0.04, 0.28, 0.26), (-0.135, 0.01, -0.12), cloth, "w"),
        common.box("drape", (0.32, 0.12, 0.08), (0, 0.13, -0.3), cloth, "w"),
    ]


def cap():
    leather = common.flat_material("leather", LEATHER)
    return [
        common.box("cap", (0.26, 0.27, 0.07), (0, 0.0, -0.005), leather, "w", top_scale=0.85),
        common.box("peak", (0.2, 0.09, 0.018), (0, -0.165, -0.035), leather, "w"),
    ]


def feather_cap():
    felt, feather = common.flat_material("felt", FELT), common.flat_material("feather", FEATHER)
    return [
        common.box("cap", (0.27, 0.28, 0.08), (0, 0.0, 0.0), felt, "w", top_scale=0.9),
        common.box("brim", (0.31, 0.32, 0.025), (0, 0.0, -0.04), felt, "w"),
        common.box("feather", (0.02, 0.05, 0.2), (0.11, 0.06, 0.1), feather, "w", top_scale=0.4),
    ]


BUILDERS = {"straw": straw, "helmet": helmet, "hood": hood, "cap": cap, "feather_cap": feather_cap}

argv = sys.argv[sys.argv.index("--") + 1:]
if len(argv) != 2 or argv[0] not in BUILDERS:
    raise SystemExit("usage: hats.py -- <%s> <out.glb>" % "|".join(BUILDERS))
kind, out = argv
common.reset_scene()
common.join(BUILDERS[kind](), kind)
common.export_glb(out)
print("EXPORTED", out)
