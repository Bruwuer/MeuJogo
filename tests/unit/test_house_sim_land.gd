extends GameTest

const B := GameConstants.Building
const G := GameConstants.Goal
const TR := GameConstants.Tradition

var gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
var scatter := PropScatter.new(gen, GameConstants.WORLD_SEED)
var s := WorldState.new()
var k: Dictionary
var house := HouseSim.new()
var society := SocietySim.new()


func _init() -> void:
	s.seed = GameConstants.WORLD_SEED
	var center := TestSpots.flat_clear(gen, scatter, B.CABIN)
	k = s.add_kingdom("Ravmia", Color.RED, center, -1)
	society.setup(s, func(_k: Dictionary, _t: String) -> void: pass, func(_k: Dictionary) -> bool: return true,
			func(_k: Dictionary) -> Dictionary: return {})
	house.setup(s, func(_k: Dictionary, _t: String) -> void: pass, society, gen)


func _member(name: String, female: bool, age := 30.0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var p := PersonGen.generate(rng)
	p.name = name
	p.female = female
	p.age = age
	var rec := s.add_person(p, k.center, k.id)
	rec.status = "resident"
	return rec


func _house(name: String, wealth: float, offset := Vector3.ZERO) -> Dictionary:
	var head := _member(name, false)
	var f := s.add_family(name, Crest.generate(RandomNumberGenerator.new(), []), k.id, head.id, 0.0)
	f.house_init = true
	f.tradition = TR.FARMERS
	f.wealth = wealth
	head.family_id = f.id
	var home := s.add_building(B.HOUSE, k.center + offset, 0, Color.WHITE, head.id)
	head.home_id = home.id
	return f


func _stakes_of(f: Dictionary) -> Array:
	return s.all_buildings().filter(func(b: Dictionary) -> bool: return b.type == B.STAKE and b.get("family_id", -1) == f.id)


func test_plot_valid_and_paid() -> void:
	var f := _house("Vale", 100.0)
	assert_true(house.acquire_plot(k, f), "a free plot near home")
	assert_eq((f.plots as Array).size(), 1)
	assert_near(f.wealth, 100.0 - GameConstants.PLOT_PRICE, 0.001)
	var rect: Rect2 = f.plots[0]
	assert_eq(rect.size, Vector2.ONE * GameConstants.PLOT_SIZE)
	assert_true(Vector2(k.center.x, k.center.z).distance_to(rect.get_center()) <= k.radius, "inside the territory")
	assert_eq(_stakes_of(f).size(), 4, "four corner stakes")
	for b in s.all_buildings():
		if b.type == B.HOUSE:
			assert_true(not rect.grow(-0.01).intersects(BuildRules.footprint_rect(b.type, b.pos, b.rot)), "plot over a house")


func test_plot_needs_money() -> void:
	var f := _house("Pobre", 5.0)
	assert_true(not house.acquire_plot(k, f))
	assert_eq((f.plots as Array).size(), 0)


func test_plot_limit_and_no_overlap() -> void:
	var f := _house("Rico", 10000.0)
	for i in GameConstants.PLOTS_MAX + 3:
		house.acquire_plot(k, f)
	assert_eq((f.plots as Array).size(), GameConstants.PLOTS_MAX)
	var plots: Array = f.plots
	for i in plots.size():
		for j in range(i + 1, plots.size()):
			assert_true(not (plots[i] as Rect2).grow(-0.01).intersects(plots[j]), "plots overlap")


func test_buy_plot_from_poor_house() -> void:
	var seller := _house("Seixas", 10.0, Vector3(12, 0, 0))
	seller.wealth = 1000.0
	house.acquire_plot(k, seller)
	house.acquire_plot(k, seller)
	seller.wealth = 10.0
	var buyer := _house("Barros", 500.0, Vector3(-12, 0, 0))
	assert_true(house.buy_plot(k, buyer, seller))
	assert_eq((buyer.plots as Array).size(), 1)
	assert_eq((seller.plots as Array).size(), 1)
	assert_true(seller.wealth > 10.0)
	assert_eq(_stakes_of(buyer).size(), 4, "the stakes change hands")


func test_upgrade_raises_level_and_capacity() -> void:
	var f := _house("Ferreira", 500.0)
	var head := s.person(f.head_id)
	var home := s.building(head.home_id)
	assert_eq(HouseRules.beds(home), 4)
	assert_true(house.upgrade(k, f))
	assert_eq(int(home.house_level), 1)
	assert_near(f.wealth, 500.0 - GameConstants.UPGRADE_PRICE[0], 0.001)
	assert_eq(HouseRules.beds(home), 6)
	assert_eq(SocietySim.room(s, home), 6 - SocietySim.occupants(s, home.id))
	assert_true(house.upgrade(k, f))
	assert_eq(int(home.house_level), 2)
	assert_true(not house.upgrade(k, f), "a manor is the top")


func _daily(day: int) -> float:
	return day * 24.0 + GameConstants.DEED_HOUR


func test_goal_success_event() -> void:
	var f := _house("Souto", 20.0)
	f.goal = {kind = G.WEALTH, target_id = -1, deadline_hour = 1000.0}
	f.wealth = GameConstants.WEALTH_COMFORT + 1.0
	house.tick_hour(k, _daily(1))
	assert_true(s.chronicle(k.id, 20).any(func(e: Dictionary) -> bool: return (e.text as String).contains("conseguiu")))
	assert_true(f.goal.is_empty() or f.goal.kind != G.WEALTH, "a reached goal is replaced")


func test_goal_failure_is_a_broken_expectation() -> void:
	var f := _house("Pinto", 0.0)
	var member := _member("Luzia", true)
	member.family_id = f.id
	member.contentment = 0.6
	f.goal = {kind = G.UPGRADE, target_id = -1, deadline_hour = 10.0, start_level = 0}
	house.tick_hour(k, _daily(2))
	assert_true(s.chronicle(k.id, 20).any(func(e: Dictionary) -> bool: return (e.text as String).contains("não conseguiu")))
	assert_true(member.contentment < 0.6, "members are let down")


func test_goal_picked_when_missing() -> void:
	var f := _house("Novo", 10.0)
	f.goal = {}
	house.tick_hour(k, _daily(1))
	assert_true(not f.goal.is_empty(), "a poor House sets itself a goal")
	assert_true(f.goal.has("deadline_hour"))
