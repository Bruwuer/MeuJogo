class_name HouseSim
extends RefCounted
## The hourly life of the Houses (stage 7), run by VillageSim right after SocietySim for every
## kingdom (records only): wealth and craft from work, prestige, vocations that clash with the
## House trade and how people leave (friendly / neutral / hostile, openly or running away at night),
## adoption of orphans. Everything goes to the chronicle; big moments also go to the HUD.
## Randomness is seeded by (world seed, tag, kingdom, hour).

const P := GameConstants.Profession

## Buildings created or changed (plot stakes, upgraded homes) so nodes can be refreshed.
signal buildings_changed(recs: Array)
## A deed was carried out (`seen`: ids of the witnesses).
signal deed_completed(rec: Dictionary, deed: Dictionary, seen: Array)

## person id -> whether the person has a node (then deeds are done for real, not summarized).
var has_node: Callable = func(_id: int) -> bool: return false

var _state: WorldState
var _say: Callable # (k: Dictionary, text: String)
var _society: SocietySim
var _gen: TerrainGenerator
var _hour := 0.0


func setup(state: WorldState, say: Callable, society: SocietySim, gen: TerrainGenerator = null) -> void:
	_state = state
	_say = say
	_society = society
	_gen = gen


## One simulated hour of kingdom `k`; `hour` = total game hours of that hour.
func tick_hour(k: Dictionary, hour: float) -> void:
	_hour = hour
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_state.seed, "houses", k.id, int(hour)])
	for f in _state.families_of(k.id):
		_init_house(f, rng)
	_work(k)
	_vocations(k, rng)
	_deeds(k)
	_discoveries(k)
	if _is_daily(GameConstants.DEED_HOUR):
		_adoptions(k)
		_goals(k, rng)
		_intrigue(k, rng)
	for f in _state.families_of(k.id):
		f.prestige = prestige_of(f)


## A House's standing: wealth, land, house level and craft (scandals lower it through `dishonor`).
func prestige_of(f: Dictionary) -> float:
	var w: Dictionary = GameConstants.PRESTIGE_WEIGHTS
	var top := 0.0
	for prof in f.skill:
		top = maxf(top, HouseRules.skill_bonus(float(f.skill[prof])) / GameConstants.SKILL_MAX_BONUS)
	return float(f.wealth) * w.wealth + (f.plots as Array).size() * w.plot + house_level_of(f) * w.level \
			+ top * w.skill - float(f.get("dishonor", 0.0))


## Level of the House's home (0 when it has none).
func house_level_of(f: Dictionary) -> int:
	var head := _state.person(int(f.head_id))
	var home := _state.building(int(head.get("home_id", -1))) if not head.is_empty() else {}
	return int(home.get("house_level", 0))


# --- House setup and work -------------------------------------------------------------------

func _init_house(f: Dictionary, rng: RandomNumberGenerator) -> void:
	if f.get("house_init", false):
		return
	var head := _state.person(int(f.head_id))
	f.tradition = HouseRules.tradition_for(head, rng) if not head.is_empty() else f.tradition
	f.values = HouseRules.values_for(f.tradition, rng)
	f.house_init = true


## During work hours every working adult brings wealth home and makes the House better at its trade.
func _work(k: Dictionary) -> void:
	var h := fmod(_hour, 24.0)
	if h < GameConstants.WORK_START_HOUR or h >= GameConstants.WORK_END_HOUR:
		return
	for p in _state.residents(k.id):
		if not SocietyRules.is_adult(p) or String(p.get("job", "")) in ["", "rest"]:
			continue
		var f := _state.family(int(p.get("family_id", -1)))
		if f.is_empty():
			continue
		var prof := int(p.profession)
		f.wealth = float(f.wealth) + HouseRules.work_wealth(prof, float(f.skill.get(prof, 0.0)))
		f.skill[prof] = float(f.skill.get(prof, 0.0)) + 1.0


# --- Vocations and departures ---------------------------------------------------------------

func _vocations(k: Dictionary, rng: RandomNumberGenerator) -> void:
	for p in _state.residents(k.id):
		var f := _state.family(int(p.get("family_id", -1)))
		if int(p.get("vocation", -1)) < 0 and float(p.age) >= GameConstants.VOCATION_AGE:
			p.vocation = HouseRules.vocation_for(p, f, rng)
		if not p.get("conflict", false) or f.is_empty() or not SocietyRules.is_adult(p):
			continue
		if rng.randf() >= SocietyRules.hourly_chance(GameConstants.CONFLICT_RESOLVE_PER_DAY):
			continue
		var rel := _state.relation(p.id, int(f.head_id))
		match HouseRules.conflict_outcome(p, f, rel, rng):
			"conform":
				p.conflict = false
				p.resentment = clampf(float(p.resentment) + GameConstants.CONFLICT_RESENTMENT, 0.0, 1.0)
				_log(k, GameConstants.HOUSE_MSG_CONFORM % [PersonGen.full_name(p), f.surname])
			"negotiate":
				p.conflict = false
				p.profession = int(p.vocation)
				f.dishonor = float(f.get("dishonor", 0.0)) + GameConstants.NEGOTIATE_DISHONOR
				_state.add_relation(p.id, int(f.head_id), GameConstants.BRANCH_RELATION_GAIN)
				_log(k, GameConstants.HOUSE_MSG_NEGOTIATE % [f.surname, PersonGen.full_name(p), PersonGen.profession_name(p)])
			"leave":
				p.conflict = false
				p.profession = int(p.vocation)
				depart(k, f, p, HouseRules.departure_style(p, f, rel, rng), _hour)


