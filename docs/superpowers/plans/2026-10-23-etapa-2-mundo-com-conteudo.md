# Etapa 2 — Mundo com conteúdo · Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 24×24-chunk world with three biomes, Blender-made trees/rocks/bushes drawn by MultiMesh, harvesting with E into resources, day/night cycle, HUD, and delta persistence.

**Architecture:** Terrain + prop scatter are computed together on WorkerThreadPool; a `Chunk` node owns terrain, one MultiMesh per prop type and collision. `WorldState` holds only deltas and is saved in binary. `HarvestSystem`, `DayNight` and `Hud` are small nodes wired by `World`.

**Tech Stack:** Godot 4.7 / GDScript, Blender 5.2 `bpy`, PowerShell tools.

**Spec:** `docs/superpowers/specs/2026-10-23-etapa-2-mundo-com-conteudo-design.md` (base: `2026-10-23-jogo-reino-vivo-design.md`)

## Global Constraints

- All gameplay numbers in `GameConstants`; enums `Biome {PLAINS, FOREST, ROCKY}`, `Prop {OAK, PINE, ROCK, BUSH}`, `Res {WOOD, STONE, BERRIES}` live there.
- No synchronous loading during play (props built off-thread; `.glb` via `ResourceLoader.load_threaded_request`).
- Models only from `tools/blender/*.py`; never edit `.glb`.
- In-game text Portuguese; code English.
- Map 24×24 chunks; harvest: tree 4 hits → 3 wood, rock 5 → 2 stone, bush 1 → 2 berries; day 480 s; autosave 60 s; save `user://save.bin`.
- Bump `WORLDGEN_VERSION` whenever generation changes.
- Done = `tools/run_tests.ps1` exit 0 read, captures inspected, committed.

## Review Focus

1. **Cut tree reappears** after its chunk unloads/reloads or after save→load → Task 4 `test_removed_prop_stays_removed_after_reload`, Task 5 `test_roundtrip`.
2. **Old save after generation change** removes the wrong trees → Task 5 `test_version_mismatch_drops_removed_only`.
3. **Spawn inside a tree/rock** → Task 2 `test_spawn_clear_of_props`.
4. **Walking through trees/rocks** → Task 4 `test_tree_blocks_player`.
5. **Harvest spam / harvesting while moving away / nothing in range** → Task 6 `test_hit_cooldown`, `test_no_target_out_of_range`.

---

## File Structure

| File | Responsibility |
|---|---|
| `scripts/core/game_constants.gd` | + enums, biome/prop/harvest/day/save constants |
| `scripts/world/terrain_generator.gd` | + `biome_at`, rocky height boost, biome colors |
| `scripts/world/prop_scatter.gd` | deterministic props per chunk (thread-safe) |
| `scripts/world/spawn_picker.gd` | + prop clearance |
| `tools/blender/props.py`, `tools/blender/humanoid.py` | prop models; + `work` animation |
| `scripts/world/prop_library.gd` | threaded load of prop meshes |
| `scripts/world/chunk.gd` | chunk node: terrain, MultiMesh per type, collision, `remove_prop` |
| `scripts/world/chunk_streamer.gd` | builds terrain+props off-thread, creates `Chunk`s, filters removed |
| `scripts/world/world_state.gd` | deltas + binary save/load |
| `scripts/world/harvest_system.gd` | targeting, hits, removal, resources |
| `scripts/actors/player.gd` | + interact/work |
| `scripts/world/day_night.gd` | sun/sky/ambient over time |
| `scripts/ui/hud.gd` | resource, prompt and clock labels |
| `scripts/world/world.gd` | wiring, seed, save/load, autosave |
| `tools/new_world.ps1`, `tests/visual/capture.gd`, `CLAUDE.md` | tooling, captures, docs |

---

### Task 1: Constants, bigger map, biomes in terrain

