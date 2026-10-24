# Etapa 6 — Sociedade · Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Residents form families with procedurally drawn crests, make friends and rivals, marry, have children who grow up, break away to found their own houses, and each person/family drifts into being the player's ally or enemy — loaded or not.

**Architecture:** Pure first (`Crest`, `SocietyRules`, `PersonGen.child`), then state (`WorldState` families/relations/person defaults), then the hourly `SocietySim` (RefCounted, driven by `VillageSim`), then the world side (crest banner model, `Chunk.set_crest`, `PeopleManager` banners/births/child scale), then HUD (card with crest, families panel on C) and wiring.

**Tech Stack:** Godot 4.7 / GDScript, Blender 5.2 `bpy`.

**Spec:** `docs/superpowers/specs/2026-10-24-etapa-6-sociedade-design.md` (section 5 "Decisões após a revisão" overrides earlier text)

## Global Constraints

- 1 game hour = 20 s, 1 day = 8 min. All numbers in `GameConstants`. In-game text Portuguese, code English.
- Everything social is record logic run hourly by `VillageSim` for every kingdom (no node needed); randomness seeded by `hash([state.seed, <tag>, k.id, int(hour)])`.
- `HOUSE_CAPACITY[HOUSE] := 4`, `KINGDOM_MAX_PEOPLE := 16`, `ADULT_AGE := 16`, `CHILD_YEARS_PER_DAY := 2.0`, `ADULT_YEARS_PER_DAY := 0.25`, `OLD_AGE := 70`.
- Thresholds: `FRIEND_AT := 0.35`, `RIVAL_AT := -0.35`, `COUPLE_AT := 0.6`, `ALLY_AT := 0.5` (exit 0.4), `ENEMY_AT := -0.4` (exit -0.3), `SPLIT_RIVAL_AT := -0.5`.
- Crest image 32 × 40 px, nearest filter, transparent outside the shield; never two equal crests in one kingdom.
- One loader (`ModelLibrary`); the banner keeps its own materials (not the occlusion shader).
- Keyboard only: E card, C families panel (new action `families`, physical key 67).
- Old saves (stage 5) load; residents without a family get one in the first hour.
- Design §5 (25 decisions after the builder check) is binding, notably: births only below `KINGDOM_BIRTH_CAP := 14`; per-day chances converted per hour `1-(1-p)^(1/24)`; `tick_hours(n)` gives SocietySim each simulated hour; `person_died` emitted before removal; `widowed` flag; house owner passes to the oldest adult occupant (else `OWNER_KINGDOM`); `THEFT_MAX_PER_DAY := 2`; gifts only wood/stone; thefts only wood/stone/berries; `FAMILY_SPLIT_COOLDOWN_DAYS := 3`; `profession_name` of -1 = "criança".

## Review Focus

1. **A family that never dies / a ghost family** (all members left, died or split; head gone) → Task 4 `test_empty_family_dissolves`, `test_head_passes_to_oldest`.
2. **Births overflowing houses or the kingdom** → Task 5 `test_no_birth_without_bed_or_at_cap`.
3. **Event spam / repeated events after reload** (stances flickering, gifts every hour) → Task 6 `test_stance_hysteresis`, `test_deeds_once_per_day`.
4. **Dangling ids** (spouse/parents/relations of removed people, banner of a removed house) → Task 2 `test_remove_person_cleans_links`, Task 7 `test_banner_follows_owner_family`.
5. **Children doing adult things** (working, leaving alone, marrying, stances) → Task 5 `test_children_do_not_work_or_marry`, Task 4 `test_leaver_takes_family`.

---

### Task 1: Constants and Crest

**Files:** Modify `scripts/core/game_constants.gd`; Create `scripts/people/crest.gd`; Test `tests/unit/test_crest.gd`