## `p` leaves House `f` and founds a House of their own (with the spouse when married), in the
## given style {tone, secret}. A secret departure is only found out the next morning.
func depart(k: Dictionary, f: Dictionary, p: Dictionary, style: Dictionary, hour: float) -> Dictionary:
	_hour = hour
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_state.seed, "depart", p.id, int(hour)])
	var hostile: bool = style.tone == "hostile"
	var crests := _state.families_of(k.id).map(func(x: Dictionary) -> Dictionary: return x.crest)
	var crest := Crest.rival(f.crest, rng, crests) if hostile else Crest.derive(f.crest, rng, crests)
	var surname := _society._new_surname(k, p, rng)
	var origin := "rival" if hostile else "branch"
	var nf := _state.add_family(surname, crest, k.id, p.id, hour, f.id, origin)
	nf.tradition = WorldState.tradition_of_profession(int(p.profession))
	nf.values = HouseRules.values_for(nf.tradition, rng)
	nf.house_init = true
	var prof := int(p.profession)
	if f.skill.has(prof):
		nf.skill[prof] = float(f.skill[prof]) * GameConstants.SKILL_INHERIT
	if style.tone == "friendly":
		var gift := floorf(maxf(0.0, float(f.wealth)) * GameConstants.BLESSING_SHARE)
		f.wealth = float(f.wealth) - gift
		nf.wealth = gift
	var movers: Array[Dictionary] = [p]
	var spouse := _state.person(int(p.get("spouse_id", -1)))
	if not spouse.is_empty() and spouse.get("family_id", -1) == f.id:
		movers.append(spouse)
	var old_name := PersonGen.full_name(p)
	for m in movers:
		m.family_id = nf.id
		m.surname = surname
		if style.secret:
			m.home_id = -1
			m.inside = -1
	if hostile:
		f.rival_id = nf.id
		nf.rival_id = f.id
		f.insulted_by = nf.id
		_state.add_relation(p.id, int(f.head_id), GameConstants.HOSTILE_DEPART_HIT)
	elif style.tone == "friendly":
		_state.add_relation(p.id, int(f.head_id), GameConstants.BRANCH_RELATION_GAIN)
	if style.secret:
		p.secret = {kind = "runaway", from = f.id, hour = hour, name = old_name}
		_state.chronicle_add(hour, GameConstants.HOUSE_MSG_RUNAWAY % [old_name, f.surname], k.id, false)
	else:
		var text: String = {"friendly": GameConstants.HOUSE_MSG_BLESSED, "hostile": GameConstants.HOUSE_MSG_HOSTILE}.get(
				style.tone, GameConstants.HOUSE_MSG_NEUTRAL)
		_log(k, text % [old_name, f.surname, surname])
	return nf


## Runaways are noticed by their old House the morning after.
func _discoveries(k: Dictionary) -> void:
	if fmod(_hour, 24.0) < GameConstants.DISCOVERY_HOUR:
		return
	for p in _state.residents(k.id):
		var sec: Dictionary = p.get("secret", {})
		if sec.get("kind", "") != "runaway" or _hour - float(sec.hour) < 24.0 - GameConstants.DISCOVERY_HOUR:
			continue
		var f := _state.family(int(sec.from))
		if not f.is_empty():
			_state.add_relation(p.id, int(f.head_id), GameConstants.RUNAWAY_HIT)
			_log(k, GameConstants.HOUSE_MSG_RUNAWAY % [sec.name, f.surname])
		p.secret = {}


# --- Deeds ----------------------------------------------------------------------------------

## Deeds of people without a node are settled at their start hour (a summary); deeds past their
## window are settled anyway, unseen.
func _deeds(k: Dictionary) -> void:
	for p in _state.residents(k.id):
		var deed: Dictionary = p.get("deed", {})
		if deed.is_empty():
			continue
		if Deeds.expired(deed, _hour):
			complete_deed(k, p, [])
		elif Deeds.is_due(deed, _hour) and not has_node.call(p.id):
			complete_deed(k, p, _offscreen_seen(k, p, deed))


## Gives `p` a deed (replacing any other).
func plan_deed(p: Dictionary, deed: Dictionary) -> void:
	p.deed = deed


## The deed of `p` is done: its effect happens now. `seen`: ids of the people who saw it.
func complete_deed(k: Dictionary, p: Dictionary, seen: Array, hour := -1.0) -> void:
	if hour >= 0.0:
		_hour = hour
	var deed: Dictionary = p.get("deed", {})
	if deed.is_empty():
		return
	p.deed = {}
	deed_completed.emit(p, deed, seen)


