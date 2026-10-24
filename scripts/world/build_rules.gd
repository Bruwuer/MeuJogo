class_name BuildRules
extends RefCounted
## Pure placement validation for buildings: map bounds, ground flatness, trees/rocks, other
## buildings and resources, in that order (the first failure is the reason shown to the player).

const _PROP_SEARCH_EXTRA := 2.0 ## Covers the largest scaled prop collision radius.


## XZ footprint centered on `pos`; odd quarter turns swap width and depth.
static func footprint_rect(type: int, pos: Vector3, rot: int) -> Rect2:
	var size: Vector2 = GameConstants.BUILD_FOOTPRINT[type]
	if rot % 2 == 1:
		size = Vector2(size.y, size.x)
	return Rect2(Vector2(pos.x, pos.z) - size * 0.5, size)


static func snap(pos: Vector3) -> Vector3:
	var g := GameConstants.BUILD_GRID
	return Vector3(snappedf(pos.x, g), pos.y, snappedf(pos.z, g))


static func circle_hits_rect(center: Vector2, radius: float, rect: Rect2) -> bool:
	var closest := Vector2(clampf(center.x, rect.position.x, rect.end.x), clampf(center.y, rect.position.y, rect.end.y))
	return closest.distance_to(center) < radius


## {ok: bool, reason: String, y: float, bushes: Array[{chunk: Vector2i, id: int}]}.
## `y` is the highest ground under the footprint (the building's floor level).
static func check(type: int, pos: Vector3, rot: int, gen: TerrainGenerator, scatter: PropScatter,
		state: WorldState) -> Dictionary:
	var rect := footprint_rect(type, pos, rot)
	var result := {ok = false, reason = "", y = 0.0, bushes = []}
	var map := Rect2(Vector2.ZERO, Vector2.ONE * ChunkMath.playable_size())
	if not map.encloses(rect):
		result.reason = GameConstants.BUILD_MSG_OUTSIDE
		return result

	var lo := INF
	var hi := -INF
	var x := rect.position.x
	while x <= rect.end.x + 0.001:
		var z := rect.position.y
		while z <= rect.end.y + 0.001:
			var h := gen.height_at(x, z)
			lo = minf(lo, h)
			hi = maxf(hi, h)
			z += GameConstants.BUILD_SAMPLE_STEP
		x += GameConstants.BUILD_SAMPLE_STEP
	result.y = hi
	if hi - lo > GameConstants.BUILD_MAX_HEIGHT_DIFF:
		result.reason = GameConstants.BUILD_MSG_SLOPE
		return result

	if type != GameConstants.Building.FLAG:
		var search := rect.size.length() * 0.5 + _PROP_SEARCH_EXTRA
		for p in scatter.props_near(pos, search):
			var c := ChunkMath.world_to_chunk(p.pos)
			if state.removed_in(c).has(p.id):
				continue
			var center := Vector2(p.pos.x, p.pos.z)
			var radius: float = GameConstants.PROP_COLLISION_RADIUS[p.type] * p.scale
			if radius > 0.0:
				if circle_hits_rect(center, radius, rect):
					result.reason = GameConstants.BUILD_MSG_PROP
					return result
			elif circle_hits_rect(center, GameConstants.BUILD_BUSH_CLEAR_RADIUS, rect):
				result.bushes.append({chunk = c, id = p.id})

		if _overlaps_building(type, rect, state):
			result.reason = GameConstants.BUILD_MSG_OCCUPIED
			return result

		var cost: Dictionary = GameConstants.BUILD_COST[type]
		for res in cost:
			if state.get_resource(res) < cost[res]:
				result.reason = GameConstants.BUILD_MSG_MISSING % [
					(GameConstants.RES_NAMES[res] as String).to_lower(), state.get_resource(res), cost[res]]
				return result

	result.ok = true
	return result


static func _overlaps_building(type: int, rect: Rect2, state: WorldState) -> bool:
	var shrunk := rect.grow(-GameConstants.BUILD_TOUCH_TOLERANCE)
	var lo := ChunkMath.world_to_chunk(Vector3(rect.position.x, 0, rect.position.y)) - Vector2i.ONE
	var hi := ChunkMath.world_to_chunk(Vector3(rect.end.x, 0, rect.end.y)) + Vector2i.ONE
	for cy in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			for b in state.buildings_in(Vector2i(cx, cy)):
				if b.type == GameConstants.Building.FLAG:
					continue
				if type == GameConstants.Building.FENCE and b.type == GameConstants.Building.FENCE:
					continue
				if shrunk.intersects(footprint_rect(b.type, b.pos, b.rot).grow(-GameConstants.BUILD_TOUCH_TOLERANCE)):
					return true
	return false
