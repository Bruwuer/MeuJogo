class_name HarvestSystem
extends Node
## Finds harvestable props near a position, counts hits and, on the last hit, removes the prop,
## records it in WorldState and adds the resources.

signal resources_changed
signal harvested(prop_type: int)

var _chunk_lookup: Callable # func(c: Vector2i) -> Chunk (null when not loaded)
var _state: WorldState
var _hits: Dictionary[Vector3i, int] = {} # (chunk x, chunk y, prop id) -> hits so far


func setup(chunk_lookup: Callable, state: WorldState) -> void:
	_chunk_lookup = chunk_lookup
	_state = state


## {} or {chunk: Chunk, prop: Dictionary}: the prop whose collision edge is closest to `pos`
## and within HARVEST_RANGE (flat distance).
func find_target(pos: Vector3) -> Dictionary:
	var best := {}
	var best_gap := GameConstants.HARVEST_RANGE
	var center := ChunkMath.world_to_chunk(pos)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var chunk: Chunk = _chunk_lookup.call(center + Vector2i(dx, dy))
			if chunk == null:
				continue
			for id in chunk.prop_ids():
				var p := chunk.get_prop(id)
				var radius: float = GameConstants.PROP_COLLISION_RADIUS[p.type] * p.scale
				var gap := Vector2(p.pos.x - pos.x, p.pos.z - pos.z).length() - radius
				if gap <= best_gap:
					best_gap = gap
					best = {chunk = chunk, prop = p}
	return best


func hits_on(target: Dictionary) -> int:
	return _hits.get(_key(target), 0)


## Registers one hit. Returns true when this hit removed the prop.
func hit(target: Dictionary) -> bool:
	var chunk: Chunk = target.chunk
	var prop: Dictionary = target.prop
	if not is_instance_valid(chunk) or not chunk.has_prop(prop.id):
		return false
	var key := _key(target)
	_hits[key] = _hits.get(key, 0) + 1
	if _hits[key] < GameConstants.HARVEST_HITS[prop.type]:
		return false
	_hits.erase(key)
	chunk.remove_prop(prop.id)
	_state.mark_removed(chunk.coord, prop.id)
	var yield_pair: Array = GameConstants.HARVEST_YIELD[prop.type]
	_state.add_resource(yield_pair[0], yield_pair[1])
	harvested.emit(prop.type)
	resources_changed.emit()
	return true


func _key(target: Dictionary) -> Vector3i:
	var c: Vector2i = (target.chunk as Chunk).coord
	return Vector3i(c.x, c.y, target.prop.id)