## Offscreen, a secret deed is seen by chance by the outsiders awake at that hour (guards on watch
## at night). Returns the witness ids (at most one).
func _offscreen_seen(k: Dictionary, p: Dictionary, deed: Dictionary) -> Array:
	if not (deed.data as Dictionary).get("secret", false):
		return []
	var party: Array = deed.data.get("party", [])
	var h := fmod(_hour, 24.0)
	var asleep := h >= GameConstants.SLEEP_START_HOUR or h < GameConstants.SLEEP_END_HOUR
	var awake := _state.residents(k.id).filter(func(o: Dictionary) -> bool:
		if o.id == p.id or party.has(o.id) or not SocietyRules.is_adult(o):
			return false
		if int(p.get("family_id", -1)) >= 0 and int(o.get("family_id", -1)) == int(p.family_id):
			return false
		var guard := int(o.profession) == GameConstants.Profession.GUARD and VillageRules.guard_on_duty(h)
		return guard or not asleep)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_state.seed, "seen", p.id, int(_hour)])
	if awake.is_empty() or rng.randf() >= Deeds.seen_chance(awake.size()):
		return []
	return [awake[rng.randi() % awake.size()].id]


# --- Adoption -------------------------------------------------------------------------------

## Children with no parent left in the kingdom are taken in by a childless couple with a home, or
## by a widow(er) of a House with some wealth.
func _adoptions(k: Dictionary) -> void:
	var people := _state.residents(k.id)
	for c in people:
		if SocietyRules.is_adult(c) or not (c.get("adopted_by", []) as Array).is_empty():
			continue
		var parents := Kinship.parents_of(_state, c.id)
		if parents.any(func(id: int) -> bool:
				var par := _state.person(id)
				return not par.is_empty() and par.status == "resident" and par.kingdom_id == k.id):
			continue
		var adopters := _adopters(people, c)
		if adopters.is_empty():
			continue
		c.adopted_by = adopters.map(func(a: Dictionary) -> int: return a.id)
		var fam := _state.family(int(adopters[0].family_id))
		c.family_id = fam.id
		c.surname = fam.surname
		c.home_id = int(adopters[0].home_id)
		_state.note_ancestry(c)
		_log(k, GameConstants.HOUSE_MSG_ADOPTED % [PersonGen.full_name(c), fam.surname])


func _adopters(people: Array[Dictionary], child: Dictionary) -> Array:
	for p in people:
		if p.id == child.id or not SocietyRules.is_adult(p) or int(p.home_id) < 0 or int(p.get("family_id", -1)) < 0:
			continue
		if not Kinship.children_of(_state, p.id).is_empty():
			continue
		var spouse := _state.person(int(p.get("spouse_id", -1)))
		if not spouse.is_empty():
			if p.female: # the couple is listed once, wife first
				return [p, spouse]
			continue
		if p.get("widowed", false) and float(_state.family(int(p.family_id)).wealth) >= GameConstants.ADOPT_MIN_WEALTH:
			return [p]
	return []


# --- Helpers --------------------------------------------------------------------------------

func _is_daily(at_hour: float) -> bool:
	var h := fmod(_hour, 24.0)
	return h >= at_hour and h < at_hour + 1.0


## ADM chronicle entry (the player never sees it).
func _log(k: Dictionary, text: String) -> void:
	_state.chronicle_add(_hour, text, k.id)


# --- Land -----------------------------------------------------------------------------------

## Claims the free plot nearest to the House's home for PLOT_PRICE. False when it cannot pay, is
## at PLOTS_MAX or no free plot is left in the territory.
func acquire_plot(k: Dictionary, f: Dictionary) -> bool:
	if (f.plots as Array).size() >= GameConstants.PLOTS_MAX or float(f.wealth) < GameConstants.PLOT_PRICE:
		return false
	var rect := _free_plot(k, _home_pos(k, f))
	if rect.size == Vector2.ZERO:
		return false
	f.wealth = float(f.wealth) - GameConstants.PLOT_PRICE
	(f.plots as Array).append(rect)
	buildings_changed.emit(_add_stakes(f, rect))
	_log(k, GameConstants.HOUSE_MSG_PLOT % f.surname)
	return true


## `buyer` buys the last plot of `seller` (a House short of money) for PLOT_PRICE x PLOT_BUY_MARKUP.
func buy_plot(k: Dictionary, buyer: Dictionary, seller: Dictionary) -> bool:
	var price := GameConstants.PLOT_PRICE * GameConstants.PLOT_BUY_MARKUP
	if (seller.plots as Array).is_empty() or float(buyer.wealth) < price \
			or (buyer.plots as Array).size() >= GameConstants.PLOTS_MAX:
		return false
	var rect: Rect2 = (seller.plots as Array).pop_back()
	(buyer.plots as Array).append(rect)
	buyer.wealth = float(buyer.wealth) - price
	seller.wealth = float(seller.wealth) + price
	var moved := []
	for b in _state.all_buildings():
		if b.type == GameConstants.Building.STAKE and b.get("family_id", -1) == seller.id \
				and rect.grow(0.5).has_point(Vector2(b.pos.x, b.pos.z)):
			b.family_id = buyer.id
			b.color = house_color(buyer)
			moved.append(b)
	buildings_changed.emit(moved)
	_log(k, GameConstants.HOUSE_MSG_PLOT_BOUGHT % [buyer.surname, seller.surname])
	return true


