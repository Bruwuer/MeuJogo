class_name ChunkMath
extends RefCounted
## Pure chunk-coordinate helpers. Chunk (0,0) starts at world origin; the playable map
## spans chunks 0..MAP_CHUNKS-1 on X and Z, surrounded by a BORDER_CHUNKS visual ring.


static func world_to_chunk(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / GameConstants.CHUNK_SIZE), floori(p.z / GameConstants.CHUNK_SIZE))


static func chunk_origin(c: Vector2i) -> Vector3:
	return Vector3(c.x * GameConstants.CHUNK_SIZE, 0.0, c.y * GameConstants.CHUNK_SIZE)


static func is_playable(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < GameConstants.MAP_CHUNKS and c.y < GameConstants.MAP_CHUNKS


static func is_in_world(c: Vector2i) -> bool:
	var lo := -GameConstants.BORDER_CHUNKS
	var hi := GameConstants.MAP_CHUNKS - 1 + GameConstants.BORDER_CHUNKS
	return c.x >= lo and c.y >= lo and c.x <= hi and c.y <= hi


static func chunks_in_radius(center: Vector2i, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(center.y - r, center.y + r + 1):
		for x in range(center.x - r, center.x + r + 1):
			var c := Vector2i(x, y)
			if is_in_world(c):
				out.append(c)
	return out


static func playable_size() -> float:
	return GameConstants.MAP_CHUNKS * GameConstants.CHUNK_SIZE
