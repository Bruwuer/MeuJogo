class_name SpawnPicker
extends RefCounted
## Picks a random spawn point on gentle ground, away from the map edge and from solid props.

const _PROP_SEARCH_EXTRA := 2.0 ## Covers the largest scaled collision radius.


static func pick(gen: TerrainGenerator, scatter: PropScatter, rng: RandomNumberGenerator) -> Vector3:
	var lo := GameConstants.SPAWN_EDGE_MARGIN
	var hi := ChunkMath.playable_size() - GameConstants.SPAWN_EDGE_MARGIN
	for i in GameConstants.SPAWN_MAX_TRIES:
		var x := rng.randf_range(lo, hi)
		var z := rng.randf_range(lo, hi)
		var p := Vector3(x, gen.height_at(x, z), z)
		if gen.slope_deg_at(x, z) <= GameConstants.SPAWN_MAX_SLOPE_DEG and _clear_of_props(scatter, p):
			return p
	var c := ChunkMath.playable_size() * 0.5
	return Vector3(c, gen.height_at(c, c), c)


static func _clear_of_props(scatter: PropScatter, p: Vector3) -> bool:
	for prop in scatter.props_near(p, GameConstants.SPAWN_PROP_CLEARANCE + _PROP_SEARCH_EXTRA):
		var r: float = GameConstants.PROP_COLLISION_RADIUS[prop.type] * prop.scale
		if r > 0.0 and Vector2(prop.pos.x - p.x, prop.pos.z - p.z).length() < GameConstants.SPAWN_PROP_CLEARANCE + r:
			return false
	return true