## The House's banner color (first field of its crest).
static func house_color(f: Dictionary) -> Color:
	return Crest.color_at(f.crest, 0.2, 0.2) if not (f.crest as Dictionary).is_empty() else Color.WHITE


func _home_pos(k: Dictionary, f: Dictionary) -> Vector3:
	var head := _state.person(int(f.head_id))
	var home := _state.building(int(head.get("home_id", -1))) if not head.is_empty() else {}
	return home.pos if not home.is_empty() else k.center


## Grid-aligned PLOT_SIZE squares around `around`, nearest first: inside the territory and the
## map, not on another plot or a building, on ground flat enough. Rect2() when none is free.
func _free_plot(k: Dictionary, around: Vector3) -> Rect2:
	var size := GameConstants.PLOT_SIZE
	var base := Vector2i(floori(around.x / size), floori(around.z / size))
	var taken: Array[Rect2] = []
	for other in _state.families_of(k.id):
		for r: Rect2 in other.plots:
			taken.append(r)
	var footprints: Array[Rect2] = []
	for b in VillageRules.kingdom_buildings(_state, k):
		if b.type != GameConstants.Building.STAKE:
			footprints.append(BuildRules.footprint_rect(b.type, b.pos, b.rot))
	var map := Rect2(Vector2.ZERO, Vector2.ONE * ChunkMath.playable_size())
	for ring in GameConstants.PLOT_SEARCH_RINGS + 1:
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var rect := Rect2(Vector2(base.x + dx, base.y + dy) * size, Vector2.ONE * size)
				var c := rect.get_center()
				if c.distance_to(Vector2(k.center.x, k.center.z)) > float(k.radius) - size * 0.5 or not map.encloses(rect):
					continue
				var inner := rect.grow(-0.01)
				if taken.any(func(r: Rect2) -> bool: return inner.intersects(r)) \
						or footprints.any(func(r: Rect2) -> bool: return inner.intersects(r)):
					continue
				if _gen and _height_span(rect) > GameConstants.PLOT_MAX_HEIGHT_DIFF:
					continue
				return rect
	return Rect2()


func _height_span(rect: Rect2) -> float:
	var lo := INF
	var hi := -INF
	for x in [rect.position.x, rect.get_center().x, rect.end.x]:
		for z in [rect.position.y, rect.get_center().y, rect.end.y]:
			var h := _gen.height_at(x, z)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return hi - lo


func _add_stakes(f: Dictionary, rect: Rect2) -> Array:
	var out := []
	var inset := 0.2
	for corner: Vector2 in [rect.position + Vector2(inset, inset), Vector2(rect.end.x - inset, rect.position.y + inset),
			Vector2(rect.position.x + inset, rect.end.y - inset), rect.end - Vector2(inset, inset)]:
		var y := _gen.height_at(corner.x, corner.y) if _gen else 0.0
		var b := _state.add_building(GameConstants.Building.STAKE, Vector3(corner.x, y, corner.y), 0, house_color(f),
				GameConstants.OWNER_KINGDOM)
		b.family_id = f.id
		out.append(b)
	return out


# --- Home upgrades --------------------------------------------------------------------------

## Simple house -> stone house -> manor, paid with House wealth. False at the top or when short.
func upgrade(k: Dictionary, f: Dictionary) -> bool:
	var head := _state.person(int(f.head_id))
	var home := _state.building(int(head.get("home_id", -1))) if not head.is_empty() else {}
	if home.is_empty() or home.type != GameConstants.Building.HOUSE or home.get("site", false):
		return false
	var level := int(home.get("house_level", 0))
	var price := HouseRules.upgrade_price(level)
	if price < 0 or float(f.wealth) < price:
		return false
	f.wealth = float(f.wealth) - price
	home.house_level = level + 1
	buildings_changed.emit([home])
	_log(k, GameConstants.HOUSE_MSG_UPGRADE % [f.surname, GameConstants.HOUSE_LEVEL_NAMES[level + 1]])
	return true


# --- Goals ----------------------------------------------------------------------------------

func _goals(k: Dictionary, rng: RandomNumberGenerator) -> void:
	for f in _state.families_of(k.id):
		var goal: Dictionary = f.goal
		if not goal.is_empty():
			if goal_reached(f, goal, goal_ctx(k, f)):
				_goal_end(k, f, true)
			elif _hour > float(goal.get("deadline_hour", INF)):
				_goal_end(k, f, false)
		if (f.goal as Dictionary).is_empty():
			var g := HouseRules.pick_goal(f, goal_ctx(k, f), rng)
			if not g.is_empty():
				g.deadline_hour = _hour + GameConstants.GOAL_DAYS * 24.0
				g.start_level = house_level_of(f)
				f.goal = g
				_state.chronicle_add(_hour, GameConstants.HOUSE_MSG_GOAL_SET % [f.surname, goal_text(g)], k.id)
				continue # a new goal is pursued from the next day
		_pursue(k, f)


