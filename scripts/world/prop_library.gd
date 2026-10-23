class_name PropLibrary
extends Node
## Loads the prop .glb scenes on a background thread and exposes their meshes for MultiMesh use.
## Scenes are requested one at a time: concurrent threaded loads that create meshes race inside
## the rendering server's storage (seen with the headless dummy renderer).

var _meshes: Dictionary[int, Mesh] = {}
var _queue: Array[int] = [] # Prop types not requested yet
var _current := -1 # Prop type being loaded, -1 = none
var _started := false


func start_loading() -> void:
	_started = true
	_queue.assign(GameConstants.PROP_SCENES.keys())
	_request_next()


func is_ready() -> bool:
	return _started and _current < 0 and _queue.is_empty()


func mesh_for(type: int) -> Mesh:
	return _meshes.get(type)


func _request_next() -> void:
	if _queue.is_empty():
		_current = -1
		return
	_current = _queue.pop_front()
	ResourceLoader.load_threaded_request(GameConstants.PROP_SCENES[_current])


func _process(_delta: float) -> void:
	if _current < 0:
		return
	var path: String = GameConstants.PROP_SCENES[_current]
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var scene: PackedScene = ResourceLoader.load_threaded_get(path)
		var root := scene.instantiate()
		var meshes := root.find_children("*", "MeshInstance3D", true, false)
		if not meshes.is_empty():
			_meshes[_current] = (meshes[0] as MeshInstance3D).mesh
		root.free()
	else:
		push_error("PropLibrary: failed to load %s" % path)
	_request_next()
