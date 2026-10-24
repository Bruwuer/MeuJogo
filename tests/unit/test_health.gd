extends GameTest


func test_damage_and_death() -> void:
	var h := Health.new(50.0)
	var hits := []
	var deaths := []
	h.damaged.connect(func(amount: float, _src: Object) -> void: hits.append(amount))
	h.died.connect(func(src: Object) -> void: deaths.append(src))
	assert_eq(h.hp, 50.0)
	assert_true(not h.damage(20.0), "should not die at 30 hp")
	assert_near(h.hp, 30.0, 0.001)
	assert_true(h.damage(40.0, self), "should die")
	assert_eq(h.hp, 0.0)
	assert_true(h.is_dead())
	assert_eq(hits.size(), 2)
	assert_eq(deaths, [self])
	assert_true(not h.damage(5.0), "dead things do not die twice")
	assert_eq(deaths.size(), 1)


func test_heal_caps() -> void:
	var h := Health.new(100.0)
	h.damage(30.0)
	h.heal(10.0)
	assert_near(h.hp, 80.0, 0.001)
	h.heal(500.0)
	assert_near(h.hp, 100.0, 0.001)
	assert_near(h.ratio(), 1.0, 0.001)
	h.damage(100.0)
	h.heal(10.0)
	assert_eq(h.hp, 0.0, "the dead do not heal")
