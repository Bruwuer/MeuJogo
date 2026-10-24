extends GameTest

const B := GameConstants.Building
const R := GameConstants.Res
const T := GameConstants.Trait
const P := GameConstants.Profession

var _gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
var _scatter := PropScatter.new(_gen, GameConstants.WORLD_SEED)


func _rng(s := 7) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func _person(traits: Array[int] = [T.WORKER, T.GENEROUS], profession := P.WOODCUTTER) -> Dictionary:
	var p := PersonGen.generate(_rng(), 0.0, profession)
	p.traits = traits
	p.opinion = 0.0
	return p


func _kingdom(s: WorldState, center := Vector3(100, 0, 100)) -> Dictionary:
	var seat := s.add_building(B.CABIN, center, 0)
	var k := s.add_kingdom("Teste", Color.RED, seat.pos, seat.id)
	k.stock = {}
	return k


## Adds `n` residents (already counted as people_ever).
func _residents(s: WorldState, k: Dictionary, n: int, profession := P.WOODCUTTER) -> void:
	for i in n:
		var p := s.add_person(_person([T.WORKER, T.GENEROUS], profession), k.center + Vector3(i, 0, 3), k.id)
		p.status = "resident"
		k.people_ever += 1


func test_founders_always_stay() -> void:
	var s := WorldState.new()
	var k := _kingdom(s) # empty stock, no house: everything says "leave"
	var snap := VillageRules.snapshot(s, k, 10.0)
	for i in 20:
		var d := VillageRules.stay_decision(_person([T.LONER, T.FEARFUL]), snap, _rng(i))
		assert_true(d.stay, "a founder stays")
		assert_eq(d.reason, GameConstants.STAY_REASONS.founder)
	k.people_ever = GameConstants.KINGDOM_FOUNDERS
	snap = VillageRules.snapshot(s, k, 10.0)
	var doubter := _person([T.LONER, T.FEARFUL], P.MERCHANT)
	doubter.opinion = -1.0
	assert_true(not VillageRules.stay_decision(doubter, snap, _rng()).stay,
			"after the founders, an empty kingdom does not convince")


func test_stays_with_food_and_shelter() -> void:
	var s := WorldState.new()
	var k := _kingdom(s)
	_residents(s, k, 3)
	s.add_building(B.HOUSE, k.center + Vector3(10, 0, 0), 0, Color.WHITE, GameConstants.OWNER_KINGDOM)
	s.add_stock(k, R.FOOD, 40)
	var snap := VillageRules.snapshot(s, k, 10.0)
	assert_eq(snap.free_beds, 3)
	assert_true(snap.food_days >= 2.0)
	var d := VillageRules.stay_decision(_person(), snap, _rng())
	assert_true(d.stay, "food and a free bed: stays (score %.2f)" % d.score)
	assert_true(d.reason == GameConstants.STAY_REASONS.house or d.reason == GameConstants.STAY_REASONS.food,
			"reason is the strongest factor: %s" % d.reason)


func test_leaves_without_shelter_reason() -> void:
	var s := WorldState.new()
	var k := _kingdom(s)
	_residents(s, k, 4)
	s.remove_building(k.seat_id) # no seat, no campfire, no house
	var snap := VillageRules.snapshot(s, k, 10.0)
	s.add_stock(k, R.FOOD, 0)
	var d := VillageRules.stay_decision(_person(), snap, _rng())
	assert_true(not d.stay)
	assert_true(d.reason == GameConstants.LEAVE_REASONS.no_food or d.reason == GameConstants.LEAVE_REASONS.no_shelter,
			"reason: %s" % d.reason)
	k.stock[R.FOOD] = 10 # one day: neither plenty nor none
	snap = VillageRules.snapshot(s, k, 10.0)
	d = VillageRules.stay_decision(_person([T.WORKER, T.GENEROUS], P.MERCHANT), snap, _rng())
	assert_eq(d.reason, GameConstants.LEAVE_REASONS.no_shelter)