**Interfaces:**
- Constants: `enum CrestPattern {PLAIN, PALE, FESS, BEND, QUARTERLY, CHEVRON}`, `enum CrestCharge {NONE, ROUNDEL, CROSS, LOZENGE, STAR, CRESCENT}`, `TINCTURES` (Array of `[name_pt, Color, is_metal]`: ouro, prata, vermelho, azul, verde, preto, púrpura), `CREST_SIZE := Vector2i(32, 40)`, `CREST_PATTERN_NAMES`, `CREST_CHARGE_NAMES` (Portuguese with article: "uma estrela"), `CREST_TRIES := 40`, `CREST_BORDER := Color(0.12, 0.1, 0.08)`.
- `Crest` (static): `generate(rng, avoid: Array) -> Dictionary` `{pattern, field, second, charge, charge_tincture}` (field/second: one metal, one colour; PLAIN has second = field; charge tincture contrasts with the field at the centre); `derive(parent, rng, avoid) -> Dictionary` (same pattern/field/second, different charge or charge tincture); `rival(parent, rng, avoid)` (new crest keeping one tincture of the parent); `key(c) -> String`; `same(a, b) -> bool`; `color_at(c, u, v) -> Color` (u, v in 0..1; alpha 0 outside the shield); `image(c) -> Image`; `texture(c) -> ImageTexture` (cached by key); `material(c) -> StandardMaterial3D` (cached; nearest, alpha scissor, cull disabled); `describe(c) -> String`.

- [ ] Step 1: failing tests `test_generate_deterministic`, `test_metal_on_colour`, `test_avoids_existing`, `test_derive_changes_only_charge`, `test_rival_keeps_one_tincture`, `test_image_colours_and_mask` (PALE: pixel left-centre = field colour, right-centre = second; corner below the point transparent), `test_charge_drawn_at_centre`, `test_describe_portuguese` (contains tincture names and "partido" for PALE), `test_texture_cached`.
- [ ] Step 2: run `tools/run_tests.ps1 test_crest` → FAIL (Crest missing). Step 3: implement. Step 4: PASS.
- [ ] Step 5: commit `feat: brasões gerados por código`.

### Task 2: WorldState families, relations, person defaults

**Files:** Modify `scripts/world/world_state.gd`, `scripts/core/game_constants.gd`; Test `tests/unit/test_families_state.gd`

**Interfaces:**
- `WorldState.person_defaults(p)` (static) fills `family_id = -1, spouse_id = -1, parents = [], stance = "", last_birth_hour = -1e9, talk_day = -1, deed_day = -1`; called by `add_person` and `_from_dict`.
- Families: `add_family(surname: String, crest: Dictionary, kingdom_id: int, head_id: int, hour: float, parent_id := -1, origin := "founded") -> Dictionary` (`stance = ""`), `family(id)`, `families_of(kingdom_id) -> Array[Dictionary]`, `all_families()`, `family_members(id) -> Array[Dictionary]` (residents with that `family_id`, status "resident"), `remove_family(id)`.
- Relations: `relation(a, b) -> float` (0 if none), `set_relation(a, b, v)` (clamped −1..1), `add_relation(a, b, d)`, `relations_of(id) -> Dictionary` (other id → value).
- `remove_person(id)` also erases its relations and clears `spouse_id` of the spouse.
- Save: `families`, `next_family_id`, `relations` as `[[a, b, v], ...]`.

- [ ] Step 1: failing tests `test_family_roundtrip`, `test_relation_symmetric_and_clamped`, `test_remove_person_cleans_links`, `test_family_members_only_residents`, `test_loads_stage5_save` (dict without the new keys → defaults, no crash).
- [ ] Steps 2–4. Step 5: commit `feat: famílias e relações no estado do mundo`.

### Task 3: SocietyRules and PersonGen.child

**Files:** Create `scripts/people/society_rules.gd`; Modify `scripts/people/person_gen.gd`, `scripts/core/game_constants.gd`; Test `tests/unit/test_society_rules.gd`

**Interfaces (static, pure):**
- `SocietyRules.is_adult(p) -> bool` (age ≥ `ADULT_AGE`); `is_kin(a, b) -> bool` (parent/child or sharing a parent); `meeting_delta(a, b, close: bool, rng) -> float` (spec numbers: base 0.02, same trait +0.04, opposite −0.06, sociable +0.02 each, loner −0.02 each, close +0.02, noise ±0.03); `can_marry(a, b, rel: float) -> bool` (both adult ≥ `MARRY_MIN_AGE` 18, unmarried, not kin, gap ≤ 15, rel ≥ `COUPLE_AT`); `birth_mother(a, b) -> Dictionary` (the female partner aged 18..45 or {}); `opinion_drift(p, family_mean: float, ties: Array) -> float` (ties = `[[relation, other_opinion], ...]`; spec numbers); `stance_for(opinion, current: String) -> String` ("ally" / "enemy" / "" with hysteresis); `family_stance(members, current) -> String` (mean of adults); `label(rel) -> String` ("friend" / "rival" / "").
- `PersonGen.child(mother, father, surname: String, rng) -> Dictionary` (age 0, profession −1, one trait from each parent from different pairs, skin/hair from a random parent, height = parents' mean ± 0.03, opinion = parents' mean).
- Constants for every number above (spec §4 table) plus `MARRY_MIN_AGE := 18`, `BIRTH_AGE := Vector2i(18, 45)`.

