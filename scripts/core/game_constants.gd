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

# Harvesting
const HARVEST_RANGE := 2.2 ## Max gap (m) between player and a prop's collision edge.
const HARVEST_HIT_TIME := 0.45 ## One swing; input and movement are locked meanwhile.
const HARVEST_HITS := { Prop.OAK: 4, Prop.PINE: 4, Prop.ROCK: 5, Prop.BUSH: 1 }
const HARVEST_YIELD := {
	Prop.OAK: [Res.WOOD, 3],
	Prop.PINE: [Res.WOOD, 3],
	Prop.ROCK: [Res.STONE, 2],
	Prop.BUSH: [Res.BERRIES, 2],
}
const HARVEST_PROMPTS := {
	Prop.OAK: "[E] Cortar árvore",
	Prop.PINE: "[E] Cortar árvore",
	Prop.ROCK: "[E] Quebrar rocha",
	Prop.BUSH: "[E] Colher frutas",
}
const RES_NAMES := { Res.WOOD: "Madeira", Res.STONE: "Pedra", Res.BERRIES: "Frutas" }

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

# Buildings
enum Building { CABIN, CAMPFIRE, STORAGE, FENCE, WELL, FLAG }
## What the player can choose in build mode (keys 1-5, in this order). FLAG is placed automatically.
const BUILDABLE := [Building.CABIN, Building.CAMPFIRE, Building.STORAGE, Building.FENCE, Building.WELL]
const BUILD_NAMES := {
	Building.CABIN: "Cabana", Building.CAMPFIRE: "Fogueira", Building.STORAGE: "Depósito",
	Building.FENCE: "Cerca", Building.WELL: "Poço", Building.FLAG: "Bandeira",
}
const BUILD_COST := {
	Building.CABIN: { Res.WOOD: 30, Res.STONE: 10 },
	Building.CAMPFIRE: { Res.WOOD: 5, Res.STONE: 3 },
	Building.STORAGE: { Res.WOOD: 25, Res.STONE: 5 },
	Building.FENCE: { Res.WOOD: 4 },
	Building.WELL: { Res.WOOD: 5, Res.STONE: 20 },
	Building.FLAG: {},
}
## Footprint (x = local X, y = local Z) in meters at rotation 0.
const BUILD_FOOTPRINT := {
	Building.CABIN: Vector2(4.0, 5.0),
	Building.CAMPFIRE: Vector2(1.6, 1.6),
	Building.STORAGE: Vector2(4.0, 3.0),
	Building.FENCE: Vector2(3.0, 0.4),
	Building.WELL: Vector2(2.0, 2.0),
	Building.FLAG: Vector2(0.3, 0.3),
}
## Collision boxes per type at rotation 0: [center, size], local to the building origin.
const BUILD_COLLIDERS := {
	Building.CABIN: [[Vector3(0, 1.5, 0), Vector3(4.0, 3.0, 5.0)]],
	Building.CAMPFIRE: [[Vector3(0, 0.25, 0), Vector3(1.4, 0.5, 1.4)]],
	Building.STORAGE: [[Vector3(0, 1.4, 0), Vector3(4.0, 2.8, 3.0)]],
	Building.FENCE: [[Vector3(0, 0.6, 0), Vector3(3.0, 1.2, 0.2)]],
	Building.WELL: [[Vector3(0, 0.5, 0), Vector3(1.8, 1.0, 1.8)]],
	Building.FLAG: [[Vector3(0, 2.0, 0), Vector3(0.2, 4.0, 0.2)]],
}
const BUILD_SCENES := {
	Building.CABIN: "res://assets/models/cabin.glb",
	Building.CAMPFIRE: "res://assets/models/campfire.glb",
	Building.STORAGE: "res://assets/models/storage.glb",
	Building.FENCE: "res://assets/models/fence.glb",
	Building.WELL: "res://assets/models/well.glb",
	Building.FLAG: "res://assets/models/flag.glb",
}
const BUILD_REFUND := 0.5 ## Share of the cost returned on demolish (rounded down).
const BUILD_MAX_HEIGHT_DIFF := 1.2 ## Max ground height difference under a footprint.
const BUILD_SAMPLE_STEP := 0.5 ## Ground sampling step under a footprint.
const BUILD_GRID := 0.5 ## Placement snap on X/Z.
const BUILD_TOUCH_TOLERANCE := 0.1 ## Footprints may share edges up to this overlap per side.
const BUILD_BUSH_CLEAR_RADIUS := 0.5 ## Bushes this close to a footprint are cleared on build.
const BUILD_MSG_OUTSIDE := "Fora do mapa"
const BUILD_MSG_SLOPE := "Terreno muito inclinado"
const BUILD_MSG_PROP := "Há uma árvore ou rocha no caminho"
const BUILD_MSG_OCCUPIED := "Ocupado por outra construção"
const BUILD_MSG_MISSING := "Falta %s (%d/%d)" ## resource name in lower case, have, need
const BUILD_MSG_SEAT := "A sede do reino não pode ser demolida"
const BUILD_GHOST_DISTANCE := 3.0 ## Ghost distance in front of the player when the mouse is not used.
const BUILD_DEMOLISH_RANGE := 3.0 ## Max distance from the player to a building's footprint edge.
const BUILD_RAY_LENGTH := 500.0
const FLAG_OFFSET := Vector3(1.6, 0.0, 2.3) ## Flag position in the seat cabin's local frame (front corner).
const GHOST_OK_COLOR := Color(0.35, 0.95, 0.45, 0.45)
const GHOST_BAD_COLOR := Color(0.95, 0.30, 0.25, 0.45)
const KINGDOM_COLOR_SAT := 0.65
const KINGDOM_COLOR_VAL := 0.75

