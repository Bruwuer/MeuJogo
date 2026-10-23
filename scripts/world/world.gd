class_name World
extends Node3D
## Root of the main scene: terrain streaming, light, map-edge walls, player and camera.
## The player stays frozen whenever the chunk under it has no collision yet.

signal world_ready

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const _SPAWN_DROP := 0.5
const _WALL_THICKNESS := 1.0
const _WALL_HEIGHT := 60.0
const _SUN_ROTATION_DEG := Vector3(-55.0, -35.0, 0.0)
const _SHADOW_DISTANCE := 90.0

## -1 = random spawn; any other value makes the spawn reproducible.
@export var spawn_seed := GameConstants.SPAWN_SEED

var _gen: TerrainGenerator
var _streamer: ChunkStreamer
var _player: Player
var _camera: IsoCamera
var _spawn: Vector3
var _is_ready := false


func _ready() -> void:
	_gen = TerrainGenerator.new(GameConstants.WORLD_SEED)
	_streamer = ChunkStreamer.new()
	_streamer.name = "Chunks"
	_streamer.setup(_gen)
	add_child(_streamer)
	_add_environment()
	_add_edge_walls()

	var rng := RandomNumberGenerator.new()
	if spawn_seed >= 0:
		rng.seed = spawn_seed
	else:
		rng.randomize()
	_spawn = SpawnPicker.pick(_gen, rng)

	_player = PLAYER_SCENE.instantiate()
	add_child(_player)
	_player.global_position = _spawn + Vector3.UP * _SPAWN_DROP
	_player.reset_physics_interpolation()

	_camera = IsoCamera.new()
	_camera.target = _player
	add_child(_camera)
	_camera.make_current()
	_camera.snap_to_target()

	_streamer.chunk_loaded.connect(_on_chunk_loaded)
	_streamer.update_center(_spawn)


func _physics_process(_delta: float) -> void:
	var pos := _player.global_position
	_streamer.update_center(pos)
	_player.frozen = not _streamer.is_loaded(ChunkMath.world_to_chunk(pos))


func _on_chunk_loaded(c: Vector2i) -> void:
	if not _is_ready and c == ChunkMath.world_to_chunk(_spawn):
		_is_ready = true
		world_ready.emit()


func is_world_ready() -> bool:
	return _is_ready


func get_player() -> Player:
	return _player


func get_streamer() -> ChunkStreamer:
	return _streamer


func get_generator() -> TerrainGenerator:
	return _gen


func _add_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.38, 0.55, 0.78)
	sky_mat.sky_horizon_color = Color(0.72, 0.78, 0.82)
	sky_mat.ground_horizon_color = Color(0.72, 0.78, 0.82)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = _SUN_ROTATION_DEG
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = _SHADOW_DISTANCE
	add_child(sun)


## Invisible walls just outside the playable square.
func _add_edge_walls() -> void:
	var size := ChunkMath.playable_size()
	var half_t := _WALL_THICKNESS * 0.5
	var walls := [
		[Vector3(-half_t, 0, size * 0.5), Vector3(_WALL_THICKNESS, _WALL_HEIGHT, size)],
		[Vector3(size + half_t, 0, size * 0.5), Vector3(_WALL_THICKNESS, _WALL_HEIGHT, size)],
		[Vector3(size * 0.5, 0, -half_t), Vector3(size, _WALL_HEIGHT, _WALL_THICKNESS)],
		[Vector3(size * 0.5, 0, size + half_t), Vector3(size, _WALL_HEIGHT, _WALL_THICKNESS)],
	]
	for w in walls:
		var body := StaticBody3D.new()
		body.name = "EdgeWall"
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = w[1]
		shape.shape = box
		body.add_child(shape)
		body.position = w[0]
		add_child(body)
