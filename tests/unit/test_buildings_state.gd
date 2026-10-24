extends GameTest

const B := GameConstants.Building
const R := GameConstants.Res

var _path := "user://test_buildings_%d.bin" % randi()


func _exit_tree() -> void:
	for s in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(_path + s):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(_path + s))


func test_add_and_query_by_chunk() -> void:
	var s := WorldState.new()
	var rec := s.add_building(B.CABIN, Vector3(40, 2, 40), 1)
	assert_eq(s.buildings_in(Vector2i(1, 1)).size(), 1)
	assert_eq(s.buildings_in(Vector2i(0, 0)).size(), 0)
	assert_eq(s.buildings_in(Vector2i(1, 1))[0].id, rec.id)
	assert_eq(rec.rot, 1)


func test_ids_increase_and_remove() -> void:
	var s := WorldState.new()
	var a := s.add_building(B.FENCE, Vector3(5, 0, 5), 0)
	var b := s.add_building(B.WELL, Vector3(9, 0, 5), 0)
	assert_true(a.id != b.id)
	var removed := s.remove_building(a.id)
	assert_eq(removed.id, a.id)
	assert_eq(s.building(a.id), {})
	assert_eq(s.all_buildings().size(), 1)
	assert_eq(s.buildings_in(Vector2i(0, 0)).size(), 1)


func test_buildings_roundtrip() -> void:
	var s := WorldState.new()
	s.seed = 9
	var cabin := s.add_building(B.CABIN, Vector3(100, 3, 120), 2)
	s.add_building(B.FLAG, Vector3(101, 3, 122), 2, Color(0.8, 0.1, 0.1))
	s.add_kingdom("Valdemar", Color(0.8, 0.1, 0.1), cabin.pos, cabin.id)
	assert_eq(s.save_to(_path), OK)
	var l := WorldState.load_from(_path)
	assert_eq(l.all_buildings().size(), 2)
	assert_eq(l.building(cabin.id).type, B.CABIN)
	assert_eq(l.building(cabin.id).pos, Vector3(100, 3, 120))
	assert_eq(l.kingdoms().size(), 1)
	assert_eq(l.kingdoms()[0].name, "Valdemar")
	assert_eq(l.kingdoms()[0].seat_id, cabin.id)
	var next := l.add_building(B.WELL, Vector3(0, 0, 0), 0)
	assert_true(next.id > cabin.id + 1, "ids must keep increasing after load")


func test_spend_all_or_nothing() -> void:
	var s := WorldState.new()
	s.add_resource(R.WOOD, 10)
	assert_true(not s.spend({R.WOOD: 5, R.STONE: 3}))
	assert_eq(s.get_resource(R.WOOD), 10)
	s.add_resource(R.STONE, 3)
	assert_true(s.spend({R.WOOD: 5, R.STONE: 3}))
	assert_eq(s.get_resource(R.WOOD), 5)
	assert_eq(s.get_resource(R.STONE), 0)


func test_refund_half_floor() -> void:
	var s := WorldState.new()
	s.refund({R.WOOD: 5, R.STONE: 3}, 0.5)
	assert_eq(s.get_resource(R.WOOD), 2)
	assert_eq(s.get_resource(R.STONE), 1)


func test_kingdom_at() -> void:
	var s := WorldState.new()
	s.add_kingdom("Torvela", Color.BLUE, Vector3(200, 0, 200), 1)
	assert_eq(s.kingdom_at(Vector3(230, 5, 200)).name, "Torvela")
	assert_eq(s.kingdom_at(Vector3(250, 0, 200)), {})


func test_catalog_complete() -> void:
	for t in GameConstants.BUILDABLE:
		assert_true(GameConstants.BUILD_COST.has(t) and GameConstants.BUILD_FOOTPRINT.has(t) and GameConstants.BUILD_SCENES.has(t) and GameConstants.BUILD_COLLIDERS.has(t), "incomplete catalog for %d" % t)
	assert_eq(GameConstants.BUILD_COST[B.CABIN], {R.WOOD: 30, R.STONE: 10})
