extends GameTest
## Everyday life (stage 11): meals eaten sitting by the fire, evenings at the fire, children at play,
## rainy days that send people home, and gossip when friends talk. Every act is a deed with its clip.

const B := GameConstants.Building
const T := GameConstants.Trait
const R := GameConstants.Res

var s: WorldState
var society: SocietySim
var houses: HouseSim
var gov: GovSim
var life: LifeSim
var k: Dictionary
var fire: Dictionary
var on_screen: Array = []


func _fresh() -> void:
	s = WorldState.new()
	s.seed = 31
	society = SocietySim.new()
	houses = HouseSim.new()
	gov = GovSim.new()
	life = LifeSim.new()
	on_screen = []
	society.setup(s, func(_k: Dictionary, _t: String) -> void: pass, func(_k: Dictionary) -> bool: return false,
			func(_k: Dictionary) -> Dictionary: return {})
	houses.setup(s, func(_k: Dictionary, _t: String) -> void: pass, society)
	houses.has_node = func(id: int) -> bool: return on_screen.has(id)
	gov.setup(s, houses, func(_k: Dictionary) -> bool: return false)
	life.setup(s, houses, society)
	var seat := s.add_building(B.CABIN, Vector3(300, 0, 300), 0, Color.WHITE, GameConstants.OWNER_KINGDOM)
	fire = s.add_building(B.CAMPFIRE, seat.pos + Vector3(8, 0, 0), 0, Color.WHITE, GameConstants.OWNER_KINGDOM)
	k = s.add_kingdom("Ravmia", Color.RED, seat.pos, seat.id)
	s.add_stock(k, R.FOOD, 100)


