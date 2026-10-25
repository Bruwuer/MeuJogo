extends GameTest
## Living world (stage 9): several kingdoms in one world — founder, relations between kingdoms,
## save, colors, fame and the player's respawn seat.

const B := GameConstants.Building

var _path := "user://test_realms_state_%d.bin" % randi()


func _exit_tree() -> void:
	for p in [_path, _path + ".tmp", _path + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func test_kingdoms_know_who_founded_them() -> void:
	var s := WorldState.new()
	var mine := s.add_kingdom("Meu", Color.RED, Vector3.ZERO, -1)
	var theirs := s.add_kingdom("Deles", Color.BLUE, Vector3(300, 0, 0), -1, "npc")
	assert_eq(String(mine.founder), "player")
	assert_eq(String(theirs.founder), "npc")
	var old := {id = 1, name = "Velho", color = Color.RED, center = Vector3.ZERO, radius = 40.0, seat_id = -1}
	WorldState._kingdom_defaults(old)
	assert_eq(String(old.founder), "player", "an old save's kingdom was the player's")


func test_relation_between_kingdoms_is_symmetric_and_saved() -> void:
	var s := WorldState.new()
	var a := s.add_kingdom("A", Color.RED, Vector3.ZERO, -1)
	var b := s.add_kingdom("B", Color.BLUE, Vector3(300, 0, 0), -1, "npc")
	var r := s.realm(a.id, b.id)
	assert_eq(float(r.rel), 0.0)
	assert_true(not r.war)
	r.rel = -0.4
	r.war = true
	assert_eq(float(s.realm(b.id, a.id).rel), -0.4, "the same pair either way")
	assert_true(s.at_war(b.id, a.id))
	s.realms_seeded = true
	assert_eq(s.save_to(_path), OK)
	var t := WorldState.load_from(_path)
	assert_eq(float(t.realm(a.id, b.id).rel), -0.4)
	assert_true(t.at_war(a.id, b.id))
	assert_true(t.realms_seeded)


func test_each_kingdom_has_its_own_color() -> void:
	assert_true(KingdomNames.color(7, 0) != KingdomNames.color(7, 1))
	assert_eq(KingdomNames.color(7, 2), KingdomNames.color(7, 2), "deterministic")


func test_respawn_seat_is_the_nearest_of_the_players() -> void:
	var s := WorldState.new()
	var far_seat := s.add_building(B.CABIN, Vector3(500, 0, 500), 0)
	s.add_kingdom("Longe", Color.RED, far_seat.pos, far_seat.id)
	var npc_seat := s.add_building(B.CABIN, Vector3(60, 0, 60), 0, Color.WHITE, GameConstants.OWNER_KINGDOM)
	s.add_kingdom("Alheio", Color.BLUE, npc_seat.pos, npc_seat.id, "npc")
	var near_seat := s.add_building(B.CABIN, Vector3(200, 0, 200), 0)
	s.add_kingdom("Perto", Color.GREEN, near_seat.pos, near_seat.id)
	assert_eq(s.player_seat_near(Vector3.ZERO).get("id", -1), near_seat.id, "never an NPC kingdom's seat")
	assert_eq(WorldState.new().player_seat_near(Vector3.ZERO), {})


func test_fame_comes_from_the_players_kingdoms_only() -> void:
	var s := WorldState.new()
	var mine := s.add_kingdom("Meu", Color.RED, Vector3(100, 0, 100), -1)
	var theirs := s.add_kingdom("Deles", Color.BLUE, Vector3(400, 0, 400), -1, "npc")
	for i in 3:
		var a := s.add_person(PersonGen.generate(RandomNumberGenerator.new()), mine.center, mine.id)
		a.merge({status = "resident", age = 30.0, opinion = 0.8}, true)
		var b := s.add_person(PersonGen.generate(RandomNumberGenerator.new()), theirs.center, theirs.id)
		b.merge({status = "resident", age = 30.0, opinion = -0.8}, true)
	var gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
	var sim := VillageSim.new()
	sim.setup(s, gen, PropScatter.new(gen, GameConstants.WORLD_SEED), null)
	sim.is_player_in = func(k: Dictionary) -> bool: return k.id == mine.id
	sim.tick_hours(1.0)
	assert_true(s.fame > 0.5, "strangers far away do not make the founder's name: %f" % s.fame)
	sim.free()
