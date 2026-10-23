# Etapa 1 — Fundação jogável · Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Small chunk-streamed low-poly map where a Blender-made, rigged humanoid walks/runs with screen-relative WASD under a following orthographic isometric camera, all covered by headless tests.

**Architecture:** Godot 4 project rooted at `D:\MeuJogo`. Terrain is generated per chunk in `WorkerThreadPool` and applied on the main thread via `call_deferred`. The character is a `.glb` produced by a headless Blender Python script. A tiny in-repo GDScript test runner (`godot --headless -s`) runs unit and integration tests.

**Tech Stack:** Godot 4 (latest stable, winget `GodotEngine.GodotEngine`), GDScript, Blender (winget `BlenderFoundation.Blender`) + Python `bpy`, PowerShell helper scripts, git.

**Spec:** `docs/superpowers/specs/2026-10-23-jogo-reino-vivo-design.md`

## Global Constraints

- All gameplay numbers live in `scripts/core/game_constants.gd` (`class_name GameConstants`). No magic numbers elsewhere.
- No synchronous loading during play: chunk generation off-thread, SceneTree changes only on the main thread.
- No external assets. Characters/objects come from `tools/blender/*.py` → `assets/models/*.glb`; never edit a `.glb` by hand.
- Animations named exactly `idle`, `walk`, `run`.
- Map: 8×8 playable chunks of 32×32 m + 1-chunk visual-only border ring.
- Camera: orthographic, yaw 45°, pitch -30°.
- Code and code comments in English; docs and in-game text in Portuguese.
- Done = `tools/run_tests.ps1` exits 0 with output read, capture screenshots inspected, work committed.

## Review Focus

1. **Spawn before ground exists:** player must not fall through the terrain while its chunk is still generating → pinned in Task 6 (`test_player_rests_on_ground`).
2. **Diagonal speed:** W+D must not move faster than W alone → Task 5 (`test_diagonal_is_normalized`).
3. **Map edge:** walking into the edge stops at the invisible wall; streamer never requests coords outside playable+border → Tasks 2 and 6 (`test_radius_clipped_to_world`, `test_edge_wall_blocks`).
4. **Stale chunk results:** running fast makes chunks finish after they left the radius; they must be discarded, never duplicated → Task 3 (`test_stale_chunk_discarded`, `test_no_duplicate_chunks`).
5. **Missing model/animation:** if `humanoid.glb` is absent or lacks an animation, tests fail with a clear message and the player does not crash → Task 4 (`test_humanoid_has_rig_and_animations`), Task 5 (`play_anim` guards with `has_animation`).

---

## File Structure

| File | Responsibility |
|---|---|
| `project.godot`, `.gitignore`, `CLAUDE.md` | project, input map, rules |
| `scripts/core/game_constants.gd` | every tunable constant |
| `scripts/world/chunk_math.gd` | pure coord math (static) |
| `scripts/world/terrain_generator.gd` | thread-safe heights + flat-shaded chunk mesh arrays |
| `scripts/world/chunk_streamer.gd` | async load/unload of chunk nodes around a position |
| `scripts/world/spawn_picker.gd` | valid random spawn point (static) |
| `scripts/world/world.gd` + `scenes/main.tscn` | wires generator, streamer, light, walls, player, camera |
| `scripts/actors/iso_input.gd` | input vector → world direction for a camera yaw (static) |
| `scripts/actors/player.gd` + `scenes/player.tscn` | CharacterBody3D using `humanoid.glb` |
| `scripts/camera/iso_camera.gd` | orthographic follow camera |
| `tools/blender/common.py`, `tools/blender/humanoid.py` | Blender model generation |
| `tools/godot.ps1`, `tools/build_models.ps1`, `tools/run_tests.ps1`, `tools/capture.ps1` | CLI entry points |
| `tests/run_tests.gd`, `tests/game_test.gd`, `tests/unit/*`, `tests/integration/*`, `tests/visual/capture.gd` | testing |

