"""Low-poly world props: one joined mesh per prop, origin at the base (min Z = 0), flat faces.

    blender -b --factory-startup --python tools/blender/props.py -- <oak|pine|rock|bush> <out.glb>
"""
import os
import random
import sys

import bmesh

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

BARK = (0.40, 0.27, 0.16)
OAK_LEAVES = (0.30, 0.52, 0.20)
PINE_NEEDLES = (0.18, 0.38, 0.22)
ROCK = (0.55, 0.54, 0.52)
BUSH_LEAVES = (0.26, 0.48, 0.20)
BERRY = (0.75, 0.12, 0.15)


def cone(name, r_bottom, r_top, depth, z_center, material, segments=6, offset=(0.0, 0.0)):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=r_bottom, radius2=r_top, depth=depth)
    return common.mesh_object(name, bm, (offset[0], offset[1], z_center), material)


def blob(name, radius, location, material, scale=(1.0, 1.0, 1.0), jitter=0.0, rng=None):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius)
    if jitter > 0.0:
        for v in bm.verts:
            v.co *= 1.0 + rng.uniform(-jitter, jitter)
    return common.mesh_object(name, bm, location, material, scale)


def ground(obj):
    """Shifts mesh data so the lowest vertex sits at Z = 0."""
    min_z = min(v.co.z for v in obj.data.vertices)
    for v in obj.data.vertices:
        v.co.z -= min_z


def oak():
    bark, leaves = common.flat_material("bark", BARK), common.flat_material("oak_leaves", OAK_LEAVES)
    return [
        cone("trunk", 0.24, 0.18, 1.9, 0.95, bark),
        blob("crown", 1.4, (0.0, 0.0, 2.9), leaves, scale=(1.0, 1.0, 0.85)),
        blob("crown_top", 0.9, (0.5, 0.3, 3.6), leaves),
        blob("crown_side", 0.8, (-0.7, -0.2, 2.6), leaves),
    ]


def pine():
    bark, needles = common.flat_material("bark", BARK), common.flat_material("pine_needles", PINE_NEEDLES)
    return [
        cone("trunk", 0.18, 0.14, 1.2, 0.6, bark),
        cone("tier1", 1.5, 0.0, 2.0, 2.0, needles, segments=7),
        cone("tier2", 1.15, 0.0, 1.8, 3.2, needles, segments=7),
        cone("tier3", 0.8, 0.0, 1.6, 4.4, needles, segments=7),
    ]


def rock():
    rng = random.Random(7)
    stone = common.flat_material("rock", ROCK)
    return [
        blob("rock", 0.6, (0.0, 0.0, 0.0), stone, scale=(1.3, 1.1, 0.95), jitter=0.22, rng=rng),
        blob("rock_chip", 0.3, (0.55, 0.35, -0.1), stone, scale=(1.0, 1.0, 0.8), jitter=0.2, rng=rng),
    ]


def bush():
    rng = random.Random(11)
    leaves, berry = common.flat_material("bush_leaves", BUSH_LEAVES), common.flat_material("berry", BERRY)
    parts = [
        blob("bush_a", 0.45, (0.0, 0.0, 0.38), leaves),
        blob("bush_b", 0.35, (0.35, 0.1, 0.32), leaves),
        blob("bush_c", 0.33, (-0.3, -0.15, 0.3), leaves),
    ]
    for k in range(7):
        x, y, z = rng.uniform(-0.45, 0.5), rng.uniform(-0.4, 0.35), rng.uniform(0.35, 0.75)
        parts.append(common.box(f"berry_{k}", (0.08, 0.08, 0.08), (x, y - 0.1, z), berry, "none"))
    return parts


BUILDERS = {"oak": oak, "pine": pine, "rock": rock, "bush": bush}

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:]
    if len(argv) != 2 or argv[0] not in BUILDERS:
        raise SystemExit("usage: props.py -- <oak|pine|rock|bush> <out.glb>")
    kind, out = argv
    common.reset_scene()
    obj = common.join(BUILDERS[kind](), kind)
    obj.vertex_groups.clear()
    ground(obj)
    common.export_glb(out)
    print("EXPORTED", out)
