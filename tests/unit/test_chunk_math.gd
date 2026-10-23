extends GameTest


func test_world_to_chunk() -> void:
	assert_eq(ChunkMath.world_to_chunk(Vector3(33, 0, -1)), Vector2i(1, -1))


func test_chunk_origin() -> void:
	assert_eq(ChunkMath.chunk_origin(Vector2i(2, 3)), Vector3(64, 0, 96))


func test_playable_bounds() -> void:
	assert_true(ChunkMath.is_playable(Vector2i(7, 7)))
	assert_true(not ChunkMath.is_playable(Vector2i(8, 0)))
	assert_true(not ChunkMath.is_playable(Vector2i(0, -1)))


func test_border_in_world() -> void:
	assert_true(ChunkMath.is_in_world(Vector2i(-1, 8)))
	assert_true(not ChunkMath.is_in_world(Vector2i(-2, 0)))
	assert_true(not ChunkMath.is_in_world(Vector2i(0, 9)))


func test_radius_clipped_to_world() -> void:
	var cs := ChunkMath.chunks_in_radius(Vector2i(0, 0), 2)
	assert_eq(cs.size(), 16) # x and y in -1..2
	for c in cs:
		assert_true(ChunkMath.is_in_world(c), "outside world: %s" % c)


func test_playable_size() -> void:
	assert_eq(ChunkMath.playable_size(), 256.0)
