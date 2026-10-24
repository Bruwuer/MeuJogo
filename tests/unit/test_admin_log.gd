extends GameTest
## Kingdom events never reach the player's HUD: they go to the ADM log (chronicle + file).

const PATH := "user://test_adm_log.txt"


func _state() -> Array:
	var s := WorldState.new()
	var k := s.add_kingdom("Ravmia", Color.RED, Vector3(100, 0, 100), -1)
	return [s, k]


func test_chronicle_emits_each_entry() -> void:
	var a := _state()
	var s: WorldState = a[0]
	var got: Array = []
	s.chronicled.connect(func(e: Dictionary) -> void: got.append(e))
	s.chronicle_add(30.0, "algo", a[1].id, false)
	assert_eq(got.size(), 1)
	assert_eq(got[0].text, "algo")
	assert_eq(got[0].public, false)


func test_chronicle_all_includes_secrets() -> void:
	var a := _state()
	var s: WorldState = a[0]
	s.chronicle_add(30.0, "público", a[1].id)
	s.chronicle_add(31.0, "segredo", a[1].id, false)
	assert_eq(s.chronicle(a[1].id, 10).size(), 1, "the public chronicle hides secrets")
	assert_eq(s.chronicle_all(a[1].id, 10).size(), 2)
	assert_eq(s.chronicle_all(-2, 10).size(), 2, "-2 means every kingdom")


func test_line_format() -> void:
	var a := _state()
	var s: WorldState = a[0]
	var e := {hour = 24.0 * 3 + 9.0, text = "Martim fugiu", kingdom_id = a[1].id, public = false}
	assert_eq(AdminLog.line(s, e), "Dia 3, 9h — [Ravmia] [segredo] Martim fugiu")
	e.public = true
	e.kingdom_id = -1
	assert_eq(AdminLog.line(s, e), "Dia 3, 9h — Martim fugiu", "no kingdom tag for world events")


func test_writes_every_entry_to_file() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
	var a := _state()
	var s: WorldState = a[0]
	var entries_log := AdminLog.new()
	entries_log.setup(s, PATH)
	add_child(entries_log)
	s.chronicle_add(50.0, "A Casa Vale tomou posse de um lote", a[1].id)
	s.chronicle_add(51.0, "desvio", a[1].id, false)
	var text := FileAccess.get_file_as_string(PATH)
	assert_true(text.contains("Dia 2, 2h — [Ravmia] A Casa Vale tomou posse de um lote"), text)
	assert_true(text.contains("[segredo] desvio"), text)
	entries_log.queue_free()
	DirAccess.remove_absolute(PATH)


func test_offscreen_raid_goes_to_chronicle() -> void:
	var a := _state()
	var s: WorldState = a[0]
	var k: Dictionary = a[1]
	s.add_building(GameConstants.Building.FENCE, Vector3(106, 0, 100), 0)
	var p := s.add_pack("lobo", Vector3(140, 0, 100))
	var rng := RandomNumberGenerator.new()
	s.add_creature(Genome.random("lobo", rng), Vector3(140, 0, 100), p.id)
	var sim := PackSim.new()
	add_child(sim)
	sim.setup(s, null)
	sim.resolve_offscreen_raid(p, k)
	var entries := s.chronicle(k.id, 10)
	assert_eq(entries.size(), 1)
	if entries.size() == 1:
		assert_true((entries[0].text as String).contains("Ravmia"), entries[0].text)
		assert_true(not (entries[0].text as String).contains("você"), "the log speaks to the ADM, not the player")
	sim.queue_free()