---

### Task 1: Project skeleton, constants, test runner, CLAUDE.md

**Files:**
- Create: `project.godot`, `.gitignore`, `CLAUDE.md`, `scripts/core/game_constants.gd`, `tests/run_tests.gd`, `tests/game_test.gd`, `tests/unit/test_constants.gd`, `tools/godot.ps1`, `tools/run_tests.ps1`

**Interfaces:**
- Produces: `GameConstants.*` consts (below); `GameTest` base (`extends Node`) with `assert_true(cond: bool, msg: String)`, `assert_eq(a, b, msg := "")`, `assert_near(a: float, b: float, eps: float, msg := "")`, `wait_frames(n: int)` (async), `wait_physics_frames(n: int)` (async); runner contract: every `tests/unit/test_*.gd` and `tests/integration/test_*.gd` extends `GameTest`, each `test_*` method may `await`; a fresh instance per method is added to the root and freed afterwards.
- `tools/godot.ps1` resolves the Godot console exe (`$env:GODOT` else the winget install) and forwards args.

- [ ] **Step 1:** `project.godot`: name "MeuJogo", main scene `res://scenes/main.tscn`, renderer `forward_plus`, window 1280×720, input actions `move_up`(W), `move_down`(S), `move_left`(A), `move_right`(D), `run`(Shift). `.gitignore`: `.godot/`, `captures/`, `*.blend1`.
- [ ] **Step 2:** `GameConstants` with at least: `WORLD_SEED := 1337`, `SPAWN_SEED := -1` (-1 = randomize), `CHUNK_SIZE := 32.0`, `CHUNK_CELLS := 16`, `MAP_CHUNKS := 8`, `BORDER_CHUNKS := 1`, `LOAD_RADIUS := 2`, `CHUNKS_APPLIED_PER_FRAME := 2`, `TERRAIN_HEIGHT := 6.0`, `TERRAIN_NOISE_FREQ := 0.02`, `WALK_SPEED := 4.0`, `RUN_SPEED := 7.5`, `TURN_SPEED := 10.0`, `GRAVITY := 20.0`, `CAM_YAW_DEG := 45.0`, `CAM_PITCH_DEG := -30.0`, `CAM_ORTHO_SIZE := 24.0`, `CAM_DISTANCE := 40.0`, `CAM_FOLLOW_SMOOTH := 6.0`, `SPAWN_EDGE_MARGIN := 24.0`, `SPAWN_MAX_SLOPE_DEG := 20.0`, `SPAWN_MAX_TRIES := 64`, `MAX_FRAME_MS := 50.0`, `ANIM_IDLE := "idle"`, `ANIM_WALK := "walk"`, `ANIM_RUN := "run"`, `HUMANOID_SCENE := "res://assets/models/humanoid.glb"`.
- [ ] **Step 3:** failing test `tests/unit/test_constants.gd`:

```gdscript
func test_map_fits_spawn_margin():
    assert_true(GameConstants.SPAWN_EDGE_MARGIN * 2.0 < GameConstants.MAP_CHUNKS * GameConstants.CHUNK_SIZE)
func test_run_faster_than_walk():
    assert_true(GameConstants.RUN_SPEED > GameConstants.WALK_SPEED)
func test_runner_reports_failure_sanity():
    assert_eq(1 + 1, 2)
```
- [ ] **Step 4:** implement `tests/run_tests.gd` (`extends SceneTree`): discover files, run, print `PASS <file>::<method>` / `FAIL <file>::<method>: <msg>`, final line `RESULT: <p> passed, <f> failed`, `quit(1 if f > 0 else 0)`. A test with zero asserts counts as passed. `tools/run_tests.ps1`: `godot --headless --import` then `godot --headless -s res://tests/run_tests.gd`, propagate exit code.
- [ ] **Step 5:** verify a deliberately broken assert makes the run exit 1, revert it, then `tools/run_tests.ps1` → `RESULT: 3 passed, 0 failed`, exit 0.
- [ ] **Step 6:** `CLAUDE.md` (Portuguese): vision, stack, folder structure, rules (spec §5 verbatim incl. Blender rule), roadmap (spec §8), how to run tests/build models/capture.
- [ ] **Step 7:** commit `chore: projeto Godot, constantes, runner de testes e CLAUDE.md`.