## Daily step toward the goal (the rest happens through work, marriages and intrigue).
func _pursue(k: Dictionary, f: Dictionary) -> void:
	var G := GameConstants.Goal
	match int((f.goal as Dictionary).get("kind", -1)):
		G.LAND:
			if not acquire_plot(k, f):
				for other in _state.families_of(k.id):
					if other.id != f.id and float(other.wealth) < GameConstants.WEALTH_POOR and buy_plot(k, f, other):
						break
		G.UPGRADE:
			upgrade(k, f)
		G.ALLIANCE:
			_try_alliance(k, f)
		G.UNION:
			var big := _state.family(int(f.goal.target_id))
			if not big.is_empty() and big.id != f.id:
				unite(k, f, big)
		G.REVENGE:
			var target := _state.family(int(f.goal.target_id))
			if not target.is_empty() and _roll(f.id, "revenge") < GameConstants.REVENGE_PER_DAY:
				take_revenge(k, f, target)


func goal_reached(f: Dictionary, goal: Dictionary, ctx: Dictionary) -> bool:
	var G := GameConstants.Goal
	match int(goal.kind):
		G.LAND:
			return int(ctx.plots) >= mini(maxi(1, int(ctx.adults)) * GameConstants.PLOTS_PER_ADULT, GameConstants.PLOTS_MAX)
		G.UPGRADE:
			return int(ctx.house_level) > int(goal.get("start_level", 0))
		G.WEALTH:
			return float(f.wealth) >= GameConstants.WEALTH_COMFORT
		G.SURPASS:
			var rival := _state.family(int(goal.target_id))
			return rival.is_empty() or float(f.prestige) > float(rival.prestige)
		G.HEIR:
			return int(ctx.heirs) > 0
	return goal.get("done", false)


func _goal_end(k: Dictionary, f: Dictionary, success: bool) -> void:
	var text := goal_text(f.goal)
	for m in _state.family_members(f.id):
		var d := GameConstants.GOAL_SUCCESS_CONTENT if success else GameConstants.GOAL_FAIL_CONTENT
		m.contentment = clampf(float(m.get("contentment", 0.5)) + d, 0.0, 1.0)
	if success:
		f.dishonor = maxf(0.0, float(f.get("dishonor", 0.0)) - GameConstants.GOAL_SUCCESS_HONOR)
		_log(k, GameConstants.HOUSE_MSG_GOAL_DONE % [f.surname, text])
	else:
		_log(k, GameConstants.HOUSE_MSG_GOAL_FAILED % [f.surname, text])
	f.goal = {}


func goal_text(g: Dictionary) -> String:
	return goal_text_of(_state, g)


## "conseguir mais terra", "superar a Casa Vale"...
static func goal_text_of(state: WorldState, g: Dictionary) -> String:
	var text: String = GameConstants.GOAL_TEXTS[int(g.kind)]
	if text.contains("%s"):
		var target := state.family(int(g.get("target_id", -1)))
		text = text % (target.surname if not target.is_empty() else "?")
	return text


## Everything HouseRules.goal_scores needs to know about a House.
func goal_ctx(k: Dictionary, f: Dictionary) -> Dictionary:
	var members := _state.family_members(f.id)
	var adults := members.filter(func(m: Dictionary) -> bool: return SocietyRules.is_adult(m))
	var unmarried := adults.filter(func(m: Dictionary) -> bool: return int(m.get("spouse_id", -1)) < 0)
	var expected := HouseRules.expected_professions(f)
	var heirs := members.filter(func(m: Dictionary) -> bool:
		return m.id != int(f.head_id) and ((expected.has(int(m.profession)) and SocietyRules.is_adult(m))
				or expected.has(int(m.get("vocation", -1)))))
	var head := _state.person(int(f.head_id))
	var home := _state.building(int(head.get("home_id", -1))) if not head.is_empty() else {}
	var rival := _state.family(int(f.get("rival_id", -1)))
	var allies := []
	var partners := []
	for other in _state.families_of(k.id):
		if other.id == f.id:
			continue
		if _state.relation(int(f.head_id), int(other.head_id)) > GameConstants.FAMILY_ALLY_AT:
			allies.append(other.id)
		if other.id != int(f.get("rival_id", -1)) and _state.family_members(other.id).any(func(o: Dictionary) -> bool:
				return SocietyRules.is_adult(o) and int(o.get("spouse_id", -1)) < 0 \
						and unmarried.any(func(u: Dictionary) -> bool: return bool(u.female) != bool(o.female))):
			partners.append(other.id)
	return {
		members = members.size(), adults = adults.size(), unmarried_adults = unmarried.size(), heirs = heirs.size(),
		plots = (f.plots as Array).size(), wealth = float(f.wealth), house_level = int(home.get("house_level", 0)),
		has_house = not home.is_empty() and home.type == GameConstants.Building.HOUSE,
		rival_id = rival.id if not rival.is_empty() else -1,
		rival_gap = float(rival.prestige) - float(f.prestige) if not rival.is_empty() else 0.0,
		allies = allies, partner_families = partners, insulted_by = int(f.get("insulted_by", -1)),
		head_age = float(head.get("age", 0.0)),
	}


# --- Intrigue: marriages, unions, corruption, spies, revenge, secret romances ---------------

