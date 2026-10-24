class_name TerrainGenerator
extends RefCounted
## Deterministic low-poly terrain with biomes. Thread-safe: after _init it only reads its own
## noises, so it can be used from WorkerThreadPool threads.

const _GRASS_LOW := Color(0.30, 0.50, 0.22)
const _GRASS_HIGH := Color(0.52, 0.66, 0.30)
const _FOREST_LOW := Color(0.20, 0.38, 0.17)
const _FOREST_HIGH := Color(0.30, 0.48, 0.20)
const _ROCKY_LOW := Color(0.34, 0.39, 0.26)
const _ROCKY_HIGH := Color(0.40, 0.39, 0.34)
const _ROCK := Color(0.40, 0.38, 0.35)
const _SLOPE_STEP := 1.0
const _BIOME_BLEND := 0.2 ## Width of the biome-value band over which colors/height blend.
const _OCTAVES := 3
const _BIOME_SEED_OFFSET := 7919

var _noise := FastNoiseLite.new()
var _biome_noise := FastNoiseLite.new()


func _init(seed: int) -> void:
	_noise.seed = seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = GameConstants.TERRAIN_NOISE_FREQ
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = _OCTAVES
	_biome_noise.seed = seed + _BIOME_SEED_OFFSET
	_biome_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_biome_noise.frequency = GameConstants.BIOME_NOISE_FREQ
	_biome_noise.fractal_type = FastNoiseLite.FRACTAL_NONE


## Raw biome value in [-1, 1]; see BIOME_FOREST_MIN / BIOME_ROCKY_MAX.
func biome_value(x: float, z: float) -> float:
	return clampf(_biome_noise.get_noise_2d(x, z) * 1.6, -1.0, 1.0)


func biome_at(x: float, z: float) -> int:
	var b := biome_value(x, z)
	if b > GameConstants.BIOME_FOREST_MIN:
		return GameConstants.Biome.FOREST
	if b < GameConstants.BIOME_ROCKY_MAX:
		return GameConstants.Biome.ROCKY
	return GameConstants.Biome.PLAINS


func height_at(x: float, z: float) -> float:
	var n := clampf(_noise.get_noise_2d(x, z), -1.0, 1.0)
	var base := (n + 1.0) * 0.5 * GameConstants.TERRAIN_HEIGHT
	var b := biome_value(x, z)
	# Plains and forest flatten hills around the mid level; rocky land rises above it.
	var mid := GameConstants.TERRAIN_HEIGHT * 0.5
	var relief := lerpf(GameConstants.PLAINS_RELIEF, GameConstants.FOREST_RELIEF, _forestness(b))
	var gentle := mid + (base - mid) * relief
	return lerpf(gentle, base * (1.0 + GameConstants.ROCKY_HEIGHT_BOOST), _rockiness(b))


func slope_deg_at(x: float, z: float) -> float:
	var dx := (height_at(x + _SLOPE_STEP, z) - height_at(x - _SLOPE_STEP, z)) / (2.0 * _SLOPE_STEP)
	var dz := (height_at(x, z + _SLOPE_STEP) - height_at(x, z - _SLOPE_STEP)) / (2.0 * _SLOPE_STEP)
	return rad_to_deg(atan(Vector2(dx, dz).length()))


## Flat-shaded, non-indexed triangle arrays for one chunk, vertices local to chunk_origin(c).
func build_chunk_arrays(c: Vector2i) -> Array:
	var cells := GameConstants.CHUNK_CELLS
	var step := GameConstants.CHUNK_SIZE / cells
	var origin := ChunkMath.chunk_origin(c)
	var heights := PackedFloat32Array()
	heights.resize((cells + 1) * (cells + 1))
	for j in cells + 1:
		for i in cells + 1:
			heights[j * (cells + 1) + i] = height_at(origin.x + i * step, origin.z + j * step)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for j in cells:
		for i in cells:
			var p00 := Vector3(i * step, heights[j * (cells + 1) + i], j * step)
			var p10 := Vector3((i + 1) * step, heights[j * (cells + 1) + i + 1], j * step)
			var p01 := Vector3(i * step, heights[(j + 1) * (cells + 1) + i], (j + 1) * step)
			var p11 := Vector3((i + 1) * step, heights[(j + 1) * (cells + 1) + i + 1], (j + 1) * step)
			var b := biome_value(origin.x + (i + 0.5) * step, origin.z + (j + 0.5) * step)
			# Clockwise seen from above (Godot front face).
			_add_triangle(verts, normals, colors, p00, p10, p01, b)
			_add_triangle(verts, normals, colors, p10, p11, p01, b)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	return arrays


## Blends ramp up INSIDE the rocky/forest biomes, so plains stay gentle right to their edge.
func _rockiness(b: float) -> float:
	return smoothstep(GameConstants.BIOME_ROCKY_MAX, GameConstants.BIOME_ROCKY_MAX - _BIOME_BLEND, b)


func _forestness(b: float) -> float:
	return smoothstep(GameConstants.BIOME_FOREST_MIN, GameConstants.BIOME_FOREST_MIN + _BIOME_BLEND, b)


func _add_triangle(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3, biome: float) -> void:
	var n := (c - a).cross(b - a).normalized()
	var col := _face_color((a.y + b.y + c.y) / 3.0, n, biome)
	for p in [a, b, c]:
		verts.append(p)
		normals.append(n)
		colors.append(col)


func _face_color(h: float, n: Vector3, biome: float) -> Color:
	var max_h := GameConstants.TERRAIN_HEIGHT * (1.0 + GameConstants.ROCKY_HEIGHT_BOOST)
	var t := clampf(h / max_h, 0.0, 1.0)
	var col := _GRASS_LOW.lerp(_GRASS_HIGH, t)
	col = col.lerp(_FOREST_LOW.lerp(_FOREST_HIGH, t), _forestness(biome))
	col = col.lerp(_ROCKY_LOW.lerp(_ROCKY_HIGH, t), _rockiness(biome))
	# Steep faces read as exposed rock.
	return col.lerp(_ROCK, clampf((0.92 - n.y) * 4.0, 0.0, 1.0))
