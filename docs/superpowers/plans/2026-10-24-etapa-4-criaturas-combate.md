# Etapa 4 — Criaturas e combate · Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Genome-driven creatures assembled from Blender parts with procedural animation, living in packs with motives (hunger, territory, grudge, cubs) that decide when they threaten the kingdom; keyboard-only player combat with visible sword/spear/bow; everything persists.

**Architecture:** Pure data/logic first (`Genome`, `PackMotives`, `CreatureBrain` decisions, `Combat`), then nodes (`CreatureBody`, `Creature`, `CreatureManager`, `PackSim`), then player combat and HUD. Creatures exist as records in `WorldState`; only those in loaded chunks have nodes.

**Tech Stack:** Godot 4.7 / GDScript, Blender 5.2 `bpy`.

**Spec:** `docs/superpowers/specs/2026-10-24-etapa-4-criaturas-combate-design.md` (sections 5–7 override earlier text)

## Global Constraints

- Keyboard only: Espaço ataca (para onde o personagem olha), 1/2/3 escolhem arma, Q troca, F faz 5 flechas com 1 madeira, H come 1 fruta (+15 vida). Sem mira automática.
- Raids only from motives (hunger, territory, grudge, cubs) × aggression; night only changes when packs act.
- `CREATURE_MAX_ACTIVE := 40`, `BRAIN_TICK := 0.2` s; creatures think only in loaded chunks.
- Creature visuals: parts from `tools/blender/creature_parts.py`, assembled at runtime, procedural idle/walk/run (documented exception to rule 5). Player weapons/clips from Blender.
- One loader (`ModelLibrary`). All numbers in `GameConstants`. In-game text Portuguese.

## Review Focus

1. **Raid with no motive** (well-fed, distant, no grudge pack attacks) → Task 5 `test_no_motive_no_raid`.
2. **Creature walking through walls/trees or floating/sinking** → Task 4 `test_creature_stays_on_ground`, `test_avoids_obstacle`.
3. **Population explosion from breeding** → Task 6 `test_population_cap`.
4. **Player death loop / losing items on death** → Task 7 `test_respawn_keeps_resources`.
5. **Creatures lost or duplicated across chunk unload/reload and save/load** → Task 6 `test_creatures_survive_chunk_reload`, Task 5 `test_creatures_roundtrip`.

---

### Task 1: Genome and species

**Files:** Create `scripts/creatures/genome.gd`; Modify `scripts/core/game_constants.gd`; Test `tests/unit/test_genome.gd`

**Interfaces:**
- Constants: `enum Body {CANINE, BULKY, LIZARD, DEER}`, `enum Head {WOLF, BEAR, BOAR, DEER, LIZARD, HORNED}`, `enum Legs {THIN, THICK, CLAWED}`, `enum Tail {BUSHY, STUB, LONG, SPIKED, NONE}`, `enum Extra {NONE, ANTLERS, HORNS, SPIKES, MANE}`, `enum Diet {HERBIVORE, CARNIVORE}`; `SPECIES` (id string → `{name, invented: bool, body, head, legs, tail, extra, size: Vector2, color_a: Color, color_b: Color, color_jitter: float, diet, aggression: Vector2, pack: Vector2i, speed: Vector2, hp: Vector2, damage: Vector2, perception: float, nocturnal: bool, territorial: bool, biomes: Dictionary(Biome→weight)}`) for `lobo, urso, javali, cervo, espinhudo, chifrudo, rastejante, uivante`; `MUTATION_CHANCE := 0.05`, `HYBRID_COMPATIBILITY := 0.3`.
- `Genome` (static, genome = Dictionary): `random(species: String, rng: RandomNumberGenerator) -> Dictionary` (keys: `species, lineage: PackedStringArray, body, head, legs, tail, extra, size, color_a, color_b, diet, aggression, pack, speed, max_hp, damage, perception, nocturnal, territorial, generation`); `cross(a: Dictionary, b: Dictionary, rng) -> Dictionary` (each gene from a or b; numeric genes may mutate ±15 %; part genes may mutate to a random part; `lineage` = union; `generation` = max+1); `compatibility(a, b) -> float` (1.0 same species; `HYBRID_COMPATIBILITY` if same diet and same body or overlapping lineage; else 0); `display_name(g) -> String` ("Lobo"; hybrids "Lobo-javali" from first two lineage names, capitalized first).

