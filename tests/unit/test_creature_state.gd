extends GameTest

const _PATH := "user://test_creature_state.bin"


func _genome(species := "lobo", s := 1) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return Genome.random(species, r)


func test_creatures_roundtrip() -> void:
	var s := WorldState.new()
	var p := s.add_pack("lobo", Vector3(100, 0, 100))
	var a := s.add_creature(_genome(), Vector3(100, 2, 104), p.id)
	var b := s.add_creature(_genome("lobo", 2), Vector3(102, 2, 98), p.id, 0.3)
	p.leader_id = a.id
	p.grudge = 0.4
	s.mark_visited(Vector2i(3, 3))
	a.hp = 12.0
	assert_eq(s.save_to(_PATH), OK)
	var l := WorldState.load_from(_PATH)
	assert_eq(l.all_creatures().size(), 2)
	assert_eq(l.creature(a.id).hp, 12.0)
	assert_eq(l.creature(b.id).age, 0.3)
	assert_eq(l.creature(a.id).genome, a.genome)
	assert_eq(l.creatures_in(ChunkMath.world_to_chunk(a.pos)).size(), 2)
	assert_eq(l.pack(p.id).leader_id, a.id)
	assert_near(l.pack(p.id).grudge, 0.4, 0.0001)
	assert_eq(l.pack_members(p.id).size(), 2)
	assert_true(l.visited(Vector2i(3, 3)))
	assert_true(not l.visited(Vector2i(4, 3)))
	var c := l.add_creature(_genome(), Vector3.ZERO, p.id)
	assert_true(c.id != a.id and c.id != b.id, "ids reused after load")
	l.remove_creature(a.id)
	assert_eq(l.creature(a.id), {})
	assert_eq(l.pack_members(p.id).size(), 2)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_PATH))


func test_move_creature_reindexes() -> void:
	var s := WorldState.new()
	var a := s.add_creature(_genome(), Vector3(5, 0, 5), -1)
	s.move_creature(a.id, Vector3(70, 0, 5))
	assert_eq(s.creatures_in(Vector2i(0, 0)).size(), 0)
	assert_eq(s.creatures_in(Vector2i(2, 0)).size(), 1)
	assert_eq(s.creature(a.id).pos, Vector3(70, 0, 5))


func test_building_hp_and_seat_clamp() -> void:
	var s := WorldState.new()
	var cabin := s.add_building(GameConstants.Building.CABIN, Vector3(10, 0, 10), 0)
	var fence := s.add_building(GameConstants.Building.FENCE, Vector3(16, 0, 10), 0)
	s.add_kingdom("Valdemar", Color.RED, cabin.pos, cabin.id)
	var fence_hp: float = GameConstants.BUILD_HP[GameConstants.Building.FENCE]
	assert_eq(s.building_hp(fence.id), fence_hp)
	assert_true(not s.damage_building(fence.id, 10.0))
	assert_near(s.building_hp(fence.id), fence_hp - 10.0, 0.001)
	assert_true(s.damage_building(fence.id, 1000.0), "fence should be destroyed")
	assert_eq(s.building(fence.id), {})
	assert_true(not s.damage_building(cabin.id, 100000.0), "the seat never falls")
	assert_near(s.building_hp(cabin.id), 1.0, 0.001)
	assert_true(not s.building(cabin.id).is_empty())
	assert_eq(s.save_to(_PATH), OK)
	assert_near(WorldState.load_from(_PATH).building_hp(cabin.id), 1.0, 0.001)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_PATH))
