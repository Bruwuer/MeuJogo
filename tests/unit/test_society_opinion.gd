extends GameTest

const B := GameConstants.Building
const R := GameConstants.Res
const T := GameConstants.Trait
const P := GameConstants.Profession

var _gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
var _scatter := PropScatter.new(_gen, GameConstants.WORLD_SEED)
var _said: Array[String] = []
var _player_in := [true]


func _setup(loaded := true) -> Array:
	_said = []
	_player_in = [true]
	var s := WorldState.new()
	s.seed = GameConstants.WORLD_SEED
	var center := TestSpots.flat_clear(_gen, _scatter, B.CABIN, 8.0, Vector2(200, 200))
	var seat := s.add_building(B.CABIN, center, 0)
	var k := s.add_kingdom("Teste", Color.RED, seat.pos, seat.id)
	k.next_traveler_hour = 1e9
	k.people_ever = 5
	s.add_stock(k, R.FOOD, 2000)
	var sim := VillageSim.new()
	add_child(sim)
	sim.setup(s, _gen, _scatter, null)
	sim.clock_hours = 7.0
	sim.is_kingdom_loaded = func(_k: Dictionary) -> bool: return loaded
	sim.is_player_in = func(_k: Dictionary) -> bool: return _player_in[0]
	sim.message.connect(func(t: String) -> void: _said.append(t))
	return [s, k, sim]


func _person(s: WorldState, k: Dictionary, seed_value: int, opinion := 0.0, surname := "") -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var p := s.add_person(PersonGen.generate(r, 0.0, P.WOODCUTTER), k.center + Vector3(2, 0, 4), k.id)
	p.status = "resident"
	p.age = 30.0
	p.traits = [T.WORKER, T.BRAVE]
	p.opinion = opinion
	if surname != "":
		p.surname = surname
	return p


func _count(part: String) -> int:
	return _said.filter(func(t: String) -> bool: return t.contains(part)).size()


## Runs the clock to `hour` of the current day (or the next day if already past).
func _tick_to(sim: VillageSim, hour: float) -> void:
	while fmod(sim.clock_hours, 24.0) != hour:
		sim.tick_hours(1.0)


func test_content_people_warm_up() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	var p := _person(s, k, 1, 0.0)
	var h := s.add_building(B.HOUSE, k.center + Vector3(0, 0, 12), 0, Color.WHITE, p.id)
	p.home_id = h.id
	p.contentment = 1.0
	for i in 24:
		sim.tick_hours(1.0)
	assert_true(float(p.opinion) > 0.05, "a happy resident thinks better of the founder (%.3f)" % p.opinion)
	var q := _person(s, k, 2, 0.0)
	q.contentment = 0.0
	var before := float(q.opinion)
	sim.tick_hours(1.0)
	assert_true(float(q.opinion) < before, "an unhappy one blames the founder")


func test_family_pulls_opinion() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	var x := _person(s, k, 1, 0.8, "Ferreira")
	var y := _person(s, k, 2, 0.8, "Ferreira")
	var z := _person(s, k, 3, -0.8, "Ferreira")
	var w := _person(s, k, 4, -0.8, "Couto")
	w.traits = [T.LAZY, T.FEARFUL] # no friend of the others (who would pull it up too)
	for p in [x, y, z, w]:
		p.contentment = 0.5
	for i in 24:
		sim.tick_hours(1.0)
	assert_true(float(z.opinion) - float(w.opinion) > 0.1, "the family lifts z (z %.2f, w %.2f)" % [z.opinion, w.opinion])


func test_stance_messages_once() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	var p := _person(s, k, 1, 0.7)
	var q := _person(s, k, 2, -0.8, "Couto")
	for i in 5:
		sim.tick_hours(1.0)
	assert_eq(p.stance, "ally")
	assert_eq(q.stance, "enemy")
	var ally_word: String = GameConstants.SOCIETY_MSG_ALLY[1 if p.female else 0] % PersonGen.full_name(p)
	assert_eq(_count(ally_word), 1, str(_said))
	var enemy_word: String = GameConstants.SOCIETY_MSG_ENEMY[1 if q.female else 0] % PersonGen.full_name(q)
	assert_eq(_count(enemy_word), 1, str(_said))


func test_family_stance() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	var p := _person(s, k, 1, 0.8, "Ferreira")
	_person(s, k, 2, 0.7, "Ferreira")
	sim.tick_hours(1.0)
	assert_eq(s.family(p.family_id).stance, "ally")
	assert_eq(_count("A Casa Ferreira agora é sua aliada"), 1, str(_said))


func test_ally_family_gives_gift() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	_person(s, k, 1, 0.9, "Ferreira")
	s.add_stock(k, R.WOOD, 70) # above the target: nobody cuts wood meanwhile
	var stock := s.stock_of(k, R.WOOD)
	_tick_to(sim, GameConstants.DEED_HOUR)
	assert_eq(s.get_resource(R.WOOD), GameConstants.GIFT_AMOUNT, "the player got wood")
	assert_eq(s.stock_of(k, R.WOOD), stock - GameConstants.GIFT_AMOUNT, "from the kingdom stock")
	assert_eq(_count("A Casa Ferreira lhe deu 3 de madeira"), 1, str(_said))
	_tick_to(sim, 23.0)
	assert_eq(s.get_resource(R.WOOD), GameConstants.GIFT_AMOUNT, "once a day")


