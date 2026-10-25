extends SceneTree
## Windowed gallery of the villager's clips (stage 10) for visual checks: one humanoid per clip,
## frozen mid-clip, plus the grave, the shovel and the merchant's pack. Two views: the game's camera
## and from the side. Usage: tools/godot.ps1 -s res://tests/visual/poses.gd (writes captures/poses_*.png)

const OUT_DIR := "res://captures"
const CLIPS := ["idle", "dead", "pickup", "carry", "dig", "pray", "mourn", "talk", "sit", "eat", "play"]
const SPACING := 2.2


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
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
	var person: PackedScene = load("res://assets/models/humanoid.glb")
	for i in CLIPS.size():
		var m: Node3D = person.instantiate()
		stage.add_child(m)
		m.position = Vector3(i * SPACING - (CLIPS.size() - 1) * SPACING * 0.5, 0, 0)
		var anim: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
		if anim.has_animation(CLIPS[i]):
			anim.play(CLIPS[i])
			anim.seek(anim.current_animation_length * 0.3, true)
			anim.pause()
		else:
			print("MISSING clip ", CLIPS[i])
	# In use: a bearer with the body in the arms, a digger with the shovel (as the game builds them).
	var bearer: Node3D = person.instantiate()
	stage.add_child(bearer)
	bearer.position = Vector3(-3.0, 0, -3.0)
	_freeze(bearer, "carry")
	var carried: Node3D = person.instantiate()
	carried.position = GameConstants.CARRY_OFFSET
	carried.rotation_degrees = GameConstants.CARRY_ROTATION
	carried.scale = Vector3.ONE * GameConstants.CARRY_SCALE
	bearer.add_child(carried)
	_freeze(carried, "dead")
	var digger: Node3D = person.instantiate()
	stage.add_child(digger)
	digger.position = Vector3(0.0, 0, -3.0)
	_freeze(digger, "dig")
	var holder := WeaponHolder.add(digger)
	if holder:
		holder.add_child((load(GameConstants.TOOL_SCENES.shovel) as PackedScene).instantiate())
	var props := ["grave", "shovel", "pack"]
	for i in props.size():
		var scene: PackedScene = load("res://assets/models/%s.glb" % props[i])
		var p: Node3D = scene.instantiate()
		stage.add_child(p)
		p.position = Vector3(i * 2.5 - 2.5, 0.0 if i == 0 else 1.0, 3.5)
		if props[i] == "shovel":
			p.rotation_degrees.x = 180.0 # blade down
	var cam := _camera(Vector3(0, 0.8, -0.5), Vector3(GameConstants.CAM_PITCH_DEG, GameConstants.CAM_YAW_DEG, 0), 11.0)
	await _frames(5)
	await _shot("poses_iso")
	cam.rotation_degrees = Vector3(-8, 0, 0)
	cam.global_position = Vector3(0, 0.9, 1.0) + cam.global_transform.basis.z * 30.0
	cam.size = 9.0
	await _frames(3)
	await _shot("poses_front")
	cam.rotation_degrees = Vector3(-8, 90, 0)
	await _frames(1)
	cam.global_position = Vector3(0, 0.9, 0) + cam.global_transform.basis.z * 30.0
	await _frames(3)
	await _shot("poses_side")
	quit(0)


func _freeze(model: Node3D, clip: String) -> void:
	var anim: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	anim.play(clip)
	anim.seek(anim.current_animation_length * 0.3, true)
	anim.pause()


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


func _camera(target: Vector3, rot: Vector3, ortho_size: float) -> Camera3D:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = ortho_size
	cam.rotation_degrees = rot
	root.add_child(cam)
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
