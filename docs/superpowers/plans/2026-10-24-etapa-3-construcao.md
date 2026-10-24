# Etapa 3 — Construção e fundação do reino · Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Spend wood/stone on five pre-made buildings placed with a ghost preview; the first cabin founds a named kingdom with a flag; buildings persist, stream with chunks, collide, and can be demolished for a 50 % refund.

**Architecture:** Pure `BuildRules` validates placement against terrain, props, buildings and resources. `WorldState` stores buildings and kingdoms (delta, per chunk). One sequential `ModelLibrary` (renamed from `PropLibrary`) loads prop meshes and building scenes. `Chunk` instances buildings; `BuildSystem` drives mode, ghost, place and demolish.

**Tech Stack:** Godot 4.7 / GDScript, Blender 5.2 `bpy`.

**Spec:** `docs/superpowers/specs/2026-10-24-etapa-3-construcao-design.md`

## Global Constraints

- Costs: Cabana 30 madeira + 10 pedra; Fogueira 5 + 3; Depósito 25 + 5; Cerca 4 madeira; Poço 5 madeira + 20 pedra. Refund 50 % (floor).
- Footprints (m): Cabana 4×5, Fogueira 1.6×1.6, Depósito 4×3, Cerca 3×0.4, Poço 2×2; rotation in quarter turns (odd = swap).
- `BUILD_MAX_HEIGHT_DIFF := 1.2`, `KINGDOM_RADIUS := 40.0`.
- Keys: B mode, 1–5 select, R rotate, LMB/E place, RMB/Esc leave, X demolish.
- All numbers in `GameConstants`; models only from `tools/blender`; in-game text Portuguese.
- Only one model loader at a time (renderer race found in stage 2).

## Review Focus

1. **Resources spent but nothing built (or the reverse)** when placement fails late → Task 5 `test_failed_place_spends_nothing`.
2. **Building lost after save/reload or chunk reload** → Task 1 `test_buildings_roundtrip`, Task 4 `test_building_survives_chunk_reload`.
3. **Building over a tree/rock or floating** → Task 2 reason tests + `test_y_is_max_ground`.
4. **Demolishing the seat cabin / refund rounding** → Task 5 `test_seat_cabin_cannot_be_demolished`, `test_refund_half_floor`.
5. **Ghost/raycast hitting trees instead of the ground** → Task 5 `test_ray_ignores_obstacles` (physics layers).

---

### Task 1: Building data, kingdom names, WorldState persistence

**Files:** Modify `scripts/core/game_constants.gd`, `scripts/world/world_state.gd`; Create `scripts/world/kingdom_names.gd`; Test `tests/unit/test_buildings_state.gd`, `tests/unit/test_kingdom_names.gd`

**Interfaces:**
- Constants: `enum Building {CABIN, CAMPFIRE, STORAGE, FENCE, WELL, FLAG}`; `BUILDABLE := [CABIN, CAMPFIRE, STORAGE, FENCE, WELL]` (FLAG is placed automatically); `BUILD_COST`, `BUILD_FOOTPRINT` (Vector2), `BUILD_NAMES` ("Cabana", "Fogueira", "Depósito", "Cerca", "Poço", "Bandeira"), `BUILD_SCENES` (`res://assets/models/<cabin|campfire|storage|fence|well|flag>.glb`), `BUILD_COLLIDERS` (per type: Array of `[center: Vector3, size: Vector3]` local, rot 0), `BUILD_REFUND := 0.5`.
- `WorldState`: `add_building(type: int, pos: Vector3, rot: int, color := Color.WHITE) -> Dictionary` (record `{id, type, pos, rot, color}`, id from `next_building_id`); `remove_building(id: int) -> Dictionary`; `building(id: int) -> Dictionary`; `buildings_in(c: Vector2i) -> Array[Dictionary]`; `all_buildings() -> Array[Dictionary]`; `add_kingdom(name: String, color: Color, center: Vector3, seat_id: int) -> Dictionary` (`{id, name, color, center, radius = KINGDOM_RADIUS, seat_id}`); `kingdoms() -> Array[Dictionary]`; `kingdom_at(pos: Vector3) -> Dictionary` (flat distance); `can_afford(cost: Dictionary) -> bool`; `spend(cost: Dictionary) -> bool` (all or nothing); `refund(cost: Dictionary, ratio: float)`. Saved in the payload (`buildings`, `kingdoms`, `next_building_id`).
- `KingdomNames.generate(seed: int, index: int) -> String`: 2–3 syllables from fixed Portuguese-flavored lists, capitalized, deterministic.

- [ ] **Step 1:** failing tests:

```gdscript
func test_add_and_query_by_chunk(): # building at (40,0,40) appears in buildings_in((1,1)) only
func test_ids_increase_and_remove(): # two ids differ; remove_building(first) → building(first) == {}
func test_buildings_roundtrip(): # 2 buildings + 1 kingdom + next id → save/load equal
func test_spend_all_or_nothing(): # wood 10, cost {wood 5, stone 3} → false, wood still 10
func test_refund_half_floor(): # refund({wood 5, stone 3}, 0.5) → +2 wood, +1 stone
func test_kingdom_at(): # inside radius → kingdom; outside → {}
# test_kingdom_names.gd
func test_deterministic_and_varied(): # same (seed,index) equal; 20 seeds → >= 15 distinct; 4..12 chars, capitalized
```
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** suite PASS. **Step 5:** commit `feat: dados de construções e reinos no estado do mundo`.

