extends GameTest
## Deeds: what a person goes and does for their House (stage 7, embodied actions).

const A := PersonBrain.Act
const P := GameConstants.Profession

var s := WorldState.new()
var k: Dictionary
var house := HouseSim.new()
var society := SocietySim.new()
var nodes: Array[int] = []
var done: Array = []


func _init() -> void:
	s.seed = 5
	k = s.add_kingdom("Ravmia", Color.RED, Vector3(100, 0, 100), -1)
	society.setup(s, func(_k: Dictionary, _t: String) -> void: pass, func(_k: Dictionary) -> bool: return true,
			func(_k: Dictionary) -> Dictionary: return {})
	house.setup(s, func(_k: Dictionary, _t: String) -> void: pass, society)
	house.has_node = func(id: int) -> bool: return nodes.has(id)
	house.deed_completed.connect(func(rec: Dictionary, deed: Dictionary, seen: Array) -> void: done.append([rec, deed, seen]))


func _person(name: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var rec := s.add_person(PersonGen.generate(rng), Vector3(100, 0, 100), k.id)
	rec.status = "resident"
	rec.age = 30.0
	return rec


func test_next_window_today_or_tomorrow() -> void:
	assert_eq(Deeds.next_window(10.0, 16.0, 19.0), Vector2(16, 19), "later today")
	assert_eq(Deeds.next_window(20.0, 16.0, 19.0), Vector2(40, 43), "tomorrow when today's is over")
	assert_eq(Deeds.next_window(17.0, 16.0, 19.0), Vector2(16, 19), "the window we are in")


func test_next_window_across_midnight() -> void:
	assert_eq(Deeds.next_window(10.0, 23.0, 3.0), Vector2(23, 27))
	assert_eq(Deeds.next_window(25.0, 23.0, 3.0), Vector2(23, 27), "1h is still last night's window")
	assert_eq(Deeds.next_window(28.0, 23.0, 3.0), Vector2(47, 51))


func test_is_due() -> void:
	var d := Deeds.make("x", Vector3.ZERO, 1.0, 16.0, 19.0, 5.0)
	assert_true(not Deeds.is_due(d, 15.9))
	assert_true(Deeds.is_due(d, 16.0))
	assert_true(not Deeds.is_due(d, 19.0))
	assert_true(Deeds.expired(d, 19.0))


func test_seen_chance() -> void:
	assert_eq(Deeds.seen_chance(0), 0.0, "nobody awake, nobody sees")
	assert_true(Deeds.seen_chance(3) > Deeds.seen_chance(1))
	assert_true(Deeds.seen_chance(100) <= 1.0)


func _me(extra: Dictionary) -> Dictionary:
	var me := {pos = Vector3.ZERO, status = "resident", job = "", carrying = {}, home_pos = null, door_pos = Vector3(5, 0, 0),
			is_work_time = false, is_sleep_time = true, raid = false, threat_pos = null, deed = {pos = Vector3(30, 0, 0), reach = 1.0}}
	me.merge(extra, true)
	return me


func _ctx() -> Dictionary:
	return {work_target = {}, deposit_pos = Vector3.ZERO, seat_pos = Vector3.ZERO, campfire_pos = null, exit_pos = Vector3.ZERO}


func test_brain_deed_beats_sleep_and_raid() -> void:
	var d := PersonBrain.decide(_me({}), _ctx())
	assert_eq(d.goal, A.DEED, "a deed takes them out of bed")
	assert_eq(d.act, A.WALK)
	assert_eq(d.target_pos, Vector3(30, 0, 0))
	d = PersonBrain.decide(_me({raid = true}), _ctx())
	assert_eq(d.goal, A.DEED)
	d = PersonBrain.decide(_me({pos = Vector3(30, 0, 0)}), _ctx())
	assert_eq(d.act, A.DEED, "there: doing it")


func test_brain_flee_beats_deed() -> void:
	var d := PersonBrain.decide(_me({threat_pos = Vector3(1, 0, 0)}), _ctx())
	assert_eq(d.act, A.FLEE)


func test_offscreen_deed_resolves_when_due() -> void:
	done.clear()
	var p := _person("Ana")
	p.deed = Deeds.make("visit", Vector3(110, 0, 100), 1.0, 30.0, 33.0, 5.0)
	house.tick_hour(k, 29.0)
	assert_true(not (p.deed as Dictionary).is_empty(), "not yet")
	house.tick_hour(k, 30.0)
	assert_true((p.deed as Dictionary).is_empty(), "done offscreen at its hour")
	assert_eq(done.size(), 1)


func test_deed_with_node_waits_for_the_person() -> void:
	done.clear()
	var p := _person("Bia")
	nodes.append(p.id)
	p.deed = Deeds.make("visit", Vector3(110, 0, 100), 1.0, 30.0, 33.0, 5.0)
	house.tick_hour(k, 31.0)
	assert_true(not (p.deed as Dictionary).is_empty(), "a loaded person walks there for real")
	house.tick_hour(k, 33.0)
	assert_true((p.deed as Dictionary).is_empty(), "past the window it is settled anyway")
	assert_eq(done.size(), 1)
	assert_eq(done[0][2], [], "nobody saw an expired deed")
	nodes.clear()


func test_complete_deed_clears_and_reports_witnesses() -> void:
	done.clear()
	var p := _person("Caio")
	p.deed = Deeds.make("visit", Vector3(110, 0, 100), 1.0, 30.0, 33.0, 5.0)
	house.complete_deed(k, p, [7, 8])
	assert_true((p.deed as Dictionary).is_empty())
	assert_eq(done[0][2], [7, 8])


func test_witness_filter() -> void:
	var doer := {id = 1, family_id = 10}
	var people := [
		{id = 1, family_id = 10, pos = Vector3(0, 0, 0), adult = true, visible = true}, # the doer
		{id = 2, family_id = 10, pos = Vector3(1, 0, 0), adult = true, visible = true}, # own House keeps quiet
		{id = 3, family_id = 11, pos = Vector3(2, 0, 0), adult = true, visible = true}, # sees it
		{id = 4, family_id = 11, pos = Vector3(2, 0, 0), adult = true, visible = false}, # asleep indoors
		{id = 5, family_id = 11, pos = Vector3(2, 0, 0), adult = false, visible = true}, # a child
		{id = 6, family_id = 12, pos = Vector3(GameConstants.DEED_WITNESS_RADIUS + 1.0, 0, 0), adult = true, visible = true},
		{id = 7, family_id = 12, pos = Vector3(1, 0, 1), adult = true, visible = true}, # part of the deed
	]
	assert_eq(PeopleManager.witness_ids(doer, [7], Vector3.ZERO, people), [3])
