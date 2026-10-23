extends GameTest

const SETTLE_TIMEOUT_FRAMES := 300

var _max_frame_ms := 0.0


func _make_streamer() -> ChunkStreamer:
	var s := ChunkStreamer.new()
	var lib := PropLibrary.new()
	add_child(lib)
	lib.start_loading()
	var gen := TerrainGenerator.new(7)
	s.setup(gen, PropScatter.new(gen, 7), lib, func(_c: Vector2i) -> PackedInt32Array: return PackedInt32Array())
	add_child(s)
	return s


func _center_of(c: Vector2i) -> Vector3:
	return ChunkMath.chunk_origin(c) + Vector3(GameConstants.CHUNK_SIZE, 0, GameConstants.CHUNK_SIZE) * 0.5


## Waits until the streamer has nothing in flight, tracking the worst frame time.
func _settle(s: ChunkStreamer) -> bool:
	var last := Time.get_ticks_usec()
	for i in SETTLE_TIMEOUT_FRAMES:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		_max_frame_ms = maxf(_max_frame_ms, (now - last) / 1000.0)
		last = now
		if s.pending_count() == 0:
			await get_tree().process_frame # let queue_free land
			return true
	failures.append("streamer did not settle in %d frames" % SETTLE_TIMEOUT_FRAMES)
	return false


func test_loads_async() -> void:
	var s := _make_streamer()
	s.update_center(_center_of(Vector2i(3, 3)))
	assert_true(not s.is_loaded(Vector2i(3, 3)), "chunk must not load synchronously")
	await _settle(s)
	assert_eq(s.loaded_coords().size(), 25)
	for c in ChunkMath.chunks_in_radius(Vector2i(3, 3), GameConstants.LOAD_RADIUS):
		assert_true(s.is_loaded(c), "missing %s" % c)


func test_emits_loaded_signal() -> void:
	var s := _make_streamer()
	var got: Array[Vector2i] = []
	s.chunk_loaded.connect(func(c: Vector2i) -> void: got.append(c))
	s.update_center(_center_of(Vector2i(3, 3)))
	await _settle(s)
	assert_eq(got.size(), 25)


func test_unloads_far() -> void:
	var s := _make_streamer()
	s.update_center(_center_of(Vector2i(0, 0)))
	await _settle(s)
	s.update_center(_center_of(Vector2i(6, 6)))
	await _settle(s)
	assert_true(not s.is_loaded(Vector2i(0, 0)))
	assert_true(s.get_node_or_null("Chunk_0_0") == null, "Chunk_0_0 node still present")


func test_stale_chunk_discarded() -> void:
	var s := _make_streamer()
	s.update_center(_center_of(Vector2i(0, 0)))
	s.update_center(_center_of(Vector2i(7, 7)))
	await _settle(s)
	for c in s.loaded_coords():
		assert_true(maxi(absi(c.x - 7), absi(c.y - 7)) <= GameConstants.LOAD_RADIUS, "stale chunk %s" % c)


func test_no_duplicate_chunks() -> void:
	var s := _make_streamer()
	for i in 10:
		s.update_center(_center_of(Vector2i(4, 4)))
		await get_tree().process_frame
	await _settle(s)
	assert_eq(s.get_child_count(), s.loaded_coords().size())


func test_no_frame_over_budget() -> void:
	var s := _make_streamer()
	_max_frame_ms = 0.0
	s.update_center(_center_of(Vector2i(4, 4)))
	await _settle(s)
	assert_true(_max_frame_ms < GameConstants.MAX_FRAME_MS, "worst frame %.1f ms" % _max_frame_ms)


func test_border_has_no_collision() -> void:
	var s := _make_streamer()
	s.update_center(_center_of(Vector2i(0, 0)))
	await _settle(s)
	var border := s.get_node_or_null("Chunk_-1_0")
	var inner := s.get_node_or_null("Chunk_0_0")
	assert_true(border != null and inner != null, "chunks missing")
	if border and inner:
		assert_true(border.get_node_or_null("Terrain") == null, "border has terrain collision")
		assert_true(inner.get_node_or_null("Terrain") != null, "inner lacks terrain collision")


func test_no_duplicate_after_back_and_forth() -> void:
	# A -> B -> A in one frame: A's chunks are still building when re-requested.
	var s := _make_streamer()
	s.update_center(_center_of(Vector2i(2, 2)))
	s.update_center(_center_of(Vector2i(6, 6)))
	s.update_center(_center_of(Vector2i(2, 2)))
	await _settle(s)
	assert_eq(s.loaded_coords().size(), 25)
	assert_eq(s.get_child_count(), s.loaded_coords().size())
