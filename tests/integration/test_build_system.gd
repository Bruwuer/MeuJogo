extends GameTest

const B := GameConstants.Building
const R := GameConstants.Res

var _gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
var _scatter := PropScatter.new(_gen, GameConstants.WORLD_SEED)
var _state := WorldState.new()
var _streamer: ChunkStreamer
var _player: Player
var _build: BuildSystem


func _setup(at: Vector3) -> void:
	_state.seed = GameConstants.WORLD_SEED
	var lib := ModelLibrary.new()
	add_child(lib)
	lib.start_loading()
	_streamer = ChunkStreamer.new()
	_streamer.setup(_gen, _scatter, lib, _state.removed_in, _state.buildings_in)
	add_child(_streamer)
	_streamer.update_center(at)
	_player = load("res://scenes/player.tscn").instantiate()
	add_child(_player)
	_move_player(at)
	var cam := IsoCamera.new()
	cam.target = _player
	add_child(cam)
	_build = BuildSystem.new()
	add_child(_build)
	_build.setup(_state, _gen, _scatter, _streamer, lib, _player, cam)
	_build.use_mouse = false
	for i in 900:
		if lib.is_ready() and _streamer.pending_count() == 0:
			break
		await get_tree().process_frame
	await get_tree().process_frame


## Puts the player so the ghost (3 m in front, model facing +Z) lands on `ghost_at`.
func _move_player(ghost_at: Vector3) -> void:
	var p := ghost_at - Vector3(0, 0, GameConstants.BUILD_GHOST_DISTANCE)
	_player.global_position = Vector3(p.x, _gen.height_at(p.x, p.z) + 0.2, p.z)


func _rich() -> void:
	_state.add_resource(R.WOOD, 200)
	_state.add_resource(R.STONE, 200)


func _spot(type := B.CABIN, start := Vector2(40, 40)) -> Vector3:
	return TestSpots.flat_clear(_gen, _scatter, type, 6.0, start)


func test_toggle_and_select() -> void:
	await _setup(_spot())
	_build.toggle()
	assert_true(_build.active)
	_build.select(B.WELL)
	assert_eq(_build.type, B.WELL)
	_build.rotate_ghost()
	assert_eq(_build.rot, 1)
	_build.toggle()
	assert_true(not _build.active)


func test_input_actions_drive_mode() -> void:
	await _setup(_spot())
	var ev := InputEventAction.new()
	ev.action = &"build_mode"
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	assert_true(_build.active, "B did not enter build mode")
	var sel := InputEventAction.new()
	sel.action = &"slot_5"
	sel.pressed = true
	Input.parse_input_event(sel)
	await get_tree().process_frame
	assert_eq(_build.type, GameConstants.BUILDABLE[4])


func test_place_spends_and_builds() -> void:
	var spot := _spot()
	await _setup(spot)
	_rich()
	_build.select(B.CABIN)
	assert_true(_build.try_place(), "place failed: %s" % _build.preview().reason)
	assert_eq(_state.get_resource(R.WOOD), 170)
	assert_eq(_state.get_resource(R.STONE), 190)
	var cabins := _state.all_buildings().filter(func(b: Dictionary) -> bool: return b.type == B.CABIN)
	assert_eq(cabins.size(), 1)
	assert_true(_streamer.get_chunk(ChunkMath.world_to_chunk(cabins[0].pos)).has_building(cabins[0].id))


func test_failed_place_spends_nothing() -> void:
	await _setup(_spot())
	_state.add_resource(R.WOOD, 10)
	_build.select(B.CABIN)
	assert_true(not _build.try_place())
	assert_eq(_state.get_resource(R.WOOD), 10)
	assert_eq(_state.all_buildings().size(), 0)