**Files:** Modify `scripts/core/game_constants.gd`, `scripts/world/terrain_generator.gd`, `tests/unit/test_chunk_math.gd` (playable size 768, radius test unchanged); Test `tests/unit/test_biomes.gd`

**Interfaces:**
- Produces constants: `MAP_CHUNKS := 24`, `WORLDGEN_VERSION := 1`, `BIOME_NOISE_FREQ := 0.006`, `BIOME_FOREST_MIN := 0.2`, `BIOME_ROCKY_MAX := -0.3`, `ROCKY_HEIGHT_BOOST := 1.2`, the three enums, `BIOME_NAMES := {PLAINS:"Planície", FOREST:"Floresta", ROCKY:"Pedregoso"}`.
- `TerrainGenerator.biome_at(x: float, z: float) -> int`; `height_at` = base × (1 + ROCKY_HEIGHT_BOOST × rockiness), rockiness = smoothstep from `BIOME_ROCKY_MAX + 0.2` down to `BIOME_ROCKY_MAX` on the biome value; face colors blend grass/forest-dark/rock tints by the same weights. `height_at` range test becomes `[0, TERRAIN_HEIGHT × (1 + ROCKY_HEIGHT_BOOST)]`.

- [ ] **Step 1:** failing tests `test_biomes.gd`:

```gdscript
func test_biome_deterministic(): assert_eq(TerrainGenerator.new(7).biome_at(300, 120), TerrainGenerator.new(7).biome_at(300, 120))
func test_all_biomes_present(): # sample 768x768 every 16 m with WORLD_SEED: each biome covers >= 10% of samples
func test_height_continuous_across_biomes(): # for 2000 random points: |height_at(x,z) - height_at(x+0.5,z)| < 1.0
func test_rocky_is_higher_on_average(): # mean height of ROCKY samples > mean of PLAINS samples
```
- [ ] **Step 2:** FAIL. **Step 3:** implement; update chunk-math/terrain range tests. **Step 4:** full suite PASS (tune thresholds/freq if `test_all_biomes_present` fails; ledger the values).
- [ ] **Step 5:** commit `feat: mapa 24x24 e biomas no terreno`.

### Task 2: Prop scatter + spawn clearance

**Files:** Create `scripts/world/prop_scatter.gd`; Modify `scripts/world/spawn_picker.gd`, `tests/unit/test_spawn.gd`, `scripts/world/world.gd` (call site only); Test `tests/unit/test_prop_scatter.gd`