## Daily: unhappy marriages, skimming and its discovery, spies at work (and caught), new spies in
## rival Houses, secret romances starting and coming out.
func _intrigue(k: Dictionary, rng: RandomNumberGenerator) -> void:
	var people := _state.residents(k.id)
	for p in people:
		var sp := _state.person(int(p.get("spouse_id", -1)))
		if p.get("unhappy_marriage", false) and not sp.is_empty() and p.id < sp.id:
			_unhappy_day(k, p, sp)
	for f in _state.families_of(k.id):
		var head := _state.person(int(f.head_id))
		if rng.randf() < HouseRules.corruption_chance(f, head) and _is_work_day():
			skim(k, f)
		for sec in (f.get("secrets", []) as Array).duplicate():
			if rng.randf() < HouseRules.discovery_chance(_watchers(k, f.id)):
				expose(k, f, sec)
		var rival := _state.family(int(f.get("rival_id", -1)))
		if not rival.is_empty() and int((f.goal as Dictionary).get("kind", -1)) in [GameConstants.Goal.SURPASS, GameConstants.Goal.REVENGE] \
				and _state.relation(int(f.head_id), int(rival.head_id)) < GameConstants.INFILTRATE_AT \
				and rng.randf() < GameConstants.INFILTRATE_PER_DAY and not _has_spy(f.id, rival.id):
			plant_spy(k, f, rival)
	for p in _state.residents(k.id):
		var sec: Dictionary = p.get("secret", {})
		match String(sec.get("kind", "")):
			"spy":
				spy_day(k, p)
				if rng.randf() < HouseRules.discovery_chance(_watchers(k, int(sec.in_id))):
					expose_spy(k, p)
			"romance":
				var other := _state.person(int(sec.with))
				var watchers := _watchers(k, int(p.family_id)) + _watchers(k, int(other.get("family_id", -1)))
				if p.id < int(sec.with) and rng.randf() < HouseRules.discovery_chance(watchers):
					expose_romance(k, p)
	_romances(k, rng)


## Marries one of `f`'s unmarried adults into the House it wants an alliance with.
func _try_alliance(k: Dictionary, f: Dictionary) -> void:
	var target := _state.family(int(f.goal.target_id))
	if target.is_empty():
		return
	var single := func(m: Dictionary) -> bool: return SocietyRules.is_adult(m) and int(m.get("spouse_id", -1)) < 0
	var own := _state.family_members(f.id).filter(single)
	var theirs := _state.family_members(target.id).filter(single)
	var m := HouseRules.arranged_match(own, theirs, _state)
	if m.is_empty():
		return
	var person := _state.person(int(m.person_id))
	var partner := _state.person(int(m.partner_id))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_state.seed, "arranged", person.id, int(_hour)])
	var response := HouseRules.arranged_response(person, _state.relation(person.id, partner.id), _love_rel(person, partner.id), rng)
	arranged_marriage(k, f, person, partner, response)


## Outcome of an arranged marriage: "accept" (dowry, alliance, maybe an unhappy marriage),
## "resist" (resentment) or "flee" (runs away and marries the one they love).
func arranged_marriage(k: Dictionary, f: Dictionary, person: Dictionary, partner: Dictionary, response: String) -> void:
	var other := _state.family(int(partner.family_id))
	match response:
		"accept":
			var dowry := minf(float(GameConstants.DOWRY), maxf(0.0, float(f.wealth)))
			f.wealth = float(f.wealth) - dowry
			if not other.is_empty():
				other.wealth = float(other.wealth) + dowry
				_state.add_relation(int(f.head_id), int(other.head_id), GameConstants.ALLIANCE_RELATION_GAIN)
			var unhappy := _state.relation(person.id, partner.id) < GameConstants.UNHAPPY_AT
			_society._marry(k, person, partner)
			person.unhappy_marriage = unhappy
			partner.unhappy_marriage = unhappy
			if not (f.goal as Dictionary).is_empty():
				f.goal.done = true
			_log(k, GameConstants.HOUSE_MSG_ARRANGED % [f.surname, PersonGen.full_name(person), PersonGen.full_name(partner),
					other.get("surname", "?")])
		"resist":
			person.resentment = clampf(float(person.resentment) + GameConstants.RESIST_RESENTMENT, 0.0, 1.0)
			_state.add_relation(person.id, int(f.head_id), GameConstants.RESIST_RELATION_HIT)
			_log(k, GameConstants.HOUSE_MSG_RESISTED % [PersonGen.full_name(person), f.surname])
		"flee":
			var lover := _lover(person)
			var nf := depart(k, f, person, {tone = "hostile", secret = true}, _hour)
			if not lover.is_empty():
				var lf := _state.family(int(lover.family_id))
				if not lf.is_empty() and lf.id != nf.id:
					lover.secret = {kind = "runaway", from = lf.id, hour = _hour, name = PersonGen.full_name(lover)}
				lover.family_id = nf.id
				lover.surname = nf.surname
				lover.home_id = -1
				_society._marry(k, person, lover)


func _unhappy_day(k: Dictionary, a: Dictionary, b: Dictionary) -> void:
	_state.add_relation(a.id, b.id, GameConstants.UNHAPPY_DRIFT)
	if _state.relation(a.id, b.id) >= GameConstants.SEPARATE_AT:
		return
	a.spouse_id = -1
	b.spouse_id = -1
	a.unhappy_marriage = false
	b.unhappy_marriage = false
	var f := _state.family(int(a.family_id))
	b.home_id = -1 # one of them moves out
	if not f.is_empty():
		f.dishonor = float(f.get("dishonor", 0.0)) + GameConstants.SEPARATION_DISHONOR
	_log(k, GameConstants.HOUSE_MSG_SEPARATED % [PersonGen.full_name(a), PersonGen.full_name(b), f.get("surname", "?")])