### Task 2: Placement rules

**Files:** Create `scripts/world/build_rules.gd`; Test `tests/unit/test_build_rules.gd`

**Interfaces:**
- Constants: `BUILD_MAX_HEIGHT_DIFF := 1.2`, `BUILD_SAMPLE_STEP := 0.5`, `BUILD_GRID := 0.5`, message strings `BUILD_MSG_OUTSIDE := "Fora do mapa"`, `BUILD_MSG_SLOPE := "Terreno muito inclinado"`, `BUILD_MSG_PROP := "Há uma árvore ou rocha no caminho"`, `BUILD_MSG_OCCUPIED := "Ocupado por outra construção"`, `BUILD_MSG_MISSING := "Falta %s (%d/%d)"` (lower-case resource name).
- `BuildRules.footprint_rect(type: int, pos: Vector3, rot: int) -> Rect2` (XZ, centered on pos, swapped for odd rot).
- `BuildRules.check(type: int, pos: Vector3, rot: int, gen: TerrainGenerator, scatter: PropScatter, state: WorldState) -> Dictionary` → `{ok: bool, reason: String, y: float, bushes: Array}` (bushes = `[{chunk: Vector2i, id: int}]` under the footprint, not yet removed). Order of checks: outside → slope (max−min of heights sampled every `BUILD_SAMPLE_STEP` > max diff) → solid prop whose circle (radius×scale) intersects the rect, ignoring removed ids → overlapping building rect (chunks around) → resources. `y` = max sampled height. FLAG ignores resources.
- `BuildRules.snap(pos: Vector3) -> Vector3` to `BUILD_GRID` on X/Z.
- Overlap: rects shrunk by `BUILD_TOUCH_TOLERANCE := 0.1` per side; FENCE vs FENCE never overlaps; FLAG records are ignored.

- [ ] **Step 1:** failing tests (find spots with `gen`/`scatter`, `WORLD_SEED`): `test_ok_on_flat_clear_ground`, `test_outside_map`, `test_too_steep`, `test_blocked_by_tree`, `test_removed_tree_does_not_block`, `test_bush_is_cleared_not_blocking`, `test_overlap_other_building`, `test_missing_resource_message` (wood 12 → "Falta madeira (12/30)"), `test_rotation_swaps_footprint`, `test_y_is_max_ground`.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS. **Step 5:** commit `feat: regras de colocação de construções`.

### Task 3: Blender buildings and ModelLibrary

**Files:** Create `tools/blender/buildings.py`, `assets/models/{cabin,campfire,storage,fence,well,flag}.glb`; Rename `scripts/world/prop_library.gd` → `scripts/world/model_library.gd` (`class_name ModelLibrary`), update all users and tests; Modify `tools/build_models.ps1`; Test `tests/unit/test_building_models.gd`

**Interfaces:**
- `buildings.py -- <cabin|campfire|storage|fence|well|flag> <out.glb>`: origin at footprint center on the ground, front (door) facing −Y in Blender (= +Z Godot), sizes match `BUILD_FOOTPRINT`, stone foundation skirt 0.3 m tall at the base; flag has a material named `banner`.
- Building scenes also get their surface materials swapped for the occlusion shader (flag banner: per-instance duplicated ShaderMaterial with `albedo` = record color).
- `ModelLibrary`: unchanged prop API (`mesh_for`, `OCCLUSION_SHADER`) + `scene_for(building: int) -> PackedScene`; one sequential queue for props then buildings; `is_ready()` when all are loaded.

- [ ] **Step 1:** failing tests: `test_building_glbs_exist`, `test_building_sizes_match_footprint` (AABB x/z within ±0.6 m of footprint, base ≈ 0), `test_flag_has_banner_material`, `test_library_scenes_for_buildings`.
- [ ] **Step 2:** FAIL. **Step 3:** implement + `tools/build_models.ps1`. **Step 4:** PASS. **Step 5:** commit `feat: modelos de construções do Blender e ModelLibrary`.

### Task 4: Buildings in chunks

**Files:** Modify `scripts/world/chunk.gd`, `scripts/world/chunk_streamer.gd`, `scripts/actors/player.gd` (collision mask), `scripts/world/world.gd` (setup call); Create `scripts/world/campfire_light.gd`; Test `tests/integration/test_chunk_buildings.gd`

