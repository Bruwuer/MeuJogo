extends GameTest


func test_deterministic() -> void:
	assert_eq(TerrainGenerator.new(7).height_at(10.5, 3.2), TerrainGenerator.new(7).height_at(10.5, 3.2))


func test_seed_changes_terrain() -> void:
	assert_true(TerrainGenerator.new(1).height_at(50, 50) != TerrainGenerator.new(2).height_at(50, 50))


func test_height_range() -> void:
	var gen := TerrainGenerator.new(7)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 200:
		var h := gen.height_at(rng.randf_range(-64, 320), rng.randf_range(-64, 320))
		assert_true(h >= 0.0 and h <= GameConstants.TERRAIN_HEIGHT * (1.0 + GameConstants.ROCKY_HEIGHT_BOOST), "height out of range: %f" % h)


func test_terrain_not_flat() -> void:
	var gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
	var lo := INF
	var hi := -INF
	for x in range(0, 256, 8):
		for z in range(0, 256, 8):
			var h := gen.height_at(x, z)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	assert_true(hi - lo > GameConstants.TERRAIN_HEIGHT * 0.3, "terrain too flat: %f" % (hi - lo))


func test_slope_flat_vs_steep() -> void:
	var gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
	var s := gen.slope_deg_at(100, 100)
	assert_true(s >= 0.0 and s < 90.0)


func test_chunk_mesh_shape() -> void:
	var a := TerrainGenerator.new(7).build_chunk_arrays(Vector2i(2, 3))
	assert_eq(a.size(), Mesh.ARRAY_MAX)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	assert_eq(verts.size(), GameConstants.CHUNK_CELLS ** 2 * 6)
	assert_eq((a[Mesh.ARRAY_NORMAL] as PackedVector3Array).size(), verts.size())
	assert_eq((a[Mesh.ARRAY_COLOR] as PackedColorArray).size(), verts.size())


func test_chunk_vertices_are_local() -> void:
	var verts: PackedVector3Array = TerrainGenerator.new(7).build_chunk_arrays(Vector2i(2, 3))[Mesh.ARRAY_VERTEX]
	for v in verts:
		assert_true(v.x >= 0.0 and v.x <= GameConstants.CHUNK_SIZE and v.z >= 0.0 and v.z <= GameConstants.CHUNK_SIZE)


func test_normals_point_up_and_front_faces_up() -> void:
	var a := TerrainGenerator.new(7).build_chunk_arrays(Vector2i(0, 0))
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	for i in range(0, verts.size(), 3):
		assert_true(normals[i].y > 0.0)
		# Godot front faces are clockwise: (c - a) x (b - a) must point up.
		assert_true((verts[i + 2] - verts[i]).cross(verts[i + 1] - verts[i]).y > 0.0)


func test_chunk_edges_match() -> void:
	var gen := TerrainGenerator.new(7)
	var size := GameConstants.CHUNK_SIZE
	for v in gen.build_chunk_arrays(Vector2i(0, 0))[Mesh.ARRAY_VERTEX] as PackedVector3Array:
		if is_equal_approx(v.x, size):
			assert_near(v.y, gen.height_at(size, v.z), 0.0001)
	for v in gen.build_chunk_arrays(Vector2i(1, 0))[Mesh.ARRAY_VERTEX] as PackedVector3Array:
		if is_equal_approx(v.x, 0.0):
			assert_near(v.y, gen.height_at(size, v.z), 0.0001)