## `small` joins `big`: members, land, stakes and wealth.
func unite(k: Dictionary, small: Dictionary, big: Dictionary) -> void:
	for m in _state.family_members(small.id):
		m.family_id = big.id
		m.surname = big.surname
	var head := _state.person(int(small.head_id))
	if not head.is_empty():
		head.family_id = big.id
		head.surname = big.surname
	big.wealth = float(big.wealth) + maxf(0.0, float(small.wealth))
	(big.plots as Array).append_array(small.plots)
	var moved := []
	for b in _state.all_buildings():
		if b.type == GameConstants.Building.STAKE and b.get("family_id", -1) == small.id:
			b.family_id = big.id
			b.color = house_color(big)
			moved.append(b)
	buildings_changed.emit(moved)
	_state.remove_family(small.id)
	if not (big.goal as Dictionary).is_empty() and int(big.goal.get("target_id", -1)) == small.id:
		big.goal.done = true
	_log(k, GameConstants.HOUSE_MSG_UNION % [small.surname, big.surname])


## A greedy House takes some of the most plentiful resource of the kingdom stock (a secret).
func skim(k: Dictionary, f: Dictionary) -> void:
	var res := SocietySim._most([GameConstants.Res.WOOD, GameConstants.Res.STONE, GameConstants.Res.FOOD],
			func(r: int) -> int: return _state.stock_of(k, r))
	var n := mini(GameConstants.SKIM_AMOUNT, _state.stock_of(k, res))
	if n <= 0:
		return
	_state.add_stock(k, res, -n)
	f.wealth = float(f.wealth) + n * GameConstants.SKIM_VALUE
	(f.secrets as Array).append({kind = "skim", res = res, amount = n, hour = _hour})
	_state.chronicle_add(_hour, "A Casa %s desviou %d de %s" % [f.surname, n, SocietySim._res_name(res)], k.id, false)


## A House secret comes out: scandal.
func expose(k: Dictionary, f: Dictionary, secret: Dictionary) -> void:
	(f.secrets as Array).erase(secret)
	f.dishonor = float(f.get("dishonor", 0.0)) + GameConstants.SCANDAL_DISHONOR
	for other in _state.families_of(k.id):
		if other.id != f.id:
			_state.add_relation(int(f.head_id), int(other.head_id), GameConstants.SCANDAL_RELATION_HIT)
	_log(k, GameConstants.HOUSE_MSG_SKIM % [f.surname, SocietySim._res_name(int(secret.get("res", 0)))])


## Plants a member of `f` in the rival House as a household member (cover: "went to serve").
func plant_spy(k: Dictionary, f: Dictionary, rival: Dictionary) -> bool:
	var spy := HouseRules.spy_candidate(f, rival, _state.family_members(f.id))
	if spy.is_empty():
		return false
	spy.family_id = rival.id
	spy.home_id = int(_state.person(int(rival.head_id)).get("home_id", -1))
	spy.secret = {kind = "spy", for_id = f.id, in_id = rival.id, hour = _hour}
	_log(k, GameConstants.HOUSE_MSG_SERVE % [PersonGen.full_name(spy), f.surname, rival.surname])
	return true


## A spy's day: wealth slips from the rival House to the spy's own, and the rival's plans slip.
func spy_day(_k: Dictionary, spy: Dictionary) -> void:
	var own := _state.family(int(spy.secret.get("for_id", -1)))
	var rival := _state.family(int(spy.secret.get("in_id", -1)))
	if own.is_empty() or rival.is_empty():
		return
	var take := maxf(0.0, float(rival.wealth)) * GameConstants.SPY_STEAL_SHARE
	rival.wealth = float(rival.wealth) - take
	own.wealth = float(own.wealth) + take
	if not (rival.goal as Dictionary).is_empty():
		rival.goal.deadline_hour = float(rival.goal.get("deadline_hour", _hour)) - GameConstants.SPY_SABOTAGE_HOURS


func expose_spy(k: Dictionary, spy: Dictionary) -> void:
	var own := _state.family(int(spy.secret.get("for_id", -1)))
	var rival := _state.family(int(spy.secret.get("in_id", -1)))
	spy.secret = {}
	if own.is_empty() or rival.is_empty():
		return
	spy.family_id = own.id
	spy.home_id = int(_state.person(int(own.head_id)).get("home_id", -1))
	own.dishonor = float(own.get("dishonor", 0.0)) + GameConstants.SCANDAL_DISHONOR
	rival.insulted_by = own.id
	own.rival_id = rival.id
	rival.rival_id = own.id
	_state.add_relation(int(own.head_id), int(rival.head_id), GameConstants.FEUD_RELATION_HIT)
	_state.add_relation(spy.id, int(rival.head_id), GameConstants.FEUD_RELATION_HIT)
	_log(k, GameConstants.HOUSE_MSG_SPY % [PersonGen.full_name(spy), rival.surname, own.surname])


