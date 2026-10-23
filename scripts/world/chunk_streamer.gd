class_name ChunkStreamer
extends Node3D
## Keeps the chunks within LOAD_RADIUS of a center loaded. Meshes are built on
## WorkerThreadPool threads; nodes are created on the main thread in _process,
## at most CHUNKS_APPLIED_PER_FRAME per frame. Results for chunks that left the
## radius while building are discarded.

signal chunk_loaded(c: Vector2i)
signal chunk_unloaded(c: Vector2i)

var _gen: TerrainGenerator
var _material: StandardMaterial3D
var _center := Vector2i(1 << 30, 1 << 30)
var _desired: Dictionary[Vector2i, bool] = {}
var _loaded: Dictionary[Vector2i, Node3D] = {}
var _in_flight: Dictionary[Vector2i, int] = {} # coord -> WorkerThreadPool task id
var _results: Array = [] # [coord, arrays], written by worker threads
var _results_mutex := Mutex.new()


func setup(gen: TerrainGenerator) -> void:
	_gen = gen
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.roughness = 1.0


func update_center(world_pos: Vector3) -> void:
	var c := ChunkMath.world_to_chunk(world_pos)
	if c == _center:
		return
	_center = c
	_desired.clear()
	for coord in ChunkMath.chunks_in_radius(c, GameConstants.LOAD_RADIUS):
		_desired[coord] = true
	for coord in _loaded.keys():
		if not _desired.has(coord):
			_unload(coord)
	for coord in _desired:
		if not _loaded.has(coord) and not _in_flight.has(coord):
			_in_flight[coord] = WorkerThreadPool.add_task(_build.bind(coord), false, "chunk %s" % coord)


func is_loaded(c: Vector2i) -> bool:
	return _loaded.has(c)


func loaded_coords() -> Array[Vector2i]:
	return _loaded.keys()


func pending_count() -> int:
	return _in_flight.size()


func _build(coord: Vector2i) -> void: # worker thread
	var arrays := _gen.build_chunk_arrays(coord)
	_results_mutex.lock()
	_results.append([coord, arrays])
	_results_mutex.unlock()


func _process(_delta: float) -> void:
	_results_mutex.lock()
	var batch := _results.slice(0, GameConstants.CHUNKS_APPLIED_PER_FRAME)
	_results = _results.slice(GameConstants.CHUNKS_APPLIED_PER_FRAME)
	_results_mutex.unlock()
	for item in batch:
		var coord: Vector2i = item[0]
		WorkerThreadPool.wait_for_task_completion(_in_flight[coord])
		_in_flight.erase(coord)
		if _desired.has(coord) and not _loaded.has(coord):
			_apply(coord, item[1])


func _apply(coord: Vector2i, arrays: Array) -> void:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)

	var chunk := Node3D.new()
	chunk.name = "Chunk_%d_%d" % [coord.x, coord.y]
	chunk.position = ChunkMath.chunk_origin(coord)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	chunk.add_child(mi)
	if ChunkMath.is_playable(coord):
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		body.add_child(shape)
		chunk.add_child(body)
	add_child(chunk)
	_loaded[coord] = chunk
	chunk_loaded.emit(coord)


func _unload(coord: Vector2i) -> void:
	_loaded[coord].queue_free()
	_loaded.erase(coord)
	chunk_unloaded.emit(coord)


func _exit_tree() -> void:
	for task_id in _in_flight.values():
		WorkerThreadPool.wait_for_task_completion(task_id)
	_in_flight.clear()
	_results.clear()
