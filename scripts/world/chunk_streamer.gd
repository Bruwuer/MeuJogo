class_name ChunkStreamer
extends Node3D
## Keeps the chunks within LOAD_RADIUS of a center loaded. Terrain meshes and prop lists are
## built on WorkerThreadPool threads; Chunk nodes are created on the main thread in _process,
## at most CHUNKS_APPLIED_PER_FRAME per frame and only once the PropLibrary is ready.
## Results for chunks that left the radius while building are discarded.

signal chunk_loaded(c: Vector2i)
signal chunk_unloaded(c: Vector2i)

var _gen: TerrainGenerator
var _scatter: PropScatter
var _library: PropLibrary
var _removed_provider: Callable # func(c: Vector2i) -> PackedInt32Array
var _material: StandardMaterial3D
var _center := Vector2i(1 << 30, 1 << 30)
var _desired: Dictionary[Vector2i, bool] = {}
var _loaded: Dictionary[Vector2i, Chunk] = {}
var _in_flight: Dictionary[Vector2i, int] = {} # coord -> WorkerThreadPool task id
var _results: Array = [] # [coord, arrays, props], written by worker threads
var _results_mutex := Mutex.new()


func setup(gen: TerrainGenerator, scatter: PropScatter, library: PropLibrary, removed_provider: Callable) -> void:
	_gen = gen
	_scatter = scatter
	_library = library
	_removed_provider = removed_provider
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


func get_chunk(c: Vector2i) -> Chunk:
	return _loaded.get(c)


func loaded_coords() -> Array[Vector2i]:
	return _loaded.keys()


func pending_count() -> int:
	return _in_flight.size()


func _build(coord: Vector2i) -> void: # worker thread
	var arrays := _gen.build_chunk_arrays(coord)
	var props: Array[Dictionary] = []
	if ChunkMath.is_playable(coord):
		props = _scatter.build_chunk_props(coord)
	_results_mutex.lock()
	_results.append([coord, arrays, props])
	_results_mutex.unlock()


func _process(_delta: float) -> void:
	if not _library.is_ready():
		return
	_results_mutex.lock()
	var batch := _results.slice(0, GameConstants.CHUNKS_APPLIED_PER_FRAME)
	_results = _results.slice(GameConstants.CHUNKS_APPLIED_PER_FRAME)
	_results_mutex.unlock()
	for item in batch:
		var coord: Vector2i = item[0]
		WorkerThreadPool.wait_for_task_completion(_in_flight[coord])
		_in_flight.erase(coord)
		if _desired.has(coord) and not _loaded.has(coord):
			_apply(coord, item[1], item[2])


func _apply(coord: Vector2i, arrays: Array, props: Array[Dictionary]) -> void:
	var chunk := Chunk.new()
	chunk.build(coord, arrays, props, _removed_provider.call(coord), _library, _material)
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