### Task 2: Chunk math and terrain generator

**Files:** Create `scripts/world/chunk_math.gd`, `scripts/world/terrain_generator.gd`; Test `tests/unit/test_chunk_math.gd`, `tests/unit/test_terrain.gd`

**Interfaces:**
- `ChunkMath` (static): `world_to_chunk(p: Vector3) -> Vector2i`, `chunk_origin(c: Vector2i) -> Vector3` (min corner, y=0), `is_playable(c: Vector2i) -> bool` (0..MAP_CHUNKS-1), `is_in_world(c: Vector2i) -> bool` (playable ± BORDER_CHUNKS), `chunks_in_radius(center: Vector2i, r: int) -> Array[Vector2i]` (square, clipped to `is_in_world`), `playable_size() -> float`.
- `TerrainGenerator` (`extends RefCounted`): `_init(seed: int)`, `height_at(x: float, z: float) -> float` (in `[0, TERRAIN_HEIGHT]`), `slope_deg_at(x: float, z: float) -> float`, `build_chunk_arrays(c: Vector2i) -> Array` (`Mesh.ARRAY_MAX` arrays, vertices local to chunk origin, non-indexed flat-shaded triangles with per-face normals and vertex colors by height). Thread-safe: only reads its own `FastNoiseLite`.

- [ ] **Step 1:** failing tests:

```gdscript
# test_chunk_math.gd
func test_world_to_chunk(): assert_eq(ChunkMath.world_to_chunk(Vector3(33, 0, -1)), Vector2i(1, -1))
func test_playable_bounds(): assert_true(ChunkMath.is_playable(Vector2i(7, 7)) and not ChunkMath.is_playable(Vector2i(8, 0)))
func test_border_in_world(): assert_true(ChunkMath.is_in_world(Vector2i(-1, 8)) and not ChunkMath.is_in_world(Vector2i(-2, 0)))
func test_radius_clipped_to_world():
    var cs := ChunkMath.chunks_in_radius(Vector2i(0, 0), 2)
    assert_eq(cs.size(), 16)  # x,y in -1..2
    for c in cs: assert_true(ChunkMath.is_in_world(c))
# test_terrain.gd
func test_deterministic(): assert_eq(TerrainGenerator.new(7).height_at(10.5, 3.2), TerrainGenerator.new(7).height_at(10.5, 3.2))
func test_seed_changes_terrain(): assert_true(TerrainGenerator.new(1).height_at(50, 50) != TerrainGenerator.new(2).height_at(50, 50))
func test_height_range(): # sample 200 points, all within [0, TERRAIN_HEIGHT]
func test_chunk_mesh_shape():
    var a := TerrainGenerator.new(7).build_chunk_arrays(Vector2i(2, 3))
    assert_eq((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), GameConstants.CHUNK_CELLS ** 2 * 6)
func test_chunk_edges_match(): # last column of chunk (0,0) equals first column of chunk (1,0) in world heights
```
- [ ] **Step 2:** run → FAIL (unknown classes). **Step 3:** implement. **Step 4:** run → all PASS.
- [ ] **Step 5:** commit `feat: matemática de chunks e gerador de terreno low-poly`.

### Task 3: Async chunk streamer

**Files:** Create `scripts/world/chunk_streamer.gd`; Test `tests/integration/test_chunk_streamer.gd`