func test_enemy_steals_only_with_player() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	var thief := _person(s, k, 1, -0.9)
	s.add_stock(k, R.WOOD, 60) # at the target: nobody cuts wood meanwhile
	var stock := s.stock_of(k, R.WOOD)
	s.add_resource(R.WOOD, 10)
	s.add_resource(R.STONE, 4)
	_player_in[0] = false
	_tick_to(sim, GameConstants.DEED_HOUR)
	assert_eq(s.get_resource(R.WOOD), 10, "nothing stolen while the player is away")
	_player_in[0] = true
	sim.tick_hours(1.0)
	assert_eq(s.get_resource(R.WOOD), 10 - GameConstants.THEFT_AMOUNT, "steals the most plentiful")
	assert_eq(s.stock_of(k, R.WOOD), stock + GameConstants.THEFT_AMOUNT, "into the kingdom stock")
	assert_eq(_count("%s roubou 2 de madeira de você" % PersonGen.full_name(thief)), 1, str(_said))


func test_deeds_once_per_day() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	for i in 3:
		_person(s, k, 10 + i, -0.9)
	s.add_resource(R.WOOD, 40)
	_tick_to(sim, 23.0)
	assert_eq(_count("roubou"), GameConstants.THEFT_MAX_PER_DAY, "at most two thefts a day: %s" % str(_said))
	_tick_to(sim, GameConstants.DEED_HOUR)
	assert_eq(_count("roubou"), GameConstants.THEFT_MAX_PER_DAY * 2, "again the next day")


func test_talk_opinion_once_a_day() -> void:
	var p := {traits = [T.SOCIABLE, T.WORKER], opinion = 0.0, talk_day = -1}
	assert_true(SocietyRules.talk(p, 3), "first talk of the day")
	assert_near(float(p.opinion), GameConstants.TALK_OPINION.sociable, 0.0001)
	assert_true(not SocietyRules.talk(p, 3), "not twice a day")
	assert_true(SocietyRules.talk(p, 4))
	var loner := {traits = [T.LONER, T.WORKER], opinion = 0.0, talk_day = -1}
	SocietyRules.talk(loner, 1)
	assert_near(float(loner.opinion), GameConstants.TALK_OPINION.loner, 0.0001)


func test_donation_scaled() -> void:
	assert_near(PeopleManager.donation_opinion(1), GameConstants.DONATE_OPINION / GameConstants.DONATE_FULL_AT, 0.0001)
	assert_near(PeopleManager.donation_opinion(30), GameConstants.DONATE_OPINION, 0.0001)


func test_news_capped() -> void:
	var a := _setup(false)
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	for i in GameConstants.VILLAGE_NEWS_MAX + 10:
		sim._say(k, "notícia %d" % i)
	assert_eq(sim.pending_messages.size(), GameConstants.VILLAGE_NEWS_MAX)
	assert_eq(sim.pending_messages[-1], "notícia %d" % (GameConstants.VILLAGE_NEWS_MAX + 9), "keeps the latest")
	assert_eq(sim.take_dropped(), 10)
	assert_eq(sim.take_dropped(), 0)


func test_traveler_approach_message() -> void:
	var a := _setup()
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	sim.has_node = func(_id: int) -> bool: return true
	k.next_traveler_hour = 0.0
	sim.tick_hours(1.0)
	assert_eq(_count(GameConstants.VILLAGE_MSG_APPROACH % k.name), 1, str(_said))


func test_catch_up_hours_with_day_night() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	var dn := DayNight.new()
	var sun := DirectionalLight3D.new()
	add_child(sun)
	dn.setup(sun, Environment.new(), ProceduralSkyMaterial.new())
	add_child(dn)
	dn.set_process(false)
	dn.day = 3
	dn.time_of_day = 23.5 / 24.0
	sim.setup(s, _gen, _scatter, dn)
	_person(s, k, 1, -0.9)
	s.add_resource(R.WOOD, 20)
	sim.tick_hours(24.0) # a whole day caught up at once
	assert_eq(_count("roubou"), 1, "each caught-up hour is its own hour: one theft that day (%s)" % str(_said))


func test_reload_does_not_repeat_news() -> void:
	var a := _setup()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	var sim: VillageSim = a[2]
	_person(s, k, 1, 0.9, "Ferreira")
	_person(s, k, 2, 0.8, "Ferreira")
	s.add_stock(k, R.WOOD, 70)
	_tick_to(sim, GameConstants.DEED_HOUR)
	assert_eq(_count("A Casa Ferreira agora é sua aliada"), 1)
	assert_eq(_count("lhe deu"), 1)
	const PATH := "user://test_reload_news.bin"
	s.save_to(PATH)
	var l := WorldState.load_from(PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var sim2 := VillageSim.new()
	add_child(sim2)
	sim2.setup(l, _gen, _scatter, null)
	sim2.clock_hours = sim.clock_hours
	sim2.is_kingdom_loaded = func(_k: Dictionary) -> bool: return true
	sim2.is_player_in = func(_k: Dictionary) -> bool: return true
	sim2.message.connect(func(t: String) -> void: _said.append(t))
	sim2.tick_hours(2.0)
	assert_eq(_count("A Casa Ferreira agora é sua aliada"), 1, "no repeated ally news after a reload")
	assert_eq(_count("lhe deu"), 1, "no second gift the same day")