func test_first_cabin_founds_kingdom_with_flag() -> void:
	await _setup(_spot())
	_rich()
	var founded := []
	_build.kingdom_founded.connect(func(k: Dictionary) -> void: founded.append(k))
	_build.select(B.CABIN)
	_build.try_place()
	assert_eq(founded.size(), 1)
	assert_eq(_state.kingdoms().size(), 1)
	var k: Dictionary = _state.kingdoms()[0]
	assert_eq(k.name, KingdomNames.generate(_state.seed, 0))
	var flags := _state.all_buildings().filter(func(b: Dictionary) -> bool: return b.type == B.FLAG)
	assert_eq(flags.size(), 1)
	assert_eq(flags[0].color, k.color)
	assert_true(BuildRules.footprint_rect(B.CABIN, _state.building(k.seat_id).pos, 0).has_point(Vector2(flags[0].pos.x, flags[0].pos.z)),
			"flag outside the seat cabin footprint")


func test_second_cabin_does_not_found() -> void:
	var a := _spot()
	await _setup(a)
	_rich()
	_build.select(B.CABIN)
	assert_true(_build.try_place())
	var b := _spot(B.CABIN, Vector2(a.x + 30, a.z))
	_streamer.update_center(b)
	_move_player(b)
	while _streamer.pending_count() > 0:
		await get_tree().process_frame
	assert_true(_build.try_place(), "second cabin: %s" % _build.preview().reason)
	assert_eq(_state.kingdoms().size(), 1)


func test_place_clears_bushes() -> void:
	var bush := {}
	for cy in range(2, 22):
		for cx in range(2, 22):
			for p in _scatter.build_chunk_props(Vector2i(cx, cy)):
				if p.type == GameConstants.Prop.BUSH and BuildRules.check(B.CAMPFIRE, p.pos, 0, _gen, _scatter, _rich_state()).ok:
					bush = p
					break
			if not bush.is_empty():
				break
		if not bush.is_empty():
			break
	await _setup(BuildRules.snap(bush.pos))
	_rich()
	_build.select(B.CAMPFIRE)
	assert_true(_build.try_place(), "campfire on bush: %s" % _build.preview().reason)
	var c := ChunkMath.world_to_chunk(bush.pos)
	assert_true(_state.removed_in(c).has(bush.id), "bush not cleared")
	assert_true(not _streamer.get_chunk(c).has_prop(bush.id))


func _rich_state() -> WorldState:
	var s := WorldState.new()
	s.add_resource(R.WOOD, 100)
	s.add_resource(R.STONE, 100)
	return s


func test_demolish_refunds_half() -> void:
	var spot := _spot(B.WELL)
	await _setup(spot)
	_state.add_resource(R.WOOD, 5)
	_state.add_resource(R.STONE, 20)
	_build.select(B.WELL)
	assert_true(_build.try_place())
	var well: Dictionary = _state.all_buildings()[0]
	_build.toggle() # leave build mode
	assert_true(_build.try_demolish(_player.global_position))
	assert_eq(_state.get_resource(R.WOOD), 2)
	assert_eq(_state.get_resource(R.STONE), 10)
	assert_eq(_state.building(well.id), {})
	assert_true(not _streamer.get_chunk(ChunkMath.world_to_chunk(well.pos)).has_building(well.id))


func test_seat_cabin_cannot_be_demolished() -> void:
	await _setup(_spot())
	_rich()
	_build.select(B.CABIN)
	_build.try_place()
	_build.toggle()
	var seat: int = _state.kingdoms()[0].seat_id
	assert_true(not _build.try_demolish(_player.global_position))
	assert_true(not _state.building(seat).is_empty())


func test_ray_ignores_obstacles() -> void:
	var oak := {}
	for p in _scatter.build_chunk_props(Vector2i(8, 8)) + _scatter.build_chunk_props(Vector2i(9, 9)):
		if p.type == GameConstants.Prop.OAK:
			oak = p
			break
	await _setup(oak.pos)
	await wait_physics_frames(2)
	var top: Vector3 = oak.pos + Vector3(0, 50, 0)
	var hit: Variant = _build.ground_hit(top, oak.pos - Vector3(0, 50, 0))
	assert_true(hit != null, "ray hit nothing")
	if hit != null:
		assert_near((hit as Vector3).y, _gen.height_at(oak.pos.x, oak.pos.z), 0.3, "ray stopped on the tree")


func test_harvest_disabled_in_build_mode() -> void:
	await _setup(_spot())
	_build.toggle()
	assert_true(not _player.harvest_enabled)
	_build.toggle()
	assert_true(_player.harvest_enabled)


