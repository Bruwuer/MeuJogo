extends GameTest

const C := Vector2i(1, 1)

var _gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
var _state: WorldState
var _chunk: Chunk
var _harvest: HarvestSystem


func _prop(id: int, type: int, x: float, z: float) -> Dictionary:
	var o := ChunkMath.chunk_origin(C)
	return {id = id, type = type, pos = Vector3(o.x + x, _gen.height_at(o.x + x, o.z + z), o.z + z), yaw = 0.0, scale = 1.0}


## One hand-made chunk with an oak (id 1), a bush (id 2) and a rock (id 3).
func _setup() -> void:
	var lib := ModelLibrary.new()
	add_child(lib)
	lib.start_loading()
	while not lib.is_ready():
		await get_tree().process_frame
	var props: Array[Dictionary] = [
		_prop(1, GameConstants.Prop.OAK, 10, 10),
		_prop(2, GameConstants.Prop.BUSH, 18, 10),
		_prop(3, GameConstants.Prop.ROCK, 10, 22),
	]
	_chunk = Chunk.new()
	var mat := StandardMaterial3D.new()
	_chunk.build(C, _gen.build_chunk_arrays(C), props, PackedInt32Array(), lib, mat)
	add_child(_chunk)
	_state = WorldState.new()
	_harvest = HarvestSystem.new()
	_harvest.setup(func(c: Vector2i) -> Chunk: return _chunk if c == C else null, _state)
	add_child(_harvest)


func _near(id: int, offset: Vector3) -> Vector3:
	return _chunk.get_prop(id).pos + offset


func _player_at(pos: Vector3) -> Player:
	var p: Player = load("res://scenes/player.tscn").instantiate()
	add_child(p)
	p.global_position = Vector3(pos.x, _gen.height_at(pos.x, pos.z) + 0.3, pos.z)
	p.reset_physics_interpolation()
	p.harvest = _harvest
	p.frozen = false
	return p


func test_find_target_nearest() -> void:
	await _setup()
	var t := _harvest.find_target(_near(1, Vector3(1.2, 0, 0)))
	assert_true(not t.is_empty(), "no target next to the oak")
	if not t.is_empty():
		assert_eq(t.prop.id, 1)


func test_no_target_out_of_range() -> void:
	await _setup()
	assert_true(_harvest.find_target(_near(1, Vector3(0, 0, 4.0))).is_empty())


func test_tree_needs_four_hits_and_gives_wood() -> void:
	await _setup()
	var t := _harvest.find_target(_near(1, Vector3(1.2, 0, 0)))
	for i in 3:
		assert_true(not _harvest.hit(t), "removed too early at hit %d" % (i + 1))
	assert_true(_chunk.has_prop(1))
	assert_eq(_state.get_resource(GameConstants.Res.WOOD), 0)
	assert_true(_harvest.hit(t), "4th hit should remove the oak")
	assert_true(not _chunk.has_prop(1))
	assert_eq(_state.get_resource(GameConstants.Res.WOOD), 3)
	assert_eq(_state.removed_in(C), PackedInt32Array([1]))


func test_bush_one_hit_berries() -> void:
	await _setup()
	var t := _harvest.find_target(_near(2, Vector3(1.0, 0, 0)))
	assert_eq(t.prop.id, 2)
	assert_true(_harvest.hit(t))
	assert_eq(_state.get_resource(GameConstants.Res.BERRIES), 2)


func test_rock_gives_stone() -> void:
	await _setup()
	var t := _harvest.find_target(_near(3, Vector3(0, 0, -2.0)))
	assert_eq(t.prop.id, 3)
	for i in 5:
		_harvest.hit(t)
	assert_eq(_state.get_resource(GameConstants.Res.STONE), 2)
	assert_true(not _chunk.has_prop(3))


func test_hit_cooldown() -> void:
	await _setup()
	var p := _player_at(_near(1, Vector3(1.2, 0, 0)))
	await wait_physics_frames(5)
	var oak := _harvest.find_target(p.global_position)
	Input.action_press("interact")
	await wait_physics_frames(2)
	Input.action_release("interact")
	await wait_physics_frames(3) # well inside HARVEST_HIT_TIME
	Input.action_press("interact")
	await wait_physics_frames(2)
	Input.action_release("interact")
	assert_eq(_harvest.hits_on(oak), 1, "second press inside HARVEST_HIT_TIME must be ignored")
	await wait_physics_frames(int(GameConstants.HARVEST_HIT_TIME * Engine.physics_ticks_per_second) + 2)
	Input.action_press("interact")
	await wait_physics_frames(2)
	Input.action_release("interact")
	assert_eq(_harvest.hits_on(oak), 2, "press after the cooldown must count")


func test_player_works_and_stops() -> void:
	await _setup()
	var p := _player_at(_near(1, Vector3(1.5, 0, 0)))
	await wait_physics_frames(5)
	Input.action_press("interact")
	await wait_physics_frames(1)
	Input.action_release("interact")
	Input.action_press("move_up")
	var start := p.global_position
	await wait_physics_frames(15)
	Input.action_release("move_up")
	assert_true(p.is_working() or p.current_anim() == GameConstants.ANIM_WORK, "not working after interact")
	assert_eq(p.current_anim(), GameConstants.ANIM_WORK)
	var moved := Vector2(p.global_position.x - start.x, p.global_position.z - start.z).length()
	assert_true(moved < 0.1, "moved %.2f m while working" % moved)
