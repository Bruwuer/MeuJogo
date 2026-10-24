class_name Chunk
extends Node3D
## One streamed chunk: terrain mesh (+ collision when playable), one MultiMeshInstance3D per
## prop type and one cylinder collision shape per solid prop. Built on the main thread from
## data prepared off-thread by ChunkStreamer.

var coord: Vector2i

var _props: Dictionary[int, Dictionary] = {} # id -> prop
var _multimeshes: Dictionary[int, MultiMeshInstance3D] = {} # Prop type -> instance
var _shapes: Dictionary[int, CollisionShape3D] = {} # id -> shape
var _library: ModelLibrary


func build(c: Vector2i, terrain_arrays: Array, props: Array[Dictionary], removed: PackedInt32Array,
		library: ModelLibrary, terrain_material: Material) -> void:
	coord = c
	_library = library
	name = "Chunk_%d_%d" % [c.x, c.y]
	position = ChunkMath.chunk_origin(c)

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, terrain_arrays)
	mesh.surface_set_material(0, terrain_material)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	if ChunkMath.is_playable(c):
		var body := StaticBody3D.new()
		body.name = "Terrain"
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		body.add_child(shape)
		add_child(body)

	var prop_body := StaticBody3D.new()
	prop_body.name = "PropBodies"
	add_child(prop_body)
	for p in props:
		if removed.has(p.id):
			continue
		_props[p.id] = p
		var radius: float = GameConstants.PROP_COLLISION_RADIUS[p.type] * p.scale
		if radius > 0.0:
			var cyl := CylinderShape3D.new()
			cyl.radius = radius
			cyl.height = GameConstants.PROP_COLLISION_HEIGHT
			var shape := CollisionShape3D.new()
			shape.shape = cyl
			shape.position = p.pos - position + Vector3.UP * GameConstants.PROP_COLLISION_HEIGHT * 0.5
			prop_body.add_child(shape)
			_shapes[p.id] = shape
	for type in GameConstants.PROP_SCENES:
		_rebuild_type(type)


func has_prop(id: int) -> bool:
	return _props.has(id)


func get_prop(id: int) -> Dictionary:
	return _props.get(id, {})


func prop_ids() -> PackedInt32Array:
	return PackedInt32Array(_props.keys())


func instance_count(type: int) -> int:
	var mmi: MultiMeshInstance3D = _multimeshes.get(type)
	return mmi.multimesh.instance_count if mmi else 0


func remove_prop(id: int) -> void:
	if not _props.has(id):
		return
	var type: int = _props[id].type
	_props.erase(id)
	if _shapes.has(id):
		_shapes[id].queue_free()
		_shapes[id].get_parent().remove_child(_shapes[id])
		_shapes.erase(id)
	_rebuild_type(type)


func _rebuild_type(type: int) -> void:
	var transforms: Array[Transform3D] = []
	for p in _props.values():
		if p.type == type:
			var basis := Basis(Vector3.UP, p.yaw).scaled(Vector3.ONE * p.scale)
			transforms.append(Transform3D(basis, p.pos - position))
	var mmi: MultiMeshInstance3D = _multimeshes.get(type)
	if transforms.is_empty():
		if mmi:
			mmi.queue_free()
			_multimeshes.erase(type)
		return
	if mmi == null:
		mmi = MultiMeshInstance3D.new()
		mmi.name = "Props_%d" % type
		mmi.multimesh = MultiMesh.new()
		mmi.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		mmi.multimesh.mesh = _library.mesh_for(type)
		add_child(mmi)
		_multimeshes[type] = mmi
	mmi.multimesh.instance_count = transforms.size()
	for i in transforms.size():
		mmi.multimesh.set_instance_transform(i, transforms[i])
