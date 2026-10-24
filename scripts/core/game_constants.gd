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
enum Res { WOOD, STONE, BERRIES, ARROWS, FOOD } ## New values only at the end (saves store ints).
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
const RES_NAMES := { Res.WOOD: "Madeira", Res.STONE: "Pedra", Res.BERRIES: "Frutas", Res.ARROWS: "Flechas", Res.FOOD: "Comida" }

# Player
const WALK_SPEED := 4.0
const RUN_SPEED := 7.5
const TURN_SPEED := 10.0
const GRAVITY := 20.0

# Player combat (keyboard only: Space attacks where the character faces)
const PLAYER_HP := 100.0
const PLAYER_REGEN_DELAY := 6.0 ## Seconds without damage before health regenerates.
const PLAYER_REGEN_PER_SEC := 2.0
const EAT_HEAL := 15.0
const EAT_COST := { Res.BERRIES: 1 }
const ARROW_CRAFT_COST := { Res.WOOD: 1 }
const ARROWS_PER_CRAFT := 5
enum Weapon { SWORD, SPEAR, BOW }
## range: reach (m) from the player to a target's body edge; arc: full melee angle (degrees).
const WEAPONS := {
	Weapon.SWORD: { name = "Espada", damage = 22.0, range = 1.8, arc = 110.0, cooldown = 0.55,
		hit_time = 0.29, clip = "attack_sword", scene = "res://assets/models/sword.glb", knockback = 3.0 },
	Weapon.SPEAR: { name = "Lança", damage = 30.0, range = 3.2, arc = 40.0, cooldown = 0.85,
		hit_time = 0.33, clip = "attack_spear", scene = "res://assets/models/spear.glb", knockback = 4.5 },
	Weapon.BOW: { name = "Arco", damage = 25.0, range = 0.0, arc = 0.0, cooldown = 0.9,
		hit_time = 0.5, clip = "shoot_bow", scene = "res://assets/models/bow.glb", knockback = 1.5 },
}
const ARROW_SCENE := "res://assets/models/arrow.glb"
const ARROW_SPEED := 26.0
const ARROW_GRAVITY := 9.8
const ARROW_SPAWN_HEIGHT := 1.35 ## Above the player's feet.
const ARROW_LIFETIME := 5.0
const ARROW_STICK_SEC := 4.0 ## A stuck arrow stays this long.
const KNOCKBACK_DECAY := 8.0 ## Per second.
const RESPAWN_GRACE_SEC := 5.0 ## No damage right after waking up.
const KILL_GRUDGE_KEEP := 0.3 ## Share of grudge a pack keeps after killing the player.
const RESPAWN_MSG_SEAT := "Você caiu e despertou na sede do reino"
const RESPAWN_MSG_SPAWN := "Você caiu e despertou onde tudo começou"
const NO_ARROWS_MSG := "Sem flechas · F faz 5 com 1 madeira"
const KILL_MSG := "Você abateu: %s"

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
enum Building { CABIN, CAMPFIRE, STORAGE, FENCE, WELL, FLAG, HOUSE, FARM, MARKET, STAKE } ## New values only at the end.
## What the player can choose in build mode (keys 1-5, in this order). FLAG is placed automatically.
const BUILDABLE := [Building.CABIN, Building.CAMPFIRE, Building.STORAGE, Building.FENCE, Building.WELL]
const BUILD_NAMES := {
	Building.CABIN: "Cabana", Building.CAMPFIRE: "Fogueira", Building.STORAGE: "Depósito",
	Building.FENCE: "Cerca", Building.WELL: "Poço", Building.FLAG: "Bandeira",
	Building.HOUSE: "Casa", Building.FARM: "Fazenda", Building.MARKET: "Comércio", Building.STAKE: "Estaca",
}
const BUILD_COST := {
	Building.CABIN: { Res.WOOD: 30, Res.STONE: 10 },
	Building.CAMPFIRE: { Res.WOOD: 5, Res.STONE: 3 },
	Building.STORAGE: { Res.WOOD: 25, Res.STONE: 5 },
	Building.FENCE: { Res.WOOD: 4 },
	Building.WELL: { Res.WOOD: 5, Res.STONE: 20 },
	Building.FLAG: {},
	Building.HOUSE: { Res.WOOD: 40, Res.STONE: 10 },
	Building.FARM: { Res.WOOD: 12 },
	Building.MARKET: { Res.WOOD: 25, Res.STONE: 8 },
	Building.STAKE: {},
}
## Footprint (x = local X, y = local Z) in meters at rotation 0.
const BUILD_FOOTPRINT := {
	Building.CABIN: Vector2(4.0, 5.0),
	Building.CAMPFIRE: Vector2(1.6, 1.6),
	Building.STORAGE: Vector2(4.0, 3.0),
	Building.FENCE: Vector2(3.0, 0.4),
	Building.WELL: Vector2(2.0, 2.0),
	Building.FLAG: Vector2(0.3, 0.3),
	Building.HOUSE: Vector2(4.5, 5.5),
	Building.FARM: Vector2(6.0, 6.0),
	Building.MARKET: Vector2(4.0, 3.0),
	Building.STAKE: Vector2(0.25, 0.25),
}
## Collision boxes per type at rotation 0: [center, size], local to the building origin.
const BUILD_COLLIDERS := {
	Building.CABIN: [[Vector3(0, 1.5, 0), Vector3(4.0, 3.0, 5.0)]],
	Building.CAMPFIRE: [[Vector3(0, 0.25, 0), Vector3(1.4, 0.5, 1.4)]],
	Building.STORAGE: [[Vector3(0, 1.4, 0), Vector3(4.0, 2.8, 3.0)]],
	Building.FENCE: [[Vector3(0, 0.6, 0), Vector3(3.0, 1.2, 0.2)]],
	Building.WELL: [[Vector3(0, 0.5, 0), Vector3(1.8, 1.0, 1.8)]],
	Building.FLAG: [[Vector3(0, 2.0, 0), Vector3(0.2, 4.0, 0.2)]],
	Building.HOUSE: [[Vector3(0, 1.6, 0), Vector3(4.5, 3.2, 5.5)]],
	Building.FARM: [], # walkable field
	Building.MARKET: [[Vector3(0, 1.2, 0), Vector3(4.0, 2.4, 3.0)]],
	Building.STAKE: [],
}
const BUILD_SCENES := {
	Building.CABIN: "res://assets/models/cabin.glb",
	Building.CAMPFIRE: "res://assets/models/campfire.glb",
	Building.STORAGE: "res://assets/models/storage.glb",
	Building.FENCE: "res://assets/models/fence.glb",
	Building.WELL: "res://assets/models/well.glb",
	Building.FLAG: "res://assets/models/flag.glb",
	Building.HOUSE: "res://assets/models/house.glb",
	Building.FARM: "res://assets/models/farm.glb",
	Building.MARKET: "res://assets/models/market.glb",
	Building.STAKE: "res://assets/models/stake.glb",
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
const BUILD_MSG_PLAYER := "Há alguém no caminho" ## The player or a villager.
const BUILD_MSG_VILLAGE := "Foi erguido pelos moradores: não pode ser demolido"
const BUILD_MSG_NOT_YOURS := "É de %s: não pode ser demolido"
const BUILD_MSG_SITE := "É uma obra dos moradores: não pode ser demolida"
## Building owners: the player (and its kingdom seat), the villagers as a whole, or a person id (>= 0).
const OWNER_PLAYER := -1
const OWNER_KINGDOM := -2
## Buildings that get no stone foundation nor collision (fields).
const BUILD_FLAT := [Building.FARM, Building.STAKE]
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
const LAYER_CREATURES := 4
const LAYER_PEOPLE := 8 ## Villagers: collide with terrain and obstacles only.

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

# Creature behaviour
const CREATURE_MAX_ACTIVE := 40 ## Creature nodes alive at once (only in loaded chunks).
const CREATURES_SPAWNED_PER_FRAME := 2 ## Creature nodes created per frame at most.
const BRAIN_TICK := 0.2 ## Seconds between brain decisions.
const HUNT_HUNGER := 0.5 ## Carnivores hunt prey above this hunger.
const FLEE_HP_RATIO := 0.25 ## Below this share of health any creature flees.
const FLEE_DISTANCE := 15.0 ## How far ahead of a threat a fleeing creature aims.
const THREAT_SHARE := 0.6 ## Herbivores react to carnivores within this share of perception.
const WAKE_SHARE := 0.25 ## Sleepers only notice threats within this share of perception.
const TERRITORY_FIGHT_AGGRESSION := 0.75 ## Territorial carnivores this aggressive fight other carnivores.
const TERRITORY_FIGHT_SHARE := 0.4 ## ... within this share of perception.
const PLAYER_DEFENSE_AGGRESSION := 0.5 ## Herbivores at least this aggressive charge a close player.
const PLAYER_DEFENSE_SHARE := 0.25
const FOLLOW_DISTANCE := 8.0 ## Pack members rejoin the leader beyond this distance.
const WANDER_RADIUS := 12.0 ## Wander targets are picked this far around the den.
const GRAZE_HUNGER := 0.4 ## Herbivores graze above this hunger (eating slowly lowers it).
const GRAZE_RATE := 0.05 ## Hunger lost per second while grazing.
const CREATURE_HUNGER_PER_SEC := 1.0 / 240.0 ## Hunger gained per second (half a day to get hungry).
const CREATURE_ATTACK_RANGE := 1.4 ## Bite reach (m) at size 1, from torso center to target.
const CREATURE_ATTACK_COOLDOWN := 1.2
const CREATURE_WANDER_SPEED := 0.35 ## Share of top speed while wandering, grazing or following.
const CREATURE_ARRIVE := 0.8 ## Distance at which a target point counts as reached.
const STAMINA_DRAIN := { Diet.HERBIVORE: 1.0 / 5.0, Diet.CARNIVORE: 1.0 / 14.0 } ## Per second sprinting.
const STAMINA_REGEN := 1.0 / 8.0
const EXHAUSTED_SPEED := 0.5 ## Share of top speed with no stamina left.
const AVOID_RAY := 2.2 ## Obstacle look-ahead (m) at size 1.
const AVOID_TURN_DEG := 70.0
const CUB_SIZE := 0.45 ## Size of a newborn relative to an adult.
const CORPSE_SEC := 3.0 ## Dead creatures lie down this long before disappearing.

# Packs and their motives (all 0..1; rates per in-game hour)
const TERRITORY_RADIUS := 45.0 ## Around a pack's den.
const PREY_RADIUS := 70.0 ## Herbivores this close to the den count as the pack's prey.
const PREY_ENOUGH := 5 ## With this many prey around the pack feeds itself fully.
const UNVISITED_CHUNK_PREY := 1 ## Prey assumed in each not-yet-visited chunk near a den.
const PACK_KILL_FEED := 0.5 ## Pack hunger lost when a member kills prey.
const HUNGER_RATE := 0.05
const PACK_FEED_RATE := 0.08 ## Hunger lost per hour with PREY_ENOUGH prey around.
const TERRITORY_PER_BUILDING := 0.25 ## Territory motive per building inside the den radius.
const GRUDGE_PER_KILL := 0.3
const GRUDGE_PER_CUB := 0.6
const GRUDGE_PER_HURT := 0.03
const GRUDGE_DECAY_PER_DAY := 0.5
const CUB_ALARM_RADIUS := 20.0 ## Player this close to a den with cubs sets off the alarm.
const CUBS_ALARM_DECAY := 0.5 ## Per hour.
const MOTIVE_WEIGHTS := { hunger = 0.9, territory = 0.9, grudge = 1.0, cubs = 1.0 }
const RAID_THRESHOLD := 0.6 ## Weighted motive x (0.5 + aggression) needed to raid.
const RAID_RANGE := 130.0 ## Packs only raid kingdoms this close to their den.
const RAID_COOLDOWN_HOURS := 24.0
const RAID_SATED_HUNGER := 0.35 ## Hunger lost after a raid (they raid food stores).
const RAID_GRUDGE_KEEP := 0.5 ## Share of grudge left after a raid.
const OFFSCREEN_RAID_HITS := 8.0 ## Bites per raider when a raid on an unloaded kingdom is summarized.
## Text shown when a pack raids: (species plural in lower case, kingdom name).
const RAID_MESSAGES := {
	hunger = "Os %s famintos rondam o Reino de %s: a caça acabou na região",
	territory = "Os %s defendem seu território: o Reino de %s foi erguido perto da toca",
	grudge = "Os %s querem vingança contra o Reino de %s pelos seus mortos",
	cubs = "Os %s furiosos protegem os filhotes perto do Reino de %s",
}
const OFFSCREEN_RAID_MSG := "Enquanto você estava fora, os %s destruíram %s no Reino de %s"
const OFFSCREEN_RAID_NOTHING_MSG := "Enquanto você estava fora, os %s atacaram o Reino de %s, mas nada caiu"
## Creature population and breeding.
const CREATURE_PACK_CHANCE := 0.3 ## Chance that a chunk starts with a pack on its first visit.
const CREATURE_SPAWN_SPREAD := 4.0 ## Pack members start this far around the den.
const FIRST_WOLVES_DISTANCE := Vector2(60.0, 120.0) ## New worlds: a wolf pack this far from the spawn.
const POPULATION_CAP_PER_CHUNK := 4 ## No breeding when the 3x3 chunks around hold this many per chunk.
const BREED_CHECK_SEC := 3.0
const BREED_CHANCE := 0.25 ## Per check for a ready pair, times their compatibility.
const BREED_SEEK_RADIUS := 15.0 ## Ready adults this close walk toward each other.
const BREED_RADIUS := 2.5 ## ... and have a cub once this close.
const BREED_MAX_HUNGER := 0.5 ## Only fed creatures breed.
const BREED_COOLDOWN_HOURS := 48.0
const CUB_DAYS := 2.0 ## In-game days for a cub to grow up.
const CREATURE_SYNC_SEC := 0.25 ## How often live creatures write their position back to the records.
const HOSTILE_GRUDGE := 0.5 ## Pack grudge above this makes members attack the player on sight.
const HOSTILE_CUBS := 0.5
const HOSTILE_HUNGER := 0.9 ## Starving carnivores risk attacking people.
const RAID_SATISFY_DAMAGE := 150.0 ## A live raid ends after the pack dealt this much damage (or razed one building).
const BUILD_DESTROYED_MSG := {
	Building.CABIN: "Uma Cabana foi destruída pelos %s", Building.CAMPFIRE: "Uma Fogueira foi destruída pelos %s",
	Building.STORAGE: "Um Depósito foi destruído pelos %s", Building.FENCE: "Uma Cerca foi destruída pelos %s",
	Building.WELL: "Um Poço foi destruído pelos %s", Building.FLAG: "A Bandeira foi destruída pelos %s",
	Building.HOUSE: "Uma Casa foi destruída pelos %s", Building.FARM: "Uma Fazenda foi destruída pelos %s",
	Building.MARKET: "Um Comércio foi destruído pelos %s",
	Building.STAKE: "Uma Estaca foi derrubada pelos %s",
}
## Building hit points; the seat cabin never drops below 1.
const BUILD_HP := {
	Building.CABIN: 300.0, Building.CAMPFIRE: 60.0, Building.STORAGE: 250.0,
	Building.FENCE: 80.0, Building.WELL: 200.0, Building.FLAG: 50.0,
	Building.HOUSE: 300.0, Building.FARM: 60.0, Building.MARKET: 200.0, Building.STAKE: 20.0,
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

# People: generator (names, traits, professions, looks)
enum Trait { WORKER, LAZY, BRAVE, FEARFUL, GENEROUS, GREEDY, SOCIABLE, LONER, DEVOUT, SKEPTIC }
## Opposite traits; a person gets two traits from two different pairs.
const TRAIT_PAIRS := [
	[Trait.WORKER, Trait.LAZY], [Trait.BRAVE, Trait.FEARFUL], [Trait.GENEROUS, Trait.GREEDY],
	[Trait.SOCIABLE, Trait.LONER], [Trait.DEVOUT, Trait.SKEPTIC],
]
## [male form, female form], in lower case (they go inside sentences).
const TRAIT_NAMES := {
	Trait.WORKER: ["trabalhador", "trabalhadora"], Trait.LAZY: ["preguiçoso", "preguiçosa"],
	Trait.BRAVE: ["corajoso", "corajosa"], Trait.FEARFUL: ["medroso", "medrosa"],
	Trait.GENEROUS: ["generoso", "generosa"], Trait.GREEDY: ["ganancioso", "gananciosa"],
	Trait.SOCIABLE: ["sociável", "sociável"], Trait.LONER: ["solitário", "solitária"],
	Trait.DEVOUT: ["devoto", "devota"], Trait.SKEPTIC: ["cético", "cética"],
}
## Initial opinion of the player pushed by each trait.
const TRAIT_OPINION := {
	Trait.WORKER: 0.0, Trait.LAZY: 0.0, Trait.BRAVE: 0.0, Trait.FEARFUL: 0.0,
	Trait.GENEROUS: 0.1, Trait.GREEDY: -0.1, Trait.SOCIABLE: 0.05, Trait.LONER: -0.05,
	Trait.DEVOUT: 0.1, Trait.SKEPTIC: -0.05,
}
const OPINION_JITTER := 0.2 ## Initial opinion spread (+-).
const FAME_OPINION_SHARE := 0.5 ## Share of the player's fame a newcomer already believes.
enum Profession { WOODCUTTER, MASON, FARMER, GATHERER, BUILDER, MERCHANT, GUARD }
## Trades a traveler can arrive with (guards come only from warrior Houses and vocations).
const TRAVELER_PROFESSIONS := [Profession.WOODCUTTER, Profession.MASON, Profession.FARMER, Profession.GATHERER,
		Profession.BUILDER, Profession.MERCHANT]
const PROFESSION_NAMES := {
	Profession.WOODCUTTER: ["lenhador", "lenhadora"], Profession.MASON: ["pedreiro", "pedreira"],
	Profession.FARMER: ["agricultor", "agricultora"], Profession.GATHERER: ["coletor", "coletora"],
	Profession.BUILDER: ["construtor", "construtora"], Profession.MERCHANT: ["comerciante", "comerciante"],
	Profession.GUARD: ["guarda", "guarda"],
}
const MALE_NAMES := [
	"Afonso", "Álvaro", "Bento", "Bartolomeu", "Martim", "Gonçalo", "Vasco", "Rodrigo", "Nuno", "Fernão",
	"Lourenço", "Estêvão", "Diogo", "Sancho", "Garcia", "Mendo", "Pero", "Gil", "Tomé", "Simão",
	"João", "Mateus", "Henrique", "Duarte", "Rui",
]
const FEMALE_NAMES := [
	"Ana", "Beatriz", "Leonor", "Inês", "Constança", "Teresa", "Urraca", "Mécia", "Catarina", "Isabel",
	"Margarida", "Brites", "Guiomar", "Violante", "Joana", "Maria", "Clara", "Filipa", "Aldonça", "Sancha",
	"Branca", "Marta", "Helena", "Luzia", "Carla",
]
const SURNAMES := [
	"Ferreira", "Moleiro", "Carpinteiro", "Pastor", "Pescador", "Tecelão", "Oleiro", "Ferrador",
	"do Vale", "da Serra", "do Rio", "da Ponte", "do Monte", "da Fonte", "do Souto", "da Lagoa",
	"Pinheiro", "Carvalho", "Silva", "Rocha", "Barros", "Couto", "Pereira", "Seixas",
]
const SKIN_COLORS := [
	Color(0.96, 0.80, 0.66), Color(0.90, 0.70, 0.55), Color(0.80, 0.60, 0.45), Color(0.66, 0.47, 0.33),
	Color(0.50, 0.34, 0.24), Color(0.38, 0.26, 0.18),
]
const HAIR_COLORS := [
	Color(0.10, 0.08, 0.06), Color(0.28, 0.18, 0.10), Color(0.45, 0.30, 0.16), Color(0.72, 0.55, 0.30),
	Color(0.60, 0.25, 0.10), Color(0.62, 0.60, 0.58),
]
const TUNIC_COLORS := [
	Color(0.55, 0.20, 0.16), Color(0.25, 0.38, 0.22), Color(0.22, 0.30, 0.50), Color(0.62, 0.52, 0.30),
	Color(0.45, 0.30, 0.45), Color(0.70, 0.66, 0.58), Color(0.35, 0.28, 0.20), Color(0.20, 0.45, 0.45),
]
const TROUSER_COLORS := [
	Color(0.32, 0.26, 0.20), Color(0.22, 0.22, 0.25), Color(0.40, 0.36, 0.28), Color(0.25, 0.30, 0.22),
]
const PERSON_HEIGHT := Vector2(0.92, 1.06) ## Model scale range.
const PERSON_AGE := Vector2i(16, 60)

# Kingdom stock and villagers' buildings
## A new kingdom starts with the founders' supplies (separate from the player's inventory).
const KINGDOM_START_STOCK := { Res.WOOD: 20, Res.BERRIES: 24 }
## Person-hours of work to finish a site of each type.
const BUILD_WORK_HOURS := {
	Building.CABIN: 8.0, Building.CAMPFIRE: 1.0, Building.STORAGE: 6.0, Building.FENCE: 1.0, Building.WELL: 5.0,
	Building.FLAG: 1.0, Building.HOUSE: 8.0, Building.FARM: 4.0, Building.MARKET: 6.0, Building.STAKE: 1.0,
}
## Beds per building type for villagers (the seat cabin is the player's).
const HOUSE_CAPACITY := { Building.HOUSE: 4, Building.CABIN: 2 } ## A house fits a couple and two children.
const SCAFFOLD_SCENE := "res://assets/models/scaffold.glb" ## Unit frame (1 x 1 x 3 m), scaled to each footprint.
const SITE_MIN_SCALE := 0.15 ## Height scale of a building model on a site with no progress.
const PERSON_START_CONTENTMENT := 0.6

# Village rules (1 game hour = DAY_LENGTH_SEC / 24 s)
const KINGDOM_FOUNDERS := 2 ## The first people to reach a kingdom always stay.
const KINGDOM_MAX_PEOPLE := 16 ## Children count too.
const KINGDOM_STOCK_TARGET := { Res.WOOD: 60, Res.STONE: 30 } ## Villagers gather only below these.
const BERRY_FOOD_DAYS := 3.0 ## Gatherers pick berries while food lasts less than this.
const FOOD_PER_DAY := 2 ## Meals a person eats a day (1 food or 1 berry each).
const HUNGER_PER_HOUR := 1.0 / 24.0 ## Hunger reaches 0.5 (a meal) twice a day.
const HUNGER_MEAL := 0.5 ## Eats at this hunger; a meal removes as much.
const FARM_FOOD_PER_DAY := 8.0 ## Planning estimate of one tended farm.
const RAID_RECENT_HOURS := 48.0
const FOOD_SAFE_DAYS := 2.0 ## Food for this many days counts as "food stored".
const PROJECT_FOOD_DAYS := 2.0 ## Below this the farm goes before the house.
const PROJECT_FARM_PER_PEOPLE := 3 ## Up to one farm per this many residents when food is short.
const PROJECT_MARKET_AT := 4
const PROJECT_WELL_AT := 3
## Stay decision weights (the traveler stays if the sum is > 0).
const STAY_HOUSE := 0.25
const STAY_CAMPFIRE := 0.05
const STAY_NO_SHELTER := -0.3
const STAY_FOOD := 0.25
const STAY_NO_FOOD := -0.35
const STAY_RAID := -0.25
const FEARFUL_RAID_MULT := 2.0
const BRAVE_RAID_MULT := 0.5
const STAY_JOB := 0.1
const STAY_WELL := 0.05
const STAY_SMALL := 0.2
const STAY_SMALL_BELOW := 3
const STAY_SOCIABLE_PER := 0.05
const STAY_SOCIABLE_FROM := 3
const STAY_SOCIABLE_MAX := 0.15
const STAY_LONER_PER := -0.05
const STAY_LONER_FROM := 6
const STAY_OPINION := 0.2
const STAY_NOISE := 0.1
## "Ana Ferreira decidiu ficar: <reason>".
const STAY_REASONS := {
	founder = "o reino é novo e precisa de gente", house = "há uma casa com vaga",
	campfire = "dá para dormir junto à fogueira", food = "há comida guardada", job = "há trabalho de %s",
	well = "há um poço", small = "o reino é pequeno e precisa de gente", sociable = "gosta de um reino animado",
	opinion = "gosta de você", kin = "tem parentes no reino", other = "gostou do lugar",
}
## "Bento do Vale seguiu viagem: <reason>".
const LEAVE_REASONS := {
	no_shelter = "não há onde morar", no_food = "não há comida", raid = "o reino foi atacado há pouco",
	loner = "há gente demais", opinion = "desconfia de você", other = "não gostou do lugar",
}
## "Carla deixou o Reino de X: <reason>".
const LEAVE_REASONS_PAST := {
	hunger = "passava fome", shelter = "não tinha onde morar", raid = "tinha medo dos ataques",
	other = "não estava feliz",
}
## Hourly contentment changes.
const CONTENT_HUNGRY := -0.04
const CONTENT_NO_SHELTER := -0.03
const CONTENT_CAMPFIRE_ONLY := -0.01
const CONTENT_RAID := -0.02
const CONTENT_FED := 0.02
const CONTENT_HOME := 0.01
const CONTENT_WELL := 0.005
const CONTENT_MARKET := 0.01
const LEAVE_CONTENTMENT := 0.25
const LEAVE_AFTER_HOURS := 24.0
## Site placement: a deterministic spiral around the kingdom center.
const SITE_CANDIDATES := 24 ## Places tested per planning hour.
const SITE_MIN_RADIUS := 9.0
const SITE_SPIRAL_STEP := 1.2 ## Radius gained per candidate.
const SITE_GAP := 1.5 ## Free corridor kept around a new site (to other buildings).

# Village simulation (hourly, every kingdom)
const TRAVELER_FIRST_HOURS := 1.0 ## First traveler after the founding.
const TRAVELER_INTERVAL_HOURS := 6.0
const TRAVELER_INTERVAL_MARKET := 4.0 ## With a Market.
const TRAVELER_DISTANCE := Vector2(60.0, 90.0) ## Spawn ring around the kingdom center.
const TRAVELER_NEEDED_SHARE := 0.5 ## Travelers that bring the trade the kingdom needs most.
const TRAVELER_MAP_MARGIN := 4.0
const WORK_START_HOUR := 7.0
const WORK_END_HOUR := 19.0
const SLEEP_START_HOUR := 21.0
const SLEEP_END_HOUR := 6.0
## Summarized output of one work hour of a person without a node.
const OFFSCREEN_RATE := { "wood": 2.0, "stone": 1.2, "berries": 1.5 }
const FARM_FOOD_PER_HOUR := 0.75 ## Food per farmer-hour on a farm (one farmer per farm counts).
const VILLAGE_HARVEST_RADIUS := 35.0 ## Villagers gather props this close to the kingdom center.
const SITE_STALL_HOURS := 48.0 ## A site with no work for this long is abandoned (cost back).
const VILLAGE_MSG_STAYS := "%s decidiu ficar: %s"
const VILLAGE_MSG_GOES := "%s seguiu viagem: %s"
const VILLAGE_MSG_LEFT := "%s deixou o Reino de %s: %s"
const VILLAGE_MSG_SITE := "Os moradores do Reino de %s começaram a construir: %s"
const VILLAGE_MSG_HOUSE_DONE := "Ficou pronta a casa de %s"
const VILLAGE_MSG_DONE := "Os moradores do Reino de %s terminaram: %s"
const VILLAGE_MSG_ABANDONED := "A obra (%s) do Reino de %s foi abandonada"

# People nodes
const PEOPLE_MAX_ACTIVE := 30
const PEOPLE_SPAWNS_PER_FRAME := 2
const PERSON_BRAIN_TICK := 0.25
const PERSON_WALK_SPEED := 2.2
const PERSON_RUN_SPEED := 4.5 ## Fleeing.
const PERSON_ARRIVE := 0.8
const PERSON_RADIUS := 0.3
const PERSON_AVOID_RAY := 1.6
const PERSON_SEAT_RADIUS := 3.5 ## Travelers stop this close to the seat to look around.
const PERSON_FIRE_SLEEP_RADIUS := 2.5 ## Homeless people sleep this close to the campfire.
const PERSON_FLEE_DIST := 14.0
const PERSON_EVALUATE_SEC := 4.0 ## A traveler looks at the kingdom this long before deciding.
const PERSON_IDLE_RADIUS := 6.0 ## Idle people stroll this far around the seat.
const PEOPLE_SYNC_SEC := 1.0 ## Live people are written back to their records this often.
const PEOPLE_SNAPSHOT_MS := 1000 ## A kingdom's snapshot is reused this long by the brains.
const PERSON_DOOR_GAP := 0.7 ## Door spot in front of a footprint.
const PERSON_THREAT_RADIUS := 10.0 ## Carnivores (and raiders) this close scare a person.
const PERSON_WORK_GAP := 0.6 ## Distance kept from a prop's trunk while working on it.
## Seconds of work per prop (then the person carries the yield to the stock).
const PERSON_HARVEST_SEC := { Prop.OAK: 6.0, Prop.PINE: 6.0, Prop.ROCK: 8.0, Prop.BUSH: 2.0 }
const PERSON_SITE_SEC := 5.0 ## One work action on a site (adds 5 s worth of person-hours).
const PERSON_FARM_SEC := 5.0

# Talking to and helping villagers
const TALK_RANGE := 2.2
const TALK_PROMPT := "[E] Falar com %s"
const PERSON_CARD_SEC := 6.0
const DONATE_MAX := 10 ## Of each resource per G press.
const DONATE_RES := [Res.WOOD, Res.STONE, Res.BERRIES]
const DONATE_OPINION := 0.05
const DONATE_RADIUS := 25.0 ## Who sees a donation.
const DONATE_MSG := "Você doou %s ao Reino de %s"
const DONATE_NOTHING_MSG := "Você não tem madeira, pedra nem frutas para doar"
const DONATE_OUTSIDE_MSG := "Doe dentro de um reino"
const PROTECT_OPINION := 0.05 ## To every resident when the player kills a raider inside the kingdom.
const AWAY_OPINION_PER_DAY := 0.1 ## Opinions drift toward neutral while the player is away.
## Opinion lines on the card, for opinions >= each step (the last one is below every step).
const OPINION_STEPS := [0.3, 0.1, -0.1, -0.3]
const OPINION_TEXTS := ["Gosta de você", "Simpatiza com você", "Não tem opinião sobre você", "Desconfia de você", "Não gosta de você"]
const JOB_TEXTS := {
	"wood": "cortando lenha", "stone": "quebrando pedra", "berries": "colhendo frutas", "farm": "cuidando da fazenda",
	"build": "trabalhando na obra", "market": "cuidando do comércio", "idle": "sem trabalho", "rest": "descansando",
	"child": "brincando",
	"": "olhando o reino",
}
const STATUS_TEXTS := { "traveler": "chegando ao reino", "leaving": "indo embora", "inside": "em casa" }
const NEED_TEXTS := { "food": "comida", "home": "uma casa", "mood": "ânimo", "none": "nada por enquanto" }
const VILLAGE_LINE := "Moradores: %d · Famílias: %d · Estoque: %s"
const VILLAGE_NEWS_SHOWN := 3 ## Village messages shown when the player comes back.
const VILLAGE_NEWS_MORE := "Enquanto você estava fora, aconteceram mais %d coisas nos povoados"
const PERSON_STUCK_CHECK_SEC := 1.0 ## How often a walking person checks it is getting anywhere.
const PERSON_STUCK_MOVE := 0.3 ## Less than this in a check counts as stuck.
const PERSON_DETOUR_SEC := 0.8 ## Sidestep when stuck.
const PERSON_STUCK_TELEPORT_SEC := 6.0 ## Stuck this long: placed at the target.

# Society: crests (drawn pixel by pixel, see Crest)
enum CrestPattern { PLAIN, PALE, FESS, BEND, QUARTERLY, CHEVRON }
enum CrestCharge { NONE, ROUNDEL, CROSS, LOZENGE, STAR, CRESCENT }
## [Portuguese name, color, is metal]. Heraldry: metal on colour, never metal on metal.
const TINCTURES := [
	["ouro", Color(0.86, 0.68, 0.20), true], ["prata", Color(0.90, 0.90, 0.86), true],
	["vermelho", Color(0.72, 0.12, 0.12), false], ["azul", Color(0.16, 0.30, 0.66), false],
	["verde", Color(0.16, 0.46, 0.22), false], ["preto", Color(0.10, 0.10, 0.11), false],
	["púrpura", Color(0.46, 0.20, 0.52), false],
]
const CREST_PATTERN_NAMES := {
	CrestPattern.PLAIN: "pleno", CrestPattern.PALE: "partido", CrestPattern.FESS: "cortado",
	CrestPattern.BEND: "em banda", CrestPattern.QUARTERLY: "esquartelado", CrestPattern.CHEVRON: "em asna",
}
const CREST_CHARGE_NAMES := {
	CrestCharge.ROUNDEL: "um besante", CrestCharge.CROSS: "uma cruz", CrestCharge.LOZENGE: "um losango",
	CrestCharge.STAR: "uma estrela", CrestCharge.CRESCENT: "um crescente",
}
const CREST_SIZE := Vector2i(32, 40) ## Pixels of a crest image (a shield with a pointed base).
const CREST_TRIES := 40 ## Attempts to find a crest not used in the kingdom.
const CREST_BORDER := Color(0.12, 0.10, 0.08)

# Society: ages, relations, couples, children, families, opinion (1 day = 24 game hours)
const ADULT_AGE := 16.0
const CHILD_YEARS_PER_DAY := 2.0 ## Children grow fast (adult in 8 game days).
const ADULT_YEARS_PER_DAY := 0.25
const OLD_AGE := 70.0
const DEATH_CHANCE_PER_DAY := 0.15 ## From OLD_AGE on.
const CHILD_MIN_SCALE := 0.55 ## Model scale of a newborn (times the adult height).
const SOCIAL_PAIRS_PER_HOUR := 6 ## Meetings per kingdom per hour (half between close people).
const MEET_BASE := 0.02
const MEET_SAME_TRAIT := 0.04
const MEET_OPPOSITE_TRAIT := -0.06
const MEET_SOCIABLE := 0.02 ## Per sociable person in the pair.
const MEET_LONER := -0.02 ## Per loner in the pair.
const MEET_CLOSE := 0.02 ## Same house or family.
const MEET_NOISE := 0.03
const FRIEND_AT := 0.35
const RIVAL_AT := -0.35
const COUPLE_AT := 0.6
const MARRY_MIN_AGE := 18.0
const COUPLE_MAX_AGE_GAP := 15.0
const BIRTH_AGE := Vector2(18.0, 45.0) ## The mother's age.
const BIRTH_CHANCE_PER_DAY := 0.35
const BIRTH_CONTENTMENT := 0.5
const BIRTH_FOOD_DAYS := 2.0
const BIRTH_GAP_HOURS := 72.0
const KINGDOM_BIRTH_CAP := 14 ## Births stop here (room is left for travelers).
const CHILD_HEIGHT_JITTER := 0.03
const SPLIT_RIVAL_AT := -0.5 ## A member this hostile to the head breaks away.
const SPLIT_RELATION_HIT := -0.2 ## Relation change with the old family after a rival split.
const BRANCH_RELATION_GAIN := 0.1
const FAMILY_BRANCH_SIZE := 5 ## Bigger families let a household branch off.
const BRANCH_CHANCE_PER_DAY := 0.25
const FAMILY_SPLIT_COOLDOWN_DAYS := 3.0
const KIN_START_RELATION := 0.2 ## A newcomer with the family's surname.
const SPOUSE_START_RELATION := 0.8
## Hourly opinion drift (of the player).
const OPINION_CONTENT_RATE := 0.01 ## Times (contentment - 0.5).
const OPINION_FAMILY_PULL := 0.02 ## Share of the gap to the family's adult mean.
const OPINION_FRIEND_PULL := 0.01
const OPINION_RIVAL_PUSH := 0.005
const ALLY_AT := 0.5
const ALLY_EXIT := 0.4
const ENEMY_AT := -0.4
const ENEMY_EXIT := -0.3
const TALK_OPINION := { "sociable": 0.03, "loner": -0.02, "other": 0.01 } ## Once per game day.
const DEED_HOUR := 10.0 ## Gifts and thefts happen from this hour, once a day, with the player in the kingdom.
const GIFT_AMOUNT := 3
const GIFT_MIN_STOCK := 10
const GIFT_RES := [Res.WOOD, Res.STONE]
const THEFT_AMOUNT := 2
const THEFT_RES := [Res.WOOD, Res.STONE, Res.BERRIES]
const THEFT_MAX_PER_DAY := 2
const STAY_KIN := 0.1
const CHILD_PROFESSION_NAME := "criança"
## Society messages (Portuguese, shown in the HUD or kept for the player's return).
const SOCIETY_MSG_KIN := "%s juntou-se à Casa %s, de parentes"
const SOCIETY_MSG_MARRIED := "%s e %s se casaram"
const SOCIETY_MSG_MERGED := "A Casa %s uniu-se à Casa %s"
const SOCIETY_MSG_DISSOLVED := "A Casa %s se desfez"
const VILLAGE_MSG_LEFT_FAMILY := "%s deixou o Reino de %s com a família: %s"
const SOCIETY_MSG_BORN := "Nasceu %s, %s de %s e %s"
const CHILD_WORDS := ["filho", "filha"]
const SOCIETY_MSG_GREW := "%s cresceu e agora é %s"
const SOCIETY_MSG_DIED := "Morreu %s, aos %d anos"
const SOCIETY_MSG_BROKE := "%s rompeu com a Casa %s e fundou a Casa %s"
const SOCIETY_MSG_BRANCH := "%s deixou a Casa %s em paz e fundou a Casa %s"
const SOCIETY_MSG_ALLY := ["%s agora é seu aliado", "%s agora é sua aliada"]
const SOCIETY_MSG_ENEMY := ["%s agora é seu inimigo", "%s agora é sua inimiga"]
const SOCIETY_MSG_FAMILY_ALLY := "A Casa %s agora é sua aliada"
const SOCIETY_MSG_FAMILY_ENEMY := "A Casa %s agora é sua inimiga"
const SOCIETY_MSG_GIFT := "A Casa %s lhe deu %d de %s"
const SOCIETY_MSG_THEFT := "%s roubou %d de %s de você"
const DONATE_FULL_AT := 10 ## Resources given at once for the full opinion gain.
const VILLAGE_NEWS_MAX := 40 ## News kept for the player's return (the oldest go first).
const VILLAGE_MSG_APPROACH := "Um viajante se aproxima do Reino de %s"
const CREST_BANNER_SCENE := "res://assets/models/crest_banner.glb"
## Banner beside a house: local offset from the footprint corner on the door (+Z) side, outward.
const CREST_BANNER_GAP := Vector2(0.35, 0.4)
## Person card and families panel.
const CARD_FAMILY := "Casa %s"
const CARD_HEAD := " (chefe)"
const CARD_SPOUSE := ["Casado com %s", "Casada com %s"]
const CARD_WIDOWED := ["Viúvo", "Viúva"]
const CARD_PARENTS := ["Filho de %s", "Filha de %s"]
const CARD_CHILDREN := "Filhos: %s"
const CARD_FRIEND := ["Amigo: %s", "Amiga: %s"]
const CARD_RIVAL := "Rival: %s"
const CARD_STANCE := { "ally": [" — seu aliado", " — sua aliada"], "enemy": [" — seu inimigo", " — sua inimiga"] }
const CARD_CREST := "Brasão: %s"
const FAMILY_STANCE_TEXTS := { "ally": "aliada", "enemy": "inimiga", "": "neutra" }
const FAMILIES_TITLE := "Famílias do Reino de %s"
const FAMILIES_EMPTY := "Ainda não há famílias"
const FAMILIES_REFRESH_SEC := 1.0

# Houses and ambitions (stage 7)
enum Tradition { WARRIORS, FARMERS, MERCHANTS, BUILDERS, FOREST }
const TRADITION_NAMES := {
	Tradition.WARRIORS: "Guerreiros", Tradition.FARMERS: "Lavradores", Tradition.MERCHANTS: "Mercadores",
	Tradition.BUILDERS: "Construtores", Tradition.FOREST: "Gente da mata",
}
## Trades a House expects from its members.
const TRADITION_PROFESSIONS := {
	Tradition.WARRIORS: [Profession.GUARD], Tradition.FARMERS: [Profession.FARMER],
	Tradition.MERCHANTS: [Profession.MERCHANT], Tradition.BUILDERS: [Profession.BUILDER, Profession.MASON],
	Tradition.FOREST: [Profession.WOODCUTTER, Profession.GATHERER],
}
## What a House cares about (0..1), before a little per-House noise.
const TRADITION_VALUES := {
	Tradition.WARRIORS: { wealth = 0.3, land = 0.4, prestige = 0.8, faith = 0.4, honor = 0.9 },
	Tradition.FARMERS: { wealth = 0.4, land = 0.9, prestige = 0.3, faith = 0.6, honor = 0.5 },
	Tradition.MERCHANTS: { wealth = 0.9, land = 0.3, prestige = 0.6, faith = 0.3, honor = 0.4 },
	Tradition.BUILDERS: { wealth = 0.5, land = 0.5, prestige = 0.6, faith = 0.4, honor = 0.6 },
	Tradition.FOREST: { wealth = 0.3, land = 0.6, prestige = 0.3, faith = 0.5, honor = 0.6 },
}
const VALUE_NOISE := 0.15
enum Goal { LAND, UPGRADE, ALLIANCE, SURPASS, REVENGE, WEALTH, HEIR, UNION }
const GOAL_TEXTS := {
	Goal.LAND: "conseguir mais terra", Goal.UPGRADE: "melhorar a casa", Goal.ALLIANCE: "aliança por casamento com a Casa %s",
	Goal.SURPASS: "superar a Casa %s", Goal.REVENGE: "vingar-se da Casa %s", Goal.WEALTH: "juntar riqueza",
	Goal.HEIR: "formar um herdeiro no ofício", Goal.UNION: "unir-se à Casa %s",
}
enum Desire { NONE, LOVE, RICH, PROTECT, LEAVE, SURPASS_PARENT }
const DESIRE_TEXTS := {
	Desire.NONE: "", Desire.LOVE: "casar com %s", Desire.RICH: "ficar rico", Desire.PROTECT: "proteger os irmãos",
	Desire.LEAVE: "sair da Casa", Desire.SURPASS_PARENT: "superar %s",
}
const HOUSE_LEVEL_NAMES := ["casa simples", "casa de pedra", "solar"]
const HOUSE_LEVEL_CAPACITY := [4, 6, 8]
const UPGRADE_PRICE := [120, 300] ## Wealth to go from level 0 -> 1 and 1 -> 2.
const PLOT_SIZE := 8.0
const PLOT_PRICE := 40
const PLOTS_PER_ADULT := 1 ## A House wants about one plot per adult member.
const PLOTS_MAX := 6
const DOWRY := 30
const BRIBE := 25
const WEALTH_PER_WORK_HOUR := 0.5 ## Base wealth a working member brings home each hour.
const SKILL_HOURS_FOR_MAX := 200.0 ## House hours in a trade for the full skill bonus.
const SKILL_MAX_BONUS := 0.5
const SKILL_INHERIT := 0.6 ## Share of the House's skill a child following the trade starts with.
const CHRONICLE_MAX := 200
const TRADITION_TRAIT_NUDGE := 0.25 ## Chance a head's trait pulls the new House to another tradition.
const VOCATION_FOLLOW_TRADITION := 0.6 ## Chance a child wants the House trade.
const VOCATION_FROM_TRAIT := 0.25 ## Else, chance the vocation comes from a trait (rest: any trade).
## Trades a trait pulls toward (vocation and tradition nudges).
const TRAIT_VOCATIONS := {
	Trait.BRAVE: [Profession.GUARD], Trait.GREEDY: [Profession.MERCHANT], Trait.SOCIABLE: [Profession.MERCHANT],
	Trait.LONER: [Profession.WOODCUTTER, Profession.GATHERER], Trait.DEVOUT: [Profession.FARMER],
	Trait.WORKER: [Profession.MASON, Profession.BUILDER],
}
const DEPART_FRIENDLY_AT := 0.25 ## Relation with the head above this: a friendly departure.
const DEPART_HOSTILE_AT := -0.3
const WEALTH_POOR := 50.0 ## Below this a House wants to gather wealth.
const WEALTH_COMFORT := 150.0 ## The "gather wealth" goal is met here.
const HEIR_AGE := 40.0 ## A head this old without an heir in the trade wants one.
const UNION_MAX_MEMBERS := 2 ## Houses this small without heirs seek a union with an ally.
const GOAL_NOISE := 0.05
const CORRUPTION_BASE := 0.15
const DISCOVERY_BASE := 0.05
const DISCOVERY_PER_WATCHER := 0.04
const DISCOVERY_MAX := 0.4
const VOCATION_AGE := 12.0 ## Children start dreaming of a trade at this age.
const CONFLICT_RESOLVE_PER_DAY := 0.3 ## Chance a vocation clash is settled each day.
const CONFLICT_RESENTMENT := 0.3 ## Resentment added when someone gives in to the House trade.
const NEGOTIATE_DISHONOR := 0.2 ## Prestige a House loses when it lets a member choose another trade.
const BLESSING_SHARE := 0.2 ## Share of the House wealth a friendly departure takes along.
const HOSTILE_DEPART_HIT := -0.4 ## Relation with the old House after a hostile departure.
const RUNAWAY_HIT := -0.25 ## Extra relation hit when the family finds out someone ran away.
const DISCOVERY_HOUR := 7.0 ## Secret runaways are noticed at this hour, the next day.
const ADOPT_MIN_WEALTH := 40.0 ## A widow(er) adopting alone needs at least this House wealth.
const PRESTIGE_WEIGHTS := { wealth = 0.01, plot = 0.5, level = 1.0, skill = 2.0 }
const HOUSE_MSG_BLESSED := "%s deixou a Casa %s com a bênção da família e fundou a Casa %s"
const HOUSE_MSG_NEUTRAL := "%s deixou a Casa %s e fundou a Casa %s"
const HOUSE_MSG_HOSTILE := "%s rompeu com a Casa %s e fundou a Casa %s, agora rival"
const HOUSE_MSG_RUNAWAY := "%s fugiu da Casa %s durante a noite"
const HOUSE_MSG_CONFORM := "%s aceitou seguir o ofício da Casa %s, contra a vontade"
const HOUSE_MSG_NEGOTIATE := "A Casa %s aceitou que %s seja %s"
const HOUSE_MSG_ADOPTED := "%s foi adotado pela Casa %s"
const GOAL_DAYS := 3.0 ## A House gives itself this long to reach a goal.
const GOAL_SUCCESS_CONTENT := 0.08
const GOAL_FAIL_CONTENT := -0.1
const GOAL_SUCCESS_HONOR := 0.3 ## Dishonor wiped by a reached goal.
const PLOT_SEARCH_RINGS := 6 ## Rings of PLOT_SIZE around the home searched for a free plot.
const PLOT_MAX_HEIGHT_DIFF := 2.5
const PLOT_BUY_MARKUP := 1.5
const HOUSE_MSG_PLOT := "A Casa %s tomou posse de um lote"
const HOUSE_MSG_PLOT_BOUGHT := "A Casa %s comprou um lote da Casa %s"
const HOUSE_MSG_UPGRADE := "A Casa %s transformou o lar em %s"
const HOUSE_MSG_GOAL_SET := "A Casa %s quer %s"
const HOUSE_MSG_GOAL_DONE := "A Casa %s conseguiu %s"
const HOUSE_MSG_GOAL_FAILED := "A Casa %s não conseguiu %s"
const FAMILY_ALLY_AT := 0.3 ## Heads this fond of each other make their Houses allies.
const UNHAPPY_AT := 0.2 ## An arranged couple below this relation starts an unhappy marriage.
const UNHAPPY_DRIFT := -0.1 ## Daily relation change of an unhappy couple.
const SEPARATE_AT := -0.5
const SEPARATION_DISHONOR := 0.2
const ALLIANCE_RELATION_GAIN := 0.3
const RESIST_RESENTMENT := 0.2
const RESIST_RELATION_HIT := -0.2
const SKIM_AMOUNT := 5
const SKIM_VALUE := 2.0 ## Wealth per unit skimmed from the kingdom stock.
const SCANDAL_DISHONOR := 1.0
const SCANDAL_RELATION_HIT := -0.2
const INFILTRATE_AT := -0.4 ## Heads this hostile may plant a spy in the rival House.
const INFILTRATE_PER_DAY := 0.15
const SPY_STEAL_SHARE := 0.1
const SPY_SABOTAGE_HOURS := 12.0
const FEUD_RELATION_HIT := -0.5
const REVENGE_PER_DAY := 0.3
const REVENGE_DISHONOR := 0.4
const REVENGE_STEAL_SHARE := 0.1
const ROMANCE_START_PER_DAY := 0.2
const ROMANCE_DISHONOR := 0.5
const ROMANCE_RELATION_HIT := -0.3
const ROMANCE_RESENTMENT := 0.4
const HOUSE_MSG_ARRANGED := "A Casa %s casou %s com %s, da Casa %s"
const HOUSE_MSG_RESISTED := "%s recusou o casamento arranjado pela Casa %s"
const HOUSE_MSG_SEPARATED := "%s e %s se separaram — escândalo na Casa %s"
const HOUSE_MSG_UNION := "A Casa %s uniu-se à Casa %s"
const HOUSE_MSG_SKIM := "A Casa %s foi pega desviando %s do estoque do reino"
const HOUSE_MSG_SERVE := "%s deixou a Casa %s e foi servir a Casa %s"
const HOUSE_MSG_SPY := "Descoberto: %s espionava a Casa %s a mando da Casa %s"
const HOUSE_MSG_REVENGE := "A Casa %s vingou-se da Casa %s"
const HOUSE_MSG_ROMANCE := "A Casa %s descobriu o romance secreto de %s e %s"
const HOUSE_LEVEL_SCENES := ["res://assets/models/house.glb", "res://assets/models/house_stone.glb",
		"res://assets/models/manor.glb"]
const GUARD_REACH := 2.6 ## Spear reach of a guard.
const GUARD_DAMAGE := 18.0
const GUARD_STRIKE_SEC := 0.9
const GUARD_PATROL_SHARE := 0.6 ## Patrol ring radius, as a share of the territory radius.
const GUARD_PATROL_SPEED := 0.02 ## Radians per second along the ring.
const GUARD_ALERT_MARGIN := 10.0 ## Hostiles this far outside the territory still draw guards.
const GUARD_REST_HOURS := Vector2(13.0, 18.0) ## Guards sleep in the afternoon and watch at night.
const GUARD_RAID_REDUCTION := 0.2 ## Each guard weakens a summarized raid by this share.
const GUARD_RAID_FLOOR := 0.2