func test_fearful_avoids_raided_kingdom() -> void:
	var s := WorldState.new()
	var k := _kingdom(s)
	_residents(s, k, 4)
	s.add_stock(k, R.FOOD, 40)
	k.last_raid_hour = 5.0
	var snap := VillageRules.snapshot(s, k, 10.0)
	assert_true(snap.recent_raid)
	var brave := VillageRules.stay_decision(_person([T.BRAVE, T.WORKER], P.MERCHANT), snap, _rng())
	var fearful := VillageRules.stay_decision(_person([T.FEARFUL, T.WORKER], P.MERCHANT), snap, _rng())
	assert_true(fearful.score < brave.score - 0.3, "raids weigh more for the fearful")
	assert_true(not fearful.stay)
	assert_eq(fearful.reason, GameConstants.LEAVE_REASONS.raid)
	k.last_raid_hour = 10.0 - GameConstants.RAID_RECENT_HOURS - 1.0
	assert_true(not VillageRules.snapshot(s, k, 10.0).recent_raid, "old raids are forgotten")


func test_contentment_drops_hungry() -> void:
	var s := WorldState.new()
	var k := _kingdom(s)
	_residents(s, k, 2)
	var snap := VillageRules.snapshot(s, k, 10.0)
	var p := s.residents(k.id)[0]
	var hungry := VillageRules.hourly_contentment(p, snap, false)
	var fed := VillageRules.hourly_contentment(p, snap, true)
	assert_true(hungry < 0.0, "hungry, sleeping by the seat: drops (%.3f)" % hungry)
	assert_near(fed - hungry, GameConstants.CONTENT_FED - GameConstants.CONTENT_HUNGRY, 0.0001)
	p.hunger = 0.9
	assert_eq(VillageRules.leave_reason(p, snap), GameConstants.LEAVE_REASONS_PAST.hunger)


func test_eat_prefers_food() -> void:
	var s := WorldState.new()
	var k := _kingdom(s)
	s.add_stock(k, R.FOOD, 1)
	s.add_stock(k, R.BERRIES, 1)
	var p := _person()
	p.hunger = 0.2
	assert_true(VillageRules.eat(p, k, s), "not hungry yet: fed")
	assert_eq(s.stock_of(k, R.FOOD), 1, "eats only when hungry")
	p.hunger = 0.6
	assert_true(VillageRules.eat(p, k, s))
	assert_eq(s.stock_of(k, R.FOOD), 0, "Comida first")
	assert_eq(s.stock_of(k, R.BERRIES), 1)
	assert_near(p.hunger, 0.1, 0.0001)
	p.hunger = 0.7
	assert_true(VillageRules.eat(p, k, s))
	assert_eq(s.stock_of(k, R.BERRIES), 0, "then Frutas")
	p.hunger = 0.7
	assert_true(not VillageRules.eat(p, k, s), "nothing left: hungry")


func test_project_order() -> void:
	var s := WorldState.new()
	var k := _kingdom(s)
	_residents(s, k, 1)
	s.add_stock(k, R.FOOD, 1) # food for less than 2 days
	assert_eq(VillageRules.next_project(VillageRules.snapshot(s, k, 0.0)), B.FARM, "food first")
	s.add_stock(k, R.FOOD, 100)
	assert_eq(VillageRules.next_project(VillageRules.snapshot(s, k, 0.0)), B.HOUSE, "then the homeless")
	var house := s.add_building(B.HOUSE, k.center + Vector3(10, 0, 0), 0, Color.WHITE, GameConstants.OWNER_KINGDOM)
	s.residents(k.id)[0].home_id = house.id
	var farm := s.add_building(B.FARM, k.center + Vector3(-10, 0, 0), 0, Color.WHITE, GameConstants.OWNER_KINGDOM)
	assert_eq(VillageRules.next_project(VillageRules.snapshot(s, k, 0.0)), B.STORAGE, "1 farm feeds 1: storage")
	_residents(s, k, 2) # 3 residents, 2 homeless, 2 free beds left
	assert_eq(VillageRules.next_project(VillageRules.snapshot(s, k, 0.0)), B.WELL, "beds enough: well at 3")
	_residents(s, k, 1) # 4: one more homeless than beds
	assert_eq(VillageRules.next_project(VillageRules.snapshot(s, k, 0.0)), B.HOUSE)
	s.add_building(B.HOUSE, k.center + Vector3(10, 0, 10), 0, Color.WHITE, GameConstants.OWNER_KINGDOM)
	s.add_building(B.FARM, k.center + Vector3(-10, 0, 10), 0, Color.WHITE, GameConstants.OWNER_KINGDOM)
	assert_eq(VillageRules.next_project(VillageRules.snapshot(s, k, 0.0)), B.MARKET, "market at 4")
	k.site_id = 99
	assert_eq(VillageRules.next_project(VillageRules.snapshot(s, k, 0.0)), -1, "one site at a time")
	assert_true(farm.id > 0)


