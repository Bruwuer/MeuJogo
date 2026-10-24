extends GameTest

const B := GameConstants.Building
const R := GameConstants.Res

var _gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
var _scatter := PropScatter.new(_gen, GameConstants.WORLD_SEED)


func _rich_state() -> WorldState:
	var s := WorldState.new()
	s.add_resource(R.WOOD, 500)
	s.add_resource(R.STONE, 500)
	return s


func _solid_props_touching(type: int, pos: Vector3, rot: int) -> Array:
	var rect := BuildRules.footprint_rect(type, pos, rot)
	var out := []
	for p in _scatter.props_near(pos, 8.0):
		var r: float = GameConstants.PROP_COLLISION_RADIUS[p.type] * p.scale
		if r > 0.0 and BuildRules.circle_hits_rect(Vector2(p.pos.x, p.pos.z), r, rect):
			out.append(p)
	return out


func _height_diff(type: int, pos: Vector3) -> float:
	var rect := BuildRules.footprint_rect(type, pos, 0)
	var lo := INF
	var hi := -INF
	for x in [rect.position.x, rect.end.x, pos.x]:
		for z in [rect.position.y, rect.end.y, pos.z]:
			var h := _gen.height_at(x, z)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return hi - lo


## First grid point (inside the map) satisfying `ok(pos)`.
func _find(ok: Callable) -> Vector3:
	for z in range(40, 700, 6):
		for x in range(40, 700, 6):
			var p := Vector3(x, 0, z)
			if ok.call(p):
				return p
	return Vector3(-1, -1, -1)


func _flat_clear(type: int) -> Vector3:
	return _find(func(p: Vector3) -> bool:
		return _height_diff(type, p) < 0.3 and _solid_props_touching(type, p, 0).is_empty() \
				and _scatter.props_near(p, 6.0).is_empty())


func test_ok_on_flat_clear_ground() -> void:
	var p := _flat_clear(B.CABIN)
	var r := BuildRules.check(B.CABIN, p, 0, _gen, _scatter, _rich_state())
	assert_true(r.ok, "expected ok, got '%s'" % r.reason)


func test_outside_map() -> void:
	var r := BuildRules.check(B.CABIN, Vector3(1.0, 0, 300), 0, _gen, _scatter, _rich_state())
	assert_eq(r.reason, GameConstants.BUILD_MSG_OUTSIDE)


func test_too_steep() -> void:
	var p := _find(func(p: Vector3) -> bool: return _height_diff(B.CABIN, p) > 3.0)
	var r := BuildRules.check(B.CABIN, p, 0, _gen, _scatter, _rich_state())
	assert_eq(r.reason, GameConstants.BUILD_MSG_SLOPE)


func _gentle_oak() -> Dictionary:
	for cy in range(2, 22):
		for cx in range(2, 22):
			for p in _scatter.build_chunk_props(Vector2i(cx, cy)):
				if p.type == GameConstants.Prop.OAK and _height_diff(B.CAMPFIRE, p.pos) < 0.5:
					return p
	return {}


func test_blocked_by_tree() -> void:
	var oak := _gentle_oak()
	var r := BuildRules.check(B.CAMPFIRE, oak.pos, 0, _gen, _scatter, _rich_state())
	assert_eq(r.reason, GameConstants.BUILD_MSG_PROP)


func test_removed_tree_does_not_block() -> void:
	var oak := _gentle_oak()
	var s := _rich_state()
	for p in _solid_props_touching(B.CAMPFIRE, oak.pos, 0):
		s.mark_removed(ChunkMath.world_to_chunk(p.pos), p.id)
	var r := BuildRules.check(B.CAMPFIRE, oak.pos, 0, _gen, _scatter, s)
	assert_true(r.reason != GameConstants.BUILD_MSG_PROP, "removed trees still block")


func test_bush_is_cleared_not_blocking() -> void:
	var bush := {}
	for cy in range(2, 22):
		for cx in range(2, 22):
			for p in _scatter.build_chunk_props(Vector2i(cx, cy)):
				if p.type == GameConstants.Prop.BUSH and _solid_props_touching(B.CAMPFIRE, p.pos, 0).is_empty() \
						and _height_diff(B.CAMPFIRE, p.pos) < 0.5:
					bush = p
					break
			if not bush.is_empty():
				break
		if not bush.is_empty():
			break
	var r := BuildRules.check(B.CAMPFIRE, bush.pos, 0, _gen, _scatter, _rich_state())
	assert_true(r.ok, "bush blocked: %s" % r.reason)
	assert_true(r.bushes.any(func(b: Dictionary) -> bool: return b.id == bush.id), "bush not listed for clearing")


func test_overlap_other_building() -> void:
	var p := _flat_clear(B.CABIN)
	var s := _rich_state()
	s.add_building(B.CABIN, p, 0)
	assert_eq(BuildRules.check(B.CABIN, p + Vector3(0.5, 0, 0), 0, _gen, _scatter, s).reason, GameConstants.BUILD_MSG_OCCUPIED)


