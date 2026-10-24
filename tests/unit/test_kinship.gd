extends GameTest

var s := WorldState.new()


func _p(name: String, female: bool, parents := []) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var p := PersonGen.generate(rng)
	p.name = name
	p.female = female
	var rec := s.add_person(p, Vector3.ZERO, 1)
	rec.status = "resident"
	rec.parents = parents.map(func(x: Dictionary) -> int: return x.id)
	s.note_ancestry(rec)
	return rec


func test_three_generations() -> void:
	var g1 := _p("Afonso", false)
	var g2 := _p("Beatriz", true)
	var a := _p("Duarte", false, [g1, g2])
	var b := _p("Leonor", true, [g1, g2])
	var w := _p("Inês", true)
	var c1 := _p("Martim", false, [a, w])
	var spouse := _p("Tomé", false)
	var c2 := _p("Joana", true, [b, spouse])
	a.spouse_id = w.id
	w.spouse_id = a.id
	assert_eq(Kinship.relation_word(s, a, c1), "pai")
	assert_eq(Kinship.relation_word(s, c1, a), "filho")
	assert_eq(Kinship.relation_word(s, a, b), "irmão")
	assert_eq(Kinship.relation_word(s, b, a), "irmã")
	assert_eq(Kinship.relation_word(s, g1, c1), "avô")
	assert_eq(Kinship.relation_word(s, c2, g2), "neta")
	assert_eq(Kinship.relation_word(s, a, c2), "tio")
	assert_eq(Kinship.relation_word(s, b, c1), "tia")
	assert_eq(Kinship.relation_word(s, c1, b), "sobrinho")
	assert_eq(Kinship.relation_word(s, c1, c2), "primo")
	assert_eq(Kinship.relation_word(s, c2, c1), "prima")
	assert_eq(Kinship.relation_word(s, w, a), "esposa")
	assert_eq(Kinship.relation_word(s, w, c2), "")
	assert_true(Kinship.is_close_kin(s, c1, c2))
	assert_true(not Kinship.is_close_kin(s, w, c2))


func test_kinship_survives_death() -> void:
	var g1 := _p("Afonso", false)
	var a := _p("Duarte", false, [g1])
	var b := _p("Leonor", true, [g1])
	var c1 := _p("Martim", false, [a])
	var c2 := _p("Joana", true, [b])
	s.remove_person(g1.id)
	assert_eq(Kinship.relation_word(s, c1, c2), "primo", "cousins must stay cousins after the grandparent dies")
	assert_true(Kinship.is_close_kin(s, c1, c2))


func test_adoption_by_a_couple() -> void:
	var x := _p("Maria", true)
	var y := _p("Vasco", false)
	var orphan := _p("Rui", false)
	orphan.adopted_by = [x.id, y.id]
	s.note_ancestry(orphan)
	assert_eq(Kinship.relation_word(s, x, orphan), "mãe")
	assert_eq(Kinship.relation_word(s, y, orphan), "pai")
	assert_eq(Kinship.relation_word(s, orphan, y), "filho")
	assert_eq(Kinship.parents_of(s, orphan.id).size(), 2)