const FOUNDATION_DEPTH := 2.0 ## Stone base below a building's floor, hides gaps on slopes.
const FOUNDATION_STONE := Color(0.46, 0.45, 0.43)
const FOUNDATION_WOOD := Color(0.36, 0.25, 0.15) ## Fences get a thin wooden skirt instead.
const CAMPFIRE_LIGHT_ENERGY := 2.0
const CAMPFIRE_LIGHT_RANGE := 9.0
const CAMPFIRE_LIGHT_COLOR := Color(1.0, 0.62, 0.30)

# Physics layers (bit values)
const LAYER_TERRAIN := 1
const LAYER_OBSTACLES := 2 ## Trees, rocks and buildings.

# Kingdoms
const KINGDOM_RADIUS := 40.0

# Day / night
const DAY_LENGTH_SEC := 480.0 ## One full day-night cycle.
const START_TIME_OF_DAY := 0.30 ## 0 = midnight, 0.5 = noon.
const NIGHT_MIN_AMBIENT := 0.55 ## Ambient energy floor so the player stays visible at night.
const MOON_ENERGY := 0.35
const MOON_COLOR := Color(0.62, 0.72, 1.0)
const DAY_AMBIENT := 0.65
const SUN_MAX_ENERGY := 1.1
const SUN_YAW_DEG := -35.0
const SUN_DAY_COLOR := Color(1.0, 0.97, 0.90)
const SUN_DUSK_COLOR := Color(1.0, 0.62, 0.38)
const SKY_DAY_TOP := Color(0.38, 0.55, 0.78)
const SKY_DAY_HORIZON := Color(0.72, 0.78, 0.82)
const SKY_DUSK_HORIZON := Color(0.95, 0.60, 0.42)
const SKY_NIGHT_TOP := Color(0.03, 0.05, 0.12)
const SKY_NIGHT_HORIZON := Color(0.10, 0.13, 0.24)
const AMBIENT_DAY_COLOR := Color(0.70, 0.74, 0.80)
const AMBIENT_NIGHT_COLOR := Color(0.40, 0.48, 0.72)

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
