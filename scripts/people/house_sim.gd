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
	_discoveries(k)
	if _is_daily(GameConstants.DEED_HOUR):
		_adoptions(k)
		_goals(k, rng)
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
		_log(k, text % [old_name, f.surname, surname], true)
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
			_log(k, GameConstants.HOUSE_MSG_RUNAWAY % [sec.name, f.surname], true)
		p.secret = {}


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
		_log(k, GameConstants.HOUSE_MSG_ADOPTED % [PersonGen.full_name(c), fam.surname], true)


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


## Chronicle entry; `announce` also shows it in the HUD.
func _log(k: Dictionary, text: String, announce := false) -> void:
	_state.chronicle_add(_hour, text, k.id)
	if announce:
		_say.call(k, text)


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
	_log(k, GameConstants.HOUSE_MSG_UPGRADE % [f.surname, GameConstants.HOUSE_LEVEL_NAMES[level + 1]], true)
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
	var text: String = GameConstants.GOAL_TEXTS[int(g.kind)]
	if text.contains("%s"):
		var target := _state.family(int(g.get("target_id", -1)))
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
