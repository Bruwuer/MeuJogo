class_name SpawnPicker
extends RefCounted
## Picks spawn points on gentle ground, away from the map edge and from solid props.

const _PROP_SEARCH_EXTRA := 2.0 ## Covers the largest scaled collision radius.
const _RING_STEP := 1.5 ## nearest_clear: distance between search rings (m).
const _RING_MAX := 30.0 ## nearest_clear: give up beyond this radius.
const _EDGE_KEEP := 1.0 ## nearest_clear: stay this far inside the playable square.


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


## The closest valid point to `pos` (searching outward in rings), placed on the ground.
## Used when restoring a saved position whose terrain or props may have changed.
static func nearest_clear(gen: TerrainGenerator, scatter: PropScatter, pos: Vector3) -> Vector3:
	var size := ChunkMath.playable_size()
	var r := 0.0
	while r <= _RING_MAX:
		var samples := 1 if r == 0.0 else int(ceil(TAU * r / _RING_STEP))
		for i in samples:
			var a := TAU * i / samples
			var x := clampf(pos.x + cos(a) * r, _EDGE_KEEP, size - _EDGE_KEEP)
			var z := clampf(pos.z + sin(a) * r, _EDGE_KEEP, size - _EDGE_KEEP)
			var p := Vector3(x, gen.height_at(x, z), z)
			if gen.slope_deg_at(x, z) <= GameConstants.SPAWN_MAX_SLOPE_DEG and _clear_of_props(scatter, p):
				return p
		r += _RING_STEP
	var c := size * 0.5
	return Vector3(c, gen.height_at(c, c), c)


static func _clear_of_props(scatter: PropScatter, p: Vector3) -> bool:
	for prop in scatter.props_near(p, GameConstants.SPAWN_PROP_CLEARANCE + _PROP_SEARCH_EXTRA):
		var r: float = GameConstants.PROP_COLLISION_RADIUS[prop.type] * prop.scale
		if r > 0.0 and Vector2(prop.pos.x - p.x, prop.pos.z - p.z).length() < GameConstants.SPAWN_PROP_CLEARANCE + r:
			return false
	return true
