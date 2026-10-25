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
	assert_eq(_label("Hint").text, "E fala · G doa · B construir · X demolir · Espaço ataca · H come · F flechas · P governo")


func test_resources_label_follows_any_change() -> void:
	await _setup()
	_state.add_resource(R.STONE, 7)
	await wait_physics_frames(1)
	assert_eq(_label("Resources").text, "Madeira: 0   Pedra: 7   Frutas: 0")


func test_government_panel_changes_decrees() -> void:
	await _setup()
	_state.add_resource(R.WOOD, 30)
	_state.add_resource(R.STONE, 10)
	_build.select(B.CABIN)
	_build.try_place()
	_build.toggle()
	var k: Dictionary = _state.kingdoms()[0]
	var society := SocietySim.new()
	society.setup(_state, func(_k: Dictionary, _t: String) -> void: pass, func(_k: Dictionary) -> bool: return true,
			func(_k: Dictionary) -> Dictionary: return {})
	var houses := HouseSim.new()
	houses.setup(_state, func(_k: Dictionary, _t: String) -> void: pass, society)
	var gov := GovSim.new()
	gov.setup(_state, houses, func(_k: Dictionary) -> bool: return true)
	_hud.set_gov(gov)
	_player.frozen = false
	await wait_physics_frames(2)
	assert_eq(_label("Kingdom").text, "Reino de %s" % k.name)
	assert_eq(_label("Government").text, GameConstants.GOV_LABEL_YOU)
	_hud.toggle_gov()
	assert_true(_hud.gov_visible())
	assert_true(_player.frozen, "the player stands still while governing")
	assert_true(_hud.gov_text().contains("> Imposto: nenhum"), _hud.gov_text())
	_hud.gov_change(1)
	assert_eq(String(k.decrees.tax), "low")
	_hud.gov_move(1)
	_hud.gov_change(1)
	assert_eq(String(k.decrees.ration), "farta")
	assert_true(_hud.gov_text().contains("> Ração: farta"), _hud.gov_text())
	_hud.gov_move(1)
	_hud.gov_move(1)
	_hud.gov_change(1)
	assert_eq(int(k.decrees.build), GameConstants.Building.HOUSE)
	_hud.toggle_gov()
	assert_true(not _hud.gov_visible())
	assert_true(not _player.frozen)
	var ruler := _state.add_person(PersonGen.generate(RandomNumberGenerator.new()), k.center, k.id)
	ruler.status = "resident"
	k.ruler_id = ruler.id
	k.ruler_way = "inimigo"
	_hud.toggle_gov()
	assert_true(_hud.gov_text().contains("não é seu"), _hud.gov_text())
	_hud.gov_change(1)
	assert_eq(String(k.decrees.tax), "low", "no decrees from someone who does not rule")
	await wait_physics_frames(2)
	assert_eq(_label("Government").text, GameConstants.GOV_LABEL_RULER % PersonGen.full_name(ruler))
	_hud.toggle_gov()


