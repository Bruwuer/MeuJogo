class_name CreatureManager
extends Node3D
## Owns the creature nodes. Records live in WorldState; a node exists only while its chunk is
## loaded (at most CREATURE_MAX_ACTIVE, nearest to the player first). On a chunk's first visit
## its starting pack is rolled from the seed and biome. Also handles breeding, growing up,
## deaths (and the grudge they leave), and live raids on loaded kingdoms.

signal creature_killed(rec: Dictionary, by_player: bool)
signal message(text: String)

const _REGROUND := 0.3 ## Creatures are dropped this far above the ground when (re)created.
const _FALL_LIMIT := 3.0 ## Below the ground by this much a creature is put back on top.

## Used when there is no DayNight (tests).
var is_night_override := false

var _state: WorldState
var _gen: TerrainGenerator
var _scatter: PropScatter
var _streamer: ChunkStreamer
var _library: ModelLibrary
var _day_night: DayNight
var _sim: PackSim
var _player: Node3D
var _nodes: Dictionary[int, Creature] = {}
var _mates: Dictionary[int, int] = {} # creature id -> partner id
var _raid_damage: Dictionary[int, float] = {} # pack id -> damage dealt in the current raid
var _rng := RandomNumberGenerator.new()
var _sync_left := 0.0
var _breed_left := GameConstants.BREED_CHECK_SEC
var _hours := 0.0 ## Own clock when there is no DayNight.
var _queue: Array[int] = [] # record ids waiting for a node


func setup(state: WorldState, gen: TerrainGenerator, scatter: PropScatter, streamer: ChunkStreamer,
		library: ModelLibrary, day_night: DayNight, pack_sim: PackSim, player: Node3D) -> void:
	_state = state
	_gen = gen
	_scatter = scatter
	_streamer = streamer
	_library = library
	_day_night = day_night
	_sim = pack_sim
	_player = player
	_rng.seed = hash([state.seed, "creatures"])
	streamer.chunk_loaded.connect(_on_chunk_loaded)
	streamer.chunk_unloaded.connect(_on_chunk_unloaded)
	if pack_sim:
		pack_sim.kingdom_loaded = is_kingdom_loaded
		pack_sim.raid_started.connect(_on_raid_started)


func pending_spawns() -> int:
	return _queue.size()


func active_count() -> int:
	return _nodes.size()


func node_for(id: int) -> Creature:
	return _node(id)


func active_creatures() -> Array[Creature]:
	var out: Array[Creature] = []
	for id in _nodes.keys():
		var n := _node(id)
		if n and not n.is_dead():
			out.append(n)
	return out


func is_night() -> bool:
	return _day_night.is_night() if _day_night else is_night_override


func now_hours() -> float:
	return _day_night.total_hours() if _day_night else _hours


func is_kingdom_loaded(k: Dictionary) -> bool:
	return _streamer.is_loaded(ChunkMath.world_to_chunk(k.center))


## New worlds: a calm wolf pack (no hunger, no grudge) between 60 and 120 m from the spawn.
func ensure_first_wolves(spawn: Vector3) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_state.seed, "first_wolves"])
	var size := ChunkMath.playable_size()
	var den := spawn
	for i in 32:
		var a := rng.randf() * TAU
		var r := rng.randf_range(GameConstants.FIRST_WOLVES_DISTANCE.x, GameConstants.FIRST_WOLVES_DISTANCE.y)
		den = spawn + Vector3(cos(a) * r, 0.0, sin(a) * r)
		var margin := GameConstants.SPAWN_EDGE_MARGIN
		if den.x > margin and den.z > margin and den.x < size - margin and den.z < size - margin:
			break
	den.y = _gen.height_at(den.x, den.z)
	return _spawn_pack("lobo", den, rng)


func _process(delta: float) -> void:
	if not _day_night:
		_hours += delta / GameConstants.DAY_LENGTH_SEC * 24.0
	_spawn_queued()
	_sync_left -= delta
	if _sync_left <= 0.0:
		_sync_left = GameConstants.CREATURE_SYNC_SEC
		_sync(GameConstants.CREATURE_SYNC_SEC)
	_breed_left -= delta
	if _breed_left <= 0.0:
		_breed_left = GameConstants.BREED_CHECK_SEC
		breed_tick()


