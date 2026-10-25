extends SceneTree
## Windowed look at villagers of each trade as the game builds them (Person nodes): hats, the
## guard's spear, the merchant's pack. Usage: tools/godot.ps1 -s res://tests/visual/trades.gd

const P := GameConstants.Profession


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var lib := ModelLibrary.new()
	root.add_child(lib)
	lib.start_loading()
	while not lib.is_ready():
		await process_frame
	var stage := Node3D.new()
	root.add_child(stage)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	stage.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.75, 0.88)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.74, 0.8)
	var we := WorldEnvironment.new()
	we.environment = env
	stage.add_child(we)
	var trades := [P.FARMER, P.GUARD, P.WOODCUTTER, P.GATHERER, P.MASON, P.BUILDER, P.MERCHANT]
	for i in trades.size():
		var rng := RandomNumberGenerator.new()
		rng.seed = i + 3
		var rec := PersonGen.generate(rng, 0.0, trades[i])
		rec.merge({id = 100 + i, pos = Vector3(i * 1.6 - 4.8, 0, 0), status = "merchant" if trades[i] == P.MERCHANT else "resident",
				carrying = {}, home_id = -1, inside = -1, job = "", age = 30.0}, true)
		var n := Person.new()
		stage.add_child(n)
		n.setup(rec, lib, null)
		n.set_physics_process(false)
		n.rotation.y = deg_to_rad(20)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 5.0
	cam.rotation_degrees = Vector3(GameConstants.CAM_PITCH_DEG, GameConstants.CAM_YAW_DEG, 0)
	root.add_child(cam)
	cam.global_position = Vector3(0, 1.1, 0) + cam.global_transform.basis.z * 30.0
	cam.make_current()
	for f in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://captures/trades.png")
	root.get_texture().get_image().save_png(path)
	print("CAPTURED ", path)
	quit(0)
