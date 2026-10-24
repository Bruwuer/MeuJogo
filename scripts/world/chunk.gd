class_name Chunk
extends Node3D
## One streamed chunk: terrain mesh (+ collision when playable), one MultiMeshInstance3D per
## prop type, one cylinder collision shape per solid prop, and the player's buildings.
## Built on the main thread from data prepared off-thread by ChunkStreamer.

const _FENCE_SKIRT_DEPTH := 0.2

var coord: Vector2i

var _props: Dictionary[int, Dictionary] = {} # id -> prop
var _multimeshes: Dictionary[int, MultiMeshInstance3D] = {} # Prop type -> instance
var _shapes: Dictionary[int, CollisionShape3D] = {} # id -> shape
var _buildings: Dictionary[int, Node3D] = {} # building id -> node
var _library: ModelLibrary


func build(c: Vector2i, terrain_arrays: Array, props: Array[Dictionary], removed: PackedInt32Array,
		library: ModelLibrary, terrain_material: Material, buildings: Array[Dictionary] = []) -> void:
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
		body.collision_layer = GameConstants.LAYER_TERRAIN
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		body.add_child(shape)
		add_child(body)

	var prop_body := StaticBody3D.new()
	prop_body.name = "PropBodies"
	prop_body.collision_layer = GameConstants.LAYER_OBSTACLES
	prop_body.collision_mask = 0
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
	for rec in buildings:
		add_building(rec)


func has_building(id: int) -> bool:
	return _buildings.has(id)


## Instances a building record (see WorldState.add_building) inside this chunk.
func add_building(rec: Dictionary) -> void:
	if _buildings.has(rec.id):
		return
	var type: int = rec.type
	var node := Node3D.new()
	node.name = "B_%d" % rec.id
	node.position = rec.pos - position
	node.rotation.y = rec.rot * PI * 0.5
	var site: bool = rec.get("site", false)
	var scene := _library.scene_for(type)
	if scene:
		var model := scene.instantiate() as Node3D
		model.name = "Model"
		if site:
			model.scale.y = _site_scale(rec)
		node.add_child(model)
	var fp: Vector2 = GameConstants.BUILD_FOOTPRINT[type]
	var flat := type in GameConstants.BUILD_FLAT
	if site and _library.scaffold_scene():
		var scaffold := _library.scaffold_scene().instantiate() as Node3D
		scaffold.name = "Scaffold"
		scaffold.scale = Vector3(fp.x, 1.0, fp.y)
		node.add_child(scaffold)
	if type != GameConstants.Building.FLAG and not flat:
		node.add_child(_foundation(type, fp))
	if not flat:
		node.add_child(_colliders(type, fp, site))
	if type == GameConstants.Building.FLAG or type == GameConstants.Building.STAKE:
		_color_banner(node, rec.color)
	elif type == GameConstants.Building.CAMPFIRE:
		var light := CampfireLight.new()
		light.position = Vector3.UP * 0.6
		node.add_child(light)
	add_child(node)
	_buildings[rec.id] = node


## Refreshes a site after work: the model rises with progress; a finished site is rebuilt as a
## normal building (no scaffold, full collision).
func update_site(rec: Dictionary) -> void:
	if not _buildings.has(rec.id):
		return
	if not rec.get("site", false):
		remove_building(rec.id)
		add_building(rec)
		return
	var model := _buildings[rec.id].get_node_or_null("Model") as Node3D
	if model:
		model.scale.y = _site_scale(rec)


func _site_scale(rec: Dictionary) -> float:
	return lerpf(GameConstants.SITE_MIN_SCALE, 1.0, float(rec.get("progress", 0.0)))


func remove_building(id: int) -> void:
	if not _buildings.has(id):
		return
	var node := _buildings[id]
	_buildings.erase(id)
	remove_child(node)
	node.queue_free()


func _foundation(type: int, fp: Vector2) -> MeshInstance3D:
	var is_fence := type == GameConstants.Building.FENCE
	var box := BoxMesh.new()
	box.size = Vector3(fp.x, GameConstants.FOUNDATION_DEPTH, _FENCE_SKIRT_DEPTH if is_fence else fp.y)
	var mat := ShaderMaterial.new()
	mat.shader = preload(ModelLibrary.OCCLUSION_SHADER)
	mat.set_shader_parameter("albedo", GameConstants.FOUNDATION_WOOD if is_fence else GameConstants.FOUNDATION_STONE)
	box.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Foundation"
	mi.mesh = box
	mi.position = Vector3.DOWN * GameConstants.FOUNDATION_DEPTH * 0.5
	return mi


## Static body on the obstacle layer: the type's boxes plus one for the foundation (a site has
## only the foundation).
func _colliders(type: int, fp: Vector2, site := false) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = GameConstants.LAYER_OBSTACLES
	body.collision_mask = 0
	var boxes: Array = [] if site else GameConstants.BUILD_COLLIDERS[type].duplicate()
	if type != GameConstants.Building.FLAG:
		var depth := _FENCE_SKIRT_DEPTH if type == GameConstants.Building.FENCE else fp.y
		boxes.append([Vector3.DOWN * GameConstants.FOUNDATION_DEPTH * 0.5, Vector3(fp.x, GameConstants.FOUNDATION_DEPTH, depth)])
	for b in boxes:
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = b[1]
		shape.shape = bs
		shape.position = b[0]
		body.add_child(shape)
	return body


func _color_banner(node: Node3D, color: Color) -> void:
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat and mat.resource_name == "banner":
				var own := mat.duplicate() as ShaderMaterial
				own.set_shader_parameter("albedo", color)
				mi.set_surface_override_material(s, own)


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


func building_node(id: int) -> Node3D:
	return _buildings.get(id)


## Shows `crest` on a banner beside the building's front corner ({} removes it). Does nothing when
## the banner already shows that crest. The chunk knows nothing about families: PeopleManager calls it.
func set_crest(rec: Dictionary, crest: Dictionary) -> void:
	var node: Node3D = _buildings.get(rec.id)
	if node == null:
		return
	var key := Crest.key(crest) if not crest.is_empty() else ""
	var old := node.get_node_or_null("Crest")
	if old and old.get_meta("crest_key", "") == key:
		return
	if old:
		node.remove_child(old)
		old.queue_free()
	if key == "" or _library.crest_scene() == null:
		return
	var banner := _library.crest_scene().instantiate() as Node3D
	banner.name = "Crest"
	banner.set_meta("crest_key", key)
	# The camera never turns: the banner goes on the corner it sees, its cloth turned to it.
	var yaw := deg_to_rad(GameConstants.CAM_YAW_DEG)
	var cam := Vector3(sin(yaw), 0.0, cos(yaw)).rotated(Vector3.UP, -node.rotation.y) # in the building's frame
	var fp: Vector2 = GameConstants.BUILD_FOOTPRINT[rec.type]
	banner.position = Vector3(signf(cam.x) * (fp.x * 0.5 + GameConstants.CREST_BANNER_GAP.x), 0.0,
			signf(cam.z) * (fp.y * 0.5 - GameConstants.CREST_BANNER_GAP.y))
	banner.rotation.y = yaw - node.rotation.y
	for mi: MeshInstance3D in banner.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat and mat.resource_name == "crest":
				mi.set_surface_override_material(s, Crest.material(crest))
	node.add_child(banner)
