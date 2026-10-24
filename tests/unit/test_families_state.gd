extends GameTest

const PATH := "user://test_families_state.bin"


func _person(s: WorldState, seed_value: int, kingdom_id := 1) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var p := s.add_person(PersonGen.generate(r), Vector3(10, 0, 10), kingdom_id)
	p.status = "resident"
	return p


func test_family_roundtrip() -> void:
	var s := WorldState.new()
	var a := _person(s, 1)
	var b := _person(s, 2)
	var crest := {pattern = 1, field = 0, second = 2, charge = 3, charge_tincture = 2}
	var f := s.add_family("Ferreira", crest, 1, a.id, 5.0)
	a.family_id = f.id
	s.set_relation(a.id, b.id, 0.4)
	assert_eq(f.origin, "founded")
	assert_eq(f.parent_id, -1)
	assert_eq(s.save_to(PATH), OK)
	var l := WorldState.load_from(PATH)
	var lf := l.family(f.id)
	assert_eq(lf.surname, "Ferreira")
	assert_eq(lf.head_id, a.id)
	assert_true(Crest.same(lf.crest, crest), "crest saved")
	assert_near(l.relation(a.id, b.id), 0.4, 0.001, "relation saved")
	assert_eq(l.person(a.id).family_id, f.id)
	var g := l.add_family("Seixas", crest, 1, b.id, 6.0)
	assert_true(g.id != f.id, "next family id saved")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_relation_symmetric_and_clamped() -> void:
	var s := WorldState.new()
	s.set_relation(3, 1, 0.5)
	assert_near(s.relation(1, 3), 0.5, 0.001, "symmetric")
	s.add_relation(1, 3, 0.9)
	assert_near(s.relation(3, 1), 1.0, 0.001, "clamped")
	assert_near(s.relation(1, 2), 0.0, 0.001, "none = 0")
	s.set_relation(1, 2, -0.2)
	var of1 := s.relations_of(1)
	assert_eq(of1.size(), 2)
	assert_near(float(of1[2]), -0.2, 0.001)


func test_remove_person_cleans_links() -> void:
	var s := WorldState.new()
	var a := _person(s, 1)
	var b := _person(s, 2)
	var c := _person(s, 3)
	a.spouse_id = b.id
	b.spouse_id = a.id
	c.parents = [a.id, b.id]
	s.set_relation(a.id, b.id, 0.7)
	s.set_relation(a.id, c.id, 0.3)
	s.remove_person(a.id)
	assert_eq(b.spouse_id, -1, "spouse unlinked")
	assert_true(b.widowed, "widowed")
	assert_true(s.relations_of(b.id).is_empty(), "relations gone")
	assert_eq(c.parents, [a.id, b.id], "parents kept for kinship")


func test_family_members_only_residents() -> void:
	var s := WorldState.new()
	var a := _person(s, 1)
	var b := _person(s, 2)
	var c := _person(s, 3, 2)
	var f := s.add_family("Ferreira", {}, 1, a.id, 0.0)
	for p in [a, b, c]:
		p.family_id = f.id
	b.status = "leaving"
	var ids := s.family_members(f.id).map(func(p: Dictionary) -> int: return p.id)
	assert_true(ids.has(a.id) and ids.has(c.id) and not ids.has(b.id), str(ids))
	assert_eq(s.families_of(1).size(), 1)
	assert_eq(s.families_of(2).size(), 0)
	s.remove_family(f.id)
	assert_true(s.family(f.id).is_empty())


func test_loads_stage5_save() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 4
	var old := PersonGen.generate(r)
	old.merge({id = 1, pos = Vector3.ZERO, kingdom_id = 1, home_id = -1, inside = -1, hunger = 0.0,
			contentment = 0.6, status = "resident", unhappy_hours = 0.0, job = "", carrying = {}, arrived_hour = 0.0})
	WorldState.write_payload(PATH, {seed = 1, people = [old], next_person_id = 2})
	var s := WorldState.load_from(PATH)
	var p := s.person(1)
	for key in ["family_id", "spouse_id", "parents", "stance", "last_birth_hour", "talk_day", "deed_day", "widowed"]:
		assert_true(p.has(key), "default %s" % key)
	assert_eq(p.family_id, -1)
	assert_true(s.all_families().is_empty())
	assert_near(s.relation(1, 2), 0.0, 0.001)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