**Interfaces:**
- Consumes: `ChunkMath`, `TerrainGenerator`.
- Produces: `class_name ChunkStreamer extends Node3D`; `setup(gen: TerrainGenerator) -> void`; `update_center(world_pos: Vector3) -> void`; `is_loaded(c: Vector2i) -> bool`; `loaded_coords() -> Array[Vector2i]`; `pending_count() -> int`; signals `chunk_loaded(c: Vector2i)`, `chunk_unloaded(c: Vector2i)`. Each chunk node is named `Chunk_x_y`, holds a `MeshInstance3D` and, only when `is_playable`, a `StaticBody3D` + trimesh collision.
- Approach: desired set = `chunks_in_radius(center, LOAD_RADIUS)`; new coords → `WorkerThreadPool.add_task` building arrays → `call_deferred("_queue_result", c, arrays)`; `_process` applies at most `CHUNKS_APPLIED_PER_FRAME` results, discarding any whose coord is no longer desired or already loaded; coords leaving the set are `queue_free`d and emit `chunk_unloaded`. `_exit_tree` waits for in-flight tasks.

- [ ] **Step 1:** failing tests:

```gdscript
func test_loads_async():  # update_center(origin of (3,3)); same frame: is_loaded == false; after awaiting until pending_count()==0 (timeout 300 frames): all 25 coords loaded
func test_unloads_far(): # load at (0,0), then update_center at (6,6), settle: Vector2i(0,0) not loaded, Chunk_0_0 node gone
func test_stale_chunk_discarded(): # update_center (0,0) then immediately (7,7); settle: no loaded coord farther than LOAD_RADIUS from (7,7)
func test_no_duplicate_chunks(): # call update_center same pos 10x; settle: get_child_count() == loaded_coords().size()
func test_no_frame_over_budget(): # while settling, record Time.get_ticks_usec deltas per frame; max < MAX_FRAME_MS
func test_border_has_no_collision(): # load around (0,0); Chunk_-1_0 has no StaticBody3D, Chunk_0_0 has one
```
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS (run whole suite).
- [ ] **Step 5:** commit `feat: streaming assíncrono de chunks`.

### Task 4: Blender humanoid pipeline

**Files:** Create `tools/blender/common.py`, `tools/blender/humanoid.py`, `tools/build_models.ps1`, `assets/models/humanoid.glb` (generated, committed); Test `tests/unit/test_humanoid_model.gd`

**Interfaces:**
- `common.py`: `reset_scene()`, `flat_material(name: str, rgb: tuple) -> Material`, `box(name, size, location, material) -> Object`, `export_glb(path: str)` (glTF binary, `export_animation_mode='ACTIONS'`, skins on, apply modifiers). Output path from argv after `--`.
- `humanoid.py`: ~1.8 m figure, origin at feet, facing −Y in Blender (= +Z in Godot? see Step 3), parts as low-poly boxes/tapered prisms (hips, torso, head, upper/lower arms, upper/lower legs, feet) with tunic/trousers/skin colors; armature bones `root, hips, spine, head, upper_arm.L/R, forearm.L/R, thigh.L/R, shin.L/R`; rigid skinning (each part 100% to one bone); actions `idle` (2 s breathing bob), `walk` (1 s cycle, limbs ±30°), `run` (0.6 s, ±55°, forward lean), first frame = last frame.
- `tools/build_models.ps1`: runs `blender -b --factory-startup --python tools/blender/humanoid.py -- assets/models/humanoid.glb`, fails if the file is not produced, then runs Godot `--headless --import`.
- Produces: `res://assets/models/humanoid.glb` → instantiated scene contains `Skeleton3D` and `AnimationPlayer` with `idle`, `walk`, `run`.

- [ ] **Step 1:** failing test:

