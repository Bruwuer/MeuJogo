class_name PropLibrary
extends Node
## Loads the prop .glb scenes on a background thread and exposes their meshes for MultiMesh use.
## Scenes are requested one at a time: concurrent threaded loads that create meshes race inside
## the rendering server's storage (seen with the headless dummy renderer).
## Each surface's material is swapped for the occlusion shader (same color), so props between
## the camera and the player fade out.

const OCCLUSION_SHADER := "res://shaders/prop_occlusion.gdshader"
const _SHADER := preload(OCCLUSION_SHADER)
const _DEFAULT_ROUGHNESS := 0.9

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
			var mesh: Mesh = (meshes[0] as MeshInstance3D).mesh
			_use_occlusion_shader(mesh)
			_meshes[_current] = mesh
		root.free()
	else:
		push_error("PropLibrary: failed to load %s" % path)
	_request_next()


func _use_occlusion_shader(mesh: Mesh) -> void:
	for s in mesh.get_surface_count():
		var src := mesh.surface_get_material(s) as BaseMaterial3D
		if src == null and mesh.surface_get_material(s) is ShaderMaterial:
			continue # already converted (scene cached by an earlier library)
		var mat := ShaderMaterial.new()
		mat.shader = _SHADER
		mat.set_shader_parameter("albedo", src.albedo_color if src else Color.WHITE)
		mat.set_shader_parameter("roughness", src.roughness if src else _DEFAULT_ROUGHNESS)
		mesh.surface_set_material(s, mat)