- [ ] Step 1: failing tests `test_same_traits_attract_opposites_repel`, `test_kin_cannot_marry`, `test_marry_needs_adults_and_love`, `test_birth_mother`, `test_stance_hysteresis`, `test_opinion_drift_parts`, `test_child_inherits`.
- [ ] Steps 2–4. Step 5: commit `feat: regras da sociedade e filhos`.

### Task 4: SocietySim — families, couples, homes, leaving

**Files:** Create `scripts/people/society_sim.gd`; Modify `scripts/people/village_sim.gd`, `scripts/people/village_rules.gd`, `scripts/core/game_constants.gd`; Test `tests/unit/test_society_sim.gd`

**Interfaces:**
- `SocietySim extends RefCounted`: `setup(state, say: Callable(k, text), now: Callable() -> float, is_player_in: Callable(k) -> bool)`; `tick_hour(k)`; signals `families_changed`, `person_born(rec)`, `person_died(rec)`. Order inside `tick_hour`: `_ensure_families`, `_age` (Task 5), `_meetings`, `_marriages`, `_reunite`, `_births` (Task 5), `_splits` (Task 5), `_cleanup_families`, `_opinions` / `_stances` / `_deeds` (Task 6).
- `_ensure_families`: resident without family → joins a kingdom family with the same surname (`origin` kin message `SOCIETY_MSG_KIN`) or founds one (`Crest.generate`, avoid the kingdom's crests; silent).
- Marriage: spouse joins the larger family (tie: lower id); a family left empty dissolves with `SOCIETY_MSG_MERGED` ("A Casa %s uniu-se à Casa %s"); `SOCIETY_MSG_MARRIED`.
- `_reunite`: a married pair with different homes moves into the home with room (spouse's first), else both into a house with 2 free beds.
- `VillageSim`: owns `society: SocietySim`, calls `society.tick_hour(k)` after `_needs`; re-emits its signals as `person_born`, `person_died`, `families_changed`; `_assign_homes` places a homeless person first in the spouse's home, then a family member's, then any; `_leave` takes spouse and minor children (`VILLAGE_MSG_LEFT_FAMILY`), children never leave alone (skip their unhappy check).
- `VillageRules.stay_decision` adds `kin` (+0.1, `STAY_REASONS.kin = "tem parentes no reino"`) when `snap.surnames` has the traveler's surname; `snapshot` adds `surnames` (family surnames of the kingdom) and `families`.
- Head: when the head is not a resident member any more, the oldest adult member (silent).

- [ ] Step 1: failing tests `test_newcomer_founds_family_with_crest`, `test_newcomer_joins_kin`, `test_couple_forms_and_moves_in`, `test_empty_family_dissolves`, `test_head_passes_to_oldest`, `test_leaver_takes_family`, `test_kin_helps_stay`.
- [ ] Steps 2–4 (`tools/run_tests.ps1 society village`). Step 5: commit `feat: famílias, casamentos e lares`.

### Task 5: SocietySim — children, growing up, old age, splits

**Files:** Modify `scripts/people/society_sim.gd`, `scripts/people/village_rules.gd` (`choose_job` → `"child"`), `scripts/core/game_constants.gd` (`JOB_TEXTS.child = "brincando"`); Test `tests/unit/test_society_life.gd`

**Interfaces:**
- `_births`: couple at the same home, `birth_mother` exists, both contentment ≥ 0.5, `food_days` ≥ 2, home with a free bed, mother's `last_birth_hour` ≥ 72 h ago, residents < `KINGDOM_MAX_PEOPLE`, chance `BIRTH_CHANCE_PER_DAY / 24` per hour → `state.add_person(PersonGen.child(...), door pos, k.id, now)` with status "resident", `home_id`, `family_id`, `parents`; message `SOCIETY_MSG_BORN` ("Nasceu %s, %s de %s e %s"); `person_born`.
- `_age`: hourly `age += rate / 24`; crossing `ADULT_AGE` → `profession = VillageRules.needed_profession(snap)`, `SOCIETY_MSG_GREW`; ≥ `OLD_AGE` → chance `DEATH_CHANCE_PER_DAY / 24` → `SOCIETY_MSG_DIED`, `person_died`, record removed (or `status = "dead"` when it has a node: PeopleManager frees it).
- Splits: adult non-head member with `relation(member, head) ≤ SPLIT_RIVAL_AT` → rival split (`Crest.rival`, new surname, `SOCIETY_MSG_BROKE`, relation −0.2 with old members); family size > `FAMILY_BRANCH_SIZE` (5) and a married non-head adult whose home differs from the head's → chance `BRANCH_CHANCE_PER_DAY / 24` → branch (`Crest.derive`, `SOCIETY_MSG_BRANCH`). Leaver takes spouse and minor children; leaver and children take the new surname (from `SURNAMES` not used by the kingdom's families; fallback `"%s de %s"`).
- Children: `choose_job` returns `"child"`, never in meetings with non-family, never marry, no stance.

- [ ] Step 1: failing tests `test_couple_has_child`, `test_no_birth_without_bed_or_at_cap`, `test_child_grows_and_gets_trade`, `test_old_person_dies_and_spouse_widowed`, `test_rival_of_head_breaks_away`, `test_big_family_branches`, `test_children_do_not_work_or_marry`.
- [ ] Steps 2–4. Step 5: commit `feat: filhos, crescer, velhice e rupturas de família`.

### Task 6: SocietySim — opinion, stances, gifts and thefts; stage-5 minors

**Files:** Modify `scripts/people/society_sim.gd`, `scripts/people/village_sim.gd`, `scripts/people/people_manager.gd`, `scripts/core/game_constants.gd`; Test `tests/unit/test_society_opinion.gd`

**Interfaces:**
- `_opinions`: each resident `opinion += SocietyRules.opinion_drift(...)` (clamped).
- `_stances`: adults' `stance` via `stance_for` (messages `SOCIETY_MSG_ALLY` / `SOCIETY_MSG_ENEMY` on entering, silent on leaving); family `stance` via `family_stance` (`SOCIETY_MSG_FAMILY_ALLY` / `SOCIETY_MSG_FAMILY_ENEMY`).
- `_deeds` at hour of day `DEED_HOUR` (10) with `is_player_in(k)`: each ally family once per day (`deed_day` on the family) gives `GIFT_AMOUNT` (3) of the stock's largest resource if it has ≥ `GIFT_MIN_STOCK` (10) → player inventory (`SOCIETY_MSG_GIFT`); each enemy adult once per day steals `THEFT_AMOUNT` (2) of the player's largest resource → kingdom stock (`SOCIETY_MSG_THEFT`).
- `PeopleManager.talked_to(rec)`: once per game day per person, opinion + `TALK_OPINION` (sociable 0.03, loner −0.02, else 0.01).
- `PeopleManager.donate`: opinion gain × `min(1, total / DONATE_FULL_AT)` (`DONATE_FULL_AT := 10`).
- `VillageSim`: `pending_messages` capped at `VILLAGE_NEWS_MAX := 40` (oldest dropped, counted in `dropped_news` and added to the "mais N coisas" count); `VILLAGE_MSG_APPROACH` ("Um viajante se aproxima do Reino de %s") when a traveler spawns.

- [ ] Step 1: failing tests `test_content_people_warm_up`, `test_family_pulls_opinion`, `test_stance_messages_once`, `test_family_stance`, `test_ally_family_gives_gift`, `test_enemy_steals_only_with_player`, `test_deeds_once_per_day`, `test_talk_opinion_once_a_day`, `test_donation_scaled`, `test_news_capped`, `test_traveler_approach_message`.
- [ ] Steps 2–4 (`tools/run_tests.ps1 society village people`). Step 5: commit `feat: opinião, aliados e inimigos no reino`.

### Task 7: Crest banner, chunk crests, child nodes

**Files:** Modify `tools/blender/buildings.py`, `tools/build_models.ps1`, `scripts/world/model_library.gd`, `scripts/world/chunk.gd`, `scripts/people/people_manager.gd`, `scripts/people/person.gd`, `scripts/core/game_constants.gd`; Test `tests/unit/test_building_models.gd` (+), `tests/integration/test_society_world.gd`

**Interfaces:**
- `assets/models/crest_banner.glb` (pole ≈ 2.2 m, crossbar, shield-shaped cloth with UV 0..1 and material `crest`); `CREST_BANNER_SCENE`; `CREST_BANNER_OFFSET` (local position beside the door: right of the front wall).
- `ModelLibrary.crest_scene()` (kind "crest", own materials).
- `Chunk.set_crest(building_id: int, crest: Dictionary)` — `{}` removes; child node `"Crest"` of the building node; survives `update_site` rebuilds through the manager re-applying.
- `PeopleManager`: `refresh_crests()` for every loaded house with owner ≥ 0 (owner's family crest); called on `chunk_loaded`, `site_finished`, `families_changed`, `building_removed`; `person_born` → `_fill()`; `person_died` frees the node.
- `Person`: model scale = `looks.height × lerp(CHILD_MIN_SCALE 0.55, 1, min(age/ADULT_AGE, 1))`, updated in `_think`; `PeopleManager.person_context` sets a child's `seat_pos` to its home door when it has one.

- [ ] Step 1: failing tests `test_crest_banner_model` (mesh with a `crest` surface with UVs), `test_banner_on_owned_house`, `test_banner_follows_owner_family`, `test_child_node_smaller`, `test_birth_spawns_node`.
- [ ] Step 2–4 (+ `tools/build_models.ps1`). Step 5: commit `feat: estandartes com brasão nas casas e crianças no mundo`.

### Task 8: HUD card, families panel, wiring

**Files:** Modify `scripts/ui/hud.gd`, `scripts/people/people_manager.gd` (`card_text`), `scripts/world/world.gd`, `project.godot` (action `families`, C), `scripts/core/game_constants.gd`; Test `tests/integration/test_hud_society.gd`

**Interfaces:**
- `PeopleManager.card_text(rec, state)` adds: `"Casa %s"` line, spouse (`"Casado com %s"` / `"Casada com %s"` / `"Viúvo"`), parents or children (`"Filhos: Inês (5), Rui (2)"`), best friend and worst rival, stance suffix on the opinion line (`" — seu aliado"` / `" — sua inimiga"`, gendered), and `"Brasão: <describe>"`.
- `Hud`: card panel = `HBox` [`TextureRect` "Crest" (scaled ×3, nearest), Label]; `show_card` sets the crest texture (hidden without family); `toggle_families()`, `families_visible()`, `families_text()`; panel "Families" with title `"Famílias do Reino de %s"` and one row per family (crest + `"Casa X · N pessoas · chefe: Ana · aliada"` + `" · rival da Casa Y"` when the mean cross relation ≤ `RIVAL_AT`); hidden outside a kingdom; `_unhandled_input` handles action `families`. Village line: `"Moradores: %d · Famílias: %d · Estoque: %s"`. Hint adds `"C famílias"`.
- `World`: `_player.talked` → `_people.talked_to`; HUD gets state for families.

- [ ] Step 1: failing tests `test_card_shows_family_and_relations`, `test_card_crest_texture`, `test_families_panel_toggle`, `test_families_panel_rows`, `test_village_line_has_families`, `test_family_key_action_exists`.
- [ ] Steps 2–4 (`tools/run_tests.ps1 hud people`). Step 5: full suite; commit `feat: cartão com família e brasão, painel de famílias (C)`.

### Task 9: Captures

**Files:** Modify `tests/visual/capture.gd`

- [ ] Step 1: `_society()` after `_people()`: build a family scene (couple + 2 children, houses with owners from 3 families), shots `23_family_card`, `24_couple_children`, `25_house_crests`, `26_families_panel`, `27_family_split` (force a rival split by setting the relation, tick one hour; shot of the new crest house + HUD message), `28_allies_enemies` (force opinions, tick to `DEED_HOUR`; HUD messages gift + theft).
- [ ] Step 2: `tools/capture.ps1`; open each new PNG; fix what looks wrong. Step 3: commit `test: capturas da etapa 6`.
