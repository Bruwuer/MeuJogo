class_name GameConstants
extends RefCounted
## Single source of every tunable gameplay number. Do not hardcode these elsewhere.

# World generation
const WORLD_SEED := 1337
const SPAWN_SEED := -1 ## -1 = random spawn every run.
const WORLDGEN_VERSION := 2 ## Bump whenever terrain or prop generation changes (invalidates saved removals).

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
const PLAINS_RELIEF := 0.25 ## Hill amplitude in plains (1 = full TERRAIN_HEIGHT); flat enough to build.
const FOREST_RELIEF := 0.7

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
const BUILD_MSG_PLAYER := "Você está no caminho"
const BUILD_PLAYER_RADIUS := 0.4 ## Capsule radius plus margin kept free of new footprints.
## Space a footprint must keep from each prop (crowns are wider than trunks), at scale 1.
const BUILD_PROP_CLEARANCE := { Prop.OAK: 1.3, Prop.PINE: 1.4, Prop.ROCK: 0.9, Prop.BUSH: 0.0 }
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
const FOUNDING_TOAST_SEC := 5.0

# Creatures: body parts, diets and species (genome templates)
enum Body { CANINE, BULKY, LIZARD, DEER }
enum Head { WOLF, BEAR, BOAR, DEER, LIZARD, HORNED }
enum Legs { THIN, THICK, CLAWED }
enum Tail { BUSHY, STUB, LONG, SPIKED, NONE }
enum Extra { NONE, ANTLERS, HORNS, SPIKES, MANE }
enum Diet { HERBIVORE, CARNIVORE }
const MUTATION_CHANCE := 0.05 ## Per gene, when two creatures have a cub.
const MUTATION_SPREAD := 0.15 ## Numeric genes mutate by up to +-15 %.
const HYBRID_COMPATIBILITY := 0.3 ## Chance factor for close species to breed.
## Blender parts (tools/blender/creature_parts.py); names are <slot>_<enum name in lower case>.
const CREATURE_PART_PATH := "res://assets/models/parts/%s.glb"
const CREATURE_PARTS := [
	"body_canine", "body_bulky", "body_lizard", "body_deer",
	"head_wolf", "head_bear", "head_boar", "head_deer", "head_lizard", "head_horned",
	"leg_thin", "leg_thick", "leg_clawed",
	"tail_bushy", "tail_stub", "tail_long", "tail_spiked",
	"extra_antlers", "extra_horns", "extra_spikes", "extra_mane",
]
## Attachment points per body at size 1 (Godot axes: front +Z, up +Y), relative to the torso center.
## Legs hang from their hip socket; leg_length is the hip height above the ground.
const BODY_SOCKETS := {
	Body.CANINE: { head = Vector3(0, 0.12, 0.55), tail = Vector3(0, 0.08, -0.5), extra = Vector3(0, 0.2, 0.3),
		legs = [Vector3(0.14, -0.15, 0.35), Vector3(-0.14, -0.15, 0.35), Vector3(0.14, -0.15, -0.35), Vector3(-0.14, -0.15, -0.35)],
		leg_length = 0.55 },
	Body.BULKY: { head = Vector3(0, 0.1, 0.65), tail = Vector3(0, 0.15, -0.6), extra = Vector3(0, 0.33, 0.35),
		legs = [Vector3(0.24, -0.28, 0.4), Vector3(-0.24, -0.28, 0.4), Vector3(0.24, -0.28, -0.4), Vector3(-0.24, -0.28, -0.4)],
		leg_length = 0.5 },
	Body.LIZARD: { head = Vector3(0, 0.02, 0.72), tail = Vector3(0, 0.0, -0.7), extra = Vector3(0, 0.15, 0.0),
		legs = [Vector3(0.3, -0.1, 0.45), Vector3(-0.3, -0.1, 0.45), Vector3(0.3, -0.1, -0.45), Vector3(-0.3, -0.1, -0.45)],
		leg_length = 0.3 },
	Body.DEER: { head = Vector3(0, 0.22, 0.5), tail = Vector3(0, 0.12, -0.48), extra = Vector3(0, 0.2, 0.3),
		legs = [Vector3(0.12, -0.17, 0.33), Vector3(-0.12, -0.17, 0.33), Vector3(0.12, -0.17, -0.33), Vector3(-0.12, -0.17, -0.33)],
		leg_length = 0.8 },
}
## Extras that sit on top of the head instead of on the body socket, and where (head space).
const EXTRA_ON_HEAD := [Extra.ANTLERS, Extra.HORNS]
const HEAD_TOP := Vector3(0, 0.18, 0.12)
## Ranges are Vector2(min, max) (Vector2i for pack size). Biome weights drive spawning.
const SPECIES := {
	"lobo": { name = "Lobo", invented = false, body = Body.CANINE, head = Head.WOLF, legs = Legs.THIN,
		tail = Tail.BUSHY, extra = Extra.NONE, size = Vector2(0.9, 1.15),
		color_a = Color(0.45, 0.43, 0.40), color_b = Color(0.78, 0.75, 0.70), color_jitter = 0.08,
		diet = Diet.CARNIVORE, aggression = Vector2(0.5, 0.75), pack = Vector2i(3, 5), speed = Vector2(5.5, 7.0),
		hp = Vector2(40, 55), damage = Vector2(8, 12), perception = 22.0, nocturnal = false, territorial = true,
		biomes = { Biome.FOREST: 0.5, Biome.PLAINS: 0.35, Biome.ROCKY: 0.15 } },
	"urso": { name = "Urso", invented = false, body = Body.BULKY, head = Head.BEAR, legs = Legs.THICK,
		tail = Tail.STUB, extra = Extra.NONE, size = Vector2(1.1, 1.4),
		color_a = Color(0.36, 0.24, 0.15), color_b = Color(0.25, 0.17, 0.11), color_jitter = 0.06,
		diet = Diet.CARNIVORE, aggression = Vector2(0.4, 0.7), pack = Vector2i(1, 1), speed = Vector2(4.5, 5.5),
		hp = Vector2(120, 160), damage = Vector2(18, 26), perception = 18.0, nocturnal = false, territorial = true,
		biomes = { Biome.FOREST: 0.5, Biome.ROCKY: 0.4 } },
	"javali": { name = "Javali", invented = false, body = Body.BULKY, head = Head.BOAR, legs = Legs.THIN,
		tail = Tail.STUB, extra = Extra.NONE, size = Vector2(0.6, 0.8),
		color_a = Color(0.30, 0.24, 0.20), color_b = Color(0.45, 0.38, 0.30), color_jitter = 0.06,
		diet = Diet.HERBIVORE, aggression = Vector2(0.5, 0.8), pack = Vector2i(2, 4), speed = Vector2(5.0, 6.0),
		hp = Vector2(45, 60), damage = Vector2(8, 12), perception = 16.0, nocturnal = false, territorial = true,
		biomes = { Biome.FOREST: 0.6, Biome.PLAINS: 0.3 } },
	"cervo": { name = "Cervo", invented = false, body = Body.DEER, head = Head.DEER, legs = Legs.THIN,
		tail = Tail.STUB, extra = Extra.ANTLERS, size = Vector2(0.9, 1.1),
		color_a = Color(0.62, 0.45, 0.30), color_b = Color(0.85, 0.78, 0.65), color_jitter = 0.07,
		diet = Diet.HERBIVORE, aggression = Vector2(0.0, 0.1), pack = Vector2i(3, 6), speed = Vector2(6.5, 8.0),
		hp = Vector2(30, 40), damage = Vector2(3, 5), perception = 24.0, nocturnal = false, territorial = false,
		biomes = { Biome.PLAINS: 0.5, Biome.FOREST: 0.4 } },
	"espinhudo": { name = "Espinhudo", invented = true, body = Body.LIZARD, head = Head.LIZARD, legs = Legs.CLAWED,
		tail = Tail.SPIKED, extra = Extra.SPIKES, size = Vector2(0.9, 1.3),
		color_a = Color(0.35, 0.45, 0.30), color_b = Color(0.70, 0.62, 0.30), color_jitter = 0.08,
		diet = Diet.CARNIVORE, aggression = Vector2(0.6, 0.9), pack = Vector2i(1, 2), speed = Vector2(4.0, 5.0),
		hp = Vector2(80, 110), damage = Vector2(12, 18), perception = 15.0, nocturnal = false, territorial = true,
		biomes = { Biome.ROCKY: 0.7, Biome.PLAINS: 0.1 } },
	"chifrudo": { name = "Chifrudo", invented = true, body = Body.BULKY, head = Head.HORNED, legs = Legs.THICK,
		tail = Tail.LONG, extra = Extra.HORNS, size = Vector2(1.3, 1.7),
		color_a = Color(0.50, 0.42, 0.36), color_b = Color(0.82, 0.78, 0.70), color_jitter = 0.06,
		diet = Diet.HERBIVORE, aggression = Vector2(0.3, 0.6), pack = Vector2i(2, 4), speed = Vector2(4.5, 5.5),
		hp = Vector2(140, 190), damage = Vector2(16, 24), perception = 18.0, nocturnal = false, territorial = true,
		biomes = { Biome.PLAINS: 0.4, Biome.ROCKY: 0.3 } },
	"rastejante": { name = "Rastejante", invented = true, body = Body.LIZARD, head = Head.LIZARD, legs = Legs.CLAWED,
		tail = Tail.LONG, extra = Extra.NONE, size = Vector2(1.0, 1.4),
		color_a = Color(0.20, 0.28, 0.22), color_b = Color(0.50, 0.60, 0.35), color_jitter = 0.06,
		diet = Diet.CARNIVORE, aggression = Vector2(0.5, 0.8), pack = Vector2i(1, 3), speed = Vector2(5.0, 6.5),
		hp = Vector2(50, 70), damage = Vector2(10, 15), perception = 20.0, nocturnal = true, territorial = false,
		biomes = { Biome.FOREST: 0.4, Biome.ROCKY: 0.3 } },
	"uivante": { name = "Uivante", invented = true, body = Body.CANINE, head = Head.WOLF, legs = Legs.THIN,
		tail = Tail.BUSHY, extra = Extra.MANE, size = Vector2(1.0, 1.25),
		color_a = Color(0.85, 0.85, 0.88), color_b = Color(0.55, 0.58, 0.65), color_jitter = 0.05,
		diet = Diet.CARNIVORE, aggression = Vector2(0.6, 0.85), pack = Vector2i(4, 6), speed = Vector2(6.0, 7.5),
		hp = Vector2(50, 65), damage = Vector2(10, 14), perception = 26.0, nocturnal = true, territorial = true,
		biomes = { Biome.ROCKY: 0.3, Biome.FOREST: 0.3 } },
}

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
