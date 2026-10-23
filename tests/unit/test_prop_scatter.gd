extends GameTest


func _scatter() -> PropScatter:
	return PropScatter.new(TerrainGenerator.new(GameConstants.WORLD_SEED), GameConstants.WORLD_SEED)


func _cells() -> int:
	return int(GameConstants.CHUNK_SIZE / GameConstants.PROP_CELL)


func test_deterministic() -> void:
	assert_eq(_scatter().build_chunk_props(Vector2i(3, 4)), _scatter().build_chunk_props(Vector2i(3, 4)))


func test_props_inside_chunk() -> void:
	var s := _scatter()
	var gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
	var c := Vector2i(5, 9)
	var o := ChunkMath.chunk_origin(c)
	for p: Dictionary in s.build_chunk_props(c):
		var pos: Vector3 = p.pos
		assert_true(pos.x >= o.x and pos.x < o.x + GameConstants.CHUNK_SIZE and pos.z >= o.z and pos.z < o.z + GameConstants.CHUNK_SIZE, "outside: %s" % pos)
		assert_near(pos.y, gen.height_at(pos.x, pos.z), 0.2)


func test_ids_unique_and_in_range() -> void:
	var seen := {}
	for p: Dictionary in _scatter().build_chunk_props(Vector2i(10, 10)):
		assert_true(not seen.has(p.id), "duplicate id %d" % p.id)
		assert_true(p.id >= 0 and p.id < _cells() * _cells())
		seen[p.id] = true


func test_ids_are_grid_cells() -> void:
	var c := Vector2i(7, 2)
	var o := ChunkMath.chunk_origin(c)
	for p: Dictionary in _scatter().build_chunk_props(c):
		var local: Vector3 = p.pos - o
		var i := floori(local.x / GameConstants.PROP_CELL)
		var j := floori(local.z / GameConstants.PROP_CELL)
		assert_eq(p.id, j * _cells() + i)


func test_forest_denser_than_plains() -> void:
	var s := _scatter()
	var gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
	var totals := {GameConstants.Biome.FOREST: 0, GameConstants.Biome.PLAINS: 0}
	var chunks := {GameConstants.Biome.FOREST: 0, GameConstants.Biome.PLAINS: 0}
	for cy in range(0, GameConstants.MAP_CHUNKS, 2):
		for cx in range(0, GameConstants.MAP_CHUNKS, 2):
			var center := ChunkMath.chunk_origin(Vector2i(cx, cy)) + Vector3(16, 0, 16)
			var b := gen.biome_at(center.x, center.z)
			if totals.has(b):
				totals[b] += s.build_chunk_props(Vector2i(cx, cy)).size()
				chunks[b] += 1
	assert_true(chunks[GameConstants.Biome.FOREST] > 0 and chunks[GameConstants.Biome.PLAINS] > 0, "need both biomes")
	var forest := float(totals[GameConstants.Biome.FOREST]) / maxi(1, chunks[GameConstants.Biome.FOREST])
	var plains := float(totals[GameConstants.Biome.PLAINS]) / maxi(1, chunks[GameConstants.Biome.PLAINS])
	assert_true(forest > plains * 2.0, "forest %.1f vs plains %.1f props/chunk" % [forest, plains])


func test_no_props_on_steep_slope() -> void:
	var gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
	var s := _scatter()
	for c in [Vector2i(1, 1), Vector2i(12, 12), Vector2i(20, 5)]:
		for p: Dictionary in s.build_chunk_props(c):
			assert_true(gen.slope_deg_at(p.pos.x, p.pos.z) <= GameConstants.PROP_MAX_SLOPE_DEG)


func test_props_near_filters_by_distance() -> void:
	var s := _scatter()
	var center := Vector3(200, 0, 200)
	for p: Dictionary in s.props_near(center, 10.0):
		var d := Vector2(p.pos.x - center.x, p.pos.z - center.z).length()
		assert_true(d <= 10.0, "too far: %f" % d)
