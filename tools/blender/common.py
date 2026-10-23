"""Shared helpers for headless Blender model scripts.

Run a model script with:
    blender -b --factory-startup --python tools/blender/<model>.py -- <output.glb>

Conventions: Z up, 1 unit = 1 m, model origin at the feet, character front faces -Y
(the glTF exporter turns -Y into +Z, which is the front in Godot).
"""
import math
import sys

import bmesh
import bpy

FPS = 24


def output_path() -> str:
    argv = sys.argv
    if "--" not in argv or len(argv) <= argv.index("--") + 1:
        raise SystemExit("usage: blender -b --python <script> -- <output.glb>")
    return argv[argv.index("--") + 1]


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)


def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def flat_material(name: str, rgb: tuple) -> bpy.types.Material:
    """`rgb` is an sRGB color (as picked in a color picker); Blender stores Base Color linear."""
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*(srgb_to_linear(c) for c in rgb), 1.0)
    bsdf.inputs["Roughness"].default_value = 0.9
    return mat


def box(name: str, size: tuple, location: tuple, material: bpy.types.Material,
        bone: str, top_scale: float = 1.0) -> bpy.types.Object:
    """Axis-aligned box, optionally tapered (top face scaled in X/Y), weighted 100% to `bone`."""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
        if v.co.z > 0:
            v.co.x *= top_scale
            v.co.y *= top_scale
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    obj.location = location
    obj.data.materials.append(material)
    group = obj.vertex_groups.new(name=bone)
    group.add([v.index for v in mesh.vertices], 1.0, "REPLACE")
    bpy.context.scene.collection.objects.link(obj)
    return obj


def join_and_skin(parts: list, armature: bpy.types.Object, name: str) -> bpy.types.Object:
    """Joins parts into one mesh with transforms applied and binds it to the armature."""
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = name
    body.parent = armature
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = armature
    return body


def build_armature(name: str, bones: list) -> bpy.types.Object:
    """bones: list of (name, head, tail, parent_or_None). Roll is 0 for all bones."""
    data = bpy.data.armatures.new(name)
    arm = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for bone_name, head, tail, parent in bones:
        eb = data.edit_bones.new(bone_name)
        eb.head = head
        eb.tail = tail
        eb.roll = 0.0
        if parent:
            eb.parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"
    return arm


def make_action(armature: bpy.types.Object, name: str, keys: dict, length: int) -> bpy.types.Action:
    """keys: {(bone, "rot_x"|"rot_y"|"rot_z"|"loc_y"): [(frame, value_deg_or_m), ...]}.
    Each channel must start and end on the same value so the clip loops seamlessly."""
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    armature.animation_data_create()
    armature.animation_data.action = action
    for pb in armature.pose.bones:
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)
    for (bone, channel), frames in keys.items():
        pb = armature.pose.bones[bone]
        kind, axis = channel.split("_")
        index = "xyz".index(axis)
        for frame, value in frames:
            if kind == "rot":
                pb.rotation_euler[index] = math.radians(value)
                pb.keyframe_insert("rotation_euler", index=index, frame=frame)
            else:
                pb.location[index] = value
                pb.keyframe_insert("location", index=index, frame=frame)
    action.use_frame_range = True
    action.frame_start = 0
    action.frame_end = length
    armature.animation_data.action = None
    return action


def export_glb(path: str) -> None:
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_yup=True,
        export_apply=False,
        export_skins=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
    )
