extends GameTest

var _path := "user://test_house_state_%d.bin" % randi()


func _exit_tree() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(_path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(_path + suffix))


func test_stage6_save_defaults() -> void:
	# A stage-6 save: a family and a person without any stage-7 field.
	var s := WorldState.new()
	s.seed = 3
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var p := s.add_person(PersonGen.generate(rng), Vector3.ZERO, 1)
	var f := s.add_family("Ferreira", {}, 1, p.id, 0.0)
	for key in ["tradition", "values", "wealth", "plots", "skill", "prestige", "goal", "rival_id"]:
		f.erase(key)
	for key in ["vocation", "desire", "resentment", "secret", "adopted_by"]:
		p.erase(key)
	assert_eq(s.save_to(_path), OK)
	var l := WorldState.load_from(_path)
	var lf := l.family(f.id)
	var lp := l.person(p.id)
	for key in ["tradition", "values", "wealth", "plots", "skill", "prestige", "goal", "rival_id"]:
		assert_true(lf.has(key), "family lacks %s" % key)
	for key in ["vocation", "desire", "resentment", "secret", "adopted_by"]:
		assert_true(lp.has(key), "person lacks %s" % key)
	assert_true(lf.wealth >= 0.0)
	assert_true(GameConstants.Tradition.values().has(lf.tradition))


func test_new_family_and_person_have_fields() -> void:
	var s := WorldState.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var p := s.add_person(PersonGen.generate(rng), Vector3.ZERO, 1)
	var f := s.add_family("Vale", {}, 1, p.id, 0.0)
	assert_true(f.has("tradition") and f.has("wealth") and f.has("goal"))
	assert_true(p.has("vocation") and p.has("desire") and p.has("secret"))


func test_chronicle_limit_and_order() -> void:
	var s := WorldState.new()
	for i in GameConstants.CHRONICLE_MAX + 50:
		s.chronicle_add(float(i), "evento %d" % i, 1)
	s.chronicle_add(999.0, "outro reino", 2)
	var last := s.chronicle(1, 3)
	assert_eq(last.size(), 3)
	assert_eq(last[2].text, "evento %d" % (GameConstants.CHRONICLE_MAX + 49))
	assert_true(s.chronicle(1, 10000).size() <= GameConstants.CHRONICLE_MAX)
	assert_eq(s.chronicle(2, 5).size(), 1)


func test_private_entries_hidden() -> void:
	var s := WorldState.new()
	s.chronicle_add(1.0, "segredo", 1, false)
	s.chronicle_add(2.0, "público", 1)
	var pub := s.chronicle(1, 10)
	assert_eq(pub.size(), 1)
	assert_eq(pub[0].text, "público")


func test_chronicle_persists() -> void:
	var s := WorldState.new()
	s.chronicle_add(5.0, "A Casa Vale comprou um lote", 1)
	s.save_to(_path)
	assert_eq(WorldState.load_from(_path).chronicle(1, 5)[0].text, "A Casa Vale comprou um lote")