```gdscript
func test_humanoid_has_rig_and_animations():
    assert_true(ResourceLoader.exists(GameConstants.HUMANOID_SCENE), "humanoid.glb missing: run tools/build_models.ps1")
    var m: Node = load(GameConstants.HUMANOID_SCENE).instantiate()
    add_child(m)
    assert_true(m.find_children("*", "Skeleton3D").size() == 1)
    var ap: AnimationPlayer = m.find_children("*", "AnimationPlayer")[0]
    for a in [GameConstants.ANIM_IDLE, GameConstants.ANIM_WALK, GameConstants.ANIM_RUN]:
        assert_true(ap.has_animation(a), "missing animation " + a)
func test_humanoid_height(): # merged AABB of all MeshInstance3D height in [1.6, 2.0], min y within 0.05 of 0
```
- [ ] **Step 2:** FAIL (file missing). **Step 3:** implement scripts; run `tools/build_models.ps1`; check the facing convention in Godot (character's front must point to +Z after import, so `look_at`-style rotation in Task 5 is correct). **Step 4:** PASS.
- [ ] **Step 5:** commit `feat: humanoide low-poly gerado por script do Blender com rig e animações`.

### Task 5: Screen-relative input, player, iso camera

**Files:** Create `scripts/actors/iso_input.gd`, `scripts/actors/player.gd`, `scenes/player.tscn`, `scripts/camera/iso_camera.gd`; Test `tests/unit/test_iso_input.gd`, `tests/integration/test_player.gd`

**Interfaces:**
- `IsoInput` (static): `to_world(input: Vector2, cam_yaw_deg: float) -> Vector3` — `input` is `Input.get_vector("move_left","move_right","move_up","move_down")` (W = (0,-1)); screen-up = camera forward flattened `(-sin yaw, 0, -cos yaw)`, screen-right = `(cos yaw, 0, -sin yaw)`; result length ≤ 1.
- `Player` (`class_name Player extends CharacterBody3D`): child `Model` (instance of `HUMANOID_SCENE`), capsule collision 1.8 m; `var frozen := true` (no gravity/movement while true); `move_input: Vector2` and `run_held: bool` read from `Input` each physics frame; speed WALK/RUN; turns `Model` toward velocity with `TURN_SPEED`; `play_anim(name: String) -> void` (no-op if `not has_animation`, sets loop on `idle/walk/run`); `current_anim() -> String`; animation: idle when horizontal speed < 0.1, run when running, else walk.
- `IsoCamera` (`class_name IsoCamera extends Camera3D`): `target: Node3D`; orthographic, `size = CAM_ORTHO_SIZE`; rotation from `CAM_YAW_DEG`/`CAM_PITCH_DEG`; position = target + back-vector × `CAM_DISTANCE`; `_process` lerps with `CAM_FOLLOW_SMOOTH`; `snap_to_target()`.

- [ ] **Step 1:** failing tests:

```gdscript
# test_iso_input.gd
func test_up_yaw0(): assert_true(IsoInput.to_world(Vector2(0, -1), 0).is_equal_approx(Vector3(0, 0, -1)))
func test_right_yaw0(): assert_true(IsoInput.to_world(Vector2(1, 0), 0).is_equal_approx(Vector3(1, 0, 0)))
func test_up_yaw45(): assert_true(IsoInput.to_world(Vector2(0, -1), 45).is_equal_approx(Vector3(-0.70710678, 0, -0.70710678)))
func test_diagonal_is_normalized(): assert_true(IsoInput.to_world(Vector2(1, -1), 45).length() <= 1.0001)
# test_player.gd (flat StaticBody3D floor built in the test, player frozen=false)
func test_walk_speed():   # press move_up 60 physics frames → horizontal distance ≈ WALK_SPEED*1.0 (±15%), Input.action_release after
func test_run_faster():   # same with run → distance > walk distance * 1.5
func test_anim_states():  # idle when still; walk while moving; run with run held
func test_camera_follows(): # IsoCamera targeting player; after moving 4 m and 120 frames, camera-to-player flat offset within 0.5 m of rest offset
func test_camera_is_ortho_iso(): # projection == PROJECTION_ORTHOGONAL, rotation_degrees ≈ (CAM_PITCH_DEG, CAM_YAW_DEG, 0)
```
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS.
- [ ] **Step 5:** commit `feat: jogador com WASD relativo à tela, animações e câmera isométrica`.

### Task 6: World scene, spawn, edge walls

**Files:** Create `scripts/world/spawn_picker.gd`, `scripts/world/world.gd`, `scenes/main.tscn`; Test `tests/unit/test_spawn.gd`, `tests/integration/test_world.gd`

**Interfaces:**
- `SpawnPicker.pick(gen: TerrainGenerator, rng: RandomNumberGenerator) -> Vector3` — random x,z in playable area minus `SPAWN_EDGE_MARGIN`, accept when `slope_deg_at <= SPAWN_MAX_SLOPE_DEG`, up to `SPAWN_MAX_TRIES`, fallback map center; y = `height_at`.
- `World` (`extends Node3D`, root of `main.tscn`): `@export var spawn_seed := GameConstants.SPAWN_SEED`; builds generator (`WORLD_SEED`), `ChunkStreamer`, `DirectionalLight3D` with shadows, `WorldEnvironment` (procedural sky), four invisible `StaticBody3D` walls on playable edges, `Player`, `IsoCamera`; picks spawn, calls `streamer.update_center(spawn)`, keeps player `frozen` until the spawn chunk `is_loaded`, then places player at spawn + 0.5 m, unfreezes, `camera.snap_to_target()`, emits `signal world_ready`. Each `_physics_process` calls `streamer.update_center(player.global_position)`. `get_player() -> Player`, `get_streamer() -> ChunkStreamer`.

- [ ] **Step 1:** failing tests:

```gdscript
# test_spawn.gd
func test_spawn_inside_margin(): # 100 seeds: x,z within [MARGIN, playable_size()-MARGIN]
func test_spawn_slope_ok():      # 100 seeds: slope_deg_at(spawn) <= SPAWN_MAX_SLOPE_DEG (or spawn == center fallback)
func test_spawn_seeded_deterministic()
# test_world.gd (instantiate main.tscn with spawn_seed = 42, await world_ready, timeout 600 frames)
func test_world_ready_and_chunks_loaded()
func test_player_rests_on_ground(): # after 120 physics frames, |player.y - height_at(player.x,z)| < 0.3
func test_w_moves_screen_up():       # hold move_up 60 frames → displacement direction ≈ IsoInput.to_world((0,-1), CAM_YAW_DEG) (dot > 0.95)
func test_edge_wall_blocks():        # teleport near x=0 edge, hold move toward −x for 120 frames → x >= -0.5
func test_streams_while_walking():   # hold run 300 frames; chunk under player is_loaded at every sampled frame; max frame < MAX_FRAME_MS
```
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** full suite PASS.
- [ ] **Step 5:** commit `feat: cena principal com spawn aleatório, bordas e streaming ao andar`.

### Task 7: Visual capture and final verification

**Files:** Create `tests/visual/capture.gd`, `tools/capture.ps1`

**Interfaces:** `capture.gd` (`extends SceneTree`, run windowed): loads `main.tscn` with `spawn_seed = 42`, awaits `world_ready`, saves `captures/01_spawn.png`, holds W 1.5 s → `02_walk_up.png` (mid-stride), holds D+Shift 1.5 s → `03_run_right.png`, holds S+A 1 s → `04_diag.png`; prints worst frame ms; quits 0. `tools/capture.ps1` runs it (not headless) and lists the files.

- [ ] **Step 1:** implement and run `tools/capture.ps1`; open each PNG and confirm: terrain visible and faceted, character on the ground (not floating/sunk), facing its movement, isometric angle, no gaps between chunks.
- [ ] **Step 2:** run `tools/run_tests.ps1` → `RESULT: N passed, 0 failed`, exit 0.
- [ ] **Step 3:** commit `test: capturas visuais da etapa 1`; show the screenshots to the author.
