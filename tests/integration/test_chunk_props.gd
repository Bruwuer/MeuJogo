extends GameTest

const SETTLE_TIMEOUT_FRAMES := 600

var removed: Dictionary = {} # Vector2i -> PackedInt32Array
var _gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
var _scatter := PropScatter.new(_gen, GameConstants.WORLD_SEED)
var _max_frame_ms := 0.0


func _provider(c: Vector2i) -> PackedInt32Array:
	return removed.get(c, PackedInt32Array())


func _make_streamer() -> ChunkStreamer:
	var lib := ModelLibrary.new()
	add_child(lib)
	lib.start_loading()
	var s := ChunkStreamer.new()
	s.setup(_gen, _scatter, lib, _provider)
	add_child(s)
	return s


func _center_of(c: Vector2i) -> Vector3:
	return ChunkMath.chunk_origin(c) + Vector3(16, 0, 16)


func _settle(s: ChunkStreamer) -> void:
	var last := Time.get_ticks_usec()
	for i in SETTLE_TIMEOUT_FRAMES:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		_max_frame_ms = maxf(_max_frame_ms, (now - last) / 1000.0)
		last = now
		if s.pending_count() == 0:
			await get_tree().process_frame
			return
	failures.append("streamer did not settle")


func _count(props: Array, type: int) -> int:
	return props.filter(func(p: Dictionary) -> bool: return p.type == type).size()


## First chunk (scanning the map) holding a prop of `type`.
func _find_chunk_with(type: int) -> Vector2i:
	for cy in GameConstants.MAP_CHUNKS:
		for cx in GameConstants.MAP_CHUNKS:
			if _count(_scatter.build_chunk_props(Vector2i(cx, cy)), type) > 0:
				return Vector2i(cx, cy)
	return Vector2i(-99, -99)


func test_chunk_instances_match_scatter() -> void:
	var c := _find_chunk_with(GameConstants.Prop.OAK)
	var s := _make_streamer()
	s.update_center(_center_of(c))
	await _settle(s)
	var chunk := s.get_chunk(c)
	assert_true(chunk != null, "chunk not loaded")
	if chunk == null:
		return
	var props := _scatter.build_chunk_props(c)
	for type in GameConstants.PROP_SCENES:
		assert_eq(chunk.instance_count(type), _count(props, type), "type %d" % type)


func test_removed_filtered_on_build() -> void:
	var c := _find_chunk_with(GameConstants.Prop.OAK)
	var props := _scatter.build_chunk_props(c)
	var first: Dictionary = props[0]
	removed[c] = PackedInt32Array([first.id])
	var s := _make_streamer()
	s.update_center(_center_of(c))
	await _settle(s)
	var chunk := s.get_chunk(c)
	assert_true(not chunk.has_prop(first.id))
	assert_eq(chunk.instance_count(first.type), _count(props, first.type) - 1)


func test_remove_prop_updates_multimesh_and_collision() -> void:
	var c := _find_chunk_with(GameConstants.Prop.OAK)
	var s := _make_streamer()
	s.update_center(_center_of(c))
	await _settle(s)
	var chunk := s.get_chunk(c)
	var oak: Dictionary = _scatter.build_chunk_props(c).filter(func(p: Dictionary) -> bool: return p.type == GameConstants.Prop.OAK)[0]
	var before := chunk.instance_count(GameConstants.Prop.OAK)
	var shapes_before := chunk.find_children("*", "CollisionShape3D", true, false).size()
	chunk.remove_prop(oak.id)
	await get_tree().process_frame
	assert_eq(chunk.instance_count(GameConstants.Prop.OAK), before - 1)
	assert_eq(chunk.find_children("*", "CollisionShape3D", true, false).size(), shapes_before - 1)
	assert_true(not chunk.has_prop(oak.id))


