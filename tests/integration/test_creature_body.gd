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


func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func _make(species: String, s := 1) -> CreatureBody:
	var lib: ModelLibrary = await _library()
	var b := CreatureBody.new()
	add_child(b)
	b.build(Genome.random(species, _rng(s)), lib)
	return b


func _lowest_leg_point(b: CreatureBody) -> float:
	var lo := INF
	for i in 4:
		var leg := b.get_node("Body/Leg%d" % i) as Node3D
		for mi: MeshInstance3D in leg.find_children("*", "MeshInstance3D", true, false):
			var box := mi.global_transform * mi.mesh.get_aabb()
			lo = minf(lo, box.position.y)
	return lo


func test_assembles_parts() -> void:
	var b: CreatureBody = await _make("lobo")
	for n in ["Body", "Body/Head", "Body/Tail", "Body/Leg0", "Body/Leg1", "Body/Leg2", "Body/Leg3"]:
		assert_true(b.get_node_or_null(n) != null, "missing %s" % n)


func test_extra_on_head_for_antlers() -> void:
	var b: CreatureBody = await _make("cervo")
	assert_true(b.get_node_or_null("Body/Head/Extra") != null, "antlers should sit on the head")
	var s: CreatureBody = await _make("espinhudo")
	assert_true(s.get_node_or_null("Body/Extra") != null, "spikes should sit on the body")


func test_colors_applied() -> void:
	var b: CreatureBody = await _make("urso", 4)
	var found := false
	for mi: MeshInstance3D in b.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(s) as ShaderMaterial
			if m and m.resource_name == "primary":
				assert_eq(m.get_shader_parameter("albedo"), b.genome.color_a)
				found = true
	assert_true(found, "no recolored primary surface")


func test_feet_on_ground() -> void:
	for species in GameConstants.SPECIES:
		var b: CreatureBody = await _make(species, 7)
		await get_tree().process_frame
		assert_near(_lowest_leg_point(b), 0.0, 0.06, "%s feet" % species)


func test_walk_swings_legs() -> void:
	var b: CreatureBody = await _make("lobo")
	for i in 10:
		b.animate(1.0 / 60.0, 0.0)
	assert_near(b.leg_angle(0), 0.0, 0.01, "legs swing while idle")
	var max_angle := 0.0
	for i in 40:
		b.animate(1.0 / 60.0, 1.0)
		max_angle = maxf(max_angle, absf(b.leg_angle(0)))
	assert_true(max_angle > deg_to_rad(15.0), "legs barely move while walking: %f" % max_angle)
	assert_true(b.leg_angle(0) * b.leg_angle(1) <= 0.0001, "front legs should swing in opposite phase")


func test_size_scales_height() -> void:
	var lib: ModelLibrary = await _library()
	var g := Genome.random("lobo", _rng(9))
	g.size = 1.0
	var a := CreatureBody.new()
	add_child(a)
	a.build(g, lib)
	var big := g.duplicate()
	big.size = 2.0
	var b := CreatureBody.new()
	add_child(b)
	b.build(big, lib)
	assert_near(b.standing_height(), a.standing_height() * 2.0, 0.001)
