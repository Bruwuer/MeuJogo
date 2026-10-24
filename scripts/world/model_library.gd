class_name ModelLibrary
extends Node
## Loads every model the world streams (prop meshes for MultiMesh, building scenes, creature
## parts) on a
## background thread, ONE file at a time: concurrent threaded loads that create meshes race
## inside the rendering server's storage (seen with the headless dummy renderer).
## Every surface material is swapped for the occlusion shader (same color, emission and name),
## so props and buildings between the camera and the player fade out.

const OCCLUSION_SHADER := "res://shaders/prop_occlusion.gdshader"
const _SHADER := preload(OCCLUSION_SHADER)
const _DEFAULT_ROUGHNESS := 0.9

var _meshes: Dictionary[int, Mesh] = {} # Prop type -> mesh
var _scenes: Dictionary[int, PackedScene] = {} # Building type -> scene
var _parts: Dictionary[String, PackedScene] = {} # creature part name -> scene
var _weapons: Dictionary[int, PackedScene] = {} # Weapon -> scene (own materials: never faded)
var _arrow: PackedScene
var _queue: Array[Array] = [] # [kind ("prop" | "building" | "part" | "weapon" | "arrow"), key, path] not requested yet
var _current: Array = [] # entry being loaded, [] = none
var _started := false


func start_loading() -> void:
	_started = true
	for type in GameConstants.PROP_SCENES:
		_queue.append(["prop", type, GameConstants.PROP_SCENES[type]])
	for type in GameConstants.BUILD_SCENES:
		_queue.append(["building", type, GameConstants.BUILD_SCENES[type]])
	for part in GameConstants.CREATURE_PARTS:
		_queue.append(["part", part, GameConstants.CREATURE_PART_PATH % part])
	for w in GameConstants.WEAPONS:
		_queue.append(["weapon", w, GameConstants.WEAPONS[w].scene])
	_queue.append(["arrow", 0, GameConstants.ARROW_SCENE])
	_request_next()


func is_ready() -> bool:
	return _started and _current.is_empty() and _queue.is_empty()


func mesh_for(type: int) -> Mesh:
	return _meshes.get(type)


func scene_for(building: int) -> PackedScene:
	return _scenes.get(building)


func weapon_scene(weapon: int) -> PackedScene:
	return _weapons.get(weapon)


func arrow_scene() -> PackedScene:
	return _arrow


func part_scene(part: String) -> PackedScene:
	return _parts.get(part)


func _request_next() -> void:
	if _queue.is_empty():
		_current = []
		return
	_current = _queue.pop_front()
	ResourceLoader.load_threaded_request(_current[2])


func _process(_delta: float) -> void:
	if _current.is_empty():
		return
	var path: String = _current[2]
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var scene: PackedScene = ResourceLoader.load_threaded_get(path)
		var root := scene.instantiate()
		var meshes := root.find_children("*", "MeshInstance3D", true, false)
		if not (_current[0] in ["weapon", "arrow"]): # held items keep their own materials
			for mi: MeshInstance3D in meshes:
				_use_occlusion_shader(mi.mesh)
		if _current[0] == "prop":
			if not meshes.is_empty():
				_meshes[_current[1]] = (meshes[0] as MeshInstance3D).mesh
		elif _current[0] == "weapon":
			_weapons[_current[1]] = scene
		elif _current[0] == "arrow":
			_arrow = scene
		elif _current[0] == "building":
			_scenes[_current[1]] = scene
		else:
			_parts[_current[1]] = scene
		root.free()
	else:
		push_error("ModelLibrary: failed to load %s" % path)
	_request_next()


## Mesh resources are shared by every instance of a scene, so converting them once is enough.
func _use_occlusion_shader(mesh: Mesh) -> void:
	for s in mesh.get_surface_count():
		if mesh.surface_get_material(s) is ShaderMaterial:
			continue # already converted (scene cached by an earlier library)
		var src := mesh.surface_get_material(s) as BaseMaterial3D
		var mat := ShaderMaterial.new()
		mat.shader = _SHADER
		mat.resource_name = src.resource_name if src else ""
		mat.set_shader_parameter("albedo", src.albedo_color if src else Color.WHITE)
		mat.set_shader_parameter("roughness", src.roughness if src else _DEFAULT_ROUGHNESS)
		if src and src.emission_enabled:
			mat.set_shader_parameter("emission", src.emission * src.emission_energy_multiplier)
		mesh.surface_set_material(s, mat)