func take_revenge(k: Dictionary, f: Dictionary, target: Dictionary) -> void:
	target.dishonor = float(target.get("dishonor", 0.0)) + GameConstants.REVENGE_DISHONOR
	var take := maxf(0.0, float(target.wealth)) * GameConstants.REVENGE_STEAL_SHARE
	target.wealth = float(target.wealth) - take
	f.wealth = float(f.wealth) + take
	f.insulted_by = -1
	if not (f.goal as Dictionary).is_empty():
		f.goal.done = true
	_log(k, GameConstants.HOUSE_MSG_REVENGE % [f.surname, target.surname])


## Two adults of the same sex in love meet in secret (frowned upon: never marriage or children).
func start_romance(_k: Dictionary, a: Dictionary, b: Dictionary) -> bool:
	if not HouseRules.secret_romance_possible(a, b, _state.relation(a.id, b.id), Kinship.is_close_kin(_state, a, b)):
		return false
	if not (a.get("secret", {}) as Dictionary).is_empty() or not (b.get("secret", {}) as Dictionary).is_empty():
		return false
	a.secret = {kind = "romance", with = b.id, hour = _hour}
	b.secret = {kind = "romance", with = a.id, hour = _hour}
	return true


## The romance comes out: dishonor for both Houses and family pressure — each gives in (resentment)
## or leaves the House.
func expose_romance(k: Dictionary, a: Dictionary) -> void:
	var b := _state.person(int(a.secret.get("with", -1)))
	a.secret = {}
	if not b.is_empty():
		b.secret = {}
	var fa := _state.family(int(a.get("family_id", -1)))
	_log(k, GameConstants.HOUSE_MSG_ROMANCE % [fa.get("surname", "?"), PersonGen.full_name(a),
			PersonGen.full_name(b) if not b.is_empty() else "?"])
	for p in [a, b]:
		if p.is_empty():
			continue
		var f := _state.family(int(p.get("family_id", -1)))
		if f.is_empty():
			continue
		f.dishonor = float(f.get("dishonor", 0.0)) + GameConstants.ROMANCE_DISHONOR
		_state.add_relation(p.id, int(f.head_id), GameConstants.ROMANCE_RELATION_HIT)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([_state.seed, "romance", p.id, int(_hour)])
		if p.id != int(f.head_id) and HouseRules.conflict_outcome(p, f, _state.relation(p.id, int(f.head_id)), rng) == "leave":
			depart(k, f, p, HouseRules.departure_style(p, f, _state.relation(p.id, int(f.head_id)), rng), _hour)
		else:
			p.resentment = clampf(float(p.get("resentment", 0.0)) + GameConstants.ROMANCE_RESENTMENT, 0.0, 1.0)


func _romances(k: Dictionary, rng: RandomNumberGenerator) -> void:
	var people := _state.residents(k.id).filter(func(p: Dictionary) -> bool: return SocietyRules.is_adult(p))
	for a in people:
		for other_id in _state.relations_of(a.id):
			if other_id <= a.id:
				continue
			var b := _state.person(other_id)
			if b.is_empty() or b.status != "resident" or bool(a.female) != bool(b.female):
				continue
			if rng.randf() < GameConstants.ROMANCE_START_PER_DAY:
				start_romance(k, a, b)


# --- Intrigue helpers -----------------------------------------------------------------------

## Honest, devout or sociable adults outside House `family_id` who might notice a secret.
func _watchers(k: Dictionary, family_id: int) -> int:
	var n := 0
	for p in _state.residents(k.id):
		if int(p.get("family_id", -1)) == family_id or not SocietyRules.is_adult(p):
			continue
		var traits: Array = p.get("traits", [])
		if traits.has(GameConstants.Trait.GENEROUS) or traits.has(GameConstants.Trait.DEVOUT) or traits.has(GameConstants.Trait.SOCIABLE):
			n += 1
	return n


func _has_spy(from_id: int, in_id: int) -> bool:
	return _state.all_people().any(func(p: Dictionary) -> bool:
		var sec: Dictionary = p.get("secret", {})
		return sec.get("kind", "") == "spy" and int(sec.get("for_id", -1)) == from_id and int(sec.get("in_id", -1)) == in_id)


## Strongest love for someone other than `except_id` (-1 when none).
func _love_rel(p: Dictionary, except_id: int) -> float:
	var lover := _lover(p, except_id)
	return _state.relation(p.id, lover.id) if not lover.is_empty() else -1.0


func _lover(p: Dictionary, except_id := -1) -> Dictionary:
	var best := {}
	var best_rel := GameConstants.COUPLE_AT
	var rels := _state.relations_of(p.id)
	for other_id in rels:
		var o := _state.person(other_id)
		if other_id == except_id or o.is_empty() or bool(o.female) == bool(p.female) or int(o.get("spouse_id", -1)) >= 0:
			continue
		if rels[other_id] >= best_rel and not Kinship.is_close_kin(_state, p, o):
			best_rel = rels[other_id]
			best = o
	return best


func _is_work_day() -> bool:
	return true


## A seeded roll per House, tag and day.
func _roll(id: int, tag: String) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_state.seed, tag, id, floori(_hour / 24.0)])
	return rng.randf()
