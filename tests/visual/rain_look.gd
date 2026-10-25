extends SceneTree
## Windowed look at a rainy day (stage 11): the drops, the grey sky and the dim light. The weather is
## set to rain now (a look check of the effect; what people do in the rain is in the tests and in
## life_watch.gd). Usage: tools/godot.ps1 -s res://tests/visual/rain_look.gd (writes captures/rain_look.png)

const MAIN_SCENE := "res://scenes/main.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world: World = load(MAIN_SCENE).instantiate()
	world.spawn_seed = 42
	world.world_seed = GameConstants.WORLD_SEED
	world.save_path = ""
	root.add_child(world)
	while not world.is_world_ready():
		await process_frame
	var dn := world.get_day_night()
	dn.time_of_day = 0.45
	dn.apply()
	var now := dn.total_hours()
	world.get_state().rain_from = now - 1.0
	world.get_state().rain_until = now + 5.0
	for f in 90:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://captures/rain_look.png")
	root.get_texture().get_image().save_png(path)
	print("CAPTURED ", path)
	quit(0)
