extends GameTest

const C := Vector2i(1, 1)

var _gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
var _state := WorldState.new()
var _harvest := HarvestSystem.new()
var _day_night := DayNight.new()
var _chunk: Chunk
var _player: Player
var _hud: Hud


func _setup() -> void:
	var lib := ModelLibrary.new()
	add_child(lib)
	lib.start_loading()
	while not lib.is_ready():
		await get_tree().process_frame
	var o := ChunkMath.chunk_origin(C)
	var oak_pos := Vector3(o.x + 10, _gen.height_at(o.x + 10, o.z + 10), o.z + 10)
	var props: Array[Dictionary] = [{id = 1, type = GameConstants.Prop.OAK, pos = oak_pos, yaw = 0.0, scale = 1.0}]
	_chunk = Chunk.new()
	_chunk.build(C, _gen.build_chunk_arrays(C), props, PackedInt32Array(), lib, StandardMaterial3D.new())
	add_child(_chunk)
	_harvest.setup(func(c: Vector2i) -> Chunk: return _chunk if c == C else null, _state)
	add_child(_harvest)
	var sun := DirectionalLight3D.new()
	add_child(sun)
	_day_night.setup(sun, Environment.new(), ProceduralSkyMaterial.new())
	add_child(_day_night)
	_day_night.set_process(false)
	_player = load("res://scenes/player.tscn").instantiate()
	add_child(_player)
	_player.global_position = oak_pos + Vector3(1.5, 0.3, 0)
	_hud = Hud.new()
	add_child(_hud)
	_hud.setup(_state, _harvest, _day_night, _player)


func _label(node_name: String) -> Label:
	return _hud.find_child(node_name, true, false) as Label


func test_resources_text() -> void:
	await _setup()
	_state.add_resource(GameConstants.Res.WOOD, 3)
	_state.add_resource(GameConstants.Res.BERRIES, 2)
	_harvest.resources_changed.emit()
	await wait_physics_frames(2)
	assert_eq(_hud.resources_text(), "Madeira: 3   Pedra: 0   Frutas: 2")
	assert_eq(_label("Resources").text, "Madeira: 3   Pedra: 0   Frutas: 2")


func test_prompt_near_tree_and_hidden_far() -> void:
	await _setup()
	await wait_physics_frames(2)
	var prompt := _label("Prompt")
	assert_true(prompt.visible, "prompt hidden next to a tree")
	assert_eq(prompt.text, "[E] Cortar árvore")
	_player.global_position += Vector3(0, 0, 12)
	await wait_physics_frames(2)
	assert_true(not prompt.visible, "prompt visible with nothing in range")


func test_clock_label_matches_day_night() -> void:
	await _setup()
	_day_night.day = 2
	_day_night.time_of_day = 0.5
	await wait_physics_frames(2)
	assert_eq(_label("Clock").text, "Dia 2 · 12:00")
