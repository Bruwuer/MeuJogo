"""Low-poly creature parts, assembled at runtime by CreatureBody from a creature's genome.

    blender -b --factory-startup --python tools/blender/creature_parts.py -- <part> <out.glb>

Blender axes: front = -Y, up = +Z (Godot: front = +Z). Conventions (size 1 ~ a wolf):
  body_*  : origin at the torso center
  head_*  : origin at the neck joint, extends toward -Y (front)
  tail_*  : origin at the tail base, extends toward +Y (back)
  leg_*   : origin at the hip, unit length down to z = -1 (scaled per body in Godot)
  extra_* : origin at its socket (body socket, or head top for antlers/horns)
Materials: "primary" / "secondary" are recolored per creature; "eye" and "horn" keep their color.
"""
import math
import os
import sys

import bmesh

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

GREY = (0.6, 0.6, 0.6)
LIGHT = (0.85, 0.85, 0.85)
EYE = (0.05, 0.04, 0.04)
HORN = (0.86, 0.82, 0.70)


def mats():
    return (common.flat_material("primary", GREY), common.flat_material("secondary", LIGHT),
            common.flat_material("eye", EYE), common.flat_material("horn", HORN))


def box(name, size, loc, mat, top_scale=1.0):
    return common.box(name, size, loc, mat, "none", top_scale=top_scale)


def cone(name, r1, r2, depth, loc, mat, rot=(0, 0, 0), segments=5):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=r1, radius2=r2, depth=depth)
    obj = common.mesh_object(name, bm, loc, mat)
    obj.rotation_euler = rot
    return obj


def blob(name, radius, loc, mat, scale=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius)
    return common.mesh_object(name, bm, loc, mat, scale)


def eyes(x, y, z, eye, size=0.035):
    return [box("eye_l", (size, size, size), (x, y, z), eye), box("eye_r", (size, size, size), (-x, y, z), eye)]


# --- bodies ---------------------------------------------------------------------------------
def body_canine():
    p, s, _, _ = mats()
    return [box("torso", (0.42, 1.0, 0.42), (0, 0, 0), p, top_scale=0.9),
            box("chest", (0.4, 0.35, 0.4), (0, -0.3, 0.03), p),
            box("belly", (0.34, 0.7, 0.08), (0, 0.02, -0.21), s)]


def body_bulky():
    p, s, _, _ = mats()
    return [box("torso", (0.7, 1.2, 0.7), (0, 0, 0), p, top_scale=0.85),
            box("hump", (0.6, 0.5, 0.25), (0, -0.3, 0.35), p),
            box("belly", (0.56, 0.9, 0.08), (0, 0, -0.35), s)]


def body_lizard():
    p, s, _, _ = mats()
    return [box("torso", (0.5, 1.4, 0.3), (0, 0, 0), p, top_scale=0.8),
            box("belly", (0.44, 1.2, 0.06), (0, 0, -0.15), s)]


def body_deer():
    p, s, _, _ = mats()
    return [box("torso", (0.36, 0.95, 0.4), (0, 0, 0), p, top_scale=0.9),
            box("belly", (0.3, 0.7, 0.08), (0, 0, -0.2), s),
            box("rump", (0.3, 0.12, 0.2), (0, 0.46, 0.05), s)]


# --- heads ----------------------------------------------------------------------------------
def head_wolf():
    p, s, e, _ = mats()
    return [box("skull", (0.26, 0.3, 0.24), (0, -0.15, 0.04), p),
            box("snout", (0.14, 0.24, 0.12), (0, -0.4, -0.02), s),
            box("nose", (0.06, 0.04, 0.05), (0, -0.53, 0.02), e),
            cone("ear_l", 0.05, 0.0, 0.14, (0.08, -0.1, 0.22), p, segments=4),
            cone("ear_r", 0.05, 0.0, 0.14, (-0.08, -0.1, 0.22), p, segments=4),
            *eyes(0.08, -0.29, 0.09, e)]


def head_bear():
    p, s, e, _ = mats()
    return [blob("skull", 0.2, (0, -0.17, 0.05), p, (1.0, 1.0, 0.9)),
            box("snout", (0.16, 0.16, 0.12), (0, -0.38, -0.02), s),
            box("nose", (0.07, 0.04, 0.05), (0, -0.47, 0.02), e),
            blob("ear_l", 0.06, (0.13, -0.12, 0.2), p), blob("ear_r", 0.06, (-0.13, -0.12, 0.2), p),
            *eyes(0.09, -0.33, 0.1, e)]


def head_boar():
    p, s, e, h = mats()
    return [box("skull", (0.3, 0.36, 0.3), (0, -0.18, 0.0), p, top_scale=0.8),
            box("snout", (0.18, 0.16, 0.14), (0, -0.42, -0.05), s),
            cone("tusk_l", 0.025, 0.0, 0.14, (0.1, -0.44, -0.04), h, rot=(math.radians(-30), 0, 0), segments=4),
            cone("tusk_r", 0.025, 0.0, 0.14, (-0.1, -0.44, -0.04), h, rot=(math.radians(-30), 0, 0), segments=4),
            *eyes(0.1, -0.33, 0.07, e)]


def head_deer():
    p, s, e, _ = mats()
    neck = box("neck", (0.13, 0.13, 0.38), (0, -0.06, 0.15), p)
    neck.rotation_euler = (math.radians(-20), 0, 0)
    return [neck,
            box("skull", (0.17, 0.28, 0.17), (0, -0.2, 0.36), p, top_scale=0.9),
            box("muzzle", (0.11, 0.12, 0.1), (0, -0.38, 0.33), s),
            cone("ear_l", 0.04, 0.0, 0.14, (0.09, -0.12, 0.47), p, segments=4),
            cone("ear_r", 0.04, 0.0, 0.14, (-0.09, -0.12, 0.47), p, segments=4),
            *eyes(0.07, -0.28, 0.41, e, 0.03)]


