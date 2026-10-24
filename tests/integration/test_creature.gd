extends GameTest

var _lib: ModelLibrary


func _library() -> ModelLibrary:
	if _lib == null:
		_lib = ModelLibrary.new()
		add_child(_lib)
		_lib.start_loading()
		while not _lib.is_ready():
			await get_tree().process_frame
	return _lib


func _floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = GameConstants.LAYER_TERRAIN
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)


func _spawn(species: String, pos: Vector3, seed_value := 1, extra := {}) -> Creature:
	var lib: ModelLibrary = await _library()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var g := Genome.random(species, rng)
	var rec := { id = seed_value, genome = g, pos = pos, hp = g.max_hp, age = 1.0, pack_id = -1, hunger = 0.0 }
	rec.merge(extra, true)
	var c := Creature.new()
	add_child(c)
	c.setup(rec, lib, null)
	return c


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


func _fast(on: bool) -> void:
	Engine.time_scale = 4.0 if on else 1.0


func test_creature_stays_on_ground() -> void:
	_floor()
	var c: Creature = await _spawn("lobo", Vector3(0, 0.3, 0))
	c.command(CreatureBrain.State.WANDER, Vector3(10, 0, 4))
	var lo := INF
	var hi := -INF
	for i in 120:
		await get_tree().physics_frame
		if i > 20:
			lo = minf(lo, c.global_position.y)
			hi = maxf(hi, c.global_position.y)
	assert_near(lo, 0.0, 0.08, "sinks")
	assert_near(hi, 0.0, 0.08, "floats")
	assert_true(_flat(c.global_position).length() > 1.0, "did not move")
	assert_eq(c.collision_layer, GameConstants.LAYER_CREATURES)


func test_avoids_obstacle() -> void:
	_floor()
	var wall := StaticBody3D.new()
	wall.collision_layer = GameConstants.LAYER_OBSTACLES
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 2, 0.6)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0, 1, 4)
	add_child(wall)
	var c: Creature = await _spawn("lobo", Vector3(0, 0.1, 0))
	c.command(CreatureBrain.State.HUNT, Vector3(0, 0, 10))
	_fast(true)
	for i in 300:
		await get_tree().physics_frame
		if c.global_position.z > 7.0:
			break
	_fast(false)
	assert_true(c.global_position.z > 7.0, "stuck behind the wall at %s" % c.global_position)


func test_wolf_kills_deer() -> void:
	_floor()
	var wolf: Creature = await _spawn("lobo", Vector3(0, 0.1, 0), 11, { hunger = 1.0 })
	var deer: Creature = await _spawn("cervo", Vector3(3, 0.1, 0), 12)
	deer.health.damage(deer.health.max_hp - 15.0)
	var died := []
	deer.health.died.connect(func(src: Object) -> void: died.append(src))
	_fast(true)
	for i in 1200:
		await get_tree().physics_frame
		if not died.is_empty():
			break
	_fast(false)
	assert_eq(died.size(), 1, "the wolf never killed the deer")
	if not died.is_empty():
		assert_eq(died[0], wolf)
		assert_true(wolf.record.hunger < 0.5, "eating should feed the wolf")


func test_record_tracks_position_and_hp() -> void:
	_floor()
	var c: Creature = await _spawn("javali", Vector3(0, 0.1, 0))
	c.command(CreatureBrain.State.WANDER, Vector3(6, 0, 0))
	await wait_physics_frames(40)
	c.health.damage(5.0)
	c.sync_record()
	assert_true((c.record.pos as Vector3).distance_to(c.global_position) < 0.01)
	assert_near(c.record.hp, c.health.hp, 0.001)
