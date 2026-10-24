"""Low-poly buildings: one joined mesh per building, origin at the footprint center on the ground,
front (door) facing -Y in Blender (= +Z in Godot). Footprints match GameConstants.BUILD_FOOTPRINT.

    blender -b --factory-startup --python tools/blender/buildings.py -- <cabin|campfire|storage|fence|well|flag> <out.glb>
"""
import math
import os
import sys

import bmesh

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

STONE = (0.46, 0.45, 0.43)
LOGS = (0.45, 0.30, 0.18)
LOG_BANDS = (0.33, 0.21, 0.12)
ROOF = (0.42, 0.16, 0.10)
DOOR = (0.25, 0.16, 0.09)
WINDOW = (0.95, 0.80, 0.45)
PLANKS = (0.55, 0.40, 0.24)
FENCE_WOOD = (0.48, 0.34, 0.20)
WATER = (0.10, 0.20, 0.30)
FIRE_OUTER = (0.95, 0.45, 0.10)
FIRE_INNER = (1.00, 0.80, 0.25)
POLE = (0.35, 0.25, 0.15)
BANNER = (1.0, 1.0, 1.0)  # recolored per kingdom in Godot


def box(name, size, location, material):
    return common.box(name, size, location, material, "none")


def cylinder(name, radius, depth, location, material, segments=8, radius_top=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=radius,
                          radius2=radius if radius_top is None else radius_top, depth=depth)
    return common.mesh_object(name, bm, location, material)


def gable_roof(name, half_width, length, eave_z, ridge_z, material, along_y=True):
    """Triangular prism: ridge along Y (or X), eaves at +-half_width."""
    bm = bmesh.new()
    hl = length * 0.5
    if along_y:
        pts = [(-half_width, -hl, eave_z), (half_width, -hl, eave_z), (0, -hl, ridge_z),
               (-half_width, hl, eave_z), (half_width, hl, eave_z), (0, hl, ridge_z)]
    else:
        pts = [(-hl, -half_width, eave_z), (-hl, half_width, eave_z), (-hl, 0, ridge_z),
               (hl, -half_width, eave_z), (hl, half_width, eave_z), (hl, 0, ridge_z)]
    v = [bm.verts.new(p) for p in pts]
    for face in [(0, 2, 1), (3, 4, 5), (0, 1, 4, 3), (1, 2, 5, 4), (2, 0, 3, 5)]:
        bm.faces.new([v[i] for i in face])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return common.mesh_object(name, bm, (0, 0, 0), material)


def cabin():
    stone, logs = common.flat_material("stone", STONE), common.flat_material("logs", LOGS)
    bands, roof = common.flat_material("log_bands", LOG_BANDS), common.flat_material("roof", ROOF)
    door, window = common.flat_material("door", DOOR), common.flat_material("window", WINDOW, emission=0.6)
    parts = [
        box("foundation", (4.0, 5.0, 0.3), (0, 0, 0.15), stone),
        box("walls", (3.7, 4.7, 2.2), (0, 0, 1.4), logs),
        gable_roof("roof", 2.15, 5.3, 2.45, 3.7, roof),
        box("door", (0.9, 0.1, 1.7), (0, -2.38, 1.15), door),
        box("window_l", (0.6, 0.1, 0.5), (-1.2, -2.38, 1.7), window),
        box("window_r", (0.6, 0.1, 0.5), (1.2, -2.38, 1.7), window),
        box("chimney", (0.5, 0.5, 1.5), (1.1, 1.2, 3.3), stone),
    ]
    for k, z in enumerate((0.8, 1.4, 2.0)):
        parts.append(box(f"band_{k}", (3.76, 4.76, 0.08), (0, 0, z), bands))
    return parts


def campfire():
    stone = common.flat_material("stone", STONE)
    logs = common.flat_material("logs", LOGS)
    outer = common.flat_material("fire_outer", FIRE_OUTER, emission=3.0)
    inner = common.flat_material("fire_inner", FIRE_INNER, emission=4.0)
    parts = []
    for k in range(8):
        a = math.tau * k / 8
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.17)
        parts.append(common.mesh_object(f"stone_{k}", bm, (math.cos(a) * 0.62, math.sin(a) * 0.62, 0.17), stone))
    for k in range(3):
        log = box(f"log_{k}", (0.9, 0.12, 0.12), (0, 0, 0.12), logs)
        log.rotation_euler = (0, math.radians(12), math.tau * k / 6)
        parts.append(log)
    parts.append(cylinder("flame_outer", 0.3, 0.7, (0, 0, 0.45), outer, segments=6, radius_top=0.0))
    parts.append(cylinder("flame_inner", 0.17, 0.5, (0.05, 0.03, 0.4), inner, segments=5, radius_top=0.0))
    return parts


def storage():
    stone, planks = common.flat_material("stone", STONE), common.flat_material("planks", PLANKS)
    roof, door = common.flat_material("roof", ROOF), common.flat_material("door", DOOR)
    return [
        box("foundation", (4.0, 3.0, 0.3), (0, 0, 0.15), stone),
        box("walls", (3.7, 2.7, 2.0), (0, 0, 1.3), planks),
        gable_roof("roof", 1.65, 4.1, 2.3, 3.2, roof, along_y=False),
        box("door", (1.6, 0.1, 1.6), (0, -1.38, 1.1), door),
    ]


def fence():
    wood = common.flat_material("fence_wood", FENCE_WOOD)
    parts = [box(f"post_{k}", (0.14, 0.14, 1.2), (x, 0, 0.6), wood) for k, x in enumerate((-1.43, 0.0, 1.43))]
    parts += [box(f"rail_{k}", (3.0, 0.06, 0.1), (0, 0, z), wood) for k, z in enumerate((0.45, 0.9))]
    return parts


def well():
    stone, logs = common.flat_material("stone", STONE), common.flat_material("logs", LOGS)
    water, roof = common.flat_material("water", WATER), common.flat_material("roof", ROOF)
    return [
        cylinder("ring", 0.85, 0.8, (0, 0, 0.4), stone),
        cylinder("water", 0.66, 0.02, (0, 0, 0.79), water),
        box("post_l", (0.12, 0.12, 1.7), (-0.78, 0, 1.15), logs),
        box("post_r", (0.12, 0.12, 1.7), (0.78, 0, 1.15), logs),
        box("beam", (1.7, 0.1, 0.1), (0, 0, 1.95), logs),
        gable_roof("roof", 0.7, 1.9, 1.95, 2.5, roof, along_y=False),
    ]


def flag():
    pole, banner = common.flat_material("pole", POLE), common.flat_material("banner", BANNER)
    return [
        cylinder("pole", 0.06, 4.0, (0, 0, 2.0), pole, segments=6),
        box("banner", (0.9, 0.04, 0.6), (0.48, 0, 3.55), banner),
        cylinder("finial", 0.1, 0.15, (0, 0, 4.07), pole, segments=6, radius_top=0.0),
    ]


BUILDERS = {"cabin": cabin, "campfire": campfire, "storage": storage, "fence": fence, "well": well, "flag": flag}

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:]
    if len(argv) != 2 or argv[0] not in BUILDERS:
        raise SystemExit("usage: buildings.py -- <%s> <out.glb>" % "|".join(BUILDERS))
    kind, out = argv
    common.reset_scene()
    obj = common.join(BUILDERS[kind](), kind)
    obj.vertex_groups.clear()
    common.export_glb(out)
    print("EXPORTED", out)
