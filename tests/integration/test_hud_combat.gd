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


func test_raid_message_with_motive() -> void:
	var w: World = await _world()
	var hud := w.get_hud()
	var pack := w.get_state().add_pack("lobo", w.get_player().global_position)
	pack.hunger = 1.0
	w.get_creature_manager().message.emit(PackMotives.message(pack, "Valdemar"))
	await wait_frames(2)
	var text := (hud.get_node("Messages") as Label).text
	assert_true(text.contains("famintos") and text.contains("Valdemar"), text)
	for i in 5:
		hud.add_message("m%d" % i)
	assert_eq(hud.messages_text().split("\n").size(), 4, "keeps the last 4 messages")
	assert_true(not hud.messages_text().contains("famintos"), "oldest message should drop")


func test_offscreen_raid_message_on_return() -> void:
	var w: World = await _world()
	var hud := w.get_hud()
	var sim := w.get_pack_sim()
	sim.pending_messages.append("Enquanto você estava fora, os lobos destruíram Cerca no Reino de Valdemar")
	await wait_frames(5)
	assert_true(not hud.messages_text().contains("Enquanto"), "shown while the player is away from any kingdom")
	var p := w.get_player()
	w.get_state().add_kingdom("Valdemar", Color.RED, p.global_position, -1)
	for i in 120:
		await get_tree().process_frame
		if hud.messages_text().contains("Enquanto"):
			break
	assert_true(hud.messages_text().contains("Enquanto você estava fora"), "offscreen raid not reported on return")
	assert_true(sim.pending_messages.is_empty())


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
