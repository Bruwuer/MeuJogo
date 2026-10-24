# Etapa 5 — Pessoas · Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Travelers with name, traits and opinion arrive, decide whether to stay (with a readable reason), have needs, work by profession on a kingdom stock and autonomously build houses, farms and a market — loaded or not.

**Architecture:** Pure data/logic first (`PersonGen`, `VillageRules`), then state (`WorldState` people/stock/owner/sites), models, the hourly `VillageSim`, then nodes (`Person`, `PersonBrain`, `PeopleManager`), then player interaction, HUD and World wiring.

**Tech Stack:** Godot 4.7 / GDScript, Blender 5.2 `bpy`.

**Spec:** `docs/superpowers/specs/2026-10-24-etapa-5-pessoas-design.md` (section 5 overrides earlier text)

## Global Constraints

- 1 game hour = 20 s (`DAY_LENGTH_SEC / 24`). All numbers in `GameConstants`. In-game text Portuguese, code English.
- New enum values only appended (`Res.FOOD` after `ARROWS`; `Building.HOUSE, FARM, MARKET` after `FLAG`); never in `BUILDABLE`.
- `KINGDOM_MAX_PEOPLE := 12`, `PEOPLE_MAX_ACTIVE := 30`, `PERSON_BRAIN_TICK := 0.25`, at most 2 person nodes per frame.
- People: layer `LAYER_PEOPLE := 8`; mask terrain|obstacles; the player does not collide with them.
- One loader (`ModelLibrary`); people use `humanoid.glb` through it. Materials cached by color.
- Keyboard: E talks (priority over harvest, outside build mode), G donates (≤10 of each resource).
- Player cannot demolish villager buildings (`owner >= 0`).

## Review Focus

1. **Kingdom never grows / everyone leaves** at the start → Task 4 `test_founders_always_stay`, Task 5 `test_new_kingdom_grows`.
2. **Stock exploits or loss** (demolish refunds kingdom stock, destroyed site loses reservation) → Task 2 `test_destroyed_site_refunds_stock`, Task 8 `test_cannot_demolish_villager_house`.
3. **Double or lost work** across load/unload → Task 7 `test_unload_deposits_carried`, Task 5 `test_offscreen_only_for_nodeless`.
4. **People stuck or walking through walls** → Task 6 `test_person_walks_around_obstacle`.
5. **Old saves crash** → Task 2 `test_loads_stage4_save`.

---

### Task 1: Constants and PersonGen

**Files:** Modify `scripts/core/game_constants.gd`; Create `scripts/people/person_gen.gd`; Test `tests/unit/test_person_gen.gd`

**Interfaces:**
- Constants: `enum Trait {WORKER, LAZY, BRAVE, FEARFUL, GENEROUS, GREEDY, SOCIABLE, LONER, DEVOUT, SKEPTIC}`, `TRAIT_PAIRS` (opposites), `TRAIT_NAMES` (male/female forms: `[“Trabalhador”, “Trabalhadora”]`), `enum Profession {WOODCUTTER, MASON, FARMER, GATHERER, BUILDER, MERCHANT}`, `PROFESSION_NAMES` (m/f), `MALE_NAMES`, `FEMALE_NAMES`, `SURNAMES`, `SKIN_COLORS`, `HAIR_COLORS`, `TUNIC_COLORS`, `TROUSER_COLORS`, `PERSON_HEIGHT := Vector2(0.92, 1.06)`, `PERSON_AGE := Vector2i(16, 60)`, `TRAIT_OPINION` (trait → initial opinion bias), `OPINION_JITTER := 0.2`, `FAME_OPINION_SHARE := 0.5`.
- `PersonGen` (static): `generate(rng, fame := 0.0, profession := -1) -> Dictionary` with keys `name, surname, female, age, traits (Array[int], 2, from different pairs), profession, looks {skin, hair, tunic, trousers: Color, height: float}, opinion`; `full_name(p) -> String`; `trait_name(p, t)`, `profession_name(p)`; `has_trait(p, t) -> bool`.

- [ ] Step 1: failing tests `test_generates_all_fields`, `test_traits_not_opposite`, `test_deterministic`, `test_names_from_lists`, `test_profession_forced`, `test_opinion_bias_from_traits_and_fame`, `test_female_forms`.
- [ ] Step 2–4: FAIL → implement → PASS. Step 5: commit `feat: gerador de pessoas`.

