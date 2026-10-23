extends SceneTree
## Windowed visual check: runs the main scene with a fixed spawn, drives the player
## and saves screenshots to captures/. Usage: tools/capture.ps1

const MAIN_SCENE := "res://scenes/main.tscn"
const OUT_DIR := "res://captures"
const SPAWN_SEED := 42

var _worst_ms := 0.0
var _last_usec := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var world: World = load(MAIN_SCENE).instantiate()
	world.spawn_seed = SPAWN_SEED
	root.add_child(world)
	while not world.is_world_ready() or world.get_streamer().pending_count() > 0:
		await process_frame
	await _frames(30)
	_last_usec = Time.get_ticks_usec()
	_worst_ms = 0.0
	await _shot("01_spawn")
	await _hold(["move_up"], 90)
	await _shot("02_walk_up")
	await _hold(["move_right", "run"], 90)
	await _shot("03_run_right")
	await _hold(["move_down", "move_left"], 60)
	await _shot("04_diagonal")
	Input.action_release("move_down")
	Input.action_release("move_left")
	await _frames(40)
	await _shot("05_idle")
	print("WORST_FRAME_MS %.1f" % _worst_ms)
	quit(0)


## Holds the actions for n physics frames; leaves them pressed so the shot is mid-motion.
func _hold(actions: Array, n: int) -> void:
	for a in ["move_up", "move_down", "move_left", "move_right", "run"]:
		Input.action_release(a)
	for a in actions:
		Input.action_press(a)
	for i in n:
		await physics_frame
		_track()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _track() -> void:
	var now := Time.get_ticks_usec()
	_worst_ms = maxf(_worst_ms, (now - _last_usec) / 1000.0)
	_last_usec = now


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(OUT_DIR.path_join(shot_name + ".png"))
	root.get_texture().get_image().save_png(path)
	print("CAPTURED ", path)
	_last_usec = Time.get_ticks_usec() # exclude readback + PNG encode from frame timing
