class_name GameConstants
extends RefCounted
## Single source of every tunable gameplay number. Do not hardcode these elsewhere.

# World generation
const WORLD_SEED := 1337
const SPAWN_SEED := -1 ## -1 = random spawn every run.
const WORLDGEN_VERSION := 1 ## Bump whenever terrain or prop generation changes (invalidates saved removals).

# Chunks (meters)
const CHUNK_SIZE := 32.0
const CHUNK_CELLS := 16 ## Terrain quads per chunk side.
const MAP_CHUNKS := 24 ## Playable map is MAP_CHUNKS x MAP_CHUNKS.
const BORDER_CHUNKS := 1 ## Visual-only ring around the playable map.
const LOAD_RADIUS := 2 ## Chunks kept loaded around the player (square radius).
const CHUNKS_APPLIED_PER_FRAME := 2

# Terrain
const TERRAIN_HEIGHT := 10.0
const TERRAIN_NOISE_FREQ := 0.02

# Biomes
enum Biome { PLAINS, FOREST, ROCKY }
const BIOME_NAMES := { Biome.PLAINS: "Planície", Biome.FOREST: "Floresta", Biome.ROCKY: "Pedregoso" }
const BIOME_NOISE_FREQ := 0.006
const BIOME_FOREST_MIN := 0.2 ## Biome value above this is forest.
const BIOME_ROCKY_MAX := -0.3 ## Biome value below this is rocky.
const ROCKY_HEIGHT_BOOST := 1.2 ## Extra height multiplier fully inside rocky land.

# Props and resources
enum Prop { OAK, PINE, ROCK, BUSH }
enum Res { WOOD, STONE, BERRIES }
const PROP_CELL := 4.0 ## Scatter grid cell (m); at most one prop per cell.
const PROP_MAX_SLOPE_DEG := 30.0
const PROP_SINK := 0.05 ## Props are sunk this much (x scale) so they never float.
const PROP_SCALE_MIN := 0.8
const PROP_SCALE_MAX := 1.25
## Probability per cell of each prop type, by biome.
const PROP_DENSITY := {
	Biome.PLAINS: { Prop.OAK: 0.05, Prop.PINE: 0.0, Prop.ROCK: 0.03, Prop.BUSH: 0.08 },
	Biome.FOREST: { Prop.OAK: 0.25, Prop.PINE: 0.30, Prop.ROCK: 0.03, Prop.BUSH: 0.10 },
	Biome.ROCKY: { Prop.OAK: 0.0, Prop.PINE: 0.06, Prop.ROCK: 0.25, Prop.BUSH: 0.03 },
}
## Collision radius at scale 1 (0 = walk-through).
const PROP_COLLISION_RADIUS := { Prop.OAK: 0.4, Prop.PINE: 0.35, Prop.ROCK: 0.9, Prop.BUSH: 0.0 }
const PROP_COLLISION_HEIGHT := 3.0

# Player
const WALK_SPEED := 4.0
const RUN_SPEED := 7.5
const TURN_SPEED := 10.0
const GRAVITY := 20.0

# Camera
const CAM_YAW_DEG := 45.0
const CAM_PITCH_DEG := -30.0
const CAM_ORTHO_SIZE := 12.0
const CAM_DISTANCE := 40.0
const CAM_FOLLOW_SMOOTH := 6.0

# Spawn
const SPAWN_EDGE_MARGIN := 24.0
const SPAWN_MAX_SLOPE_DEG := 20.0
const SPAWN_MAX_TRIES := 64
const SPAWN_PROP_CLEARANCE := 2.0 ## Free space between spawn and any solid prop's edge.

# Day / night
const DAY_LENGTH_SEC := 480.0 ## One full day-night cycle.
const START_TIME_OF_DAY := 0.30 ## 0 = midnight, 0.5 = noon.

# Save
const SAVE_PATH := "user://save.bin"
const AUTOSAVE_SEC := 60.0

# Performance budget
const MAX_FRAME_MS := 50.0

# Models and animations
const ANIM_IDLE := "idle"
const ANIM_WALK := "walk"
const ANIM_RUN := "run"
const ANIM_WORK := "work"
const HUMANOID_SCENE := "res://assets/models/humanoid.glb"
const PROP_SCENES := {
	Prop.OAK: "res://assets/models/oak.glb",
	Prop.PINE: "res://assets/models/pine.glb",
	Prop.ROCK: "res://assets/models/rock.glb",
	Prop.BUSH: "res://assets/models/bush.glb",
}