def head_lizard():
    p, s, e, _ = mats()
    return [box("skull", (0.3, 0.38, 0.14), (0, -0.19, 0.0), p, top_scale=0.8),
            box("jaw", (0.26, 0.3, 0.06), (0, -0.2, -0.08), s),
            *eyes(0.14, -0.14, 0.05, e, 0.05)]


def head_horned():
    p, s, e, _ = mats()
    return [box("skull", (0.4, 0.4, 0.36), (0, -0.2, 0.02), p, top_scale=0.85),
            box("muzzle", (0.26, 0.18, 0.2), (0, -0.46, -0.05), s),
            *eyes(0.15, -0.38, 0.1, e, 0.045)]


# --- legs (unit length) ---------------------------------------------------------------------
def leg_thin():
    p, s, _, _ = mats()
    return [box("leg", (0.1, 0.1, 0.92), (0, 0, -0.46), p, top_scale=1.2),
            box("paw", (0.12, 0.16, 0.08), (0, -0.02, -0.96), s)]


def leg_thick():
    p, s, _, _ = mats()
    return [box("leg", (0.2, 0.2, 0.9), (0, 0, -0.45), p, top_scale=1.2),
            box("paw", (0.24, 0.28, 0.1), (0, -0.03, -0.95), s)]


def leg_clawed():
    p, _, _, h = mats()
    parts = [box("leg", (0.12, 0.12, 0.92), (0, 0, -0.46), p, top_scale=1.3)]
    for k, x in enumerate((-0.04, 0.0, 0.04)):
        parts.append(cone(f"claw_{k}", 0.025, 0.0, 0.12, (x, -0.08, -0.96), h, rot=(math.radians(-90), 0, 0), segments=4))
    return parts


# --- tails ----------------------------------------------------------------------------------
def tail_bushy():
    p, s, _, _ = mats()
    t = box("tail", (0.14, 0.5, 0.14), (0, 0.25, -0.1), p, top_scale=1.3)
    t.rotation_euler = (math.radians(-25), 0, 0)
    tip = box("tip", (0.12, 0.12, 0.12), (0, 0.5, -0.24), s)
    return [t, tip]


def tail_stub():
    p, _, _, _ = mats()
    return [box("tail", (0.1, 0.14, 0.1), (0, 0.07, 0.0), p)]


def tail_long():
    p, s, _, _ = mats()
    parts = []
    for k in range(4):
        w = 0.18 - k * 0.035
        parts.append(box(f"seg_{k}", (w, 0.25, w * 0.8), (0, 0.12 + k * 0.23, -0.03 * k), p if k < 3 else s))
    return parts


def tail_spiked():
    p, _, _, h = mats()
    parts = tail_long()
    for k in range(3):
        parts.append(cone(f"spike_{k}", 0.05, 0.0, 0.14, (0, 0.2 + k * 0.23, 0.1 - 0.03 * k), h, segments=4))
    return parts


# --- extras ---------------------------------------------------------------------------------
def extra_antlers():
    _, _, _, h = mats()
    parts = []
    for side in (1, -1):
        main = box(f"beam_{side}", (0.04, 0.04, 0.42), (0.1 * side, 0.02, 0.2), h)
        main.rotation_euler = (0, math.radians(25 * side), 0)
        parts.append(main)
        for k, z in enumerate((0.18, 0.32)):
            tine = box(f"tine_{side}_{k}", (0.03, 0.03, 0.16), (0.14 * side + 0.03 * k * side, -0.05, z), h)
            tine.rotation_euler = (math.radians(-35), math.radians(15 * side), 0)
            parts.append(tine)
    return parts


def extra_horns():
    _, _, _, h = mats()
    parts = []
    for side in (1, -1):
        base = cone(f"horn_base_{side}", 0.08, 0.05, 0.22, (0.16 * side, 0, 0.06), h, rot=(0, math.radians(70 * side), 0))
        tip = cone(f"horn_tip_{side}", 0.05, 0.0, 0.3, (0.32 * side, -0.08, 0.2), h, rot=(math.radians(-40), math.radians(20 * side), 0))
        parts += [base, tip]
    return parts


def extra_spikes():
    _, _, _, h = mats()
    return [cone(f"spike_{k}", 0.07, 0.0, 0.22, (0, -0.5 + k * 0.25, 0.08), h, segments=4) for k in range(5)]


def extra_mane():
    _, s, _, _ = mats()
    return [blob("mane", 0.3, (0, 0, 0), s, (1.1, 0.9, 1.0)),
            blob("mane_low", 0.24, (0, -0.1, -0.18), s, (1.1, 0.8, 0.9))]


BUILDERS = {name: globals()[name] for name in [
    "body_canine", "body_bulky", "body_lizard", "body_deer",
    "head_wolf", "head_bear", "head_boar", "head_deer", "head_lizard", "head_horned",
    "leg_thin", "leg_thick", "leg_clawed",
    "tail_bushy", "tail_stub", "tail_long", "tail_spiked",
    "extra_antlers", "extra_horns", "extra_spikes", "extra_mane",
]}

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:]
    if len(argv) != 2 or argv[0] not in BUILDERS:
        raise SystemExit("usage: creature_parts.py -- <%s> <out.glb>" % "|".join(BUILDERS))
    part, out = argv
    common.reset_scene()
    obj = common.join(BUILDERS[part](), part)
    obj.vertex_groups.clear()
    common.export_glb(out)
    print("EXPORTED", out)
