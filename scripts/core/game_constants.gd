class_name GameConstants
extends RefCounted
## Single source of every tunable gameplay number. Do not hardcode these elsewhere.

# World generation
const WORLD_SEED := 1337
const SPAWN_SEED := -1 ## -1 = random spawn every run.

# Chunks (meters)
const CHUNK_SIZE := 32.0
const CHUNK_CELLS := 16 ## Terrain quads per chunk side.
const MAP_CHUNKS := 8 ## Playable map is MAP_CHUNKS x MAP_CHUNKS.
const BORDER_CHUNKS := 1 ## Visual-only ring around the playable map.
const LOAD_RADIUS := 2 ## Chunks kept loaded around the player (square radius).
const CHUNKS_APPLIED_PER_FRAME := 2

# Terrain
const TERRAIN_HEIGHT := 6.0
const TERRAIN_NOISE_FREQ := 0.02

# Player
const WALK_SPEED := 4.0
const RUN_SPEED := 7.5
const TURN_SPEED := 10.0
const GRAVITY := 20.0

# Camera
const CAM_YAW_DEG := 45.0
const CAM_PITCH_DEG := -30.0
const CAM_ORTHO_SIZE := 24.0
const CAM_DISTANCE := 40.0
const CAM_FOLLOW_SMOOTH := 6.0

# Spawn
const SPAWN_EDGE_MARGIN := 24.0
const SPAWN_MAX_SLOPE_DEG := 20.0
const SPAWN_MAX_TRIES := 64

# Performance budget
const MAX_FRAME_MS := 50.0

# Models and animations
const ANIM_IDLE := "idle"
const ANIM_WALK := "walk"
const ANIM_RUN := "run"
const HUMANOID_SCENE := "res://assets/models/humanoid.glb"
