"""Low-poly medieval villager (~1.8 m) with a simple rig and idle/walk/run clips.

    blender -b --factory-startup --python tools/blender/humanoid.py -- assets/models/humanoid.glb

Front faces -Y in Blender. Limb bones point down; a negative X rotation swings them forward.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

common.reset_scene()

SKIN = common.flat_material("skin", (0.86, 0.66, 0.50))
TUNIC = common.flat_material("tunic", (0.55, 0.20, 0.16))
TROUSERS = common.flat_material("trousers", (0.32, 0.26, 0.20))
BOOTS = common.flat_material("boots", (0.18, 0.12, 0.08))
HAIR = common.flat_material("hair", (0.28, 0.18, 0.10))
BELT = common.flat_material("belt", (0.15, 0.10, 0.06))

arm = common.build_armature("Humanoid", [
    ("root", (0, 0, 0), (0, 0, 0.3), None),
    ("hips", (0, 0, 0.92), (0, 0, 1.08), "root"),
    ("spine", (0, 0, 1.08), (0, 0, 1.5), "hips"),
    ("head", (0, 0, 1.5), (0, 0, 1.8), "spine"),
    ("upper_arm.L", (0.25, 0, 1.45), (0.25, 0, 1.16), "spine"),
    ("forearm.L", (0.25, 0, 1.16), (0.25, 0, 0.88), "upper_arm.L"),
    ("upper_arm.R", (-0.25, 0, 1.45), (-0.25, 0, 1.16), "spine"),
    ("forearm.R", (-0.25, 0, 1.16), (-0.25, 0, 0.88), "upper_arm.R"),
    ("thigh.L", (0.1, 0, 0.94), (0.1, 0, 0.5), "hips"),
    ("shin.L", (0.1, 0, 0.5), (0.1, 0, 0.06), "thigh.L"),
    ("thigh.R", (-0.1, 0, 0.94), (-0.1, 0, 0.5), "hips"),
    ("shin.R", (-0.1, 0, 0.5), (-0.1, 0, 0.06), "thigh.R"),
])

parts = [
    common.box("pelvis", (0.34, 0.2, 0.18), (0, 0, 1.0), TROUSERS, "hips"),
    common.box("belt", (0.36, 0.22, 0.05), (0, 0, 1.08), BELT, "hips"),
    common.box("torso", (0.34, 0.2, 0.42), (0, 0, 1.3), TUNIC, "spine", top_scale=1.18),
    common.box("neck", (0.09, 0.09, 0.06), (0, 0, 1.53), SKIN, "head"),
    common.box("head", (0.22, 0.23, 0.25), (0, 0, 1.66), SKIN, "head"),
    common.box("hair", (0.24, 0.25, 0.07), (0, 0.01, 1.775), HAIR, "head"),
    common.box("nose", (0.04, 0.05, 0.05), (0, -0.135, 1.64), SKIN, "head"),
]
for side, x in (("L", 0.25), ("R", -0.25)):
    leg_x = 0.1 if side == "L" else -0.1
    parts += [
        common.box(f"upper_arm.{side}", (0.1, 0.11, 0.3), (x, 0, 1.31), TUNIC, f"upper_arm.{side}"),
        common.box(f"forearm.{side}", (0.085, 0.09, 0.27), (x, 0, 1.02), SKIN, f"forearm.{side}", top_scale=1.1),
        common.box(f"thigh.{side}", (0.14, 0.15, 0.44), (leg_x, 0, 0.71), TROUSERS, f"thigh.{side}", top_scale=1.1),
        common.box(f"shin.{side}", (0.12, 0.13, 0.4), (leg_x, 0, 0.3), TROUSERS, f"shin.{side}"),
        common.box(f"boot.{side}", (0.13, 0.24, 0.1), (leg_x, -0.04, 0.05), BOOTS, f"shin.{side}"),
    ]
common.join_and_skin(parts, arm, "Body")


def cycle(bone_a: str, bone_b: str, amp: float, frames: tuple) -> dict:
    """Opposite-phase swing for a left/right pair over frames (start, quarter, half, 3/4, end)."""
    f0, f1, f2, f3, f4 = frames
    return {
        (bone_a, "rot_x"): [(f0, -amp), (f2, amp), (f4, -amp)],
        (bone_b, "rot_x"): [(f0, amp), (f2, -amp), (f4, amp)],
    }


def gait(length: int, leg: float, arm_amp: float, knee: float, elbow: float,
         lean: float, bob: float) -> dict:
    q = length // 4
    frames = (0, q, 2 * q, 3 * q, length)
    keys = {}
    keys.update(cycle("thigh.L", "thigh.R", leg, frames))
    keys.update(cycle("upper_arm.R", "upper_arm.L", arm_amp, frames))
    # Knees bend (positive X) while the leg passes under the body.
    keys[("shin.L", "rot_x")] = [(0, knee * 0.2), (q, knee * 0.3), (2 * q, knee * 0.2), (3 * q, knee), (length, knee * 0.2)]
    keys[("shin.R", "rot_x")] = [(0, knee * 0.2), (q, knee), (2 * q, knee * 0.2), (3 * q, knee * 0.3), (length, knee * 0.2)]
    keys[("forearm.L", "rot_x")] = [(0, -elbow), (length, -elbow)]
    keys[("forearm.R", "rot_x")] = [(0, -elbow), (length, -elbow)]
    keys[("spine", "rot_x")] = [(0, lean), (length, lean)]
    keys[("hips", "loc_y")] = [(0, 0.0), (q, bob), (2 * q, 0.0), (3 * q, bob), (length, 0.0)]
    return keys


common.make_action(arm, "idle", {
    ("hips", "loc_y"): [(0, 0.0), (24, -0.012), (48, 0.0)],
    ("spine", "rot_x"): [(0, 0.0), (24, 2.0), (48, 0.0)],
    ("upper_arm.L", "rot_y"): [(0, 0.0), (24, 3.0), (48, 0.0)],
    ("upper_arm.R", "rot_y"): [(0, 0.0), (24, -3.0), (48, 0.0)],
    ("forearm.L", "rot_x"): [(0, -8.0), (48, -8.0)],
    ("forearm.R", "rot_x"): [(0, -8.0), (48, -8.0)],
}, 48)
common.make_action(arm, "walk", gait(24, leg=28.0, arm_amp=24.0, knee=35.0, elbow=15.0, lean=3.0, bob=0.03), 24)
common.make_action(arm, "run", gait(16, leg=50.0, arm_amp=45.0, knee=75.0, elbow=70.0, lean=14.0, bob=0.06), 16)

common.export_glb(common.output_path())
print("EXPORTED", common.output_path())
