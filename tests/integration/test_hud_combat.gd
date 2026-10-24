extends GameTest

const MAIN_SCENE := "res://scenes/main.tscn"


func _world() -> World:
	var w: World = load(MAIN_SCENE).instantiate()
	w.spawn_seed = 42
	w.world_seed = GameConstants.WORLD_SEED
	w.save_path = ""
	add_child(w)
	for i in 900:
		if w.is_world_ready():
			break
		await get_tree().process_frame
	assert_true(w.is_world_ready(), "world not ready")
	return w


func test_health_and_weapon_labels() -> void:
	var w: World = await _world()
	var hud := w.get_hud()
	var p := w.get_player()
	p.health.damage(20.0)
	w.get_state().add_resource(GameConstants.Res.ARROWS, 12)
	await wait_physics_frames(2)
	assert_eq((hud.get_node("Health") as Label).text, "Vida: 80/100")
	var weapon_text := (hud.get_node("Weapon") as Label).text
	assert_true(weapon_text.contains("Espada") and weapon_text.contains("Q troca") and weapon_text.contains("Flechas: 12"), weapon_text)
	p.select_weapon(GameConstants.Weapon.BOW)
	await wait_physics_frames(2)
	assert_true((hud.get_node("Weapon") as Label).text.begins_with("Arco"))
	var hint := (hud.get_node("Hint") as Label).text
	assert_true(hint.contains("Espaço ataca") and hint.contains("H come"), hint)


func test_raid_goes_to_adm_log_not_hud() -> void:
	var w: World = await _world()
	var hud := w.get_hud()
	var s := w.get_state()
	var k := s.add_kingdom("Valdemar", Color.RED, w.get_player().global_position, -1)
	var pack := s.add_pack("lobo", w.get_player().global_position)
	pack.hunger = 1.0
	w.get_creature_manager()._on_raid_started(pack, k, "hunger")
	await wait_frames(2)
	var text := (hud.get_node("Messages") as Label).text
	assert_true(not text.contains("Valdemar"), "kingdom events stay off the HUD: %s" % text)
	var entries_log := s.chronicle(k.id, 10)
	assert_true(entries_log.size() == 1 and (entries_log[0].text as String).contains("famintos"), "the raid and its motive are in the ADM log: %s" % [entries_log])
	for i in 5:
		hud.add_message("m%d" % i)
	assert_eq(hud.messages_text().split("\n").size(), 4, "keeps the last 4 messages")
	assert_true(not hud.messages_text().contains("famintos"), "oldest message should drop")


func test_village_news_never_on_hud() -> void:
	var w: World = await _world()
	var hud := w.get_hud()
	var p := w.get_player()
	var k := w.get_state().add_kingdom("Valdemar", Color.RED, p.global_position, -1)
	w.get_village_sim()._say(k, "Ana casou com Bento")
	for i in 30:
		await get_tree().process_frame
	assert_true(not hud.messages_text().contains("Ana"), "the player does not hear every kingdom event")
	assert_true(w.get_state().chronicle(k.id, 5).any(func(e: Dictionary) -> bool: return e.text == "Ana casou com Bento"))


func test_player_own_kill_still_shown() -> void:
	var w: World = await _world()
	var hud := w.get_hud()
	var rng := RandomNumberGenerator.new()
	var rec := {genome = Genome.random("lobo", rng), pos = Vector3(9000, 0, 9000)}
	w.get_creature_manager().creature_killed.emit(rec, true)
	await wait_frames(2)
	assert_true(hud.messages_text().begins_with("Você abateu"), "the player's own deeds stay: %s" % hud.messages_text())


func test_creature_manager_wired() -> void:
	var w: World = await _world()
	var mgr := w.get_creature_manager()
	assert_true(mgr != null)
	await wait_frames(30)
	assert_true(w.get_state().all_packs().size() >= 1, "no pack in a new world")
	assert_true(w.get_player().creature_source.is_valid(), "player cannot hit creatures")


func test_repeated_message_shown_once() -> void:
	var w: World = await _world()
	var hud := w.get_hud()
	hud.add_message("Os lobos atacam")
	hud.add_message("outra")
	hud.add_message("Os lobos atacam")
	assert_eq(hud.messages_text(), "outra\nOs lobos atacam")
