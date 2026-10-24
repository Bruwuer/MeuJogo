# Etapa 7 — Casas e ambições · Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Families become Houses with tradition, values, wealth, land, skill, house level, prestige and goals; people get vocations and desires that can clash with their House and lead to departures (friendly/neutral/hostile, open/secret); arranged marriages, unions, corruption, infiltration, adoption and guards.

**Architecture:** Pure rules (`Kinship`, `HouseRules`) + one hourly `HouseSim` called by `VillageSim` after `SocietySim`. New visuals only where needed (house levels, plot stakes, guards). Chronicle log in `WorldState`.

**Tech Stack:** Godot 4.7 / GDScript, Blender 5.2.

**Spec:** `docs/superpowers/specs/2026-10-24-etapa-7-casas-ambicoes-design.md`

## Global Constraints
- Keyboard only (new key K = crônica). In-game text Portuguese. Numbers in `GameConstants`.
- Determinism: RNG seeded by (world seed, tag, kingdom, hour); no per-frame cost (hourly/daily rules).
- Enum values are appended (never reordered) so stage-6 saves load; missing fields get coherent defaults.
- Secrets are private until discovered; UI shows only public facts.

## Review Focus
1. Incoherent goals (rich House "gathering wealth", childless House arranging a marriage) → Task 3 `test_goals_are_coherent`.
2. A departed/secret runaway still counted in the House or still sleeping at home → Task 4 `test_runaway_leaves_house_and_bed`.
3. Wealth/land growing without bound or going negative → Task 5 `test_wealth_never_negative`, `test_plot_limit`.
4. Infiltrator/marriage loops (marrying a sibling/cousin, spy of own House) → Task 6 `test_no_kin_marriage`, `test_spy_targets_rival_only`.
5. Stage-6 save without new fields → Task 1 `test_stage6_save_defaults`.

---

### Task 1: Constants, Kinship, state defaults, chronicle
**Files:** Modify `scripts/core/game_constants.gd`, `scripts/world/world_state.gd`; Create `scripts/people/kinship.gd`; Test `tests/unit/test_kinship.gd`, `tests/unit/test_house_state.gd`
- Constants: `enum Tradition {WARRIORS, FARMERS, MERCHANTS, BUILDERS, FOREST}`, `TRADITION_NAMES`, `TRADITION_PROFESSIONS`, `TRADITION_VALUES` (per tradition: `{wealth, land, prestige, faith, honor}`), `Profession.GUARD` appended + names; `enum Goal {LAND, UPGRADE, ALLIANCE, SURPASS, REVENGE, WEALTH, HEIR, UNION}` + Portuguese texts; `enum Desire {LOVE, RICH, PROTECT, LEAVE, SURPASS_PARENT, NONE}` + texts; prices/limits (`PLOT_SIZE := 8.0`, `PLOT_PRICE`, `PLOTS_MAX_PER_MEMBER`, `UPGRADE_PRICE`, `HOUSE_LEVEL_CAPACITY := [4, 6, 8]`, `DOWRY`, `BRIBE`), `CHRONICLE_MAX := 200`.
- `Kinship` (static): `parents_of(state, p)`, `children_of`, `siblings_of`, `grandparents_of`, `uncles_of`, `cousins_of`, `relation_word(state, a, b) -> String` ("pai", "mãe", "filho", "irmã", "tio", "prima", "avô", "neto", "cônjuge", ""), `is_close_kin(state, a, b) -> bool` (up to first cousins).
- `WorldState`: family defaults (`tradition`, `values`, `wealth`, `plots`, `skill`, `house_level` on house buildings, `prestige`, `goal`, `rival_id`, `known_secrets`), person defaults (`vocation`, `desire`, `resentment`, `secret`, `adopted_by`), `chronicle_add(hour, text, kingdom_id, public := true)`, `chronicle(kingdom_id, n) -> Array`.
- Tests: kinship words for a 3-generation tree (incl. cousins/uncles, adoption by a couple), `test_stage6_save_defaults`, chronicle limit.
- Commit `feat: parentesco, dados das Casas e crônica`.

