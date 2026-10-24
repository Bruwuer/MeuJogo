extends GameTest

const B := GameConstants.Building
const T := GameConstants.Trait
const P := GameConstants.Profession

var state: WorldState
var day_night: DayNight
var player: Node3D
var hud: Hud
var kingdom: Dictionary


func _make() -> void:
	state = WorldState.new()
	state.seed = GameConstants.WORLD_SEED
	var seat := state.add_building(B.CABIN, Vector3(200, 0, 200), 0)
	kingdom = state.add_kingdom("Teste", Color.RED, seat.pos, seat.id)
	day_night = DayNight.new()
	var sun := DirectionalLight3D.new()
	add_child(sun)
	day_night.setup(sun, Environment.new(), ProceduralSkyMaterial.new())
	add_child(day_night)
	day_night.set_process(false)
	player = Node3D.new()
	add_child(player)
	player.global_position = Vector3(200, 0, 206)
	var harvest := HarvestSystem.new()
	harvest.setup(func(_c: Vector2i) -> Chunk: return null, state)
	add_child(harvest)
	hud = Hud.new()
	add_child(hud)
	hud.setup(state, harvest, day_night, player)


func _person(seed_value: int, name: String, surname: String, age := 30.0, female := false) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var p := state.add_person(PersonGen.generate(r, 0.0, P.MASON), Vector3(200, 0, 205), kingdom.id)
	p.status = "resident"
	p.name = name
	p.surname = surname
	p.age = age
	p.female = female
	p.traits = [T.WORKER, T.BRAVE]
	return p