**Interfaces:**
- Constants: `PROP_CELL := 4.0`, `PROP_MAX_SLOPE_DEG := 30.0`, `PROP_SINK := 0.05`, `PROP_SCALE_MIN := 0.8`, `PROP_SCALE_MAX := 1.25`, `PROP_DENSITY` (per biome → per prop probability: PLAINS {OAK .05, PINE 0, ROCK .03, BUSH .08}, FOREST {OAK .25, PINE .30, ROCK .03, BUSH .10}, ROCKY {OAK 0, PINE .06, ROCK .25, BUSH .03}), `PROP_COLLISION_RADIUS` {OAK .4, PINE .35, ROCK .9, BUSH 0}, `SPAWN_PROP_CLEARANCE := 2.0`.
- `PropScatter.new(gen: TerrainGenerator, seed: int)`; `build_chunk_props(c: Vector2i) -> Array[Dictionary]` — each `{id: int, type: int, pos: Vector3 (world), yaw: float, scale: float}`, `id = j * cells + i` with `cells = int(CHUNK_SIZE / PROP_CELL)`; one roll per cell (cumulative probabilities of the cell's biome); RNG seeded `hash([seed, c.x, c.y])` and advanced identically for every cell (always draw jitter x, jitter z, roll, yaw, scale) so ids are stable. Skips slope > max. `props_near(pos: Vector3, radius: float) -> Array[Dictionary]` over the chunks touching the circle.
- `SpawnPicker.pick(gen: TerrainGenerator, scatter: PropScatter, rng: RandomNumberGenerator) -> Vector3` rejects points with a prop of radius > 0 within `SPAWN_PROP_CLEARANCE + radius*scale`.

- [ ] **Step 1:** failing tests:

```gdscript
func test_deterministic(): # build_chunk_props((3,4)) twice → equal arrays
func test_props_inside_chunk(): # every pos within chunk bounds, y ≈ height_at - PROP_SINK*scale tolerance 0.2
func test_ids_unique_and_in_range(): # ids unique, 0 <= id < cells*cells
func test_forest_denser_than_plains(): # avg props/chunk over chunks whose center biome is FOREST > PLAINS * 2
func test_no_props_on_steep_slope(): # slope_deg_at(pos) <= PROP_MAX_SLOPE_DEG for all
func test_ids_stable_when_density_changes(): # (structural) cell (i,j) of a prop equals floor(local/PROP_CELL) → id == j*cells+i
# test_spawn.gd
func test_spawn_clear_of_props(): # 100 seeds: no ROCK/OAK/PINE within SPAWN_PROP_CLEARANCE of spawn (unless center fallback)
```
- [ ] **Step 2:** FAIL. **Step 3:** implement; update existing spawn tests and `World` to the new signature (scatter built from `WORLD_SEED` for now). **Step 4:** suite PASS.
- [ ] **Step 5:** commit `feat: espalhamento determinístico de árvores, rochas e arbustos`.

### Task 3: Blender props, work animation, PropLibrary

**Files:** Create `tools/blender/props.py`, `scripts/world/prop_library.gd`, `assets/models/{oak,pine,rock,bush}.glb`; Modify `tools/blender/humanoid.py` (+`work`), `tools/build_models.ps1` (list of jobs: script, args, out); Test `tests/unit/test_prop_models.gd`, `tests/unit/test_humanoid_model.gd` (+work)

**Interfaces:**
- `props.py -- <oak|pine|rock|bush> <out.glb>`: one joined mesh object per prop, origin at base, flat faces, sRGB colors via `common.flat_material`; oak ≈ 4.5 m, pine ≈ 5.5 m, rock ≈ 1.2 m, bush ≈ 0.8 m with red berry boxes. Rock jitter seeded (`random.seed(7)`).
- humanoid `work` action: 0.45 s (11 frames), both arms raise (upper_arm rot_x −110°) then strike down (+10°), slight spine lean; non-looping.
- Constants: `ANIM_WORK := "work"`, `PROP_SCENES := {OAK:"res://assets/models/oak.glb", PINE:…pine.glb, ROCK:…rock.glb, BUSH:…bush.glb}`.
- `PropLibrary extends Node`: `start_loading() -> void` (threaded requests), `is_ready() -> bool`, `mesh_for(type: int) -> Mesh` (first MeshInstance3D mesh of the scene, extracted once ready, on main thread in `_process`).

- [ ] **Step 1:** failing tests:

```gdscript
# test_prop_models.gd
func test_prop_glbs_exist_with_mesh(): # for each PROP_SCENES: exists, instantiate, exactly 1 MeshInstance3D
func test_prop_sizes(): # AABB height: oak 3.5–5.5, pine 4.5–6.5, rock 0.7–1.6, bush 0.5–1.1; min y ≈ 0 (±0.1)
func test_library_loads_async(): # start_loading(); is_ready() false on same frame; ready within 300 frames; mesh_for(each) != null
# test_humanoid_model.gd
func test_humanoid_has_work_animation(): # ap.has_animation(ANIM_WORK) and length in [0.3, 0.6]
```
- [ ] **Step 2:** FAIL. **Step 3:** implement; run `tools/build_models.ps1`. **Step 4:** suite PASS.
- [ ] **Step 5:** commit `feat: árvores, rochas e arbustos do Blender, animação work e PropLibrary`.

### Task 4: Chunk node with props + streamer integration

**Files:** Create `scripts/world/chunk.gd`; Modify `scripts/world/chunk_streamer.gd`, `scripts/world/world.gd` (setup call), `tests/integration/test_chunk_streamer.gd` (setup signature); Test `tests/integration/test_chunk_props.gd`

**Interfaces:**
- Consumes: `PropScatter`, `PropLibrary`, `WorldState.removed_in(c) -> PackedInt32Array` (Task 5 — in this task pass a minimal `WorldState` stub? No: implement Task 4 against a `removed_provider: Callable` `func(c: Vector2i) -> PackedInt32Array`, default returns empty).
- `Chunk extends Node3D`: `coord: Vector2i`; `build(coord: Vector2i, terrain_arrays: Array, props: Array[Dictionary], removed: PackedInt32Array, library: PropLibrary, terrain_material: Material) -> void`; `has_prop(id: int) -> bool`; `get_prop(id: int) -> Dictionary`; `prop_ids() -> PackedInt32Array`; `remove_prop(id: int) -> void` (rebuilds that type's MultiMesh, frees its CollisionShape3D); `instance_count(type: int) -> int`. Collision: one `StaticBody3D` "Props" with a `CylinderShape3D` (radius `PROP_COLLISION_RADIUS × scale`, height 3) per OAK/PINE/ROCK; terrain collision only for playable chunks as before; props only in playable chunks.
- `ChunkStreamer.setup(gen: TerrainGenerator, scatter: PropScatter, library: PropLibrary, removed_provider: Callable) -> void`; `get_chunk(c: Vector2i) -> Chunk`; results wait in queue until `library.is_ready()`.

- [ ] **Step 1:** failing tests:

```gdscript
func test_chunk_instances_match_scatter(): # load chunk (5,5); for each type instance_count == count in scatter
func test_removed_filtered_on_build(): # provider returns [first id] → that id absent, count-1
func test_remove_prop_updates_multimesh_and_collision()
func test_removed_prop_stays_removed_after_reload(): # remove id via provider-backed dict, move away to unload, return → still absent
func test_tree_blocks_player(): # player.tscn placed 3 m from an OAK, walk toward it 120 frames → horizontal distance to trunk >= radius
func test_streaming_forest_frame_budget(): # settle around the densest forest chunk; worst frame < MAX_FRAME_MS
```
- [ ] **Step 2:** FAIL. **Step 3:** implement; adapt existing streamer tests to the new `setup`. **Step 4:** suite PASS.
- [ ] **Step 5:** commit `feat: chunks com MultiMesh de objetos, colisão e remoção`.

### Task 5: WorldState and binary save

**Files:** Create `scripts/world/world_state.gd`; Test `tests/unit/test_world_state.gd`

**Interfaces:**
- Constants: `SAVE_PATH := "user://save.bin"`, `AUTOSAVE_SEC := 60.0`.
- `WorldState extends RefCounted`: `var seed: int`, `var time_of_day: float`, `var day: int = 1`, `var player_position: Vector3`, `var has_player_position := false`; `mark_removed(c: Vector2i, id: int)`, `removed_in(c: Vector2i) -> PackedInt32Array`, `add_resource(res: int, amount: int)`, `get_resource(res: int) -> int`, `save_to(path: String) -> Error` (`FileAccess.store_var` of a Dictionary with `version = WORLDGEN_VERSION`, write to `path + ".tmp"` then rename), `static load_from(path: String) -> WorldState` (null if missing or unreadable; on version mismatch clears `removed` and `push_warning`).

- [ ] **Step 1:** failing tests:

```gdscript
func test_roundtrip(): # set all fields + 2 removed ids in 2 chunks + resources → save_to(tmp) → load_from → equal
func test_missing_file_returns_null()
func test_corrupt_file_returns_null(): # write random bytes → null, no crash (errors captured by runner must be none: use push_warning not push_error)
func test_version_mismatch_drops_removed_only(): # save, rewrite dict with version-1 → load: removed empty, resources/seed/position kept
func test_mark_removed_no_duplicates()
```
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS.
- [ ] **Step 5:** commit `feat: estado do mundo com save binário delta`.

### Task 6: Harvesting

**Files:** Create `scripts/world/harvest_system.gd`; Modify `scripts/actors/player.gd`, `project.godot` (`interact` = E, physical keycode 69); Test `tests/integration/test_harvest.gd`

**Interfaces:**
- Constants: `HARVEST_RANGE := 2.2`, `HARVEST_HIT_TIME := 0.45`, `HARVEST_HITS := {OAK:4, PINE:4, ROCK:5, BUSH:1}`, `HARVEST_YIELD := {OAK:[Res.WOOD,3], PINE:[Res.WOOD,3], ROCK:[Res.STONE,2], BUSH:[Res.BERRIES,2]}`, `HARVEST_PROMPTS := {OAK:"[E] Cortar árvore", PINE:"[E] Cortar árvore", ROCK:"[E] Quebrar rocha", BUSH:"[E] Colher frutas"}`, `RES_NAMES := {WOOD:"Madeira", STONE:"Pedra", BERRIES:"Frutas"}`.
- `HarvestSystem extends Node`: `setup(streamer: ChunkStreamer, state: WorldState) -> void`; `find_target(pos: Vector3) -> Dictionary` (`{}` or `{chunk: Chunk, prop: Dictionary}`; nearest by flat distance minus collision radius ≤ `HARVEST_RANGE`); `hit(target: Dictionary) -> bool` (true when the prop got removed); signals `resources_changed`, `harvested(prop_type: int)`.
- `Player`: `var harvest: HarvestSystem`; `is_working() -> bool`; on `interact` just-pressed while not working and a target exists: face it, `play_anim(ANIM_WORK)` (forced restart), `harvest.hit(target)`, freeze horizontal movement for `HARVEST_HIT_TIME`.

- [ ] **Step 1:** failing tests (flat floor + one `Chunk` built from a hand-made props list):

```gdscript
func test_find_target_nearest()
func test_no_target_out_of_range()
func test_tree_needs_four_hits_and_gives_wood(): # 3 hits → still present, wood 0; 4th → removed, wood 3, state.removed_in has id
func test_bush_one_hit_berries()
func test_hit_cooldown(): # player: press interact twice within HARVEST_HIT_TIME → only 1 hit counted
func test_player_stops_while_working(): # holding move_up + interact → no horizontal movement during HARVEST_HIT_TIME
```
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** suite PASS.
- [ ] **Step 5:** commit `feat: coleta de madeira, pedra e frutas`.

### Task 7: Day/night cycle

**Files:** Create `scripts/world/day_night.gd`; Test `tests/unit/test_day_night.gd`

**Interfaces:**
- Constants: `DAY_LENGTH_SEC := 480.0`, `START_TIME_OF_DAY := 0.30`, `NIGHT_MIN_AMBIENT := 0.25`, `SUN_MAX_ENERGY := 1.1`, colors `SUN_DAY_COLOR`, `SUN_DUSK_COLOR`, `SKY_DAY_TOP`, `SKY_DAY_HORIZON`, `SKY_DUSK_HORIZON`, `SKY_NIGHT_TOP`, `SKY_NIGHT_HORIZON`.
- `DayNight extends Node`: `setup(sun: DirectionalLight3D, env: Environment, sky: ProceduralSkyMaterial) -> void`; `var time_of_day: float`; `var day: int`; `advance(seconds: float) -> void` (wraps and increments `day`); `sun_elevation() -> float` = `sin((t − 0.25)·TAU)`; `apply() -> void`; `clock_text() -> String` → `"Dia %d · %02d:%02d"`.

- [ ] **Step 1:** failing tests:

```gdscript
func test_noon_brighter_than_midnight(): # t=0.5 sun energy > t=0.0 energy; t=0 env ambient energy >= NIGHT_MIN_AMBIENT
func test_wraps_and_counts_days(): # t=0.9, advance(0.2*DAY_LENGTH_SEC) → t≈0.1, day+1
func test_clock_text(): # t=0.5, day 2 → "Dia 2 · 12:00"
func test_sun_points_down_at_noon(): # sun -basis.z .y < -0.5 at t=0.5
```
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS. **Step 5:** commit `feat: ciclo de dia e noite`.

### Task 8: HUD

**Files:** Create `scripts/ui/hud.gd`; Test `tests/integration/test_hud.gd`

**Interfaces:** `Hud extends CanvasLayer`: `setup(state: WorldState, harvest: HarvestSystem, day_night: DayNight, player: Player) -> void`; child Labels `Resources`, `Prompt`, `Clock`; `resources_text() -> String` = `"Madeira: %d   Pedra: %d   Frutas: %d"`; `Prompt` shows `HARVEST_PROMPTS[type]` of `harvest.find_target(player pos)` or hidden; refreshes on `resources_changed` and every physics frame for prompt/clock.

- [ ] **Step 1:** failing tests: `test_resources_text`, `test_prompt_near_tree_and_hidden_far`, `test_clock_label_matches_day_night`.
- [ ] **Step 2:** FAIL. **Step 3:** implement (outlined text: font size 22, outline 6, readable on grass and at night). **Step 4:** PASS. **Step 5:** commit `feat: HUD de recursos, dica e relógio`.

### Task 9: World wiring, persistence, tooling, captures, docs

**Files:** Modify `scripts/world/world.gd`, `tests/integration/test_world.gd`, `tests/visual/capture.gd`, `CLAUDE.md`; Create `tools/new_world.ps1`; Test `tests/integration/test_world_persistence.gd`

**Interfaces:** `World`: `@export var world_seed := -1`, `@export var save_path := GameConstants.SAVE_PATH` ("" = never save); `_ready`: `state = WorldState.load_from(save_path)` or new (seed = `world_seed` if ≥0 else random); gen/scatter from `state.seed`; `PropLibrary.start_loading()`; streamer provider = `state.removed_in`; spawn from `state.player_position` if `has_player_position` else `SpawnPicker`; `DayNight` from `state.time_of_day/day` (START_TIME_OF_DAY for new); `HarvestSystem`, `Hud`; `save_now() -> Error` copies player position + time into state and saves; autosave every `AUTOSAVE_SEC`; save on `NOTIFICATION_WM_CLOSE_REQUEST`. Getters `get_state()`, `get_harvest()`, `get_day_night()`, `get_hud()`. `world_ready` only after the library is ready and the spawn chunk is loaded.

- [ ] **Step 1:** failing tests:

```gdscript
func test_new_world_random_seed_differs(): # two worlds world_seed=-1, save_path="" → different state.seed (retry once on collision)
func test_harvest_persists_across_save_and_reload(): # world A (save_path tmp, world_seed 42): harvest nearest bush, save_now, free; world B same path → bush id still in removed, chunk lacks it, berries == 2, player position restored
func test_existing_world_tests_still_pass() # (existing test_world.gd adapted: world_seed 42, save_path "")
```
- [ ] **Step 2:** FAIL. **Step 3:** implement; `tools/new_world.ps1` deletes `%APPDATA%\Godot\app_userdata\MeuJogo\save.bin`; update capture (`world_seed` fixed, `save_path` ""): shots spawn, walking in forest, harvesting (mid `work`), HUD with resources > 0, same spot at night (set `time_of_day = 0.02`), rocky area; CLAUDE.md: commands, WORLDGEN_VERSION rule, stage 2 done. **Step 4:** suite PASS + run capture and inspect every image.
- [ ] **Step 5:** commit `feat: mundo com save, dia/noite, HUD e capturas da etapa 2`.
