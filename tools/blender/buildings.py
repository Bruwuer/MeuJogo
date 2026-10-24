"""Low-poly buildings: one joined mesh per building, origin at the footprint center on the ground,
front (door) facing -Y in Blender (= +Z in Godot). Footprints match GameConstants.BUILD_FOOTPRINT.

    blender -b --factory-startup --python tools/blender/buildings.py -- <cabin|campfire|storage|fence|well|flag|house|farm|market|scaffold|crest_banner> <out.glb>
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


def stake():
    """Plot corner stake: a short post with a painted top (recolored per House)."""
    pole, paint = common.flat_material("pole", POLE), common.flat_material("banner", BANNER)
    return [
        box("post", (0.1, 0.1, 0.8), (0, 0, 0.4), pole),
        box("paint", (0.12, 0.12, 0.16), (0, 0, 0.72), paint),
    ]


def flag():
    pole, banner = common.flat_material("pole", POLE), common.flat_material("banner", BANNER)
    return [
        cylinder("pole", 0.06, 4.0, (0, 0, 2.0), pole, segments=6),
        box("banner", (0.9, 0.04, 0.6), (0.48, 0, 3.55), banner),
        cylinder("finial", 0.1, 0.15, (0, 0, 4.07), pole, segments=6, radius_top=0.0),
    ]


PLASTER = (0.86, 0.80, 0.68)
TIMBER = (0.32, 0.21, 0.12)
SOIL = (0.40, 0.28, 0.17)
CROP = (0.48, 0.62, 0.22)
CROP_TIP = (0.85, 0.72, 0.30)
CANOPY = (0.78, 0.30, 0.22)
CANOPY_B = (0.92, 0.86, 0.72)
CRATE = (0.62, 0.46, 0.26)


def house():
    """Villager house: plaster walls with a timber frame, thatch-like roof, door at the front."""
    stone, plaster = common.flat_material("stone", STONE), common.flat_material("plaster", PLASTER)
    timber, roof = common.flat_material("timber", TIMBER), common.flat_material("roof", ROOF)
    door, window = common.flat_material("door", DOOR), common.flat_material("window", WINDOW, emission=0.6)
    parts = [
        box("foundation", (4.5, 5.5, 0.3), (0, 0, 0.15), stone),
        box("walls", (4.1, 5.1, 2.4), (0, 0, 1.5), plaster),
        gable_roof("roof", 2.45, 5.8, 2.6, 4.1, roof),
        box("door", (0.9, 0.1, 1.8), (0, -2.58, 1.2), door),
        box("window_l", (0.6, 0.1, 0.5), (-1.3, -2.58, 1.8), window),
        box("window_r", (0.6, 0.1, 0.5), (1.3, -2.58, 1.8), window),
        box("window_side", (0.1, 0.6, 0.5), (2.08, 0.5, 1.8), window),
        box("chimney", (0.5, 0.5, 1.6), (-1.2, 1.4, 3.6), stone),
        box("beam", (4.16, 5.16, 0.12), (0, 0, 2.62), timber),
    ]
    for k, (x, y) in enumerate(((-2.05, -2.55), (2.05, -2.55), (-2.05, 2.55), (2.05, 2.55))):
        parts.append(box(f"post_{k}", (0.16, 0.16, 2.4), (x, y, 1.5), timber))
    parts.append(box("post_mid_l", (0.12, 0.1, 2.4), (-0.75, -2.57, 1.5), timber))
    parts.append(box("post_mid_r", (0.12, 0.1, 2.4), (0.75, -2.57, 1.5), timber))
    return parts


SLATE = (0.30, 0.31, 0.35)
DRESSED_STONE = (0.62, 0.60, 0.55)


def house_stone():
    """Stone house (level 1): same footprint as the house, dressed-stone walls, slate roof."""
    stone, walls = common.flat_material("stone", STONE), common.flat_material("dressed_stone", DRESSED_STONE)
    timber, roof = common.flat_material("timber", TIMBER), common.flat_material("slate", SLATE)
    door, window = common.flat_material("door", DOOR), common.flat_material("window", WINDOW, emission=0.6)
    parts = [
        box("foundation", (4.5, 5.5, 0.35), (0, 0, 0.175), stone),
        box("walls", (4.2, 5.2, 2.9), (0, 0, 1.8), walls),
        gable_roof("roof", 2.45, 5.8, 3.2, 4.9, roof),
        box("door", (1.0, 0.1, 2.0), (0, -2.63, 1.35), door),
        box("window_l", (0.6, 0.1, 0.7), (-1.3, -2.63, 2.0), window),
        box("window_r", (0.6, 0.1, 0.7), (1.3, -2.63, 2.0), window),
        box("window_side", (0.1, 0.6, 0.7), (2.13, 0.5, 2.0), window),
        box("chimney", (0.6, 0.6, 2.0), (-1.2, 1.4, 4.4), stone),
        box("lintel", (1.3, 0.14, 0.18), (0, -2.64, 2.45), timber),
    ]
    for k, (x, y) in enumerate(((-2.1, -2.6), (2.1, -2.6), (-2.1, 2.6), (2.1, 2.6))):
        parts.append(box(f"quoin_{k}", (0.24, 0.24, 2.9), (x, y, 1.8), stone))
    return parts


def manor():
    """Manor (level 2): stone ground floor, timbered upper floor, steep roof and a corner tower."""
    stone, walls = common.flat_material("stone", STONE), common.flat_material("dressed_stone", DRESSED_STONE)
    plaster, timber = common.flat_material("plaster", PLASTER), common.flat_material("timber", TIMBER)
    roof, door = common.flat_material("slate", SLATE), common.flat_material("door", DOOR)
    window = common.flat_material("window", WINDOW, emission=0.6)
    parts = [
        box("foundation", (4.5, 5.5, 0.35), (0, 0, 0.175), stone),
        box("ground_floor", (4.1, 5.1, 2.6), (0, 0, 1.65), walls),
        box("upper_floor", (4.4, 5.4, 2.2), (0, 0, 4.05), plaster),
        box("floor_beam", (4.46, 5.46, 0.16), (0, 0, 2.95), timber),
        gable_roof("roof", 2.4, 5.6, 5.15, 7.0, roof),
        box("door", (1.1, 0.1, 2.1), (0.6, -2.58, 1.4), door),
        box("tower", (1.3, 1.3, 6.6), (-1.55, 2.05, 3.65), walls),
        cylinder("tower_roof", 1.0, 1.6, (-1.55, 2.05, 7.75), roof, segments=4, radius_top=0.0),
    ]
    for k, x in enumerate((-1.3, 0.0, 1.3)):
        parts.append(box(f"window_up_{k}", (0.55, 0.1, 0.7), (x, -2.73, 4.1), window))
    parts.append(box("window_down", (0.6, 0.1, 0.7), (-1.2, -2.58, 1.8), window))
    for k, (x, y) in enumerate(((-2.2, -2.7), (2.2, -2.7), (-2.2, 2.7), (2.2, 2.7))):
        parts.append(box(f"post_{k}", (0.16, 0.16, 2.2), (x, y, 4.05), timber))
    return parts


def farm():
    """6 x 6 m field: tilled soil, five crop rows, low corner stakes (walkable, no collision)."""
    soil, crop = common.flat_material("soil", SOIL), common.flat_material("crop", CROP)
    tip, stake = common.flat_material("crop_tip", CROP_TIP), common.flat_material("fence_wood", FENCE_WOOD)
    parts = [box("soil", (6.0, 6.0, 0.1), (0, 0, 0.05), soil)]
    for k in range(5):
        x = -2.2 + k * 1.1
        parts.append(box(f"row_{k}", (0.5, 5.2, 0.4), (x, 0, 0.3), crop))
        parts.append(box(f"tips_{k}", (0.3, 5.0, 0.12), (x, 0, 0.56), tip))
    for k, (x, y) in enumerate(((-2.94, -2.94), (2.94, -2.94), (-2.94, 2.94), (2.94, 2.94))):
        parts.append(box(f"stake_{k}", (0.12, 0.12, 0.8), (x, y, 0.4), stake))
    return parts


def market():
    """Market stall: counter at the front, four posts, striped canopy, crates behind."""
    stone, planks = common.flat_material("stone", STONE), common.flat_material("planks", PLANKS)
    timber, crate = common.flat_material("timber", TIMBER), common.flat_material("crate", CRATE)
    canopy, canopy_b = common.flat_material("canopy", CANOPY), common.flat_material("canopy_b", CANOPY_B)
    fruit = common.flat_material("crop_tip", CROP_TIP)
    parts = [
        box("floor", (4.0, 3.0, 0.2), (0, 0, 0.1), stone),
        box("counter", (3.4, 0.6, 1.0), (0, -1.0, 0.7), planks),
        box("goods", (2.8, 0.4, 0.15), (0, -1.0, 1.28), fruit),
        box("crate_a", (0.8, 0.8, 0.7), (-1.1, 0.8, 0.55), crate),
        box("crate_b", (0.7, 0.7, 0.6), (0.9, 0.9, 0.5), crate),
        box("back", (3.8, 0.1, 1.2), (0, 1.42, 0.8), planks),
    ]
    for k, (x, y) in enumerate(((-1.85, -1.35), (1.85, -1.35), (-1.85, 1.35), (1.85, 1.35))):
        parts.append(box(f"post_{k}", (0.14, 0.14, 2.3), (x, y, 1.25), timber))
    for k in range(6):
        stripe = box(f"stripe_{k}", (4.0 / 6, 3.0, 0.08), (-2.0 + 4.0 / 12 + k * 4.0 / 6, 0, 2.45), canopy if k % 2 == 0 else canopy_b)
        stripe.rotation_euler = (math.radians(-10), 0, 0)
        parts.append(stripe)
    return parts


def scaffold():
    """Unit construction frame (1 x 1 m, 3 m tall); Godot scales it to each footprint."""
    wood = common.flat_material("scaffold", FENCE_WOOD)
    parts = []
    for k, (x, y) in enumerate(((-0.5, -0.5), (0.5, -0.5), (-0.5, 0.5), (0.5, 0.5))):
        parts.append(box(f"pole_{k}", (0.05, 0.05, 3.0), (x, y, 1.5), wood))
    for k, z in enumerate((1.0, 2.0, 2.9)):
        parts.append(box(f"bar_x0_{k}", (1.0, 0.03, 0.04), (0, -0.5, z), wood))
        parts.append(box(f"bar_x1_{k}", (1.0, 0.03, 0.04), (0, 0.5, z), wood))
        parts.append(box(f"bar_y0_{k}", (0.03, 1.0, 0.04), (-0.5, 0, z), wood))
        parts.append(box(f"bar_y1_{k}", (0.03, 1.0, 0.04), (0.5, 0, z), wood))
    return parts




CREST_W = 0.85  # cloth width (m); its shape matches Crest's pixel mask (32 x 40)
CREST_H = 1.05
CREST_SPLIT = 22.0 / 40.0  # where the straight sides start curving into the point


def crest_banner():
    """Family banner: pole, crossbar and a shield-shaped cloth (material `crest`, UV 0..1 over the
    crest image) facing -Y (Godot +Z). Godot paints the family's crest on the cloth."""
    pole = common.flat_material("pole", POLE)
    cloth = common.flat_material("crest", BANNER)
    parts = [
        cylinder("pole", 0.05, 3.2, (0, 0, 1.6), pole, segments=6),
        box("bar", (1.0, 0.05, 0.05), (0.48, 0, 3.08), pole),
        cylinder("finial", 0.09, 0.14, (0, 0, 3.27), pole, segments=6, radius_top=0.0),
    ]
    top, cx = 3.05, 0.5
    outline = [(0.0, 0.0), (1.0, 0.0)]  # (u, v) of the image, v down
    steps = 8
    for k in range(steps + 1):
        v = CREST_SPLIT + (1.0 - CREST_SPLIT) * k / steps
        t = (v - CREST_SPLIT) / (1.0 - CREST_SPLIT)
        outline.append((0.5 + 0.5 * (1.0 - t * t), v))
    for k in range(steps - 1, -1, -1):
        v = CREST_SPLIT + (1.0 - CREST_SPLIT) * k / steps
        t = (v - CREST_SPLIT) / (1.0 - CREST_SPLIT)
        outline.append((0.5 - 0.5 * (1.0 - t * t), v))
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    verts = []
    for u, v in outline:
        verts.append(bm.verts.new((cx + (u - 0.5) * CREST_W, -0.03, top - v * CREST_H)))
    # Drop the duplicated point at the tip.
    face_verts = []
    for vert in verts:
        if not face_verts or (vert.co - face_verts[-1].co).length > 1e-5:
            face_verts.append(vert)
    if (face_verts[0].co - face_verts[-1].co).length < 1e-5:
        face_verts.pop()
    face = bm.faces.new(face_verts)
    bm.normal_update()
    if face.normal.y > 0:  # face the front (-Y)
        face.normal_flip()
    for loop in face.loops:
        co = loop.vert.co
        loop[uv].uv = ((co.x - cx) / CREST_W + 0.5, (co.z - (top - CREST_H)) / CREST_H)  # glTF flips v
    parts.append(common.mesh_object("cloth", bm, (0, 0, 0), cloth))
    return parts


BUILDERS = {"stake": stake, "house_stone": house_stone, "manor": manor, "cabin": cabin, "campfire": campfire, "storage": storage, "fence": fence, "well": well, "flag": flag,
            "house": house, "farm": farm, "market": market, "scaffold": scaffold, "crest_banner": crest_banner}

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
