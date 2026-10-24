extends GameTest

const R := GameConstants.Res
const W := GameConstants.Weapon
const MAIN_SCENE := "res://scenes/main.tscn"

var _lib: ModelLibrary
var _state: WorldState
var _player: Player


func _library() -> ModelLibrary:
	if _lib == null:
		_lib = ModelLibrary.new()
		add_child(_lib)
		_lib.start_loading()
		while not _lib.is_ready():
			await get_tree().process_frame
	return _lib


func _make() -> Player:
	var lib: ModelLibrary = await _library()
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = GameConstants.LAYER_TERRAIN
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)
	_state = WorldState.new()
	_player = load("res://scenes/player.tscn").instantiate()
	_player.state = _state
	_player.library = lib
	_player.creature_source = func() -> Array: return get_tree().get_nodes_in_group("creatures")
	add_child(_player)
	_player.position = Vector3(0, 0.05, 0)
	_player.frozen = false
	await wait_physics_frames(5)
	return _player


## A still deer (commanded to sleep where it stands).
func _deer(pos: Vector3, s := 1) -> Creature:
	var lib: ModelLibrary = await _library()
	var r := RandomNumberGenerator.new()
	r.seed = s
	var g := Genome.random("cervo", r)
	g.max_hp = 500.0
	var c := Creature.new()
	add_child(c)
	c.setup({ id = s, genome = g, pos = pos, hp = 500.0, age = 1.0, pack_id = -1, hunger = 0.0 }, lib, null)
	c.command(CreatureBrain.State.SLEEP, pos)
	return c