func test_touching_is_not_overlap() -> void:
	var p := _find(func(p: Vector3) -> bool:
		return _height_diff(B.FENCE, p) < 0.3 and _height_diff(B.FENCE, p + Vector3(3, 0, 0)) < 0.3 \
				and _scatter.props_near(p, 6.0).is_empty())
	var s := _rich_state()
	s.add_building(B.FENCE, p, 0)
	var r := BuildRules.check(B.FENCE, p + Vector3(3, 0, 0), 0, _gen, _scatter, s)
	assert_true(r.reason != GameConstants.BUILD_MSG_OCCUPIED, "edge-to-edge fences counted as overlap")


func test_fences_may_cross() -> void:
	var p := _find(func(p: Vector3) -> bool: return _height_diff(B.FENCE, p) < 0.3 and _scatter.props_near(p, 4.0).is_empty())
	var s := _rich_state()
	s.add_building(B.FENCE, p, 0)
	var r := BuildRules.check(B.FENCE, p, 1, _gen, _scatter, s)
	assert_true(r.reason != GameConstants.BUILD_MSG_OCCUPIED, "fence corner blocked")


func test_missing_resource_message() -> void:
	var p := _flat_clear(B.CABIN)
	var s := WorldState.new()
	s.add_resource(R.WOOD, 12)
	assert_eq(BuildRules.check(B.CABIN, p, 0, _gen, _scatter, s).reason, "Falta madeira (12/30)")


func test_flag_ignores_resources() -> void:
	var p := _flat_clear(B.CABIN)
	assert_true(BuildRules.check(B.FLAG, p, 0, _gen, _scatter, WorldState.new()).ok)


func test_rotation_swaps_footprint() -> void:
	var a := BuildRules.footprint_rect(B.CABIN, Vector3(10, 0, 10), 0)
	var b := BuildRules.footprint_rect(B.CABIN, Vector3(10, 0, 10), 1)
	assert_eq(a.size, Vector2(4, 5))
	assert_eq(b.size, Vector2(5, 4))
	assert_eq(b.get_center(), Vector2(10, 10))


func test_y_is_max_ground() -> void:
	var p := _flat_clear(B.CABIN)
	var r := BuildRules.check(B.CABIN, p, 0, _gen, _scatter, _rich_state())
	var rect := BuildRules.footprint_rect(B.CABIN, p, 0)
	var hi := -INF
	var x := rect.position.x
	while x <= rect.end.x + 0.001:
		var z := rect.position.y
		while z <= rect.end.y + 0.001:
			hi = maxf(hi, _gen.height_at(x, z))
			z += GameConstants.BUILD_SAMPLE_STEP
		x += GameConstants.BUILD_SAMPLE_STEP
	assert_near(r.y, hi, 0.001)


func test_snap() -> void:
	assert_eq(BuildRules.snap(Vector3(10.26, 3.0, 7.74)), Vector3(10.5, 3.0, 7.5))


func test_rejects_footprint_over_player() -> void:
	var p := _flat_clear(B.CABIN)
	var r := BuildRules.check(B.CABIN, p, 0, _gen, _scatter, _rich_state(), [p + Vector3(1.0, 0, 1.0)])
	assert_eq(r.reason, GameConstants.BUILD_MSG_PLAYER)
	var far := BuildRules.check(B.CABIN, p, 0, _gen, _scatter, _rich_state(), [p + Vector3(6.0, 0, 0)])
	assert_true(far.ok, "player far away still blocks: %s" % far.reason)


func test_tree_crown_blocks_near_trunk() -> void:
	# A trunk 0.9 m outside the cabin wall: the trunk misses, but the crown would cross the wall.
	var oak := _gentle_oak()
	var pos: Vector3 = oak.pos + Vector3(2.0 + 0.9, 0, 0) # cabin half-width 2 m along X
	var s := _rich_state()
	for p in _scatter.props_near(pos, 8.0):
		if p.id != oak.id or ChunkMath.world_to_chunk(p.pos) != ChunkMath.world_to_chunk(oak.pos):
			s.mark_removed(ChunkMath.world_to_chunk(p.pos), p.id)
	var r := BuildRules.check(B.CABIN, pos, 0, _gen, _scatter, s)
	assert_true(r.reason == GameConstants.BUILD_MSG_PROP or r.reason == GameConstants.BUILD_MSG_SLOPE,
			"crown ignored: %s" % (r.reason if r.reason != "" else "ok"))
	if r.reason == GameConstants.BUILD_MSG_SLOPE:
		failures.append("test spot too steep; pick another oak")


func test_check_site_ignores_cost() -> void:
	var pos := _flat_clear(B.CABIN)
	var poor := WorldState.new()
	assert_true(not BuildRules.check(B.CABIN, pos, 0, _gen, _scatter, poor).ok, "player can't afford")
	var site := BuildRules.check_site(B.CABIN, pos, 0, _gen, _scatter, poor)
	assert_true(site.ok, "site check is about the place only: %s" % site.reason)
	var blocked := BuildRules.check_site(B.CABIN, pos, 0, _gen, _scatter, poor, [pos])
	assert_true(not blocked.ok, "someone standing there blocks it")
