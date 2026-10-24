extends GameTest


func test_deterministic() -> void:
	assert_eq(KingdomNames.generate(1337, 0), KingdomNames.generate(1337, 0))


func test_varied_and_well_formed() -> void:
	var names := {}
	for s in 20:
		var n := KingdomNames.generate(s * 7919, 0)
		names[n] = true
		assert_true(n.length() >= 4 and n.length() <= 12, "bad length: %s" % n)
		assert_eq(n.substr(0, 1), n.substr(0, 1).to_upper(), "not capitalized: %s" % n)
	assert_true(names.size() >= 15, "only %d distinct names" % names.size())


func test_index_changes_name() -> void:
	assert_true(KingdomNames.generate(42, 0) != KingdomNames.generate(42, 1))
