extends GameTest

const PLAYER_SCENE := "res://scenes/player.tscn"


func _make_world() -> Player:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)
	var player: Player = load(PLAYER_SCENE).instantiate()
	player.position = Vector3(0, 0.05, 0)
	add_child(player)
	player.frozen = false
	return player


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


func _hold(actions: Array, physics_frames: int) -> void:
	for a in actions:
		Input.action_press(a)
	await wait_physics_frames(physics_frames)
	for a in actions:
		Input.action_release(a)


func _ticks_per_second() -> float:
	return float(Engine.physics_ticks_per_second)


func test_walk_speed() -> void:
	var p := _make_world()
	await wait_physics_frames(10)
	var start := _flat(p.global_position)
	await _hold(["move_up"], int(_ticks_per_second()))
	var dist := _flat(p.global_position).distance_to(start)
	assert_near(dist, GameConstants.WALK_SPEED, GameConstants.WALK_SPEED * 0.15, "walked 1 s")


func test_run_faster() -> void:
	var p := _make_world()
	await wait_physics_frames(10)
	var start := _flat(p.global_position)
	await _hold(["move_up", "run"], int(_ticks_per_second()))
	var dist := _flat(p.global_position).distance_to(start)
	assert_true(dist > GameConstants.WALK_SPEED * 1.5, "ran %f m in 1 s" % dist)


func test_diagonal_not_faster() -> void:
	var p := _make_world()
	await wait_physics_frames(10)
	var start := _flat(p.global_position)
	await _hold(["move_up", "move_right"], int(_ticks_per_second()))
	var dist := _flat(p.global_position).distance_to(start)
	assert_true(dist <= GameConstants.WALK_SPEED * 1.1, "diagonal %f m in 1 s" % dist)


func test_moves_screen_up() -> void:
	var p := _make_world()
	await wait_physics_frames(10)
	var start := _flat(p.global_position)
	await _hold(["move_up"], 30)
	var dir := (_flat(p.global_position) - start).normalized()
	assert_true(dir.dot(IsoInput.to_world(Vector2(0, -1), GameConstants.CAM_YAW_DEG)) > 0.95, "dir %s" % dir)


func test_model_turns_to_movement() -> void:
	var p := _make_world()
	await wait_physics_frames(10)
	await _hold(["move_right"], 60)
	var facing: Vector3 = (p.get_node("Model") as Node3D).global_transform.basis.z
	assert_true(_flat(facing).normalized().dot(IsoInput.to_world(Vector2(1, 0), GameConstants.CAM_YAW_DEG)) > 0.95,
			"model faces %s" % facing)


func test_anim_states() -> void:
	var p := _make_world()
	await wait_physics_frames(10)
	assert_eq(p.current_anim(), GameConstants.ANIM_IDLE, "standing")
	Input.action_press("move_up")
	await wait_physics_frames(10)
	assert_eq(p.current_anim(), GameConstants.ANIM_WALK, "walking")
	Input.action_press("run")
	await wait_physics_frames(10)
	assert_eq(p.current_anim(), GameConstants.ANIM_RUN, "running")
	Input.action_release("run")
	Input.action_release("move_up")
	await wait_physics_frames(10)
	assert_eq(p.current_anim(), GameConstants.ANIM_IDLE, "stopped")


func test_frozen_player_does_not_move() -> void:
	var p := _make_world()
	p.frozen = true
	var start := p.global_position
	await _hold(["move_up"], 30)
	assert_eq(p.global_position, start)


func test_camera_is_ortho_iso() -> void:
	var cam := IsoCamera.new()
	add_child(cam)
	assert_eq(cam.projection, Camera3D.PROJECTION_ORTHOGONAL)
	assert_near(cam.size, GameConstants.CAM_ORTHO_SIZE, 0.001)
	assert_near(cam.rotation_degrees.x, GameConstants.CAM_PITCH_DEG, 0.01)
	assert_near(cam.rotation_degrees.y, GameConstants.CAM_YAW_DEG, 0.01)
	assert_near(cam.rotation_degrees.z, 0.0, 0.01)


func test_camera_follows() -> void:
	var p := _make_world()
	var cam := IsoCamera.new()
	cam.target = p
	add_child(cam)
	cam.snap_to_target()
	await wait_physics_frames(10)
	await _hold(["move_up"], 60)
	await wait_physics_frames(120)
	var offset := cam.global_position - p.global_position
	assert_true(offset.distance_to(cam.rest_offset()) < 0.5, "offset %s vs rest %s" % [offset, cam.rest_offset()])
	# The player must be on screen (near the view center).
	assert_true(not cam.is_position_behind(p.global_position))


func test_player_without_animations_still_moves() -> void:
	# A model with no AnimationPlayer (e.g. broken export) must not crash the player.
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(50, 1, 50)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)
	var p := Player.new()
	var body_shape := CollisionShape3D.new()
	body_shape.shape = CapsuleShape3D.new()
	body_shape.position = Vector3(0, 1, 0)
	p.add_child(body_shape)
	var model := Node3D.new()
	model.name = "Model"
	p.add_child(model)
	p.position = Vector3(0, 0.05, 0)
	add_child(p)
	p.frozen = false
	var start := p.global_position
	await _hold(["move_up"], 30)
	assert_eq(p.current_anim(), "")
	assert_true(_flat(p.global_position).distance_to(_flat(start)) > 1.0, "player did not move")


func test_player_collides_with_creatures_and_is_in_group() -> void:
	var p := _make_world()
	assert_true(p.collision_mask & GameConstants.LAYER_CREATURES != 0, "player walks through creatures")
	assert_true(p.is_in_group("player"))
