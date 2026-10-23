class_name SpawnPicker
extends RefCounted
## Picks a random spawn point on gentle ground away from the map edge.


static func pick(gen: TerrainGenerator, rng: RandomNumberGenerator) -> Vector3:
	var lo := GameConstants.SPAWN_EDGE_MARGIN
	var hi := ChunkMath.playable_size() - GameConstants.SPAWN_EDGE_MARGIN
	for i in GameConstants.SPAWN_MAX_TRIES:
		var x := rng.randf_range(lo, hi)
		var z := rng.randf_range(lo, hi)
		if gen.slope_deg_at(x, z) <= GameConstants.SPAWN_MAX_SLOPE_DEG:
			return Vector3(x, gen.height_at(x, z), z)
	var c := ChunkMath.playable_size() * 0.5
	return Vector3(c, gen.height_at(c, c), c)
