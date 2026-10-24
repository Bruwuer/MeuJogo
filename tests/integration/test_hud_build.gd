extends GameTest

const B := GameConstants.Building
const R := GameConstants.Res

var _gen := TerrainGenerator.new(GameConstants.WORLD_SEED)
var _scatter := PropScatter.new(_gen, GameConstants.WORLD_SEED)
var _state := WorldState.new()
var _streamer: ChunkStreamer
var _player: Player
var _build: BuildSystem
var _hud: Hud
var _day_night := DayNight.new()


func _setup() -> void:
	var spot := TestSpots.flat_clear(_gen, _scatter, B.CABIN)
	_state.seed = GameConstants.WORLD_SEED
	var lib := ModelLibrary.new()
	add_child(lib)
	lib.start_loading()
	_streamer = ChunkStreamer.new()
	_streamer.setup(_gen, _scatter, lib, _state.removed_in, _state.buildings_in)
	add_child(_streamer)
	_streamer.update_center(spot)
	_player = load("res://scenes/player.tscn").instantiate()
	add_child(_player)
	var p := spot - Vector3(0, 0, GameConstants.BUILD_GHOST_DISTANCE)
	_player.global_position = Vector3(p.x, _gen.height_at(p.x, p.z) + 0.2, p.z)
	var cam := IsoCamera.new()
	cam.target = _player
	add_child(cam)
	var harvest := HarvestSystem.new()
	harvest.setup(_streamer.get_chunk, _state)
	add_child(harvest)
	var sun := DirectionalLight3D.new()
	add_child(sun)
	_day_night.setup(sun, Environment.new(), ProceduralSkyMaterial.new())
	add_child(_day_night)
	_day_night.set_process(false)
	_build = BuildSystem.new()
	add_child(_build)
	_build.setup(_state, _gen, _scatter, _streamer, lib, _player, cam)
	_build.use_mouse = false
	_hud = Hud.new()
	add_child(_hud)
	_hud.setup(_state, harvest, _day_night, _player, _build)
	while not lib.is_ready() or _streamer.pending_count() > 0:
		await get_tree().process_frame


func _label(n: String) -> Label:
	return _hud.find_child(n, true, false) as Label


func test_build_line_and_reason() -> void:
	await _setup()
	_state.add_resource(R.WOOD, 12)
	_build.select(B.CABIN)
	await wait_physics_frames(2)
	assert_true(_label("Build").visible)
	assert_eq(_label("Build").text, "Construindo: Cabana — 30 madeira, 10 pedra · R gira · Clique constrói · Esc sai")
	assert_true(_label("BuildReason").visible)
	assert_eq(_label("BuildReason").text, "Falta madeira (12/30)")
	_build.toggle()
	await wait_physics_frames(2)
	assert_true(not _label("Build").visible and not _label("BuildReason").visible)


func test_resources_refresh_after_building() -> void:
	await _setup()
	_state.add_resource(R.WOOD, 40)
	_state.add_resource(R.STONE, 10)
	_build.select(B.CABIN)
	assert_true(_build.try_place())
	await wait_physics_frames(2)
	assert_eq(_label("Resources").text, "Madeira: 10   Pedra: 0   Frutas: 0")


func test_kingdom_label_inside_territory_and_toast() -> void:
	await _setup()
	_state.add_resource(R.WOOD, 30)
	_state.add_resource(R.STONE, 10)
	_build.select(B.CABIN)
	_build.try_place()
	await wait_physics_frames(2)
	var name: String = _state.kingdoms()[0].name
	assert_eq(_label("Kingdom").text, "Reino de %s" % name)
	assert_true(_label("Kingdom").visible)
	assert_true(_label("Toast").visible)
	assert_eq(_label("Toast").text, "Você fundou o Reino de %s!" % name)
	_player.global_position += Vector3(GameConstants.KINGDOM_RADIUS + 10.0, 0, 0)
	await wait_physics_frames(2)
	assert_true(not _label("Kingdom").visible, "kingdom label visible outside the territory")


func test_hint_outside_build_mode() -> void:
	await _setup()
	await wait_physics_frames(2)
	assert_eq(_label("Hint").text, "B construir · X demolir · Espaço ataca · H come · F flechas")


func test_resources_label_follows_any_change() -> void:
	await _setup()
	_state.add_resource(R.STONE, 7)
	await wait_physics_frames(1)
	assert_eq(_label("Resources").text, "Madeira: 0   Pedra: 7   Frutas: 0")
