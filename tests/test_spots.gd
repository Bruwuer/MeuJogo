class_name TestSpots
extends RefCounted
## Finds world positions with given properties for tests (deterministic for a seed).


static func height_diff(gen: TerrainGenerator, type: int, pos: Vector3, rot := 0) -> float:
	var rect := BuildRules.footprint_rect(type, pos, rot)
	var lo := INF
	var hi := -INF
	for x in [rect.position.x, rect.end.x, pos.x]:
		for z in [rect.position.y, rect.end.y, pos.z]:
			var h := gen.height_at(x, z)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return hi - lo


## A flat spot with no prop at all within `clearance` m, scanning from `start`.
static func flat_clear(gen: TerrainGenerator, scatter: PropScatter, type: int, clearance := 6.0,
		start := Vector2(40, 40)) -> Vector3:
	var z := start.y
	while z < 700.0:
		var x := start.x
		while x < 700.0:
			var p := Vector3(x, 0, z)
			if height_diff(gen, type, p) < 0.3 and scatter.props_near(p, clearance).is_empty():
				return Vector3(p.x, gen.height_at(p.x, p.z), p.z)
			x += 6.0
		z += 6.0
	return Vector3(-1, -1, -1)