## Writes live creatures back to their records, freezes those that walked out of the loaded
## area, grows cubs and fills free slots with waiting records.
func _sync(dt: float) -> void:
	var grow := dt / (GameConstants.CUB_DAYS * GameConstants.DAY_LENGTH_SEC)
	for id in _nodes.keys():
		var n := _node(id)
		if n == null:
			continue
		if not is_instance_valid(n) or n.is_dead():
			continue
		var p := n.global_position
		var ground := _gen.height_at(p.x, p.z)
		if p.y < ground - _FALL_LIMIT:
			n.global_position = Vector3(p.x, ground + _REGROUND, p.z)
		n.sync_record()
		_state.move_creature(id, n.global_position)
		if float(n.record.age) < 1.0:
			n.record.age = minf(1.0, float(n.record.age) + grow)
			n.refresh_growth()
		if not _streamer.is_loaded(ChunkMath.world_to_chunk(n.global_position)):
			_free_node(id)
	_fill()


## Writes every live creature back to its record (before saving).
func sync_all() -> void:
	for id in _nodes.keys():
		var n := _node(id)
		if is_instance_valid(n) and not n.is_dead():
			n.sync_record()
			_state.move_creature(id, n.global_position)


func _on_chunk_loaded(c: Vector2i) -> void:
	if not _state.visited(c):
		_state.mark_visited(c)
		if ChunkMath.is_playable(c):
			_spawn_initial(c)
	_fill()


func _on_chunk_unloaded(c: Vector2i) -> void:
	for id in _nodes.keys():
		var n := _node(id)
		if is_instance_valid(n) and ChunkMath.world_to_chunk(n.global_position) == c:
			n.sync_record()
			_state.move_creature(id, n.global_position)
			_free_node(id)
	for rec in _state.creatures_in(c):
		if _nodes.has(rec.id):
			_free_node(rec.id)


## Queues waiting records in loaded chunks, nearest to the player first; _process creates a few
## nodes per frame so streaming never stalls on a burst of creatures.
func _fill() -> void:
	if _nodes.size() >= GameConstants.CREATURE_MAX_ACTIVE:
		return
	var waiting: Array[Dictionary] = []
	for rec in _state.all_creatures():
		if not _nodes.has(rec.id) and _streamer.is_loaded(ChunkMath.world_to_chunk(rec.pos)):
			waiting.append(rec)
	var center := _player.global_position if is_instance_valid(_player) else Vector3.ZERO
	waiting.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return center.distance_squared_to(a.pos) < center.distance_squared_to(b.pos))
	_queue.assign(waiting.map(func(r: Dictionary) -> int: return r.id))


func _spawn_queued() -> void:
	if _queue.is_empty() or not _library.is_ready():
		return
	var made := 0
	while not _queue.is_empty() and made < GameConstants.CREATURES_SPAWNED_PER_FRAME:
		if _nodes.size() >= GameConstants.CREATURE_MAX_ACTIVE:
			_queue.clear()
			return
		var rec := _state.creature(_queue.pop_front())
		if rec.is_empty() or _nodes.has(rec.id) or not _streamer.is_loaded(ChunkMath.world_to_chunk(rec.pos)):
			continue
		_instantiate(rec)
		made += 1


func _instantiate(rec: Dictionary) -> void:
	var p: Vector3 = rec.pos
	rec.pos = Vector3(p.x, _gen.height_at(p.x, p.z) + _REGROUND, p.z)
	var n := Creature.new()
	add_child(n)
	n.setup(rec, _library, self)
	n.died.connect(_on_creature_died)
	n.health.damaged.connect(_on_creature_hurt.bind(rec.id))
	_nodes[rec.id] = n


func _free_node(id: int) -> void:
	var n = _nodes.get(id)
	_nodes.erase(id)
	_mates.erase(id)
	if is_instance_valid(n):
		n.queue_free()


func _spawn_initial(c: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_state.seed, c.x, c.y, "creatures"])
	if rng.randf() >= GameConstants.CREATURE_PACK_CHANCE:
		return
	var origin := ChunkMath.chunk_origin(c)
	var x := origin.x + rng.randf_range(4.0, GameConstants.CHUNK_SIZE - 4.0)
	var z := origin.z + rng.randf_range(4.0, GameConstants.CHUNK_SIZE - 4.0)
	var species := _roll_species(_gen.biome_at(x, z), rng)
	if species != "":
		_spawn_pack(species, Vector3(x, _gen.height_at(x, z), z), rng)