func test_government_panel_sends_envoys_to_known_kingdoms() -> void:
	await _setup()
	_state.add_resource(R.WOOD, 30)
	_state.add_resource(R.STONE, 10)
	_build.select(B.CABIN)
	_build.try_place()
	_build.toggle()
	var k: Dictionary = _state.kingdoms()[0]
	var far := _state.add_kingdom("Bruma", Color.BLUE, k.center + Vector3(300, 0, 0), -1, "npc")
	var unknown := _state.add_kingdom("Oculta", Color.GREEN, k.center + Vector3(0, 0, 300), -1, "npc")
	_state.mark_visited(ChunkMath.world_to_chunk(far.center))
	var society := SocietySim.new()
	society.setup(_state, func(_k: Dictionary, _t: String) -> void: pass, func(_k: Dictionary) -> bool: return true,
			func(_k: Dictionary) -> Dictionary: return {})
	var houses := HouseSim.new()
	houses.setup(_state, func(_k: Dictionary, _t: String) -> void: pass, society)
	var gov := GovSim.new()
	gov.setup(_state, houses, func(_k: Dictionary) -> bool: return true)
	var realms := RealmSim.new()
	realms.setup(_state, houses, society, gov)
	_hud.set_gov(gov, realms)
	_hud.toggle_gov()
	assert_true(_hud.gov_text().contains("Reino de Bruma: paz"), _hud.gov_text())
	assert_true(not _hud.gov_text().contains("Oculta"), "a kingdom never seen is not listed")
	for i in 4:
		_hud.gov_move(1)
	assert_true(_hud.gov_text().contains("> Reino de Bruma") and _hud.gov_text().contains("enviar presente"), _hud.gov_text())
	_hud.gov_confirm()
	assert_true(_label("Messages").text.contains("Ninguém livre"), _label("Messages").text)
	var envoy := _state.add_person(PersonGen.generate(RandomNumberGenerator.new()), k.center, k.id)
	envoy.merge({status = "resident", age = 30.0}, true)
	_hud.gov_confirm()
	assert_eq((envoy.deed as Dictionary).get("kind", ""), "envoy")
	assert_eq(int(envoy.deed.data.target_id), far.id)
	_hud.gov_change(1)
	assert_true(_hud.gov_text().contains("propor paz"))
	_hud.toggle_gov()


func test_government_panel_starts_at_the_top() -> void:
	await _setup()
	_state.add_resource(R.WOOD, 30)
	_state.add_resource(R.STONE, 10)
	_build.select(B.CABIN)
	_build.try_place()
	_build.toggle()
	var society := SocietySim.new()
	society.setup(_state, func(_k: Dictionary, _t: String) -> void: pass, func(_k: Dictionary) -> bool: return true,
			func(_k: Dictionary) -> Dictionary: return {})
	var houses := HouseSim.new()
	houses.setup(_state, func(_k: Dictionary, _t: String) -> void: pass, society)
	var gov := GovSim.new()
	gov.setup(_state, houses, func(_k: Dictionary) -> bool: return true)
	_hud.set_gov(gov)
	_hud.toggle_gov()
	_hud.gov_move(2)
	_hud.toggle_gov()
	_hud.toggle_gov()
	assert_true(_hud.gov_text().contains("> Imposto"), "the panel opens on the first row: " + _hud.gov_text())
	_hud.toggle_gov()


## Records an Esc nobody used (it sits first in the tree, so it hears the event last).
class EscProbe extends Node:
	var heard := 0
	func _unhandled_input(event: InputEvent) -> void:
		if event.is_action_pressed("ui_cancel"):
			heard += 1


func _press_esc() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_ESCAPE
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)
	await wait_frames(2)
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await wait_frames(1)


func test_esc_is_free_only_with_nothing_open() -> void:
	await _setup()
	assert_true(_hud.esc_free(), "nothing open")
	_build.toggle()
	assert_true(not _hud.esc_free(), "building uses Esc")
	_build.toggle()
	_hud.toggle_chronicle()
	if _hud.chronicle_visible():
		assert_true(not _hud.esc_free(), "an ADM panel uses Esc")
		_hud.toggle_chronicle()
	_hud.toggle_families()
	if _hud.families_visible():
		assert_true(not _hud.esc_free())
		_hud.toggle_families()
	assert_true(_hud.esc_free())


func test_esc_leaving_build_mode_is_used_up() -> void:
	await _setup()
	var probe := EscProbe.new()
	get_tree().root.add_child(probe)
	get_tree().root.move_child(probe, 0)
	_build.toggle()
	await _press_esc()
	assert_true(not _build.active, "Esc leaves build mode")
	assert_eq(probe.heard, 0, "and nothing else hears it (no pause menu behind)")
	await _press_esc()
	assert_eq(probe.heard, 1, "with nothing open, Esc is free")
	probe.queue_free()
