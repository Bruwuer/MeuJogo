extends GameTest


func _pick(seed: int) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return SpawnPicker.pick(TerrainGenerator.new(GameConstants.WORLD_SEED), rng)


func test_spawn_inside_margin() -> void:
	var lo := GameConstants.SPAWN_EDGE_MARGIN
	var hi := ChunkMath.playable_size() - GameConstants.SPAWN_EDGE_MARGIN
	for s in 100:
		var p := _pick(s)
		assert_true(p.x >= lo and p.x <= hi and p.z >= lo and p.z <= hi, "seed %d spawn %s" % [s, p])


func test_spawn_slope_ok() -> void:
	var gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
	var center := ChunkMath.playable_size() * 0.5
	for s in 100:
		var p := _pick(s)
		var is_fallback := is_equal_approx(p.x, center) and is_equal_approx(p.z, center)
		assert_true(is_fallback or gen.slope_deg_at(p.x, p.z) <= GameConstants.SPAWN_MAX_SLOPE_DEG, "seed %d too steep" % s)


func test_spawn_on_ground() -> void:
	var gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
	var p := _pick(5)
	assert_near(p.y, gen.height_at(p.x, p.z), 0.0001)


func test_spawn_seeded_deterministic() -> void:
	assert_eq(_pick(42), _pick(42))


func test_spawn_varies_with_seed() -> void:
	assert_true(_pick(1) != _pick(2))
