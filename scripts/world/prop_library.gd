class_name PropLibrary
extends Node
## Loads the prop .glb scenes on background threads and exposes their meshes for MultiMesh use.

var _meshes: Dictionary[int, Mesh] = {}
var _pending: Dictionary[int, String] = {} # Prop type -> path still loading


func start_loading() -> void:
	for type in GameConstants.PROP_SCENES:
		var path: String = GameConstants.PROP_SCENES[type]
		ResourceLoader.load_threaded_request(path)
		_pending[type] = path


func is_ready() -> bool:
	return _pending.is_empty() and not _meshes.is_empty()


func mesh_for(type: int) -> Mesh:
	return _meshes.get(type)


func _process(_delta: float) -> void:
	for type in _pending.keys():
		var path := _pending[type]
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		_pending.erase(type)
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			push_error("PropLibrary: failed to load %s" % path)
			continue
		var scene: PackedScene = ResourceLoader.load_threaded_get(path)
		var root := scene.instantiate()
		var meshes := root.find_children("*", "MeshInstance3D", true, false)
		if not meshes.is_empty():
			_meshes[type] = (meshes[0] as MeshInstance3D).mesh
		root.free()