- [ ] **Step 1:** failing tests: `test_random_within_ranges`, `test_two_wolves_differ`, `test_cross_takes_parts_from_parents` (over 50 children every part equals a parent's or is a mutation; both parents contribute), `test_mutation_rate_reasonable`, `test_compatibility`, `test_hybrid_name`, `test_all_species_valid` (every species has all keys, ranges ordered).
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS. **Step 5:** commit `feat: genoma e espécies de criaturas`.

### Task 2: Blender creature parts

**Files:** Create `tools/blender/creature_parts.py`, `assets/models/parts/*.glb`; Modify `tools/build_models.ps1`, `scripts/world/model_library.gd`, `scripts/core/game_constants.gd`; Test `tests/unit/test_creature_parts.gd`

**Interfaces:**
- Parts (names = lowercase enum names): `body_<canine|bulky|lizard|deer>`, `head_<wolf|bear|boar|deer|lizard|horned>`, `leg_<thin|thick|clawed>`, `tail_<bushy|stub|long|spiked>`, `extra_<antlers|horns|spikes|mane>`. Materials named `primary`, `secondary`, `eye`, `horn` (recolored at runtime: primary=color_a, secondary=color_b).
- Conventions (Blender, front = −Y): body origin at torso center; head/tail/extra origin at their attachment point; leg origin at the hip, leg extends down to z = −1 (unit length, scaled per body).
- `GameConstants.BODY_SOCKETS[Body]` = `{head: Vector3, tail: Vector3, extra: Vector3, legs: [Vector3 ×4], leg_length: float}` (Godot axes, front +Z, size 1).
- `ModelLibrary.part_scene(name: String) -> PackedScene`; parts are queued after buildings.

- [ ] **Step 1:** failing tests: `test_all_parts_exist`, `test_leg_unit_length` (AABB min y ≈ −1, top ≈ 0), `test_parts_have_primary_material`, `test_library_parts`.
- [ ] **Step 2:** FAIL. **Step 3:** implement + build. **Step 4:** PASS. **Step 5:** commit `feat: peças de criaturas do Blender`.

### Task 3: CreatureBody (assembly + procedural animation)

**Files:** Create `scripts/creatures/creature_body.gd`; Test `tests/integration/test_creature_body.gd`

**Interfaces:** `CreatureBody extends Node3D`: `build(genome: Dictionary, library: ModelLibrary) -> void` (nodes `Body`, `Head`, `Tail`, `Extra`, `Leg0..3` as pivots; scale = genome.size; colors via duplicated ShaderMaterials); `standing_height() -> float` (body center above ground = leg_length × size); `animate(delta: float, speed_ratio: float) -> void` (0 idle breathing, 0–1 walk, >1 run: leg swing freq/amplitude, body bob, tail sway); `play_attack()`, `play_hurt()`, `play_death()`; `leg_angle(i: int) -> float` (for tests).

- [ ] **Step 1:** failing tests: `test_assembles_parts`, `test_colors_applied`, `test_feet_on_ground` (lowest leg point ≈ 0 ±0.05 at rest), `test_walk_swings_legs`, `test_size_scales_height`.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS. **Step 5:** commit `feat: corpo de criatura montado por peças com animação procedural`.

### Task 4: Health, Creature and brain

**Files:** Create `scripts/combat/health.gd`, `scripts/creatures/creature.gd`, `scripts/creatures/creature_brain.gd`; Modify `scripts/core/game_constants.gd` (`LAYER_CREATURES := 4`, brain constants), `scripts/actors/player.gd` (mask + creatures); Test `tests/unit/test_health.gd`, `tests/unit/test_creature_brain.gd`, `tests/integration/test_creature.gd`

**Interfaces:**
- `Health extends RefCounted`: `max_hp`, `hp`, signals `damaged(amount, source)`, `died(source)`; `damage(amount: float, source: Object = null) -> bool` (true if died), `heal(amount)`, `is_dead()`.
- `CreatureBrain extends RefCounted` (pure): `enum State {WANDER, GRAZE, HUNT, ATTACK, FLEE, SLEEP, FOLLOW, MATE, RAID, RETURN}`; `decide(me: Dictionary, ctx: Dictionary) -> Dictionary` → `{state, target_pos: Vector3, target_id: int}`. `me`: `{id, genome, pos, hp_ratio, hunger, is_night, pack_leader_pos, den_pos, wants_mate, raid_target}`; `ctx.nearby`: Array of `{id, kind ("creature"|"player"|"building"), pos, diet, species, is_cub}`.
- `Creature extends CharacterBody3D` (layer `LAYER_CREATURES`, mask terrain|obstacles|creatures): `setup(record: Dictionary, library, manager)`; `record` (live dictionary, see Task 5); `health: Health`; movement toward the brain's target with obstacle-avoid ray (`LAYER_OBSTACLES`), gravity, `CreatureBody` facing; melee bite with cooldown `CREATURE_ATTACK_COOLDOWN`.

- [ ] **Step 1:** failing tests: health (`test_damage_and_death`, `test_heal_caps`); brain (`test_herbivore_flees_carnivore`, `test_carnivore_hunts_herbivore_when_hungry`, `test_fed_carnivore_ignores_prey`, `test_attacks_in_range`, `test_nocturnal_sleeps_by_day`, `test_follows_leader`, `test_low_hp_flees`, `test_raid_targets_building`); creature (`test_creature_stays_on_ground`, `test_avoids_obstacle`, `test_wolf_kills_deer`).
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS. **Step 5:** commit `feat: criaturas com vida, cérebro e movimento`.

### Task 5: Packs, motives, persistence, PackSim

**Files:** Create `scripts/creatures/pack_motives.gd`, `scripts/creatures/pack_sim.gd`; Modify `scripts/world/world_state.gd`; Test `tests/unit/test_pack_motives.gd`, `tests/unit/test_creature_state.gd`

**Interfaces:**
- Constants: `TERRITORY_RADIUS := 45.0`, motive rates (`HUNGER_RATE`, `GRUDGE_PER_KILL`, `GRUDGE_DECAY_PER_DAY`, `CUB_ALARM_RADIUS`), `RAID_THRESHOLD := 0.6`, motive weights, `RAID_MESSAGES` (motive → Portuguese text with `%s` species plural + kingdom).
- `WorldState`: creatures `add_creature(genome, pos, pack_id, age := 1.0) -> Dictionary` (`{id, genome, pos, hp, age, pack_id}`), `remove_creature(id)`, `creature(id)`, `creatures_in(c)`, `all_creatures()`, `move_creature(id, pos)` (re-index chunk); packs `add_pack(species, den: Vector3) -> Dictionary` (`{id, species, den, hunger, territory, grudge, cubs_alarm, leader_id}`), `pack(id)`, `all_packs()`; `visited(c) -> bool`, `mark_visited(c)`; building hp `building_hp(id) -> float`, `damage_building(id, amount) -> bool` (destroyed; seat clamps at 1). All saved.
- `PackMotives` (static): `update(pack, ctx, hours: float) -> void` (ctx: `{prey_count, buildings_in_territory, kingdom_center, player_near_den, cubs}`); `raid_score(pack, aggression: float) -> float`; `dominant(pack) -> String` ("hunger"|"territory"|"grudge"|"cubs"); `wants_raid(pack, aggression) -> bool`.
- `PackSim extends Node`: `setup(state, day_night)`; each in-game hour updates all packs (prey counts from records within radius); emits `raid_started(pack, kingdom, motive)`; resolves raids on unloaded kingdoms summarily (`resolve_offscreen_raid(pack, kingdom) -> Array` of destroyed building names) and queues messages (`pending_messages`).

- [ ] **Step 1:** failing tests: `test_creatures_roundtrip`, `test_move_creature_reindexes`, `test_building_hp_and_seat_clamp`, `test_hunger_rises_and_prey_scarcity`, `test_grudge_from_kills_decays`, `test_territory_from_buildings`, `test_no_motive_no_raid`, `test_dominant_motive_message`, `test_offscreen_raid_damages_non_seat`.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS. **Step 5:** commit `feat: bandos com motivos, simulação de bandos e persistência`.

### Task 6: CreatureManager

**Files:** Create `scripts/creatures/creature_manager.gd`; Test `tests/integration/test_creature_manager.gd`

**Interfaces:** `CreatureManager extends Node3D`: `setup(state, gen, scatter, streamer, library, day_night, pack_sim, player)`; on `chunk_loaded`: first visit → spawn packs from `SPECIES.biomes` weights (deterministic rng by seed+chunk), then instantiate `Creature` nodes for records in chunk (cap `CREATURE_MAX_ACTIVE`); on `chunk_unloaded`: write back pos/hp and free nodes; `ensure_first_wolves(spawn: Vector3)`; brain context building; breeding (adults, compatibility, calm, cooldown, cap per area `POPULATION_CAP_PER_CHUNK`); aging (cubs grow to adult in `CUB_DAYS`); deaths (record removed, grudge to pack if killer is player); live raid: when `raid_started` and kingdom loaded → pack members get `raid_target` buildings; building damage through `state.damage_building`, chunk removal on destroy; signals `creature_killed(rec, by_player)`, `message(text)`.

- [ ] **Step 1:** failing tests: `test_spawns_on_first_visit_only`, `test_creatures_survive_chunk_reload`, `test_first_wolves_near_spawn`, `test_breeding_makes_cub_with_parent_parts`, `test_population_cap`, `test_kill_raises_grudge`, `test_live_raid_damages_building`, `test_active_cap_and_frame_budget`.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS. **Step 5:** commit `feat: gerenciador de criaturas, cruzamento e ataques ao reino`.

### Task 7: Weapons and player combat

**Files:** Create `tools/blender/weapons.py`, `assets/models/{sword,spear,bow,arrow}.glb`, `scripts/combat/combat.gd`, `scripts/combat/arrow.gd`; Modify `tools/blender/humanoid.py` (`hand.R` bone, clips `attack_sword`, `attack_spear`, `shoot_bow`), `tools/build_models.ps1`, `scripts/actors/player.gd`, `project.godot` (actions `attack` Space, `weapon_next` Q, `craft_arrows` F, `eat` H; rename `build_1..5` → `slot_1..5` used by both systems), `scripts/world/build_system.gd`, `scripts/core/game_constants.gd` (`enum Weapon {SWORD, SPEAR, BOW}`, `WEAPONS`, `Res.ARROWS`, player hp/regen/eat constants); Test `tests/unit/test_combat.gd`, `tests/integration/test_player_combat.gd`

**Interfaces:** `Combat.melee_targets(origin: Vector3, facing: Vector3, range: float, arc_deg: float, candidates: Array) -> Array`; `Arrow extends Node3D` (`launch(pos, dir, speed, damage, shooter)`, gravity, ray step against terrain|obstacles|creatures, hits `Creature.health`); `Player`: `health: Health`, `weapon: int`, `select_weapon(w)`, `next_weapon()`, `attack()` (cooldown, clip, damage at `hit_time` to `melee_targets` from the manager's active creatures / arrow for bow, needs arrows), `craft_arrows()`, `eat()`, signals `died`, `attacked`; regen after `PLAYER_REGEN_DELAY`; World respawns at seat/spawn on `died` keeping resources.

- [ ] **Step 1:** failing tests: `test_melee_arc_and_range`, `test_weapon_switch_keys`, `test_sword_damages_creature_in_front_only`, `test_spear_reaches_farther`, `test_bow_needs_arrows_and_arrow_falls`, `test_craft_arrows_costs_wood`, `test_eat_heals_and_costs_berry`, `test_regen_after_delay`, `test_respawn_keeps_resources`, `test_weapon_visible_in_hand`, `test_humanoid_has_attack_clips`.
- [ ] **Step 2:** FAIL. **Step 3:** implement + build models. **Step 4:** PASS. **Step 5:** commit `feat: armas medievais e combate por teclado`.

### Task 8: HUD and World wiring

**Files:** Modify `scripts/ui/hud.gd`, `scripts/world/world.gd`; Test `tests/integration/test_hud_combat.gd`, `tests/integration/test_world_persistence.gd` (+creatures/packs)

**Interfaces:** HUD labels `Health` ("Vida: 80/100"), `Weapon` ("Espada · Q troca · Flechas: 12"), `Messages` (last 4 messages, 8 s each: raids with motive, destroyed buildings, deaths, offscreen raid summaries on return); `Hint` gains "Espaço ataca · H come". World creates `PackSim`, `CreatureManager`, calls `ensure_first_wolves` on new worlds, wires player death → respawn, flushes `pending_messages` when the kingdom is loaded.

- [ ] **Step 1:** failing tests: `test_health_and_weapon_labels`, `test_raid_message_with_motive`, `test_offscreen_raid_message_on_return`, `test_creatures_and_packs_persist_across_save`.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS. **Step 5:** commit `feat: HUD de combate e mensagens; criaturas no mundo`.

### Task 9: Captures, docs, handoff

**Files:** Modify `tests/visual/capture.gd`, `CLAUDE.md`, `CONTINUAR.md`; Create `docs/ENTREGAS.md`

- [ ] **Step 1:** captures: first wolf pack near spawn; gallery of the 8 species in a cleared area; a hybrid next to its parents; sword swing and arrow in flight; a motive raid at night on the village with the HUD message. Inspect each.
- [ ] **Step 2:** CLAUDE.md (controls, rule-5 exception for creatures, roadmap ✅ 4); ENTREGAS.md (stages 1–4 summary); CONTINUAR.md (stage 5 next).
- [ ] **Step 3:** full suite PASS; commit `docs: capturas e entregas da etapa 4`.
