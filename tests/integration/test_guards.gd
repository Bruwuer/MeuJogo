extends GameTest

const P := GameConstants.Profession


func _k() -> Dictionary:
	return {id = 1, center = Vector3(300, 0, 300), radius = GameConstants.KINGDOM_RADIUS}


func test_guard_job() -> void:
	var rng := RandomNumberGenerator.new()
	var g := PersonGen.generate(rng)
	g.profession = P.GUARD
	g.age = 30.0
	assert_eq(VillageRules.choose_job(g, {farms = 0, site = -1, has_market = false}), "guard")


func test_guard_attacks_hostile_in_territory() -> void:
	var k := _k()
	var t := PeopleManager.guard_target(k, 7, k.center, 0.0, [{id = 3, pos = k.center + Vector3(10, 0, 0)}])
	assert_eq(t.kind, "guard_attack")
	assert_eq(t.id, 3)
	assert_true(float(t.reach) <= GameConstants.GUARD_REACH + 0.001)


func test_guard_patrols_otherwise() -> void:
	var k := _k()
	var far := [{id = 3, pos = k.center + Vector3(k.radius + 30.0, 0, 0)}]
	var a := PeopleManager.guard_target(k, 7, k.center, 0.0, far)
	var b := PeopleManager.guard_target(k, 7, k.center, 60.0, [])
	assert_eq(a.kind, "patrol", "hostiles far outside the territory are ignored")
	assert_true(Vector2(a.pos.x - k.center.x, a.pos.z - k.center.z).length() <= k.radius, "patrols inside the territory")
	assert_true((a.pos as Vector3).distance_to(b.pos) > 1.0, "the patrol moves on")


func test_guard_rest_hours() -> void:
	assert_true(VillageRules.guard_on_duty(2.0), "guards watch at night")
	assert_true(VillageRules.guard_on_duty(10.0))
	assert_true(not VillageRules.guard_on_duty(GameConstants.GUARD_REST_HOURS.x + 1.0), "and rest in the afternoon")


func test_guards_weaken_offscreen_raids() -> void:
	var none := PackSim.raid_strength(100.0, 0)
	var two := PackSim.raid_strength(100.0, 2)
	var many := PackSim.raid_strength(100.0, 50)
	assert_near(none, 100.0, 0.001)
	assert_true(two < none and many < two)
	assert_true(many >= 100.0 * GameConstants.GUARD_RAID_FLOOR - 0.001, "a raid is never fully stopped on paper")


func test_guard_holds_a_spear() -> void:
	var lib := ModelLibrary.new()
	add_child(lib)
	lib.start_loading()
	while not lib.is_ready():
		await get_tree().process_frame
	var rng := RandomNumberGenerator.new()
	var rec := PersonGen.generate(rng)
	rec.profession = P.GUARD
	rec.age = 30.0
	var s := WorldState.new()
	var r := s.add_person(rec, Vector3.ZERO, 1)
	var n := Person.new()
	add_child(n)
	n.setup(r, lib, null)
	var holders := n.find_children("Weapon", "Node3D", true, false)
	assert_eq(holders.size(), 1, "a weapon holder on the right hand")
	if not holders.is_empty():
		assert_eq((holders[0] as Node).get_child_count(), 1, "holding the spear")
