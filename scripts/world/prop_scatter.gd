class_name PropScatter
extends RefCounted
## Deterministic placement of trees, rocks and bushes. One candidate per PROP_CELL grid cell;
## a prop's id is its cell index (j * cells + i), so ids survive density tweaks.
## Thread-safe: uses only a local RandomNumberGenerator and the (read-only) TerrainGenerator.

var _gen: TerrainGenerator
var _seed: int
var _cells: int


func _init(gen: TerrainGenerator, seed: int) -> void:
	_gen = gen
	_seed = seed
	_cells = int(GameConstants.CHUNK_SIZE / GameConstants.PROP_CELL)


## Each entry: {id: int, type: int (Prop), pos: Vector3 (world), yaw: float, scale: float}.
func build_chunk_props(c: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_seed, c.x, c.y])
	var origin := ChunkMath.chunk_origin(c)
	for j in _cells:
		for i in _cells:
			# Always draw the same five numbers per cell so later cells never shift.
			var jx := rng.randf()
			var jz := rng.randf()
			var roll := rng.randf()
			var yaw := rng.randf_range(0.0, TAU)
			var scale := rng.randf_range(GameConstants.PROP_SCALE_MIN, GameConstants.PROP_SCALE_MAX)
			var x := origin.x + (i + jx) * GameConstants.PROP_CELL
			var z := origin.z + (j + jz) * GameConstants.PROP_CELL
			var type := _roll_type(_gen.biome_at(x, z), roll)
			if type < 0 or _gen.slope_deg_at(x, z) > GameConstants.PROP_MAX_SLOPE_DEG:
				continue
			var y := _gen.height_at(x, z) - GameConstants.PROP_SINK * scale
			out.append({id = j * _cells + i, type = type, pos = Vector3(x, y, z), yaw = yaw, scale = scale})
	return out


## Props whose flat distance to `pos` is at most `radius`, across chunk borders.
func props_near(pos: Vector3, radius: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var lo := ChunkMath.world_to_chunk(pos - Vector3(radius, 0, radius))
	var hi := ChunkMath.world_to_chunk(pos + Vector3(radius, 0, radius))
	for cy in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			for p in build_chunk_props(Vector2i(cx, cy)):
				if Vector2(p.pos.x - pos.x, p.pos.z - pos.z).length() <= radius:
					out.append(p)
	return out


func _roll_type(biome: int, roll: float) -> int:
	var acc := 0.0
	var table: Dictionary = GameConstants.PROP_DENSITY[biome]
	for type in table:
		acc += table[type]
		if roll < acc:
			return type
	return -1