func _press(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _swing() -> void:
	await _press(&"attack")
	await get_tree().create_timer(0.7).timeout


func test_weapon_switch_keys() -> void:
	var p: Player = await _make()
	assert_eq(p.weapon, W.SWORD)
	await _press(&"slot_2")
	assert_eq(p.weapon, W.SPEAR)
	await _press(&"weapon_next")
	assert_eq(p.weapon, W.BOW)
	await _press(&"weapon_next")
	assert_eq(p.weapon, W.SWORD)
	await _press(&"slot_3")
	assert_eq(p.weapon, W.BOW)
	p.combat_enabled = false # build mode owns 1-5
	await _press(&"slot_1")
	assert_eq(p.weapon, W.BOW)


func test_sword_damages_creature_in_front_only() -> void:
	var p: Player = await _make()
	var front: Creature = await _deer(Vector3(0, 0.1, 1.6), 1)
	var behind: Creature = await _deer(Vector3(0, 0.1, -1.6), 2)
	await wait_physics_frames(10)
	assert_true(p.facing().dot(Vector3(0, 0, 1)) > 0.9, "player should start facing +Z")
	await _press(&"attack")
	assert_eq(p.current_anim(), GameConstants.WEAPONS[W.SWORD].clip, "attack clip not played")
	await get_tree().create_timer(0.7).timeout
	assert_true(front.health.hp < 500.0, "sword missed the deer in front")
	assert_eq(behind.health.hp, 500.0, "sword hit behind the player")


func test_spear_reaches_farther() -> void:
	var p: Player = await _make()
	var deer: Creature = await _deer(Vector3(0, 0.1, 3.2), 3)
	await wait_physics_frames(10)
	await _swing()
	assert_eq(deer.health.hp, 500.0, "the sword should not reach 3 m")
	p.select_weapon(W.SPEAR)
	await _swing()
	assert_true(deer.health.hp < 500.0, "the spear should reach 3 m")


func test_bow_needs_arrows_and_arrow_falls() -> void:
	var p: Player = await _make()
	p.select_weapon(W.BOW)
	assert_true(not p.attack(), "shot without arrows")
	_state.add_resource(R.ARROWS, 3)
	var deer: Creature = await _deer(Vector3(0, 0.1, 12.0), 4)
	await wait_physics_frames(10)
	assert_true(p.attack(), "could not shoot")
	assert_eq(_state.get_resource(R.ARROWS), 2)
	await get_tree().create_timer(GameConstants.WEAPONS[W.BOW].hit_time + 0.05).timeout
	var arrows := get_tree().get_nodes_in_group("arrows")
	assert_eq(arrows.size(), 1, "no arrow in flight")
	await get_tree().create_timer(1.0).timeout
	assert_true(deer.health.hp < 500.0, "the arrow missed a deer 12 m ahead")
	# A shot into empty space falls to the ground.
	p.global_position = Vector3(0, 0.05, 0)
	p.face(Vector3(-1, 0, 0))
	await get_tree().create_timer(GameConstants.WEAPONS[W.BOW].cooldown).timeout
	assert_true(p.attack())
	await get_tree().create_timer(GameConstants.WEAPONS[W.BOW].hit_time + 0.05).timeout
	var a: Arrow = get_tree().get_nodes_in_group("arrows").filter(func(n: Arrow) -> bool: return not n.is_stuck())[0]
	var y0 := a.global_position.y
	await get_tree().create_timer(0.4).timeout
	assert_true(a.velocity.y < 0.0, "gravity does not pull the arrow")
	await get_tree().create_timer(2.0).timeout
	assert_true(a.is_stuck(), "the arrow never hit the ground")
	assert_true(a.global_position.y < y0 and a.global_position.y < 0.3, "arrow at %s" % a.global_position)


func test_craft_arrows_costs_wood() -> void:
	var p: Player = await _make()
	_state.add_resource(R.WOOD, 1)
	await _press(&"craft_arrows")
	assert_eq(_state.get_resource(R.WOOD), 0)
	assert_eq(_state.get_resource(R.ARROWS), GameConstants.ARROWS_PER_CRAFT)
	assert_true(not p.craft_arrows(), "crafted without wood")
	assert_eq(_state.get_resource(R.ARROWS), GameConstants.ARROWS_PER_CRAFT)


func test_eat_heals_and_costs_berry() -> void:
	var p: Player = await _make()
	_state.add_resource(R.BERRIES, 1)
	assert_true(not p.eat(), "ate at full health")
	p.health.damage(30.0)
	await _press(&"eat")
	assert_near(p.health.hp, 100.0 - 30.0 + GameConstants.EAT_HEAL, 0.5)
	assert_eq(_state.get_resource(R.BERRIES), 0)
	assert_true(not p.eat(), "ate without berries")


func test_regen_after_delay() -> void:
	var p: Player = await _make()
	p.health.damage(20.0)
	await get_tree().create_timer(1.0).timeout
	assert_near(p.health.hp, 80.0, 0.01, "regenerated too soon")
	Engine.time_scale = 4.0
	await get_tree().create_timer(GameConstants.PLAYER_REGEN_DELAY + 2.0).timeout
	Engine.time_scale = 1.0
	assert_true(p.health.hp > 80.0, "no regeneration after the delay")


func test_weapon_visible_in_hand() -> void:
	var p: Player = await _make()
	await wait_frames(3)
	var holder := p.weapon_holder()
	assert_true(holder != null, "no weapon holder")
	if holder == null:
		return
	var attach := holder.get_parent() as BoneAttachment3D
	assert_true(attach != null and attach.bone_name == "hand.R", "weapon not on hand.R")
	assert_eq(holder.get_child_count(), 1)
	assert_eq(holder.get_child(0).name, "Espada")
	p.select_weapon(W.BOW)
	await wait_frames(2)
	assert_eq(holder.get_child_count(), 1)
	assert_eq(holder.get_child(0).name, "Arco")
	# At rest the blade points to the character's front.
	p.select_weapon(W.SWORD)
	p.play_anim(GameConstants.ANIM_IDLE, true)
	await wait_frames(2)
	var blade_dir := (holder.get_child(0) as Node3D).global_basis.y.normalized()
	assert_true(blade_dir.dot(p.facing()) > 0.6, "sword points %s, player faces %s" % [blade_dir, p.facing()])


func test_respawn_keeps_resources() -> void:
	var w: World = load(MAIN_SCENE).instantiate()
	w.spawn_seed = 42
	w.world_seed = GameConstants.WORLD_SEED
	w.save_path = ""
	add_child(w)
	for i in 600:
		if w.is_world_ready():
			break
		await get_tree().process_frame
	var p := w.get_player()
	var start := p.global_position
	await wait_physics_frames(10)
	w.get_state().add_resource(R.WOOD, 7)
	p.global_position = start + Vector3(10, 0, 10)
	await wait_physics_frames(3)
	p.health.damage(1000.0)
	await wait_physics_frames(3)
	assert_true(not p.health.is_dead(), "player still dead")
	assert_near(p.health.hp, GameConstants.PLAYER_HP, 0.01)
	assert_true(Vector2(p.global_position.x - start.x, p.global_position.z - start.z).length() < 2.0,
			"respawned at %s, spawn %s" % [p.global_position, start])
	assert_eq(w.get_state().get_resource(R.WOOD), 7)
