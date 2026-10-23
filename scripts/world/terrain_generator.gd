class_name TerrainGenerator
extends RefCounted
## Deterministic low-poly terrain. Thread-safe: after _init it only reads its own noise,
## so build_chunk_arrays can run on WorkerThreadPool threads.

const _GRASS_LOW := Color(0.30, 0.50, 0.22)
const _GRASS_HIGH := Color(0.52, 0.66, 0.30)
const _ROCK := Color(0.55, 0.52, 0.47)
const _SLOPE_STEP := 1.0

var _noise := FastNoiseLite.new()


func _init(seed: int) -> void:
	_noise.seed = seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = GameConstants.TERRAIN_NOISE_FREQ
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 3


func height_at(x: float, z: float) -> float:
	var n := clampf(_noise.get_noise_2d(x, z), -1.0, 1.0)
	return (n + 1.0) * 0.5 * GameConstants.TERRAIN_HEIGHT


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
			# Clockwise seen from above (Godot front face).
			_add_triangle(verts, normals, colors, p00, p10, p01)
			_add_triangle(verts, normals, colors, p10, p11, p01)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	return arrays


func _add_triangle(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (c - a).cross(b - a).normalized()
	var col := _face_color((a.y + b.y + c.y) / 3.0, n)
	for p in [a, b, c]:
		verts.append(p)
		normals.append(n)
		colors.append(col)


func _face_color(h: float, n: Vector3) -> Color:
	var t := clampf(h / GameConstants.TERRAIN_HEIGHT, 0.0, 1.0)
	var col := _GRASS_LOW.lerp(_GRASS_HIGH, t)
	# Steep faces read as exposed rock.
	return col.lerp(_ROCK, clampf((0.92 - n.y) * 4.0, 0.0, 1.0))