func test_pick_site_valid_and_away_from_dens() -> void:
	var s := WorldState.new()
	var center := TestSpots.flat_clear(_gen, _scatter, B.CABIN, 8.0)
	var k := _kingdom(s, center)
	var den := center + Vector3(60, 0, 0)
	s.add_pack("lobo", den)
	var r := VillageRules.pick_site(B.HOUSE, k, s, _gen, _scatter, [], _rng())
	assert_true(r.ok, "found a place for a house")
	if not r.ok:
		return
	assert_true(BuildRules.check_site(B.HOUSE, r.pos, r.rot, _gen, _scatter, s).ok, "the place is valid")
	assert_true(Vector2(r.pos.x - den.x, r.pos.z - den.z).length() > GameConstants.TERRITORY_RADIUS, "outside the den's territory")
	assert_true(Vector2(r.pos.x - center.x, r.pos.z - center.z).length() < k.radius, "inside the kingdom")
	var rect := BuildRules.footprint_rect(B.HOUSE, r.pos, r.rot).grow(GameConstants.SITE_GAP - 0.01)
	var seat := s.building(k.seat_id)
	assert_true(not rect.intersects(BuildRules.footprint_rect(B.CABIN, seat.pos, seat.rot)), "keeps a corridor")
	var again := VillageRules.pick_site(B.HOUSE, k, s, _gen, _scatter, [], _rng())
	assert_eq(again.pos, r.pos, "deterministic")


func test_choose_job_by_profession_and_stock() -> void:
	var s := WorldState.new()
	var k := _kingdom(s)
	_residents(s, k, 2)
	var snap := VillageRules.snapshot(s, k, 10.0)
	assert_eq(VillageRules.choose_job(_person([T.WORKER, T.BRAVE], P.WOODCUTTER), snap), "wood")
	assert_eq(VillageRules.choose_job(_person([T.WORKER, T.BRAVE], P.MASON), snap), "stone")
	s.add_stock(k, R.WOOD, GameConstants.KINGDOM_STOCK_TARGET[R.WOOD])
	snap = VillageRules.snapshot(s, k, 10.0)
	assert_eq(VillageRules.choose_job(_person([T.WORKER, T.BRAVE], P.WOODCUTTER), snap), "stone",
			"enough wood: fetches what is missing")
	assert_eq(VillageRules.choose_job(_person([T.WORKER, T.BRAVE], P.FARMER), snap), "stone", "no farm yet")
	s.add_building(B.FARM, k.center + Vector3(-10, 0, 0), 0, Color.WHITE, GameConstants.OWNER_KINGDOM)
	s.add_stock(k, R.STONE, 100)
	s.add_stock(k, R.FOOD, 100)
	snap = VillageRules.snapshot(s, k, 10.0)
	assert_eq(VillageRules.choose_job(_person([T.WORKER, T.BRAVE], P.FARMER), snap), "farm")
	assert_eq(VillageRules.choose_job(_person([T.WORKER, T.BRAVE], P.MERCHANT), snap), "idle", "nothing to do")
	k.site_id = 1
	snap.site = 1
	assert_eq(VillageRules.choose_job(_person([T.WORKER, T.BRAVE], P.MERCHANT), snap), "build", "helps on the site")
	assert_eq(VillageRules.choose_job(_person([T.WORKER, T.BRAVE], P.BUILDER), snap), "build")
	k.stock[R.FOOD] = 0
	k.site_id = -1
	snap = VillageRules.snapshot(s, k, 10.0)
	assert_eq(VillageRules.choose_job(_person([T.WORKER, T.BRAVE], P.GATHERER), snap), "berries")
	assert_eq(VillageRules.needed_profession(snap), P.FARMER, "a farm without a farmer and little food")
