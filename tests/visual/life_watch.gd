extends SceneTree
## Windowed organic check of life and death (stage 10), nothing staged: the world lives SKIP_DAYS
## with the player far away (no kingdom of the player's), then the camera follows whatever happens
## to the dead anywhere — a body lying, someone kneeling by it, carrying it, digging, the family
## praying at the grave — and the merchants and friends talking. One shot per kind of moment.
## Usage: tools/godot.ps1 -s res://tests/visual/life_watch.gd (writes captures/life_*.png)

const MAIN_SCENE := "res://scenes/main.tscn"
const OUT_DIR := "res://captures"
const SKIP_DAYS := 30
const WATCH_DAYS := 8
const SPEED := 8.0
const KINDS := ["body", "fetch_body", "carry", "bury", "funeral", "talk", "trade", "prayer"]

var _world: World
var _shots := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_world = load(MAIN_SCENE).instantiate()
	_world.spawn_seed = 42
	_world.world_seed = GameConstants.WORLD_SEED
	_world.save_path = ""
	root.add_child(_world)
	while not _world.is_world_ready():
		await process_frame
	var state := _world.get_state()
	var day_night := _world.get_day_night()
	var hour_sec := GameConstants.DAY_LENGTH_SEC / 24.0
	for h in SKIP_DAYS * 24: # the world lives on its own
		day_night.advance(hour_sec)
		await process_frame
	var graves := state.all_buildings().filter(func(b: Dictionary) -> bool: return int(b.type) == GameConstants.Building.GRAVE)
	print("LIFE skip: %d days, %d graves, %d kingdoms" % [SKIP_DAYS, graves.size(), state.kingdoms().size()])
	var end := day_night.total_hours() + WATCH_DAYS * 24.0
	var mgr := _world.get_people_manager()
	Engine.time_scale = SPEED
	var focus := Vector3(-1, -1, -1)
	while day_night.total_hours() < end and _shots.size() < KINDS.size():
		for f in 8:
			await physics_frame
		# Somewhere a body lies or is on its way to a grave: go there (the bearer will come).
		var body := _unburied(state)
		if not body.is_empty() and (focus.x < 0.0 or focus.distance_to(body.pos) > 30.0):
			focus = body.pos
			await _go(focus + Vector3(0, 0, 8))
		for n in mgr.active_people():
			var kind := _moment(n)
			if kind == "" or _shots.has(kind):
				continue
			_shots[kind] = true
			Engine.time_scale = 1.0
			_pending = "life_%s" % kind
			await _frame_on(n)
			print("LIFE %s: %s at %02dh" % [kind, PersonGen.full_name(n.record), floori(fmod(day_night.total_hours(), 24.0))])
			Engine.time_scale = SPEED
			break
	Engine.time_scale = 1.0
	print("LIFE seen: %s" % [_shots.keys()])
	quit(0)


## What this person is doing that is worth a shot ("" when nothing).
func _moment(n: Person) -> String:
	var rec := n.record
	if n.is_dead():
		return "body"
	if int(rec.get("carrying_body", -1)) >= 0 and n.act == PersonBrain.Act.WALK:
		return "carry"
	var deed: Dictionary = rec.get("deed", {})
	if not deed.is_empty() and n.act == PersonBrain.Act.DEED and String(deed.kind) in KINDS:
		return String(deed.kind)
	return ""


## A body lying anywhere (or carried), {} when none.
func _unburied(state: WorldState) -> Dictionary:
	for p in state.all_people():
		if p.status == "dead":
			var c := state.person(int(p.get("carrier_id", -1)))
			return c if not c.is_empty() else p
	return {}


## Centers the camera on `n` (the player waits hidden nearby, so the chunks stay loaded).
func _frame_on(n: Person) -> void:
	# No teleport: the person is already loaded near the player (moving the player could reload the
	# chunk and replace the node).
	var cam := _world.get_camera()
	var player := _world.get_player()
	player.visible = false
	var back := player.global_position
	player.global_position = n.global_position + Vector3(0, 2.5, 0) # hidden: the houses in front fade around it
	player.reset_physics_interpolation()
	cam.target = n
	cam.snap_to_target()
	for f in 3:
		await physics_frame
	await _shot_pending()
	player.global_position = back
	player.reset_physics_interpolation()
	cam.target = player
	cam.snap_to_target()
	player.visible = true


var _pending := ""


func _shot_pending() -> void:
	if _pending != "":
		await _shot(_pending)
		_pending = ""


func _go(pos: Vector3) -> void:
	var p := _world.get_player()
	p.global_position = Vector3(pos.x, _world.get_generator().height_at(pos.x, pos.z) + 0.3, pos.z)
	p.reset_physics_interpolation()
	_world.get_camera().snap_to_target()
	for f in 2:
		await physics_frame
	while _world.get_streamer().pending_count() > 0:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(OUT_DIR.path_join(shot_name + ".png"))
	root.get_texture().get_image().save_png(path)
	print("CAPTURED ", path)
