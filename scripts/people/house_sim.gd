class_name HouseSim
extends RefCounted
## The hourly life of the Houses (stage 7), run by VillageSim right after SocietySim for every
## kingdom (records only): wealth and craft from work, prestige, vocations that clash with the
## House trade and how people leave (friendly / neutral / hostile, openly or running away at night),
## adoption of orphans. Everything goes to the chronicle; big moments also go to the HUD.
## Randomness is seeded by (world seed, tag, kingdom, hour).

const P := GameConstants.Profession

var _state: WorldState
var _say: Callable # (k: Dictionary, text: String)
var _society: SocietySim
var _hour := 0.0


func setup(state: WorldState, say: Callable, society: SocietySim) -> void:
	_state = state
	_say = say
	_society = society


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
