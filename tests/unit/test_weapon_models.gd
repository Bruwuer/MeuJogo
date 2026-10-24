extends GameTest


func _aabb(path: String) -> AABB:
	var m: Node3D = load(path).instantiate()
	add_child(m)
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		var b := mi.global_transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func test_weapon_models_exist_and_point_up_y() -> void:
	for w in GameConstants.WEAPONS:
		var path: String = GameConstants.WEAPONS[w].scene
		assert_true(ResourceLoader.exists(path), "missing " + path)
		if not ResourceLoader.exists(path):
			continue
		var box := _aabb(path)
		assert_true(box.size.y > box.size.x and box.size.y > 0.5 or w == GameConstants.Weapon.BOW, "%s not along +Y: %s" % [path, box])
	assert_true(ResourceLoader.exists(GameConstants.ARROW_SCENE), "missing arrow")
	var arrow := _aabb(GameConstants.ARROW_SCENE)
	assert_true(arrow.position.y > -0.05 and arrow.end.y > 0.6, "arrow should start at its nock: %s" % arrow)
	var bow := _aabb(GameConstants.WEAPONS[GameConstants.Weapon.BOW].scene)
	assert_true(bow.size.z > 1.0, "bow limbs should be vertical (Godot Z before the hand turns it): %s" % bow)
