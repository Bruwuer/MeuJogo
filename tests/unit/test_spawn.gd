extends GameTest


func _pick(seed: int) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
	return SpawnPicker.pick(gen, PropScatter.new(gen, GameConstants.WORLD_SEED), rng)


func test_spawn_clear_of_props() -> void:
	var gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
	var scatter := PropScatter.new(gen, GameConstants.WORLD_SEED)
	var center := ChunkMath.playable_size() * 0.5
	for s in 100:
		var p := _pick(s)
		if is_equal_approx(p.x, center) and is_equal_approx(p.z, center):
			continue
		for prop: Dictionary in scatter.props_near(p, GameConstants.SPAWN_PROP_CLEARANCE + 2.0):
			var r: float = GameConstants.PROP_COLLISION_RADIUS[prop.type] * prop.scale
			if r <= 0.0:
				continue
			var d := Vector2(prop.pos.x - p.x, prop.pos.z - p.z).length()
			assert_true(d >= GameConstants.SPAWN_PROP_CLEARANCE + r, "seed %d spawn %.2f m from a prop" % [s, d])


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


func test_nearest_clear_moves_out_of_a_rock() -> void:
	var gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
	var scatter := PropScatter.new(gen, GameConstants.WORLD_SEED)
	var rock := {}
	for cy in range(2, 20):
		for p in scatter.build_chunk_props(Vector2i(10, cy)):
			if p.type == GameConstants.Prop.ROCK:
				rock = p
				break
		if not rock.is_empty():
			break
	assert_true(not rock.is_empty(), "no rock found")
	if rock.is_empty():
		return
	var inside: Vector3 = rock.pos + Vector3(0, -30, 0) # inside the rock and under the ground
	var p := SpawnPicker.nearest_clear(gen, scatter, inside)
	var r: float = GameConstants.PROP_COLLISION_RADIUS[GameConstants.Prop.ROCK] * rock.scale
	assert_true(Vector2(p.x - rock.pos.x, p.z - rock.pos.z).length() >= r, "still inside the rock")
	assert_near(p.y, gen.height_at(p.x, p.z), 0.001, "not on the ground")


func test_nearest_clear_keeps_a_clear_point() -> void:
	var gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
	var scatter := PropScatter.new(gen, GameConstants.WORLD_SEED)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var spawn := SpawnPicker.pick(gen, scatter, rng)
	var p := SpawnPicker.nearest_clear(gen, scatter, spawn + Vector3(0, 40, 0))
	assert_near(p.x, spawn.x, 0.001)
	assert_near(p.z, spawn.z, 0.001)
	assert_near(p.y, gen.height_at(p.x, p.z), 0.001)