### Task 2: WorldState people, stock, owner, sites; BuildRules split

**Files:** Modify `scripts/world/world_state.gd`, `scripts/world/build_rules.gd`, `scripts/world/build_system.gd`, `scripts/core/game_constants.gd`; Test `tests/unit/test_people_state.gd`, `tests/unit/test_build_rules.gd` (+)

**Interfaces:**
- Constants: `Res.FOOD`, `RES_NAMES[FOOD] = "Comida"`, `Building.HOUSE, FARM, MARKET` (+ names, cost, footprint, colliders (farm: none), scenes, HP, destroyed messages), `BUILD_WORK_HOURS`, `HOUSE_CAPACITY := {HOUSE: 3, CABIN: 2}`, `KINGDOM_START_STOCK`, `SCAFFOLD_SCENE`.
- `WorldState`: `signal building_removed(rec)`; people `add_person(p: Dictionary, pos, kingdom_id := -1) -> Dictionary` (adds `id, pos, kingdom_id, home_id = -1, hunger = 0.0, contentment = PERSON_START_CONTENTMENT, status = "traveler", unhappy_hours = 0.0, job = "", carrying = {}, inside = -1, arrived_hour`), `remove_person(id)`, `person(id)`, `people_in(c)`, `all_people()`, `residents(kingdom_id)`, `move_person(id, pos)`; kingdom `kingdom(id)`, `stock_of(k, res)`, `add_stock(k, res, n)`, `spend_stock(k, cost) -> bool`; buildings `add_building(..., owner := -1)` and `add_site(type, pos, rot, kingdom_id, owner) -> Dictionary` (`site = true, progress = 0.0, reserved = cost, started_hour`), `finish_site(id)`; `remove_building(id)` emits `building_removed`, frees homes/insides, clears `kingdom.site_id`, refunds a site's `reserved` to stock; `fame`; `add_kingdom` adds `stock` (start stock), `next_traveler_hour = -1`, `site_id = -1`, `last_raid_hour = -1e9`, `people_ever = 0`; `_from_dict` fills defaults; save `people`, `next_person_id`, `fame`.
- `BuildRules.check_site(type, pos, rot, gen, scatter, state, blockers) -> Dictionary` (no cost); `check(...)` = `check_site` + player cost (same result shape as before).
- `BuildSystem.try_demolish` skips `owner >= 0` (message `BUILD_MSG_NOT_YOURS % owner name`) and sites.

- [ ] Step 1: failing tests `test_people_roundtrip`, `test_move_person_reindexes`, `test_stock_spend_and_add`, `test_kingdom_start_stock`, `test_site_lifecycle`, `test_destroyed_site_refunds_stock`, `test_removed_house_clears_home`, `test_loads_stage4_save`, `test_check_site_ignores_cost`, `test_people_block_site`.
- [ ] Steps 2–4; Step 5: commit `feat: estado das pessoas, estoque do reino e obras`.

### Task 3: Models (house, farm, market, scaffold) and library

**Files:** Modify `tools/blender/buildings.py`, `tools/build_models.ps1`, `scripts/world/model_library.gd`, `scripts/world/chunk.gd`; Test `tests/unit/test_building_models.gd` (+), `tests/integration/test_chunk_buildings.gd` (+)

**Interfaces:** `assets/models/{house,farm,market,scaffold}.glb` (footprints match constants; house door front −Y; farm low with crop rows and corner stakes); `ModelLibrary.person_scene() -> PackedScene` (humanoid, own materials untouched), `scaffold_scene()`; `Chunk.add_building` for sites: scaffold + the building model scaled in Y by `lerp(SITE_MIN_SCALE, 1, progress)`, collider only of the foundation; `Chunk.update_site(rec)`; farms get no collider.

- [ ] Step 1: failing tests `test_new_building_models_exist`, `test_new_footprints_match`, `test_site_shows_scaffold_and_grows`, `test_farm_has_no_collision`.
- [ ] Steps 2–4 (+ build models); Step 5: commit `feat: casa, fazenda, comércio e canteiro do Blender`.

### Task 4: VillageRules (pure)

**Files:** Create `scripts/people/village_rules.gd`; Test `tests/unit/test_village_rules.gd`

