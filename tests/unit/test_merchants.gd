extends GameTest
## Life (stage 10): wandering merchants walk from kingdom to kingdom with a pack, trade with each
## kingdom's stock when they arrive, and trade with the player (bread, arrows, coins).

const B := GameConstants.Building
const R := GameConstants.Res

var s: WorldState
var society: SocietySim
var houses: HouseSim
var merchants: MerchantSim
var a: Dictionary
var b: Dictionary


func _fresh() -> void:
	s = WorldState.new()
	s.seed = 21
	society = SocietySim.new()
	houses = HouseSim.new()
	merchants = MerchantSim.new()
	society.setup(s, func(_k: Dictionary, _t: String) -> void: pass, func(_k: Dictionary) -> bool: return false,
			func(_k: Dictionary) -> Dictionary: return {})
	houses.setup(s, func(_k: Dictionary, _t: String) -> void: pass, society)
	merchants.setup(s, houses)
	a = _realm("Aldor", Vector3(200, 0, 200))
	b = _realm("Bruma", Vector3(450, 0, 200))


func _realm(name: String, at: Vector3) -> Dictionary:
	var seat := s.add_building(B.CABIN, at, 0, Color.WHITE, GameConstants.OWNER_KINGDOM)
	return s.add_kingdom(name, Color.RED, at, seat.id)


func _merchant() -> Dictionary:
	var list := s.all_people().filter(func(p: Dictionary) -> bool: return p.status == "merchant")
	return list[0] if not list.is_empty() else {}


func _run(from: float, hours: int) -> float:
	for i in hours:
		var h := from + i
		for k in s.kingdoms():
			houses.tick_hour(k, h)
		merchants.tick_hour(h)
	return from + hours


func _logged(k: Dictionary, part: String) -> bool:
	return s.chronicle_all(k.id, 500).any(func(e: Dictionary) -> bool: return (e.text as String).contains(part))


func test_a_merchant_comes_and_walks_to_a_kingdom() -> void:
	_fresh()
	_run(0.0, int(GameConstants.MERCHANT_FIRST_HOURS) + 1)
	var m := _merchant()
	assert_true(not m.is_empty(), "a merchant came")
	assert_eq(int(m.profession), GameConstants.Profession.MERCHANT)
	assert_eq((m.deed as Dictionary).get("kind", ""), "trade", "on the way to a seat")
	assert_true((m.route as Array).size() >= 1)
	assert_true(not s.residents(a.id).has(m), "a merchant lives nowhere")


func test_the_merchant_trades_on_arrival_and_moves_on() -> void:
	_fresh()
	s.add_stock(a, R.WOOD, 200) # surplus to sell
	a.stock[R.FOOD] = 0
	a.stock[R.BERRIES] = 0 # hungry
	for i in 4:
		var p := s.add_person(PersonGen.generate(RandomNumberGenerator.new()), a.center, a.id)
		p.merge({status = "resident", age = 30.0}, true)
	var h := _run(0.0, int(GameConstants.MERCHANT_FIRST_HOURS) + 1)
	var m := _merchant()
	var first: int = int(m.kingdom_id)
	_run(h, 30)
	var k := s.kingdom(first)
	assert_true(_logged(k, "mercador"), "the trade is in the ADM log")
	if first == a.id:
		assert_true(s.stock_of(a, R.FOOD) > 0, "the hungry kingdom got food")
		assert_true(s.stock_of(a, R.WOOD) < 220, "and sold its surplus wood")
	m = s.person(int(m.id))
	assert_true(m.is_empty() or int(m.kingdom_id) != first or m.status == "leaving", "the merchant moved on")


func test_the_merchant_leaves_after_the_last_stop() -> void:
	_fresh()
	_run(0.0, int(GameConstants.MERCHANT_FIRST_HOURS) + 24 * 4)
	var gone := s.all_people().filter(func(p: Dictionary) -> bool:
		return p.status == "merchant" and (p.route as Array).is_empty() and (p.deed as Dictionary).is_empty())
	assert_eq(gone.size(), 0, "no merchant is stuck with nowhere to go")


func test_player_buys_bread_and_arrows_and_sells_wood() -> void:
	_fresh()
	var m := merchants.spawn(0.0)
	s.add_resource(R.WOOD, 20)
	assert_true(MerchantRules.trade(s, m, "sell_wood").contains("vendeu"))
	assert_eq(s.get_resource(R.WOOD), 20 - GameConstants.MERCHANT_SELL_LOT)
	var coins := s.get_resource(R.COINS)
	assert_eq(coins, GameConstants.MERCHANT_WOOD_PRICE)
	s.add_resource(R.COINS, 20)
	assert_true(MerchantRules.trade(s, m, "bread").contains("comprou"))
	assert_eq(s.get_resource(R.BREAD), 1)
	var arrows := s.get_resource(R.ARROWS)
	MerchantRules.trade(s, m, "arrows")
	assert_eq(s.get_resource(R.ARROWS), arrows + GameConstants.MERCHANT_ARROW_LOT)
	s.add_resource(R.COINS, -s.get_resource(R.COINS))
	assert_true(MerchantRules.trade(s, m, "bread").contains("moedas"), "no coins, no bread")


func test_bread_heals_more_than_fruit() -> void:
	assert_true(GameConstants.BREAD_HEAL > GameConstants.EAT_HEAL)


func test_merchant_pays_fairly_and_does_not_give_food_away() -> void:
	_fresh()
	var m := merchants.spawn(0.0)
	m.coins = 1
	s.add_stock(a, R.WOOD, GameConstants.MERCHANT_SURPLUS + 20)
	var before := s.stock_of(a, R.WOOD)
	MerchantRules.kingdom_trade(s, m, a)
	assert_eq(before - s.stock_of(a, R.WOOD), GameConstants.MERCHANT_SURPLUS_RATE, "one coin buys only its worth")
	a.stock = {R.FOOD: 0, R.BERRIES: 0}
	for i in 3:
		var p := s.add_person(PersonGen.generate(RandomNumberGenerator.new()), a.center, a.id)
		p.merge({status = "resident", age = 30.0}, true)
	var food := int(m.goods[R.FOOD])
	MerchantRules.kingdom_trade(s, m, a)
	assert_eq(int(m.goods[R.FOOD]), food, "no wood or stone to pay: no food sold")


func test_merchant_moves_along_offscreen() -> void:
	_fresh()
	var m := merchants.spawn(0.0)
	var first := s.kingdom(int(m.kingdom_id))
	_run(0.0, 30)
	m = s.person(int(m.id))
	if not m.is_empty() and m.status == "merchant":
		assert_true(PackSim._flat_dist(m.pos, first.center) < 15.0 or int(m.kingdom_id) != first.id,
				"the merchant is where the trade happened")
