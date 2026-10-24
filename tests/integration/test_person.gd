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
	var body := StaticBody3D.new()
	body.collision_layer = GameConstants.LAYER_TERRAIN
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0, -0.5, 0)
	add_child(body)


func _spawn(pos: Vector3, seed_value := 1) -> Person:
	var lib: ModelLibrary = await _library()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var rec := PersonGen.generate(rng)
	rec.merge({id = seed_value, pos = pos, status = "resident", carrying = {}, home_id = -1, inside = -1, job = ""}, true)
	var p := Person.new()
	add_child(p)
	p.setup(rec, lib, null)
	return p


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


func test_person_walks_to_target() -> void:
	_floor()
	var p: Person = await _spawn(Vector3(0, 0.2, 0))
	p.walk_to(Vector3(8, 0, 3))
	Engine.time_scale = 4.0
	for i in 400:
		await get_tree().physics_frame
		if _flat(p.global_position).distance_to(Vector3(8, 0, 3)) < GameConstants.PERSON_ARRIVE:
			break
	Engine.time_scale = 1.0
	assert_true(_flat(p.global_position).distance_to(Vector3(8, 0, 3)) < GameConstants.PERSON_ARRIVE + 0.2,
			"arrived (%s)" % str(p.global_position))
	assert_near(p.global_position.y, 0.0, 0.1, "on the ground")
	assert_eq(p.collision_layer, GameConstants.LAYER_PEOPLE)
	assert_eq(p.collision_mask, GameConstants.LAYER_TERRAIN | GameConstants.LAYER_OBSTACLES)
	p.queue_free()


func test_person_walks_around_obstacle() -> void:
	_floor()
	var wall := StaticBody3D.new()
	wall.collision_layer = GameConstants.LAYER_OBSTACLES
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 3.0, 4.0)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(5, 1.5, 0)
	add_child(wall)
	var p: Person = await _spawn(Vector3(0, 0.2, 0))
	p.walk_to(Vector3(10, 0, 0))
	var inside := false
	Engine.time_scale = 4.0
	for i in 900:
		await get_tree().physics_frame
		var q := p.global_position
		if absf(q.x - 5.0) < 0.5 and absf(q.z) < 2.0:
			inside = true
		if _flat(q).distance_to(Vector3(10, 0, 0)) < GameConstants.PERSON_ARRIVE:
			break
	Engine.time_scale = 1.0
	assert_true(not inside, "never inside the wall")
	assert_true(_flat(p.global_position).distance_to(Vector3(10, 0, 0)) < GameConstants.PERSON_ARRIVE + 0.3,
			"got around it (%s)" % str(p.global_position))
	p.queue_free()
	wall.queue_free()


func test_person_colors_applied() -> void:
	_floor()
	var a: Person = await _spawn(Vector3(0, 0.2, 0), 3)
	var b: Person = await _spawn(Vector3(3, 0.2, 0), 3)
	var tunic_a := a.material_for("tunic")
	assert_true(tunic_a != null, "has a tunic material")
	if tunic_a:
		assert_eq((tunic_a as BaseMaterial3D).albedo_color, a.record.looks.tunic)
		assert_true(tunic_a == b.material_for("tunic"), "same color, same cached material")
	var skin := a.material_for("skin") as BaseMaterial3D
	assert_true(skin != null and skin.albedo_color == a.record.looks.skin)
	assert_near(a.model_scale(), a.record.looks.height, 0.001)
	a.queue_free()
	b.queue_free()