### Task 2: HouseRules A — tradition, vocation, conflict, departure, economy
**Files:** Create `scripts/people/house_rules.gd`; Test `tests/unit/test_house_rules.gd`
- `tradition_for(head: Dictionary, rng) -> int` (from the head's profession, nudged by traits); `values_for(tradition, rng) -> Dictionary`; `expected_professions(family) -> Array`; `vocation_for(child, family, rng) -> int` (tradition ~55 %, traits, random); `conflicts(person, family) -> bool`; `conflict_outcome(person, family, relation_with_head, rng) -> String` ("conform" | "negotiate" | "leave"); `departure_style(person, family, relation_with_head, rng) -> Dictionary {tone: "friendly"|"neutral"|"hostile", secret: bool}`; `work_wealth(profession, skill_hours) -> float`; `skill_bonus(skill_hours) -> float` (0..`SKILL_MAX_BONUS`); `upgrade_price(level) -> int`; `capacity(level) -> int`.
- Tests: vocation distribution, conflict only when vocation ∉ expected, departure tones follow relation/traits, secret more likely for fearful/hostile, bonus monotonic and capped.
- Commit `feat: regras de tradição, vocação, desligamento e economia das Casas`.

### Task 3: HouseRules B — goals, marriages, corruption, infiltration
**Files:** Modify `scripts/people/house_rules.gd`; Test `tests/unit/test_house_goals.gd`
- `goal_scores(family, ctx) -> Dictionary` (ctx: members, adults, land, wealth, house_level, rival, allies, heirs, unmarried adults, other families) and `pick_goal(family, ctx, rng) -> Dictionary {kind, target_id}` — zero score for incoherent goals; `goal_done(family, goal, ctx) -> bool`; `arranged_match(family, candidates, state) -> Dictionary` (no close kin, adults, useful partner House); `arranged_response(person, partner, rel, rng) -> String` ("accept" | "resist" | "flee"); `corruption_chance(family, head)`, `discovery_chance(kingdom_ctx)`; `spy_candidate(family, rival, state)`.
- Tests: `test_goals_are_coherent`, `test_goal_changes_with_situation`, `test_no_kin_marriage`, arranged response vs love, corruption only greedy, `test_spy_targets_rival_only`.
- Commit `feat: objetivos, casamentos arranjados, corrupção e infiltração (regras)`.

### Task 4: HouseSim A — economy, vocations, departures, adoption
**Files:** Create `scripts/people/house_sim.gd`; Modify `scripts/people/village_sim.gd` (call after society); Test `tests/unit/test_house_sim_people.gd`
- Hourly: wealth + skill from working members (offscreen and live), prestige recompute; on coming of age: vocation, conflict resolution over days (resentment), departures (friendly → wealth gift + new House; neutral; hostile → rivals; secret → leaves at night, House learns next day "fugiu"); adoption of orphans by childless couples or well-off singles; chronicle + HUD messages.
- Tests: `test_wealth_grows_with_work`, `test_skill_passes_to_children_in_trade`, `test_conflict_leads_to_departure_styles`, `test_runaway_leaves_house_and_bed`, `test_secret_discovered_next_day`, `test_orphan_adopted`, `test_wealth_never_negative`.
- Commit `feat: economia das Casas, vocações e desligamentos`.

### Task 5: HouseSim B — land, upgrades, goals lifecycle
**Files:** Modify `scripts/people/house_sim.gd`, `scripts/core/game_constants.gd` (`Building.STAKE`); Test `tests/unit/test_house_sim_land.gd`
- Plots: valid 8×8 grid rect in territory, not over buildings/large props/other plots; claim (pay `PLOT_PRICE`) or buy from a poorer House; stored as `family.plots` and four STAKE building records (owner family, color); farmers' farms prefer own plots. Upgrades: pay price → `house_level` +1 on the family house (site with scaffold reused). Goals: pick/keep/expire daily; success → prestige/contentment, failure → "quebra de expectativa" event and resentment.
- Tests: `test_plot_valid_and_paid`, `test_plot_limit`, `test_buy_plot_from_poor_house`, `test_upgrade_raises_level_and_capacity`, `test_goal_success_and_failure_events`.
- Commit `feat: terras, melhoria de casa e objetivos das Casas`.

### Task 6: HouseSim C — arranged marriages, unions, corruption, infiltration
**Files:** Modify `scripts/people/house_sim.gd`; Test `tests/unit/test_house_sim_intrigue.gd`
- Arranged marriages (dowry; accept/resist/flee with lover, secret marriage, unhappy marriage → quarrels/separation), secret same-sex romances (frowned upon by medieval custom: never marriage or children; discovery → House scandal and family pressure → conform or leave), union of Houses (small heirless ally absorbed: members, plots, wealth), corruption (skim from kingdom stock to House wealth; discovery → scandal: prestige −, relations −, chronicle + HUD), infiltration (spy planted via arranged marriage or as household member; spying boosts own goal vs rival, sabotage sets rival progress back/steals wealth; discovery → feud, spy expelled).
- Tests: `test_arranged_marriage_dowry_and_alliance`, `test_flee_with_lover`, `test_unhappy_marriage_separates`, `test_union_merges_houses`, `test_corruption_scandal`, `test_infiltration_and_discovery`.
- Commit `feat: intrigas das Casas`.

### Task 7: Models — house levels and stakes
**Files:** Modify `tools/blender/buildings.py` (`house_stone`, `manor`, `stake`), `tools/build_models.ps1`, `scripts/world/model_library.gd`/`chunk.gd` (scene by `house_level`, stake recolor); Test `tests/unit/test_house_models.gd`, `tests/integration/test_chunk_houses.gd`
- Commit `feat: casa de pedra, solar e estacas de lote`.

### Task 8: Guards
**Files:** Modify `scripts/people/person_brain.gd`, `scripts/people/person.gd`, `scripts/people/village_rules.gd` (choose_job), `scripts/people/people_manager.gd`, `scripts/creatures/pack_sim.gd` (offscreen raid reduction); Test `tests/integration/test_guards.gd`
- Guard patrols waypoints around the territory (more at night), attacks creatures inside the territory (spear, `Combat.melee_targets`), visible spear; offscreen raids lose strength per guard.
- Commit `feat: guardas patrulham e defendem o reino`.

### Task 9: UI — card, families panel, chronicle
**Files:** Modify `scripts/people/people_manager.gd` (card_text), `scripts/ui/hud.gd`, `project.godot` (action `chronicle` K); Test `tests/integration/test_hud_houses.gd`
- Card: kinship to nearby residents (head/spouse/parents), vocation, desire, public secret, House goal; panel C: tradition, wealth, plots, house level, specialty, prestige, goal; panel K: last 12 chronicle lines of the kingdom.
- Commit `feat: interface das Casas e crônica`.

### Task 10: ADM log — kingdom events leave the HUD (done in bd86ed8)
- Chronicle signal + `chronicle_all`, `AdminLog` file writer, all sources → chronicle, F9/F10 dev panels, hint without C/K.

### Task 11: Deed core
- `Deeds` (pure): `make(kind, at, reach, start_hour, end_hour, work_sec, data) -> Dictionary`, `is_due(deed, hour)`, `next_window(hour, from_h, to_h) -> Vector2` (start/end total hours of the next window, wrapping midnight), `seen_chance(awake_outsiders) -> float`.
- `PersonBrain.Act.DEED` (appended). `me.deed` ({pos, reach} or null) wins over raid, sleep, carrying and work; only FLEE beats it.
- `Person`: DEED act stands, plays work, counts `deed.work_sec`, calls `manager.finish_deed(self)`.
- `PeopleManager.person_context` passes a due deed; `finish_deed` → `HouseSim.complete_deed(k, rec, witnesses)`; `witnesses_of(n)` = visible adult Person nodes within `DEED_WITNESS_RADIUS`, outside the doer's family and the deed's party.
- `HouseSim`: `has_node` callable; hourly `_deeds(k)`: nodeless doers with a due deed resolve (offscreen witnesses rolled with `seen_chance`), expired deeds resolve without witnesses; `complete_deed` dispatches by kind.
- Tests: deed due/window math, brain priority, offscreen resolution, expiry, witness filter (unit on the static filter).

### Task 12: Departures as deeds
- Open departure → `farewell` deed (day window, at the head's door). Secret → `runaway` deed (night window, kingdom edge away from home). `depart` runs on completion; a seen runaway is discovered at once.
- Arranged "flee" and romance "leave" use the same deeds.

### Task 13: Land and building work
- LAND goal → `stake` deed for the head at the reserved plot (`f.claim`), paid and staked on completion (plot rechecked).
- UPGRADE → `home.upgrade = {level, done_hours}` paid at start; daily `build_home` deeds for House adults (work window, at the home); each completion adds `UPGRADE_DEED_HOURS`; level applied at `UPGRADE_WORK_HOURS[level]`. The goal does not fail while the work goes on.

### Task 14: Ceremonies
- Arranged "accept" → `wedding` deeds (next ceremony window, at the seat) for both partners (lead = person) and both heads; marriage effects on the lead's completion.
- UNION → `union` deeds for both heads; `unite` on completion.

### Task 15: Night deeds and witnesses
- `skim` deed to the storage; `spy_move` (day, rival home) then nightly `spy_report` (own home); `tryst` (both lovers, remote spot); `revenge` (target home). Effects on completion; real witnesses expose (skim → `expose`, report → `expose_spy`, tryst → `expose_romance`, revenge → seen dishonor). Remove the daily chance discoveries.

### Task 16: Captures, docs, review, merge
- Organic captures: the world runs on its own (no staged events); shots found by watching the ADM log for deeds in progress. Docs: CLAUDE.md, ENTREGAS.md, CONTINUAR.md (next: stage 8). Final review (subagent opus), fixes with failing tests, merge to main.
