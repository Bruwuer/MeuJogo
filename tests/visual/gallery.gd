extends SceneTree
## Windowed gallery of creatures for visual checks: one of each species, plus hybrids.
## Usage: tools/godot.ps1 -s res://tests/visual/gallery.gd  (writes captures/gallery_*.png)

const OUT_DIR := "res://captures"
const SPACING := 3.2


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var lib := ModelLibrary.new()
	root.add_child(lib)
	lib.start_loading()
	while not lib.is_ready():
		await process_frame
	var stage := Node3D.new()
	root.add_child(stage)
	_lighting(stage)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 30)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.62, 0.32)
	plane.material = mat
	ground.mesh = plane
	stage.add_child(ground)

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var species: Array = GameConstants.SPECIES.keys()
	for i in species.size():
		var b := CreatureBody.new()
		stage.add_child(b)
		b.build(Genome.random(species[i], rng), lib)
		b.position = Vector3((i % 4) * SPACING - SPACING * 1.5, 0, (i / 4) * SPACING * 1.3 - SPACING * 0.65)
		b.rotation.y = deg_to_rad(-60)
	var cam := _camera(stage, Vector3(0, 0, 0), 9.0)
	await _frames(5)
	await _shot("gallery_species")

	# Parents and two cubs (rendered at adult size for comparison).
	for c in stage.get_children():
		if c is CreatureBody:
			c.queue_free()
	var wolf := Genome.random("lobo", rng)
	var boar := Genome.random("javali", rng)
	var deer := Genome.random("cervo", rng)
	var horned := Genome.random("chifrudo", rng)
	var row := [wolf, boar, Genome.cross(wolf, boar, rng), Genome.cross(wolf, boar, rng),
			deer, horned, Genome.cross(deer, horned, rng), Genome.cross(deer, horned, rng)]
	for i in row.size():
		var b := CreatureBody.new()
		stage.add_child(b)
		b.build(row[i], lib)
		b.position = Vector3((i % 4) * SPACING - SPACING * 1.5, 0, (i / 4) * SPACING * 1.3 - SPACING * 0.65)
		b.rotation.y = deg_to_rad(-60)
		print("GENOME %d %s" % [i, Genome.display_name(row[i])])
	await _frames(5)
	await _shot("gallery_hybrids")

	# Walk cycle frame.
	for c in stage.get_children():
		if c is CreatureBody:
			for k in 9:
				c.animate(1.0 / 60.0, 1.0)
	await _frames(2)
	await _shot("gallery_walk")
	cam.queue_free()
	quit(0)


func _lighting(stage: Node3D) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.75, 0.88)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.74, 0.8)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	stage.add_child(we)


func _camera(stage: Node3D, target: Vector3, ortho_size: float) -> Camera3D:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = ortho_size
	cam.rotation_degrees = Vector3(GameConstants.CAM_PITCH_DEG, GameConstants.CAM_YAW_DEG, 0)
	stage.add_child(cam)
	cam.global_position = target + cam.global_transform.basis.z * 30.0
	cam.make_current()
	return cam


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(OUT_DIR.path_join(shot_name + ".png"))
	root.get_texture().get_image().save_png(path)
	print("CAPTURED ", path)