**Interfaces:**
- Constants: `LAYER_TERRAIN := 1`, `LAYER_OBSTACLES := 2` (bit values), `FOUNDATION_DEPTH := 2.0`, `CAMPFIRE_LIGHT_ENERGY := 2.0`, `CAMPFIRE_LIGHT_RANGE := 9.0`.
- `ChunkStreamer.setup(gen, scatter, library: ModelLibrary, removed_provider: Callable, buildings_provider: Callable) -> void` (`func(c) -> Array[Dictionary]`).
- `Chunk.build(..., buildings: Array[Dictionary])`; `add_building(record: Dictionary) -> void`; `remove_building(id: int) -> void`; `has_building(id: int) -> bool`. Node per building `B_<id>`: scene instance (rot `rot·PI/2`, local pos), stone foundation box from y down `FOUNDATION_DEPTH` sized to footprint, `StaticBody3D` on `LAYER_OBSTACLES` with `BUILD_COLLIDERS` boxes; FLAG recolors `banner` with `record.color`; CAMPFIRE gets `CampfireLight` (OmniLight3D with noise flicker). Prop bodies move to `LAYER_OBSTACLES`; terrain stays `LAYER_TERRAIN`; player mask = both.
- Buildings whose position lies in a chunk are stored in that chunk only (state indexes by `world_to_chunk(pos)`).

- [ ] **Step 1:** failing tests: `test_chunk_instances_buildings`, `test_building_survives_chunk_reload`, `test_add_and_remove_live`, `test_building_blocks_player`, `test_campfire_has_light`, `test_flag_banner_colored`.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** suite PASS. **Step 5:** commit `feat: construções nos chunks com colisão, fundação e luz da fogueira`.

### Task 5: BuildSystem (mode, ghost, place, demolish, kingdom)

**Files:** Create `scripts/world/build_system.gd`; Modify `project.godot` (actions `build_mode` B, `build_rotate` R, `demolish` X, `build_1`..`build_5` keys 1–5, `build_place` LMB, `build_cancel` Esc + RMB), `scripts/actors/player.gd` (`harvest_enabled`); Test `tests/integration/test_build_system.gd`

**Interfaces:**
- Constants: `BUILD_GHOST_DISTANCE := 3.0`, `BUILD_DEMOLISH_RANGE := 3.0`, `FLAG_OFFSET := Vector3(1.6, 0, 2.3)` (cabin-local), `GHOST_OK_COLOR`, `GHOST_BAD_COLOR`.
- `BuildSystem extends Node`: `setup(state: WorldState, gen: TerrainGenerator, scatter: PropScatter, streamer: ChunkStreamer, library: ModelLibrary, player: Player, camera: Camera3D) -> void`; `var active: bool`, `var type: int`, `var rot: int`; `toggle()`, `select(type: int)`, `rotate_ghost()`; `ghost_position() -> Vector3` (mouse ray to `LAYER_TERRAIN`, else 3 m in front of the player; snapped); `preview() -> Dictionary` (`BuildRules.check` at the ghost); `try_place() -> bool` (re-checks, spends, clears bushes via `state.mark_removed` + chunk removal, adds the record, adds to the loaded chunk, founds the kingdom on the first CABIN with flag); `try_demolish(near: Vector3) -> bool`; signals `built(record)`, `demolished(record)`, `kingdom_founded(kingdom)`. Input in `_unhandled_input` (actions above). While active, `player.harvest_enabled = false`.

- [ ] **Step 1:** failing tests: `test_toggle_and_select`, `test_place_spends_and_builds`, `test_failed_place_spends_nothing`, `test_first_cabin_founds_kingdom_with_flag`, `test_second_cabin_does_not_found`, `test_place_clears_bushes`, `test_demolish_refunds_half`, `test_seat_cabin_cannot_be_demolished`, `test_ray_ignores_obstacles`, `test_harvest_disabled_in_build_mode`.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS. **Step 5:** commit `feat: modo construção, fantasma, demolição e fundação do reino`.

### Task 6: HUD, World wiring, captures, docs

**Files:** Modify `scripts/ui/hud.gd`, `scripts/world/world.gd`, `tests/visual/capture.gd`, `CLAUDE.md`; Test `tests/integration/test_hud.gd` (+build/kingdom), `tests/integration/test_world_persistence.gd` (+buildings)

**Interfaces:** `Hud.setup(..., build: BuildSystem)`; labels `Build` ("Construindo: Cabana — 30 madeira, 10 pedra · R gira · Clique constrói · Esc sai"), `BuildReason` (red, reason when not ok), `Kingdom` ("Reino de <Nome>" inside a territory), `Toast` ("Você fundou o Reino de <Nome>!", `FOUNDING_TOAST_SEC := 5.0`). `World.get_build() -> BuildSystem`.

- [ ] **Step 1:** failing tests: `test_build_line_and_reason`, `test_kingdom_label_inside_territory`, `test_founding_toast`, `test_buildings_persist_across_save_and_reload` (world A: give resources, place cabin + campfire, save; world B: both present in state and chunk, kingdom kept).
- [ ] **Step 2:** FAIL. **Step 3:** implement; captures: ghost valid, ghost invalid (with reason), village (cabin+flag, storage, well, fences, campfire) by day, campfire at night; CLAUDE.md commands/controls/roadmap. **Step 4:** suite PASS + inspect captures.
- [ ] **Step 5:** commit `feat: HUD de construção e reino, capturas e docs da etapa 3`.