func test_ray_ignores_player() -> void:
	var spot := _spot()
	await _setup(spot)
	await wait_physics_frames(3)
	var pp := _player.global_position
	var hit: Variant = _build.ground_hit(pp + Vector3(0, 30, 0), pp - Vector3(0, 30, 0))
	assert_true(hit != null)
	if hit != null:
		assert_near((hit as Vector3).y, _gen.height_at(pp.x, pp.z), 0.3, "ray stopped on the player")


func test_demolish_skips_seat_for_nearby_fence() -> void:
	var spot := _spot(B.CABIN)
	await _setup(spot)
	_rich()
	_build.select(B.CABIN)
	assert_true(_build.try_place())
	# Fence touching the cabin's back wall (cabin depth 5 m: back edge at +2.5 from its center).
	var cabin: Dictionary = _state.building(_state.kingdoms()[0].seat_id)
	_build.select(B.FENCE)
	_move_player(cabin.pos + Vector3(0, 0, 2.5 + 0.2 + 0.5))
	assert_true(_build.try_place(), "fence: %s" % _build.preview().reason)
	_build.toggle()
	var fence: Dictionary = _state.all_buildings().filter(func(b: Dictionary) -> bool: return b.type == B.FENCE)[0]
	# Stand between them: the seat is the closest building, the fence is still in range.
	assert_true(_build.try_demolish(cabin.pos + Vector3(0, 0, 2.6)), "could not demolish the fence next to the seat")
	assert_eq(_state.building(fence.id), {})
	assert_true(not _state.building(cabin.id).is_empty())


func test_cannot_demolish_village_buildings() -> void:
	var spot := _spot(B.WELL)
	await _setup(spot)
	var well := _state.add_building(B.WELL, spot, 0, Color.WHITE, GameConstants.OWNER_KINGDOM)
	var msgs := []
	_build.message.connect(func(t: String) -> void: msgs.append(t))
	assert_true(not _build.try_demolish(spot), "village well demolished")
	assert_true(not _state.building(well.id).is_empty())
	assert_eq(msgs, [GameConstants.BUILD_MSG_VILLAGE])
	_state.remove_building(well.id)
	var r := RandomNumberGenerator.new()
	var owner := _state.add_person(PersonGen.generate(r), spot)
	var house := _state.add_building(B.WELL, spot, 0, Color.WHITE, owner.id)
	assert_true(not _build.try_demolish(spot), "someone's building demolished")
	assert_eq(msgs[-1], GameConstants.BUILD_MSG_NOT_YOURS % PersonGen.full_name(owner))
	assert_eq(_state.get_resource(R.STONE), 0, "no refund")
	assert_true(not _state.building(house.id).is_empty())


func test_villager_blocks_player_build() -> void:
	var spot := _spot()
	await _setup(spot)
	_rich()
	_build.toggle()
	_build.select(B.CABIN)
	_move_player(spot)
	await get_tree().process_frame
	assert_true(_build.preview().ok, "free spot")
	var someone: Vector3 = _build.ghost_position() + Vector3(0.5, 0, 0.5)
	_build.extra_blockers = func() -> Array: return [someone]
	var check := _build.preview()
	assert_true(not check.ok, "a villager stands there")
	assert_eq(check.reason, GameConstants.BUILD_MSG_PLAYER)
	assert_true(not _build.try_place(), "not built over the villager")


func test_no_building_where_the_founder_does_not_rule() -> void:
	var at := _spot()
	await _setup(at)
	_rich()
	_build.refuse_in = func(_pos: Vector3) -> String: return "O Reino de Teste não é seu: Fulano governa"
	var texts: Array[String] = []
	_build.message.connect(func(t: String) -> void: texts.append(t))
	_build.select(B.FENCE)
	assert_true(not _build.try_place())
	assert_eq(_state.get_resource(R.WOOD), 200, "nothing spent")
	assert_true(not _build.try_demolish(at))
	assert_true(texts.size() >= 1 and texts[0].contains("não é seu"), "message: %s" % str(texts))
