extends GameTest

const SAMPLE_STEP := 16.0


func _samples(gen: TerrainGenerator) -> Array:
	var out := []
	var size := ChunkMath.playable_size()
	var x := 0.0
	while x < size:
		var z := 0.0
		while z < size:
			out.append(Vector2(x, z))
			z += SAMPLE_STEP
		x += SAMPLE_STEP
	return out


func test_biome_deterministic() -> void:
	assert_eq(TerrainGenerator.new(7).biome_at(300, 120), TerrainGenerator.new(7).biome_at(300, 120))


func test_all_biomes_present() -> void:
	var gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
	var counts := {GameConstants.Biome.PLAINS: 0, GameConstants.Biome.FOREST: 0, GameConstants.Biome.ROCKY: 0}
	var points := _samples(gen)
	for p: Vector2 in points:
		counts[gen.biome_at(p.x, p.y)] += 1
	for b in counts:
		var share := float(counts[b]) / points.size()
		assert_true(share >= 0.10, "%s covers %.0f%%" % [GameConstants.BIOME_NAMES[b], share * 100.0])


func test_height_continuous_across_biomes() -> void:
	var gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 2000:
		var x := rng.randf_range(0, 768)
		var z := rng.randf_range(0, 768)
		# 5 cm apart: a real seam would jump; even a 75 degree slope moves < 0.2 m.
		var d := absf(gen.height_at(x, z) - gen.height_at(x + 0.05, z))
		assert_true(d < 0.2, "jump %.2f at (%.1f, %.1f)" % [d, x, z])
		if d >= 0.2:
			return


func test_rocky_is_higher_on_average() -> void:
	var gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
	var sums := {GameConstants.Biome.PLAINS: 0.0, GameConstants.Biome.ROCKY: 0.0}
	var counts := {GameConstants.Biome.PLAINS: 0, GameConstants.Biome.ROCKY: 0}
	for p: Vector2 in _samples(gen):
		var b := gen.biome_at(p.x, p.y)
		if sums.has(b):
			sums[b] += gen.height_at(p.x, p.y)
			counts[b] += 1
	var rocky: float = sums[GameConstants.Biome.ROCKY] / maxi(1, counts[GameConstants.Biome.ROCKY])
	var plains: float = sums[GameConstants.Biome.PLAINS] / maxi(1, counts[GameConstants.Biome.PLAINS])
	assert_true(rocky > plains, "rocky %.2f vs plains %.2f" % [rocky, plains])


func _mean_slope(gen: TerrainGenerator, biome: int) -> float:
	var sum := 0.0
	var n := 0
	for p: Vector2 in _samples(gen):
		if gen.biome_at(p.x, p.y) == biome:
			sum += gen.slope_deg_at(p.x, p.y)
			n += 1
	return sum / maxi(1, n)


func test_plains_are_flatter_than_forest() -> void:
	var gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
	var plains := _mean_slope(gen, GameConstants.Biome.PLAINS)
	var forest := _mean_slope(gen, GameConstants.Biome.FOREST)
	assert_true(plains < forest * 0.7, "plains %.1f° vs forest %.1f°" % [plains, forest])
	assert_true(plains < 12.0, "plains too hilly to build: %.1f°" % plains)


func test_village_sites_exist_in_plains() -> void:
	# An 18 x 18 m patch with < 1 m of height variation: room for a cabin and neighbors.
	var gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
	var sites := 0
	for z in range(60, 700, 24):
		for x in range(60, 700, 24):
			if gen.biome_at(x, z) != GameConstants.Biome.PLAINS:
				continue
			var lo := INF
			var hi := -INF
			for dz in [-9.0, -4.5, 0.0, 4.5, 9.0]:
				for dx in [-9.0, -4.5, 0.0, 4.5, 9.0]:
					var h := gen.height_at(x + dx, z + dz)
					lo = minf(lo, h)
					hi = maxf(hi, h)
			if hi - lo < 1.0:
				sites += 1
	assert_true(sites >= 10, "only %d village sites" % sites)