func _roll_species(biome: int, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for s in GameConstants.SPECIES:
		total += GameConstants.SPECIES[s].biomes.get(biome, 0.0)
	var roll := rng.randf() * total
	for s in GameConstants.SPECIES:
		roll -= GameConstants.SPECIES[s].biomes.get(biome, 0.0)
		if roll <= 0.0 and GameConstants.SPECIES[s].biomes.get(biome, 0.0) > 0.0:
			return s
	return ""


func _spawn_pack(species: String, den: Vector3, rng: RandomNumberGenerator) -> Dictionary:
	var pack := _state.add_pack(species, den)
	var sp: Dictionary = GameConstants.SPECIES[species]
	var count := rng.randi_range(sp.pack.x, sp.pack.y)
	for i in count:
		var a := rng.randf() * TAU
		var r := rng.randf() * GameConstants.CREATURE_SPAWN_SPREAD
		var p := SpawnPicker.nearest_clear(_gen, _scatter, den + Vector3(cos(a) * r, 0.0, sin(a) * r))
		var rec := _state.add_creature(Genome.random(species, rng), p + Vector3.UP * _REGROUND, pack.id)
		if i == 0:
			pack.leader_id = rec.id
	return pack


## Pack knowledge the brain needs (see CreatureBrain.decide).
func brain_extras(n: Creature) -> Dictionary:
	var rec := n.record
	var out := { is_night = is_night() }
	var pack := _state.pack(rec.pack_id)
	if not pack.is_empty():
		out.den_pos = pack.den
		var leader: Creature = _node(pack.leader_id)
		if is_instance_valid(leader) and leader != n and not leader.is_dead():
			out.pack_leader_pos = leader.global_position
		var raid := _raid_target(pack, n.global_position)
		if not raid.is_empty():
			out.raid_target = raid
		var g := n.genome
		var bold: bool = g.diet == GameConstants.Diet.CARNIVORE or g.aggression >= GameConstants.PLAYER_DEFENSE_AGGRESSION
		if bold and (pack.grudge >= GameConstants.HOSTILE_GRUDGE or pack.cubs_alarm >= GameConstants.HOSTILE_CUBS
				or (g.diet == GameConstants.Diet.CARNIVORE and pack.hunger >= GameConstants.HOSTILE_HUNGER)):
			out.hostile_to_player = true
	var partner: Creature = _node(_mates.get(rec.id, -1))
	if is_instance_valid(partner) and not partner.is_dead():
		out.mate = { id = partner.record.id, pos = partner.global_position }
	return out


## The building a raiding member goes for: the nearest non-seat building of the kingdom (the
## seat only when nothing else is left). {} when the pack is not raiding a loaded kingdom.
func _raid_target(pack: Dictionary, from: Vector3) -> Dictionary:
	if pack.raid_kingdom == -1:
		return {}
	var kingdom := {}
	for k in _state.kingdoms():
		if k.id == pack.raid_kingdom:
			kingdom = k
	if kingdom.is_empty() or not is_kingdom_loaded(kingdom):
		return {}
	var best := {}
	var best_d := INF
	for b in _state.all_buildings():
		if b.type == GameConstants.Building.FLAG or b.id == kingdom.seat_id:
			continue
		if PackSim._flat_dist(b.pos, kingdom.center) > kingdom.radius:
			continue
		var d := from.distance_squared_to(b.pos)
		if d < best_d:
			best = b
			best_d = d
	if best.is_empty():
		var seat := _state.building(kingdom.seat_id)
		if seat.is_empty() or _state.building_hp(seat.id) <= 1.0:
			_end_raid(pack)
			return {}
		best = seat
	var fp: Vector2 = GameConstants.BUILD_FOOTPRINT[best.type]
	return { id = best.id, pos = best.pos, radius = fp.length() * 0.5 }


## Called by a raiding creature that reached its target building.
func damage_building(id: int, amount: float, attacker: Creature) -> void:
	var rec := _state.building(id)
	if rec.is_empty():
		return
	var pack := _state.pack(attacker.record.pack_id)
	if _state.damage_building(id, amount):
		var chunk := _streamer.get_chunk(ChunkMath.world_to_chunk(rec.pos))
		if chunk:
			chunk.remove_building(id)
		var who := PackMotives.species_plural(pack.species) if not pack.is_empty() else "animais"
		message.emit(GameConstants.BUILD_DESTROYED_MSG[rec.type] % who)
		if not pack.is_empty():
			_end_raid(pack)
		return
	if not pack.is_empty():
		_raid_damage[pack.id] = _raid_damage.get(pack.id, 0.0) + amount
		if _raid_damage[pack.id] >= GameConstants.RAID_SATISFY_DAMAGE:
			_end_raid(pack)


func _end_raid(pack: Dictionary) -> void:
	if pack.raid_kingdom == -1:
		return
	_raid_damage.erase(pack.id)
	PackMotives.after_raid(pack, now_hours())


func _on_raid_started(pack: Dictionary, kingdom: Dictionary, _motive: String) -> void:
	if is_kingdom_loaded(kingdom):
		message.emit(PackMotives.message(pack, kingdom.name))


## Pairs ready adults, and makes a cub for each pair that is close enough. Returns new records.
func breed_tick() -> Array[Dictionary]:
	var born: Array[Dictionary] = []
	var now := now_hours()
	var ready: Array[Creature] = []
	for n in active_creatures():
		if _ready_to_breed(n, now):
			ready.append(n)
	for n in ready:
		var id: int = n.record.id
		var partner: Creature = _node(_mates.get(id, -1))
		if not is_instance_valid(partner) or not ready.has(partner):
			_mates.erase(id)
			partner = _find_partner(n, ready)
			if partner == null:
				continue
			if _rng.randf() >= GameConstants.BREED_CHANCE * Genome.compatibility(n.record.genome, partner.record.genome):
				continue
			_mates[id] = partner.record.id
			_mates[partner.record.id] = id
		if n.global_position.distance_to(partner.global_position) > GameConstants.BREED_RADIUS:
			continue
		if _crowded(n.global_position):
			_mates.erase(id)
			_mates.erase(partner.record.id)
			continue
		born.append(_make_cub(n, partner, now))
		ready.erase(partner)
	return born


func _ready_to_breed(n: Creature, now: float) -> bool:
	var rec := n.record
	return not n.is_cub() and float(rec.hunger) <= GameConstants.BREED_MAX_HUNGER \
			and now >= float(rec.get("breed_after", 0.0)) \
			and n.state in [CreatureBrain.State.WANDER, CreatureBrain.State.GRAZE, CreatureBrain.State.FOLLOW, CreatureBrain.State.MATE]


func _find_partner(n: Creature, ready: Array[Creature]) -> Creature:
	var best: Creature = null
	var best_d := GameConstants.BREED_SEEK_RADIUS
	for o in ready:
		if o == n or _mates.has(o.record.id) and _mates[o.record.id] != n.record.id:
			continue
		if Genome.compatibility(n.record.genome, o.record.genome) <= 0.0:
			continue
		var d := n.global_position.distance_to(o.global_position)
		if d <= best_d:
			best = o
			best_d = d
	return best


func _crowded(pos: Vector3) -> bool:
	var count := 0
	for c in ChunkMath.chunks_in_radius(ChunkMath.world_to_chunk(pos), 1):
		count += _state.creatures_in(c).size()
	return count >= GameConstants.POPULATION_CAP_PER_CHUNK * 9


func _make_cub(a: Creature, b: Creature, now: float) -> Dictionary:
	_mates.erase(a.record.id)
	_mates.erase(b.record.id)
	for parent in [a, b]:
		parent.record.breed_after = now + GameConstants.BREED_COOLDOWN_HOURS
	var pos := (a.global_position + b.global_position) * 0.5
	var rec := _state.add_creature(Genome.cross(a.record.genome, b.record.genome, _rng), pos, a.record.pack_id, 0.0)
	rec.breed_after = now + GameConstants.BREED_COOLDOWN_HOURS + GameConstants.CUB_DAYS * 24.0
	if _nodes.size() < GameConstants.CREATURE_MAX_ACTIVE:
		_instantiate(rec)
	return rec


func _on_creature_hurt(_amount: float, source: Object, id: int) -> void:
	var n := _node(id)
	if n == null or n.is_dead() or not (source is Node and (source as Node).is_in_group("player")):
		return
	var pack := _state.pack(n.record.pack_id)
	if not pack.is_empty():
		PackMotives.add_grudge(pack, false, true)


func _on_creature_died(n: Creature, source: Object) -> void:
	var rec := n.record
	_nodes.erase(rec.id)
	_mates.erase(rec.id)
	_state.remove_creature(rec.id)
	var by_player := source is Node and (source as Node).is_in_group("player")
	var pack := _state.pack(rec.pack_id)
	if not pack.is_empty():
		if by_player:
			PackMotives.add_grudge(pack, n.is_cub())
		if pack.leader_id == rec.id:
			var members := _state.pack_members(pack.id)
			pack.leader_id = members[0].id if not members.is_empty() else -1
	creature_killed.emit(rec, by_player)


## The live node for a record id, or null. Nodes freed behind the manager's back are forgotten
## (their record stays and gets a new node).
func _node(id: int) -> Creature:
	var n = _nodes.get(id)
	if n == null and not _nodes.has(id):
		return null
	if n == null or not is_instance_valid(n):
		_nodes.erase(id)
		_mates.erase(id)
		return null
	return n
