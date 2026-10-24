extends GameTest

const _PATH := "user://test_people_state.bin"
const B := GameConstants.Building
const R := GameConstants.Res


func _person(s := 1) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return PersonGen.generate(r)


func _kingdom(s: WorldState) -> Dictionary:
	var seat := s.add_building(B.CABIN, Vector3(100, 0, 100), 0)
	return s.add_kingdom("Teste", Color.RED, seat.pos, seat.id)


func test_people_roundtrip() -> void:
	var s := WorldState.new()
	var k := _kingdom(s)
	var a := s.add_person(_person(1), Vector3(100, 2, 104), k.id, 5.0)
	var b := s.add_person(_person(2), Vector3(300, 2, 300))
	a.status = "resident"
	a.hunger = 0.4
	a.carrying = { R.WOOD: 3 }
	s.fame = 0.3
	assert_eq(a.home_id, -1)
	assert_eq(b.kingdom_id, -1)
	assert_eq(b.status, "traveler")
	assert_near(a.contentment, GameConstants.PERSON_START_CONTENTMENT, 0.0001)
	assert_eq(s.save_to(_PATH), OK)
	var l := WorldState.load_from(_PATH)
	assert_eq(l.all_people().size(), 2)
	assert_eq(l.person(a.id).name, a.name)
	assert_eq(l.person(a.id).looks, a.looks)
	assert_eq(l.person(a.id).carrying, { R.WOOD: 3 })
	assert_near(l.person(a.id).hunger, 0.4, 0.0001)
	assert_eq(l.residents(k.id).size(), 1)
	assert_eq(l.people_in(ChunkMath.world_to_chunk(a.pos)).size(), 1)
	assert_near(l.fame, 0.3, 0.0001)
	var c := l.add_person(_person(3), Vector3(1, 0, 1))
	assert_true(c.id != a.id and c.id != b.id, "ids continue after load")


func test_move_person_reindexes() -> void:
	var s := WorldState.new()
	var a := s.add_person(_person(), Vector3(10, 0, 10))
	s.move_person(a.id, Vector3(80, 0, 10))
	assert_eq(s.people_in(Vector2i(0, 0)).size(), 0)
	assert_eq(s.people_in(Vector2i(2, 0)).size(), 1)
	s.remove_person(a.id)
	assert_eq(s.people_in(Vector2i(2, 0)).size(), 0)
	assert_true(s.person(a.id).is_empty())


func test_kingdom_start_stock() -> void:
	var s := WorldState.new()
	var k := _kingdom(s)
	for res in GameConstants.KINGDOM_START_STOCK:
		assert_eq(s.stock_of(k, res), GameConstants.KINGDOM_START_STOCK[res])
	assert_eq(k.site_id, -1)
	assert_eq(s.kingdom(k.id), k)


func test_stock_spend_and_add() -> void:
	var s := WorldState.new()
	var k := _kingdom(s)
	s.add_stock(k, R.STONE, 5)
	assert_eq(s.stock_of(k, R.STONE), GameConstants.KINGDOM_START_STOCK.get(R.STONE, 0) + 5)
	assert_true(not s.spend_stock(k, { R.STONE: 999 }), "can't overspend")
	assert_eq(s.stock_of(k, R.STONE), GameConstants.KINGDOM_START_STOCK.get(R.STONE, 0) + 5, "nothing spent on failure")
	assert_true(s.spend_stock(k, { R.STONE: 5 }))
	assert_eq(s.get_resource(R.STONE), 0, "player inventory untouched")


func test_site_lifecycle() -> void:
	var s := WorldState.new()
	var k := _kingdom(s)
	s.add_stock(k, R.WOOD, 100)
	s.add_stock(k, R.STONE, 100)
	var wood_before := s.stock_of(k, R.WOOD)
	var site := s.add_site(B.HOUSE, Vector3(110, 0, 100), 1, k, 3.0)
	assert_true(not site.is_empty())
	assert_true(site.site)
	assert_eq(site.owner, GameConstants.OWNER_KINGDOM)
	assert_eq(k.site_id, site.id)
	assert_eq(s.stock_of(k, R.WOOD), wood_before - GameConstants.BUILD_COST[B.HOUSE][R.WOOD], "cost reserved")
	assert_true(not s.add_progress(site.id, 1.0, 4.0), "not done after 1 h")
	assert_near(site.progress, 1.0 / GameConstants.BUILD_WORK_HOURS[B.HOUSE], 0.0001)
	assert_true(s.add_progress(site.id, 100.0, 5.0), "done")
	assert_true(not site.has("site"), "no longer a site")
	assert_eq(k.site_id, -1)
	assert_eq(s.stock_of(k, R.WOOD), wood_before - GameConstants.BUILD_COST[B.HOUSE][R.WOOD], "nothing refunded")


func test_site_needs_stock() -> void:
	var s := WorldState.new()
	var k := _kingdom(s)
	assert_true(s.add_site(B.HOUSE, Vector3(110, 0, 100), 0, k, 0.0).is_empty(), "start stock can't pay a house")
	assert_eq(k.site_id, -1)


func test_destroyed_site_refunds_stock() -> void:
	var s := WorldState.new()
	var k := _kingdom(s)
	s.add_stock(k, R.WOOD, 100)
	var before := s.stock_of(k, R.WOOD)
	var site := s.add_site(B.FARM, Vector3(110, 0, 100), 0, k, 0.0)
	var removed := []
	s.building_removed.connect(func(rec: Dictionary) -> void: removed.append(rec.id))
	s.remove_building(site.id)
	assert_eq(s.stock_of(k, R.WOOD), before)
	assert_eq(k.site_id, -1)
	assert_eq(removed, [site.id])


func test_removed_house_clears_home() -> void:
	var s := WorldState.new()
	var k := _kingdom(s)
	var house := s.add_building(B.HOUSE, Vector3(110, 0, 100), 0, Color.WHITE, GameConstants.OWNER_KINGDOM)
	var a := s.add_person(_person(), Vector3(110, 0, 104), k.id)
	a.home_id = house.id
	a.inside = house.id
	s.damage_building(house.id, 99999.0)
	assert_true(s.building(house.id).is_empty())
	assert_eq(a.home_id, -1)
	assert_eq(a.inside, -1)


func test_loads_stage4_save() -> void:
	var data := {
		version = GameConstants.WORLDGEN_VERSION, seed = 7, time_of_day = 0.4, day = 3,
		player_position = Vector3(5, 1, 5), has_player_position = true, removed = {}, resources = { 0: 4 },
		buildings = [{ id = 1, type = B.CABIN, pos = Vector3(100, 0, 100), rot = 0, color = Color.WHITE }],
		kingdoms = [{ id = 1, name = "Velho", color = Color.BLUE, center = Vector3(100, 0, 100), radius = 40.0, seat_id = 1 }],
		next_building_id = 2, building_hp = {}, creatures = [], next_creature_id = 1, packs = [], next_pack_id = 1,
		visited = [],
	}
	assert_eq(WorldState.write_payload(_PATH, data), OK)
	var l := WorldState.load_from(_PATH)
	assert_true(l != null)
	var k: Dictionary = l.kingdoms()[0]
	assert_eq(k.site_id, -1)
	assert_true(k.stock is Dictionary)
	assert_eq(l.stock_of(k, R.WOOD), 0, "old kingdoms start with an empty stock")
	assert_eq(l.building(1).owner, GameConstants.OWNER_PLAYER)
	assert_eq(l.all_people().size(), 0)
	assert_true(l.add_person(_person(), Vector3(1, 0, 1)).id >= 1)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for suffix in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(_PATH + suffix):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(_PATH + suffix))
