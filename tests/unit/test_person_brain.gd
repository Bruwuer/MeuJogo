extends GameTest

const A := PersonBrain.Act


func _me(extra := {}) -> Dictionary:
	var me := {
		pos = Vector3.ZERO, status = "resident", job = "wood", carrying = {}, home_pos = null, door_pos = null,
		is_work_time = true, is_sleep_time = false, raid = false, threat_pos = null,
	}
	me.merge(extra, true)
	return me


func _ctx(extra := {}) -> Dictionary:
	var ctx := {
		work_target = {}, deposit_pos = Vector3(0, 0, 10), seat_pos = Vector3(10, 0, 0),
		campfire_pos = null, exit_pos = Vector3(100, 0, 100),
	}
	ctx.merge(extra, true)
	return ctx


func test_sleeps_at_night_at_home() -> void:
	var me := _me({is_work_time = false, is_sleep_time = true, home_pos = Vector3(20, 0, 0), door_pos = Vector3(20, 0, 3)})
	var d := PersonBrain.decide(me, _ctx())
	assert_eq(d.act, A.WALK)
	assert_eq(d.goal, A.ENTER)
	assert_eq(d.target_pos, Vector3(20, 0, 3), "walks to the door")
	me.pos = Vector3(20, 0, 2.6)
	assert_eq(PersonBrain.decide(me, _ctx()).act, A.ENTER, "at the door: goes in")
	var homeless := _me({is_work_time = false, is_sleep_time = true, pos = Vector3(11, 0, 1)})
	assert_eq(PersonBrain.decide(homeless, _ctx()).act, A.SLEEP, "no home: sleeps by the seat")
	var by_fire := PersonBrain.decide(homeless, _ctx({campfire_pos = Vector3(-20, 0, 0)}))
	assert_eq(by_fire.goal, A.SLEEP)
	assert_true(by_fire.target_pos.distance_to(Vector3(-20, 0, 0)) < GameConstants.PERSON_FIRE_SLEEP_RADIUS + 0.01,
			"by the campfire when there is one")


func test_flees_threat() -> void:
	var d := PersonBrain.decide(_me({threat_pos = Vector3(3, 0, 0)}), _ctx())
	assert_eq(d.act, A.FLEE)
	assert_true(d.target_pos.x < -1.0, "away from the threat")


func test_goes_home_during_raid() -> void:
	var me := _me({raid = true, home_pos = Vector3(20, 0, 0), door_pos = Vector3(20, 0, 3)})
	var d := PersonBrain.decide(me, _ctx({work_target = {pos = Vector3(5, 0, 5), reach = 1.5}}))
	assert_eq(d.goal, A.ENTER, "hides at home, does not work")
	var homeless := PersonBrain.decide(_me({raid = true}), _ctx())
	assert_true(homeless.goal == A.IDLE and homeless.target_pos.distance_to(Vector3(10, 0, 0)) < 4.0, "no home: to the seat")


func test_deposits_when_carrying() -> void:
	var me := _me({carrying = {GameConstants.Res.WOOD: 3}})
	var d := PersonBrain.decide(me, _ctx({work_target = {pos = Vector3(5, 0, 5), reach = 1.5}}))
	assert_eq(d.act, A.WALK)
	assert_eq(d.goal, A.DEPOSIT)
	assert_eq(d.target_pos, Vector3(0, 0, 10))
	me.pos = Vector3(0, 0, 9.5)
	assert_eq(PersonBrain.decide(me, _ctx()).act, A.DEPOSIT)


func test_traveler_walks_to_seat_then_evaluates() -> void:
	var me := _me({status = "traveler", pos = Vector3(80, 0, 0)})
	var d := PersonBrain.decide(me, _ctx())
	assert_eq(d.act, A.WALK)
	assert_eq(d.goal, A.EVALUATE)
	me.pos = Vector3(10.5, 0, 2.0)
	assert_eq(PersonBrain.decide(me, _ctx()).act, A.EVALUATE)
	var leaving := PersonBrain.decide(_me({status = "leaving"}), _ctx())
	assert_eq(leaving.goal, A.LEAVE)
	assert_eq(leaving.target_pos, Vector3(100, 0, 100))


func test_works_at_target_in_work_hours() -> void:
	var ctx := _ctx({work_target = {pos = Vector3(5, 0, 0), reach = 1.5}})
	var d := PersonBrain.decide(_me(), ctx)
	assert_eq(d.goal, A.WORK)
	assert_eq(PersonBrain.decide(_me({pos = Vector3(4, 0, 0)}), ctx).act, A.WORK)
	assert_eq(PersonBrain.decide(_me({is_work_time = false}), ctx).goal, A.IDLE, "evening: rests")
