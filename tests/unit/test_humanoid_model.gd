extends GameTest


func _instance() -> Node3D:
	if not ResourceLoader.exists(GameConstants.HUMANOID_SCENE):
		failures.append("humanoid.glb missing: run tools/build_models.ps1")
		return null
	var m: Node3D = load(GameConstants.HUMANOID_SCENE).instantiate()
	add_child(m)
	return m


func _mesh_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var b := mi.global_transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func test_humanoid_has_rig_and_animations() -> void:
	var m := _instance()
	if m == null:
		return
	assert_eq(m.find_children("*", "Skeleton3D", true, false).size(), 1, "Skeleton3D count")
	var players := m.find_children("*", "AnimationPlayer", true, false)
	assert_eq(players.size(), 1, "AnimationPlayer count")
	if players.is_empty():
		return
	var ap: AnimationPlayer = players[0]
	for a in [GameConstants.ANIM_IDLE, GameConstants.ANIM_WALK, GameConstants.ANIM_RUN]:
		assert_true(ap.has_animation(a), "missing animation " + a)


func test_humanoid_height() -> void:
	var m := _instance()
	if m == null:
		return
	var box := _mesh_aabb(m)
	assert_true(box.size.y >= 1.6 and box.size.y <= 2.0, "height %f" % box.size.y)
	assert_near(box.position.y, 0.0, 0.05, "feet at origin")


func test_humanoid_faces_plus_z() -> void:
	# Boots and nose stick out in front, so the front extent is larger than the back one.
	var m := _instance()
	if m == null:
		return
	var box := _mesh_aabb(m)
	assert_true(box.end.z > -box.position.z, "front (+Z) %f vs back %f" % [box.end.z, -box.position.z])


func test_animations_move_bones() -> void:
	var m := _instance()
	if m == null:
		return
	var ap: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
	var skel: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	for a in [GameConstants.ANIM_IDLE, GameConstants.ANIM_WALK, GameConstants.ANIM_RUN]:
		var anim := ap.get_animation(a)
		assert_true(anim.length > 0.3, "%s too short: %f" % [a, anim.length])
		ap.play(a)
		ap.seek(0.0, true)
		var start := skel.get_bone_pose_rotation(skel.find_bone("thigh.L"))
		var spine_start := skel.get_bone_pose_rotation(skel.find_bone("spine"))
		ap.seek(anim.length * 0.5, true)
		var moved := not skel.get_bone_pose_rotation(skel.find_bone("thigh.L")).is_equal_approx(start) \
				or not skel.get_bone_pose_rotation(skel.find_bone("spine")).is_equal_approx(spine_start)
		assert_true(moved, "%s does not move bones" % a)


func test_humanoid_has_work_animation() -> void:
	var m := _instance()
	if m == null:
		return
	var ap: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
	assert_true(ap.has_animation(GameConstants.ANIM_WORK), "missing work animation")
	if ap.has_animation(GameConstants.ANIM_WORK):
		var length := ap.get_animation(GameConstants.ANIM_WORK).length
		assert_true(length >= 0.3 and length <= 0.6, "work length %f" % length)