**Interfaces (static):**
- `snapshot(state, kingdom) -> Dictionary` `{residents, free_beds, has_campfire, food, food_days, recent_raid, has_well, has_market, has_storage, farms, site, stock}`.
- `stay_decision(person, snap, rng) -> {stay: bool, score: float, reason: String}` (founders: `kingdom.people_ever < KINGDOM_FOUNDERS` always stay; reason from the strongest factor, Portuguese, `STAY_REASONS` / `LEAVE_REASONS`).
- `hourly_contentment(person, snap, fed: bool) -> float` (delta), `leave_reason(person, snap) -> String`.
- `eat(person, kingdom, state) -> bool` (hunger ≥ 0.5 → spend 1 FOOD else 1 BERRIES, hunger −0.5).
- `next_project(snap) -> int` (Building or −1): farm first if `food_days < 2` and farms < ceil(residents/3); house if homeless; farm if production < consumption; market at ≥4; well at ≥3; storage if none.
- `pick_site(type, kingdom, state, gen, scatter, blockers, rng) -> Dictionary` (`{ok, pos, rot}`; spiral of `SITE_CANDIDATES`, `check_site`, `SITE_GAP` corridor, outside den territories, inside kingdom radius).
- `choose_job(person, snap) -> String` ("build" | "wood" | "stone" | "berries" | "farm" | "market" | "idle").
- `needed_profession(snap) -> int`.

- [ ] Step 1: failing tests `test_founders_always_stay`, `test_stays_with_food_and_shelter`, `test_leaves_without_shelter_reason`, `test_fearful_avoids_raided_kingdom`, `test_contentment_drops_hungry`, `test_eat_prefers_food`, `test_project_order`, `test_pick_site_valid_and_away_from_dens`, `test_choose_job_by_profession_and_stock`.
- [ ] Steps 2–4; Step 5: commit `feat: regras do povoado (ficar, necessidades, obras, trabalho)`.

### Task 5: VillageSim (hourly)

**Files:** Create `scripts/people/village_sim.gd`; Test `tests/unit/test_village_sim.gd`

**Interfaces:** `VillageSim extends Node`: `setup(state, gen, scatter, day_night)`; `has_node: Callable` (person id → bool, set by PeopleManager); `is_kingdom_loaded: Callable`; `tick_hours(h)` per kingdom: schedule/spawn travelers (record at 60–90 m, status traveler; nodeless travelers arrive next hour and decide), decide arrivals (`decide(person)` also used live), eat, contentment, leaving (record removed, message), fame, plan + open site (`add_site`, spend stock, message), offscreen work for nodeless residents (harvest real props near center via scatter + `mark_removed`, farm food, site progress), stalled sites; signals `message(text)` (loaded kingdoms), `pending_messages` (others), `site_opened(rec)`, `site_finished(rec)`, `person_left(rec)`, `traveler_spawned(rec)`.

- [ ] Step 1: failing tests `test_first_traveler_after_founding`, `test_traveler_interval_and_cap`, `test_new_kingdom_grows`, `test_hungry_people_leave_with_reason`, `test_opens_site_and_reserves_stock`, `test_offscreen_work_builds_site`, `test_offscreen_only_for_nodeless`, `test_offscreen_harvest_removes_props`, `test_messages_queued_when_unloaded`, `test_stalled_site_abandoned`.
- [ ] Steps 2–4; Step 5: commit `feat: simulação horária dos povoados`.

### Task 6: Person node and PersonBrain

**Files:** Create `scripts/people/person.gd`, `scripts/people/person_brain.gd`; Modify `scripts/core/game_constants.gd`; Test `tests/unit/test_person_brain.gd`, `tests/integration/test_person.gd`

**Interfaces:**
- `PersonBrain` (static, pure): `enum Act {IDLE, WALK, WORK, SLEEP, FLEE, ENTER, DEPOSIT, EVALUATE}`; `decide(me, ctx) -> {act, target_pos, target}` with `me`: `{pos, status, job, carrying, home_pos, door_pos, is_work_time, is_sleep_time, raid, threat_pos}`, `ctx`: `{work_target, deposit_pos, seat_pos, campfire_pos}`.
- `Person extends CharacterBody3D`: `setup(rec, library, manager)`, `record`, `act`, `walk_to`, model recolor (cached materials), animations `idle/walk/run/work`, `work_left`, `inside` (hidden), `sync_record()`; `manager.work_target(self)`, `manager.finish_work(self)`.