func _family(head: Dictionary, crest_seed: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = crest_seed
	var f := state.add_family(head.surname, Crest.generate(r, []), kingdom.id, head.id, 0.0)
	head.family_id = f.id
	return f


## Ana (head) married to Bento, children Inês (5); friend Clara, rival Rui.
func _household() -> Dictionary:
	var ana := _person(1, "Ana", "Ferreira", 34.0, true)
	var bento := _person(2, "Bento", "do Vale", 36.0)
	var ines := _person(3, "Inês", "Ferreira", 5.0, true)
	ines.profession = -1
	var clara := _person(4, "Clara", "Seixas", 30.0, true)
	var rui := _person(5, "Rui", "Couto", 40.0)
	var f := _family(ana, 3)
	bento.family_id = f.id
	ines.family_id = f.id
	_family(clara, 4)
	var g := _family(rui, 5)
	ana.spouse_id = bento.id
	bento.spouse_id = ana.id
	ines.parents = [ana.id, bento.id]
	state.set_relation(ana.id, clara.id, 0.6)
	state.set_relation(ana.id, rui.id, -0.6)
	state.set_relation(bento.id, rui.id, -0.5)
	ana.opinion = 0.7
	ana.stance = "ally"
	bento.opinion = 0.6
	rui.opinion = -0.8
	f.stance = "ally"
	g.stance = "enemy"
	return {ana = ana, bento = bento, ines = ines, clara = clara, rui = rui, f = f, g = g}


func test_card_shows_family_and_relations() -> void:
	_make()
	var h := _household()
	var text := PeopleManager.card_text(h.ana, state)
	for part in ["Casa Ferreira", "chefe", "Casada com Bento do Vale", "Filhos: Inês (5)", "Amiga: Clara Seixas",
			"Rival: Rui Couto", "sua aliada", "Brasão: " + Crest.describe(h.f.crest)]:
		assert_true(text.contains(part), "%s in:\n%s" % [part, text])
	var kid := PeopleManager.card_text(h.ines, state)
	assert_true(kid.contains("Filha de Ana Ferreira e Bento do Vale"), kid)
	assert_true(kid.contains("Criança"), kid)
	h.bento.spouse_id = -1
	h.bento.widowed = true
	assert_true(PeopleManager.card_text(h.bento, state).contains("Viúvo"))


func test_card_crest_texture() -> void:
	_make()
	var h := _household()
	hud.show_card(h.ana)
	assert_eq(hud.card_crest(), Crest.texture(h.f.crest))
	var loner := _person(9, "Gil", "Rocha")
	hud.show_card(loner)
	assert_eq(hud.card_crest(), null, "no family, no crest")


func test_families_panel_toggle() -> void:
	_make()
	_household()
	assert_true(not hud.families_visible())
	hud.toggle_families()
	assert_true(hud.families_visible(), "C opens it inside a kingdom")
	hud.toggle_families()
	assert_true(not hud.families_visible(), "C closes it")
	player.global_position = Vector3(900, 0, 900)
	hud.toggle_families()
	assert_true(not hud.families_visible(), "nothing to show outside a kingdom")


func test_families_panel_rows() -> void:
	_make()
	var h := _household()
	hud.toggle_families()
	var text := hud.families_text()
	assert_true(text.contains("Famílias do Reino de Teste"), text)
	assert_true(text.contains("Casa Ferreira · 3 pessoas · chefe: Ana · aliada"), text)
	assert_true(text.contains("Casa Couto · 1 pessoa · chefe: Rui · inimiga"), text)
	assert_true(text.contains("rival da Casa Couto"), "Ferreira and Couto are rivals: %s" % text)
	assert_eq(hud.families_rows(), 3)
	assert_true(h.f.id > 0)


func test_village_line_has_families() -> void:
	_make()
	_household()
	assert_true(hud.village_line(kingdom).contains("Famílias: 3"), hud.village_line(kingdom))


func test_adm_panels_on_dev_keys_only() -> void:
	assert_true(not InputMap.has_action("families"), "no families panel for the player")
	assert_true(not InputMap.has_action("chronicle"), "no chronicle for the player")
	for pair in [["adm_log", KEY_F9], ["adm_houses", KEY_F10]]:
		assert_true(InputMap.has_action(pair[0]), pair[0])
		var keys := InputMap.action_get_events(pair[0]).map(func(e: InputEvent) -> int: return (e as InputEventKey).physical_keycode)
		assert_true(keys.has(pair[1]), "%s on its dev key" % pair[0])


func test_card_fits_on_screen() -> void:
	_make()
	var h := _household()
	hud.show_card(h.ana)
	await wait_frames(3)
	var rect := hud.card_rect()
	var view := get_viewport().get_visible_rect()
	assert_near(rect.get_center().y, view.get_center().y, 1.0, "centered on its anchor, grows up and down (%s)" % rect)
	assert_true(rect.size.y < 620.0, "short enough for a 720 p screen (%s)" % rect)
	hud.hide_card()
	assert_true(not hud.card_visible())


func test_families_panel_stays_on_screen() -> void:
	_make()
	for i in 12:
		var p := _person(20 + i, "Pessoa%d" % i, GameConstants.SURNAMES[i])
		_family(p, 30 + i)
	hud.toggle_families()
	await wait_frames(3)
	var rect := hud.families_rect()
	var view := get_viewport().get_visible_rect()
	assert_near(rect.get_center().y, view.get_center().y, 1.0, "centered on its anchor, grows up and down (%s)" % rect)


func test_families_panel_fits_with_many_houses() -> void:
	_make()
	for i in 12:
		var p := _person(40 + i, "Pessoa%d" % i, GameConstants.SURNAMES[i])
		var f := _family(p, 50 + i)
		f.goal = {kind = GameConstants.Goal.WEALTH, target_id = -1}
	hud.toggle_families()
	await wait_frames(3)
	assert_eq(hud.families_rows(), GameConstants.FAMILIES_MAX_ROWS, "only the most prestigious Houses are listed")
	assert_true(hud.families_text().contains("e mais %d Casas" % (12 - GameConstants.FAMILIES_MAX_ROWS)))
	# Headless viewports are tiny: measure against the real window.
	var window_h := float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	assert_true(hud.families_rect().size.y <= window_h * 0.75, "the panel fits on screen (%s)" % hud.families_rect())
	assert_true(hud.families_centered(), "a modal panel in the middle of the screen, clear of the HUD lines")


func test_messages_hidden_under_panels() -> void:
	_make()
	var p := _person(70, "Ana", "Ferreira")
	_family(p, 71)
	hud.toggle_families()
	await wait_physics_frames(3)
	assert_true(not hud.messages_visible(), "messages would print over the families panel")
	hud.toggle_families()
	await wait_physics_frames(3)
	assert_true(hud.messages_visible())
	hud.toggle_chronicle()
	await wait_physics_frames(3)
	assert_true(not hud.messages_visible(), "nor over the chronicle")