func _person(name: String, age := 30.0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var p := PersonGen.generate(rng)
	p.name = name
	p.age = age
	p.traits = [T.WORKER]
	var rec := s.add_person(p, k.center + Vector3(5, 0, 0), k.id)
	rec.status = "resident"
	return rec


func _at_hour(h: float) -> void:
	houses.tick_hour(k, h)
	gov.tick_hour(k, h)
	life.tick_hour(k, h)


# --- Meals ---

func test_people_on_screen_go_to_eat_by_the_fire() -> void:
	_fresh()
	var p := _person("Faminto")
	on_screen.append(p.id)
	p.hunger = GameConstants.HUNGER_MEAL
	var meal_hour: float = GameConstants.MEAL_HOURS[1]
	_at_hour(meal_hour)
	var deed: Dictionary = p.get("deed", {})
	assert_eq(deed.get("kind", ""), "meal")
	assert_eq(deed.get("anim", ""), GameConstants.ANIM_EAT)
	assert_true((deed.pos as Vector3).distance_to(fire.pos) <= GameConstants.MEAL_RING + 0.5, "around the campfire")
	var food := s.stock_of(k, R.FOOD)
	life.complete_deed(k, p, deed, [], meal_hour)
	assert_true(float(p.hunger) < GameConstants.HUNGER_MEAL, "fed")
	assert_eq(s.stock_of(k, R.FOOD), food - 1, "the meal came from the stock")


func test_people_on_screen_do_not_eat_out_of_thin_air() -> void:
	_fresh()
	var p := _person("Na tela")
	on_screen.append(p.id)
	p.hunger = GameConstants.HUNGER_MEAL
	var sim := VillageSim.new()
	sim.setup(s, TerrainGenerator.new(GameConstants.WORLD_SEED), PropScatter.new(TerrainGenerator.new(GameConstants.WORLD_SEED), 31), null)
	sim.has_node = func(id: int) -> bool: return on_screen.has(id)
	var food := s.stock_of(k, R.FOOD)
	sim.clock_hours = 1.0 # not a meal hour
	sim.tick_hours(1.0)
	assert_eq(s.stock_of(k, R.FOOD), food, "on screen one eats at the fire, at meal time")
	p.hunger = GameConstants.HUNGER_STARVING
	sim.tick_hours(1.0)
	assert_true(s.stock_of(k, R.FOOD) < food, "but nobody starves waiting for supper")
	sim.free()


# --- Evenings and play ---

func test_evening_by_the_fire() -> void:
	_fresh()
	var p := _person("Serão")
	p.needs = {social = 0.3, faith = 0.0}
	_at_hour(GameConstants.FIRESIDE_HOURS.x)
	var deed: Dictionary = p.get("deed", {})
	assert_eq(deed.get("kind", ""), "fireside")
	assert_eq(deed.get("anim", ""), GameConstants.ANIM_SIT)
	life.complete_deed(k, p, deed, [], GameConstants.FIRESIDE_HOURS.x)
	assert_true(float(p.needs.social) < 0.3, "company by the fire")


func test_children_play() -> void:
	_fresh()
	var kid := _person("Menina", 7.0)
	_at_hour(GameConstants.PLAY_HOURS[0])
	var deed: Dictionary = kid.get("deed", {})
	assert_eq(deed.get("kind", ""), "play")
	assert_eq(deed.get("anim", ""), GameConstants.ANIM_PLAY)
	life.complete_deed(k, kid, deed, [], GameConstants.PLAY_HOURS[0])
	assert_true(float(kid.mood.joy) > 0.0)


# --- Rain ---

func test_rainy_days_come_and_go() -> void:
	_fresh()
	var weather := WeatherSim.new()
	weather.setup(s)
	var rainy := 0
	for h in 24 * 20:
		weather.tick_hour(float(h))
		if s.raining(float(h)):
			rainy += 1
	assert_true(rainy > 0, "it rains some days")
	assert_true(rainy < 24 * 20 / 3, "but not most of the time: %d h" % rainy)


func test_rain_sends_people_home() -> void:
	var me := {pos = Vector3.ZERO, status = "resident", job = "", carrying = {}, home_pos = Vector3(10, 0, 0),
			door_pos = Vector3(10, 0, 2), is_work_time = true, is_sleep_time = false, raid = false, threat_pos = null,
			idle_offset = Vector3.ZERO, rain = true}
	var ctx := {work_target = {pos = Vector3(-20, 0, 0), reach = 1.0}, deposit_pos = Vector3.ZERO, seat_pos = Vector3.ZERO,
			campfire_pos = null, exit_pos = Vector3.ZERO}
	var d := PersonBrain.decide(me, ctx)
	assert_eq(d.goal, PersonBrain.Act.ENTER, "under a roof while it rains")


# --- Gossip ---

func test_friends_talking_share_their_views() -> void:
	_fresh()
	var a := _person("Linguaruda")
	var b := _person("Ouvinte")
	var c := _person("Malfalado")
	a.opinion = -0.8
	b.opinion = 0.4
	s.set_relation(a.id, c.id, -0.9) # a can't stand c
	var deed := Deeds.make("talk", k.center, 1.0, 0.0, 1.0, 5.0, {with = a.id, lead = false})
	life.complete_deed(k, b, deed, [], 18.0)
	assert_true(float(b.opinion) < 0.4, "b heard what a thinks of the founder")
	assert_true(s.relation(b.id, c.id) < 0.0, "and what a thinks of c")


# --- Final review fixes ---

func test_supper_then_the_evening_at_the_fire() -> void:
	_fresh()
	var p := _person("Ceia")
	on_screen.append(p.id)
	p.needs = {social = 0.4, faith = 0.0}
	p.hunger = 0.5
	_at_hour(GameConstants.MEAL_HOURS[2]) # supper first
	life.complete_deed(k, p, p.deed, [], GameConstants.MEAL_HOURS[2])
	p.deed = {}
	_at_hour(GameConstants.FIRESIDE_HOURS.x)
	assert_eq((p.get("deed", {}) as Dictionary).get("kind", ""), "fireside", "after supper, the fire")


func test_a_meal_settled_offscreen_feeds_only_once() -> void:
	_fresh()
	var p := _person("Uma vez só")
	p.hunger = 0.1 # already fed by the summarized meal
	var food := s.stock_of(k, R.FOOD)
	var deed := Deeds.make("meal", k.center, 1.0, 0.0, 1.0, 5.0, {})
	life.complete_deed(k, p, deed, [], 12.0)
	assert_eq(s.stock_of(k, R.FOOD), food, "not hungry: no second meal")


func test_short_ration_on_screen_too() -> void:
	_fresh()
	k.decrees.ration = "curta"
	var p := _person("Racionado")
	p.hunger = GameConstants.HUNGER_MEAL * float(GameConstants.GOV_RATION_EAT_AT.curta)
	assert_true(LifeRules.meal(p, k, s))
	assert_eq(float(p.hunger), 0.0, "a short ration meal comes later and takes the whole hunger")


func test_no_play_or_fire_in_the_rain() -> void:
	_fresh()
	var kid := _person("Molhado", 7.0)
	s.rain_from = 0.0
	s.rain_until = 48.0
	_at_hour(GameConstants.PLAY_HOURS[0])
	assert_true((kid.get("deed", {}) as Dictionary).is_empty(), "children stay in when it rains")


func test_spots_are_never_inside_a_building() -> void:
	_fresh()
	var kid := _person("Pequeno", 7.0)
	var home := s.add_building(B.HOUSE, k.center + Vector3(-12, 0, 0), 0, Color.WHITE, GameConstants.OWNER_KINGDOM)
	kid.home_id = home.id
	# A wall of houses all around the campfire and the door: every spot must still be outside them.
	for a in 8:
		var d := Vector3.FORWARD.rotated(Vector3.UP, TAU * a / 8.0)
		s.add_building(B.FENCE, fire.pos + d * GameConstants.MEAL_RING, 0, Color.WHITE, GameConstants.OWNER_KINGDOM)
	for h in 20:
		life._hour = float(h)
		for spot in [life._ring_spot(k, kid, GameConstants.MEAL_RING), life._play_spot(k, kid)]:
			for b in s.all_buildings():
				var r := BuildRules.footprint_rect(int(b.type), b.pos, int(b.rot))
				assert_true(not r.grow(0.3).has_point(Vector2(spot.x, spot.z)),
						"spot %s inside %s" % [spot, GameConstants.BUILD_NAMES[int(b.type)]])
