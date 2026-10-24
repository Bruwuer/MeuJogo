class_name BuildSystem
extends Node
## Build mode: choose a building (1-5), rotate (R), see a green/red ghost at the mouse (or in
## front of the player), place (click / E), leave (Esc / right click). Outside build mode X
## demolishes the nearest building for a partial refund. The first cabin founds the kingdom.

signal built(rec: Dictionary)
signal demolished(rec: Dictionary)
signal kingdom_founded(kingdom: Dictionary)
signal message(text: String)

var active := false
var type: int = GameConstants.Building.CABIN
var rot := 0
## Tests turn this off so the ghost follows the player instead of the (absent) mouse.
var use_mouse := true

var _state: WorldState
var _gen: TerrainGenerator
var _scatter: PropScatter
var _streamer: ChunkStreamer
var _library: ModelLibrary
var _player: Player
var _camera: Camera3D
var _ghost: Node3D
var _ghost_type := -1
var _ok_mat := _ghost_material(GameConstants.GHOST_OK_COLOR)
var _bad_mat := _ghost_material(GameConstants.GHOST_BAD_COLOR)


func setup(state: WorldState, gen: TerrainGenerator, scatter: PropScatter, streamer: ChunkStreamer,
		library: ModelLibrary, player: Player, camera: Camera3D) -> void:
	_state = state
	_gen = gen
	_scatter = scatter
	_streamer = streamer
	_library = library
	_player = player
	_camera = camera


func toggle() -> void:
	active = not active
	_player.harvest_enabled = not active
	if not active and _ghost:
		_ghost.visible = false


func select(building: int) -> void:
	type = building
	if not active:
		toggle()


func rotate_ghost() -> void:
	rot = (rot + 1) % 4


func ghost_position() -> Vector3:
	if use_mouse:
		var hit: Variant = _mouse_ground()
		if hit != null:
			return BuildRules.snap(hit)
	return BuildRules.snap(_player.global_position + _player.facing() * GameConstants.BUILD_GHOST_DISTANCE)


func preview() -> Dictionary:
	return BuildRules.check(type, ghost_position(), rot, _gen, _scatter, _state)


## Validates, spends and builds at the ghost. Nothing is spent unless the building is placed.
func try_place() -> bool:
	var pos := ghost_position()
	var check := BuildRules.check(type, pos, rot, _gen, _scatter, _state)
	if not check.ok:
		message.emit(check.reason)
		return false
	if not _state.spend(GameConstants.BUILD_COST[type]):
		return false
	for bush in check.bushes:
		_state.mark_removed(bush.chunk, bush.id)
		var chunk := _streamer.get_chunk(bush.chunk)
		if chunk:
			chunk.remove_prop(bush.id)
	var rec := _state.add_building(type, Vector3(pos.x, check.y, pos.z), rot)
	_add_to_chunk(rec)
	built.emit(rec)
	if type == GameConstants.Building.CABIN and _state.kingdoms().is_empty():
		_found_kingdom(rec)
	return true


## Removes the closest building whose footprint is within BUILD_DEMOLISH_RANGE of `near`.
func try_demolish(near: Vector3) -> bool:
	var target := {}
	var best := GameConstants.BUILD_DEMOLISH_RANGE
	var center := ChunkMath.world_to_chunk(near)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			for b in _state.buildings_in(center + Vector2i(dx, dy)):
				if b.type == GameConstants.Building.FLAG:
					continue
				var rect := BuildRules.footprint_rect(b.type, b.pos, b.rot)
				var p := Vector2(near.x, near.z)
				var closest := Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y))
				var d := closest.distance_to(p)
				if d <= best:
					best = d
					target = b
	if target.is_empty():
		return false
	if _state.kingdoms().any(func(k: Dictionary) -> bool: return k.seat_id == target.id):
		message.emit(GameConstants.BUILD_MSG_SEAT)
		return false
	_state.remove_building(target.id)
	_state.refund(GameConstants.BUILD_COST[target.type], GameConstants.BUILD_REFUND)
	var chunk := _streamer.get_chunk(ChunkMath.world_to_chunk(target.pos))
	if chunk:
		chunk.remove_building(target.id)
	demolished.emit(target)
	return true


## First terrain hit along a ray (trees, rocks and buildings are ignored), or null.
func ground_hit(from: Vector3, to: Vector3) -> Variant:
	var query := PhysicsRayQueryParameters3D.create(from, to, GameConstants.LAYER_TERRAIN)
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if hit else null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_mode"):
		toggle()
	elif active:
		for i in GameConstants.BUILDABLE.size():
			if event.is_action_pressed("build_%d" % (i + 1)):
				select(GameConstants.BUILDABLE[i])
		if event.is_action_pressed("build_rotate"):
			rotate_ghost()
		elif event.is_action_pressed("build_place") or event.is_action_pressed("interact"):
			try_place()
		elif event.is_action_pressed("build_cancel"):
			toggle()
	elif event.is_action_pressed("demolish"):
		try_demolish(_player.global_position)


func _process(_delta: float) -> void:
	if not active or _library == null or not _library.is_ready():
		return
	if _ghost_type != type:
		_rebuild_ghost()
	var check := preview()
	var pos := ghost_position()
	_ghost.visible = true
	_ghost.global_position = Vector3(pos.x, check.y if check.y != 0.0 else _gen.height_at(pos.x, pos.z), pos.z)
	_ghost.rotation.y = rot * PI * 0.5
	var mat := _ok_mat if check.ok else _bad_mat
	for mi: MeshInstance3D in _ghost.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = mat


func _rebuild_ghost() -> void:
	if _ghost:
		_ghost.queue_free()
	_ghost = Node3D.new()
	_ghost.name = "Ghost"
	var scene := _library.scene_for(type)
	if scene:
		_ghost.add_child(scene.instantiate())
	for mi: MeshInstance3D in _ghost.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost)
	_ghost_type = type


func _found_kingdom(cabin: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("kingdom_color_%d" % _state.seed)
	var color := Color.from_hsv(rng.randf(), GameConstants.KINGDOM_COLOR_SAT, GameConstants.KINGDOM_COLOR_VAL)
	var name := KingdomNames.generate(_state.seed, _state.kingdoms().size())
	var offset := Basis(Vector3.UP, cabin.rot * PI * 0.5) * GameConstants.FLAG_OFFSET
	var flag := _state.add_building(GameConstants.Building.FLAG, cabin.pos + offset, cabin.rot, color)
	_add_to_chunk(flag)
	var kingdom := _state.add_kingdom(name, color, cabin.pos, cabin.id)
	kingdom_founded.emit(kingdom)


func _add_to_chunk(rec: Dictionary) -> void:
	var chunk := _streamer.get_chunk(ChunkMath.world_to_chunk(rec.pos))
	if chunk:
		chunk.add_building(rec)


func _mouse_ground() -> Variant:
	var viewport := _camera.get_viewport()
	var mouse := viewport.get_mouse_position()
	if not viewport.get_visible_rect().has_point(mouse):
		return null
	var from := _camera.project_ray_origin(mouse)
	return ground_hit(from, from + _camera.project_ray_normal(mouse) * GameConstants.BUILD_RAY_LENGTH)


static func _ghost_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