- [ ] Step 1: failing tests (brain) `test_sleeps_at_night_at_home`, `test_flees_threat`, `test_goes_home_during_raid`, `test_deposits_when_carrying`, `test_traveler_walks_to_seat_then_evaluates`; (node) `test_person_walks_to_target`, `test_person_walks_around_obstacle`, `test_person_colors_applied`.
- [ ] Steps 2–4; Step 5: commit `feat: pessoas andando, trabalhando e dormindo`.

### Task 7: PeopleManager (live work, sites, unload)

**Files:** Create `scripts/people/people_manager.gd`; Modify `scripts/creatures/creature.gd` (sense `person`), `scripts/creatures/creature_brain.gd`, `scripts/creatures/creature_manager.gd`, `scripts/creatures/pack_sim.gd` (sites not raid targets; `last_raid_hour`); Test `tests/integration/test_people_manager.gd`

**Interfaces:** `PeopleManager extends Node3D`: `setup(state, gen, scatter, streamer, library, day_night, sim, player)`; nodes for records in loaded chunks (cap, 2/frame); `work_target(person)` picks a real prop (wood/stone/berries, nearest to the person inside `VILLAGE_HARVEST_RADIUS` and not reserved by another), farm, site or market; `finish_work(person)`: removes prop (`mark_removed`, `chunk.remove_prop`), sets `carrying`, or adds farm food / site progress; deposit adds carrying to stock; finished site → `finish_site`, owner = first homeless, chunk refresh, message; unload/despawn deposits carrying; `active_people()`; signals `message`.

- [ ] Step 1: failing tests `test_spawns_people_in_loaded_chunks`, `test_woodcutter_cuts_real_tree_and_deposits`, `test_builders_finish_site`, `test_house_gets_owner_and_resident`, `test_unload_deposits_carried`, `test_people_sleep_inside_at_night`, `test_person_flees_wolf`, `test_herbivore_flees_person`, `test_sites_not_raided`, `test_frame_budget_people_and_creatures`.
- [ ] Steps 2–4; Step 5: commit `feat: gerenciador de pessoas, trabalho real e obras`.

### Task 8: Player interaction, HUD, World wiring

**Files:** Modify `scripts/actors/player.gd`, `scripts/ui/hud.gd`, `scripts/world/world.gd`, `scripts/world/build_system.gd`, `project.godot` (action `donate` G); Test `tests/integration/test_people_interaction.gd`, `tests/integration/test_world_persistence.gd` (+people)

**Interfaces:** Player `talk_target: Callable` (PeopleManager.nearest_person), E → `talked(person)` signal; `donate()` → `PeopleManager.donate(player_pos)` (≤ `DONATE_MAX` each of wood, stone, berries; opinion +`DONATE_OPINION` within `DONATE_RADIUS`); HUD `Village` label ("Moradores: N · Estoque: ...") inside a kingdom, `Card` panel for `PERSON_CARD_SEC`, prompt "[E] Falar com Ana"; creature killed by player during a raid inside the kingdom → opinion +; away decay; World creates `VillageSim`, `PeopleManager`, flushes village pending messages on return, `sync_all` before save.

- [ ] Step 1: failing tests `test_talk_shows_card`, `test_talk_has_priority_over_harvest`, `test_donate_moves_resources_and_raises_opinion`, `test_cannot_demolish_villager_house`, `test_village_line_in_hud`, `test_people_persist_across_save`, `test_protecting_raises_opinion`.
- [ ] Steps 2–4; Step 5: commit `feat: falar, doar, HUD do povoado; pessoas no mundo`.

### Task 9: Captures, docs, handoff

**Files:** Modify `tests/visual/capture.gd`, `CLAUDE.md`, `CONTINUAR.md`, `docs/ENTREGAS.md`

- [ ] Step 1: captures `18_traveler_arrives`, `19_village_working`, `20_site_rising`, `21_person_card`, `22_village_night`. Inspect each.
- [ ] Step 2: CLAUDE.md (folders `scripts/people/`, controls E/G, rule about villager buildings, roadmap ✅ 5); ENTREGAS.md; CONTINUAR.md (stage 6 next).
- [ ] Step 3: full suite PASS; commit `docs: capturas e entregas da etapa 5`.