func test_removed_prop_stays_removed_after_reload() -> void:
	var c := _find_chunk_with(GameConstants.Prop.OAK)
	var s := _make_streamer()
	s.update_center(_center_of(c))
	await _settle(s)
	var id: int = s.get_chunk(c).prop_ids()[0]
	s.get_chunk(c).remove_prop(id)
	removed[c] = PackedInt32Array([id])
	var far := Vector2i(c.x + 8 if c.x < 12 else c.x - 8, c.y)
	s.update_center(_center_of(far))
	await _settle(s)
	assert_true(s.get_chunk(c) == null, "chunk should have unloaded")
	s.update_center(_center_of(c))
	await _settle(s)
	assert_true(not s.get_chunk(c).has_prop(id), "removed prop came back")


func test_border_chunks_have_no_props() -> void:
	var s := _make_streamer()
	s.update_center(_center_of(Vector2i(0, 0)))
	await _settle(s)
	assert_eq(s.get_chunk(Vector2i(-1, 0)).prop_ids().size(), 0)


func test_tree_blocks_player() -> void:
	var c := _find_chunk_with(GameConstants.Prop.OAK)
	var oak: Dictionary = _scatter.build_chunk_props(c).filter(func(p: Dictionary) -> bool: return p.type == GameConstants.Prop.OAK)[0]
	var s := _make_streamer()
	s.update_center(oak.pos)
	await _settle(s)
	var player: Player = load("res://scenes/player.tscn").instantiate()
	add_child(player)
	# Approach from whichever side has gentle ground: try 4 directions, keep the first that stays loaded.
	var start: Vector3 = oak.pos + Vector3(-3.0, 0, 0)
	player.global_position = Vector3(start.x, _gen.height_at(start.x, start.z) + 0.5, start.z)
	player.reset_physics_interpolation()
	player.frozen = false
	await wait_physics_frames(10)
	var to_tree := Vector3(oak.pos.x - player.global_position.x, 0, oak.pos.z - player.global_position.z).normalized()
	_press_direction(to_tree)
	await wait_physics_frames(120)
	_release_all()
	var r: float = GameConstants.PROP_COLLISION_RADIUS[GameConstants.Prop.OAK] * oak.scale
	var d := Vector2(player.global_position.x - oak.pos.x, player.global_position.z - oak.pos.z).length()
	assert_true(d >= r + 0.2, "walked into the trunk: %.2f m (radius %.2f)" % [d, r])


func test_streaming_forest_frame_budget() -> void:
	var best := Vector2i.ZERO
	var best_n := -1
	for cy in range(0, GameConstants.MAP_CHUNKS, 3):
		for cx in range(0, GameConstants.MAP_CHUNKS, 3):
			var n := _scatter.build_chunk_props(Vector2i(cx, cy)).size()
			if n > best_n:
				best_n = n
				best = Vector2i(cx, cy)
	var s := _make_streamer()
	await _settle(s) # let the library finish so its load time is not counted
	_max_frame_ms = 0.0
	s.update_center(_center_of(best))
	await _settle(s)
	assert_true(_max_frame_ms < GameConstants.MAX_FRAME_MS, "worst frame %.1f ms around %s (%d props)" % [_max_frame_ms, best, best_n])


## Presses move actions with analog strengths so the screen-relative input maps to `dir`.
func _press_direction(dir: Vector3) -> void:
	var yaw := deg_to_rad(GameConstants.CAM_YAW_DEG)
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var up := Vector3(-sin(yaw), 0, -cos(yaw))
	var x := dir.dot(right)
	var y := -dir.dot(up)
	Input.action_press("move_right", maxf(x, 0.0))
	Input.action_press("move_left", maxf(-x, 0.0))
	Input.action_press("move_down", maxf(y, 0.0))
	Input.action_press("move_up", maxf(-y, 0.0))


func _release_all() -> void:
	for a in ["move_up", "move_down", "move_left", "move_right", "run"]:
		Input.action_release(a)
