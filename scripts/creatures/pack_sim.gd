class_name PackSim
extends Node
## Cheap hourly simulation of every pack, loaded or not: updates the motives from the world
## records (prey around the den, buildings in its territory, the player near the cubs) and starts
## raids when a motive is strong enough. Raids on kingdoms that are not loaded are summarized at
## once (buildings other than the seat take damage) and become messages for the player.

signal raid_started(pack: Dictionary, kingdom: Dictionary, motive: String)
signal building_destroyed(rec: Dictionary)

const _RAID_MAX_HOURS := 6.0 ## A live raid that never ends on its own is called off after this.

## Messages about raids that happened away from the player (shown when the player returns).
var pending_messages: Array[String] = []
## Used when there is no DayNight (tests).
var is_night_override := false
## Set by World: whose position triggers the cubs alarm.
var player: Node3D
## (pack, kingdom) -> "live" (simulated by the creature nodes), "offscreen" (summarized now) or
## "none" (the kingdom is loaded but the pack is frozen out of reach: no raid this hour).
var raid_mode: Callable = func(_p: Dictionary, _k: Dictionary) -> String: return "offscreen"

var _state: WorldState
var _day_night: DayNight
var _hours := 0.0 ## Own clock when there is no DayNight.
var _last_hour := -1.0


func setup(state: WorldState, day_night: DayNight) -> void:
	_state = state
	_day_night = day_night


func _process(_delta: float) -> void:
	if _day_night == null:
		return
	var h := floorf(_day_night.total_hours())
	if _last_hour < 0.0:
		_last_hour = h
	elif h > _last_hour:
		tick_hours(h - _last_hour)
		_last_hour = h


func now_hours() -> float:
	return _day_night.total_hours() if _day_night else _hours


func is_night() -> bool:
	return _day_night.is_night() if _day_night else is_night_override


func tick_hours(hours: float) -> void:
	_hours += hours
	for pack in _state.all_packs():
		var members := _state.pack_members(pack.id)
		if members.is_empty():
			_state.remove_pack(pack.id)
			continue
		PackMotives.update(pack, _context(pack, members), hours)
		if pack.raid_kingdom != -1:
			if now_hours() - pack.get("raid_hour", 0.0) > _RAID_MAX_HOURS:
				PackMotives.after_raid(pack, now_hours())
			continue
		_maybe_raid(pack, members)


func pack_aggression(members: Array) -> float:
	var total := 0.0
	for m: Dictionary in members:
		total += float(m.genome.aggression)
	return total / maxf(1.0, members.size())


## Damages the kingdom's buildings (never the seat or the flag), nearest to the den first.
## Returns the names of destroyed buildings and queues a message for the player.
func resolve_offscreen_raid(pack: Dictionary, kingdom: Dictionary) -> Array[String]:
	var strength := 0.0
	for m in _state.pack_members(pack.id):
		strength += float(m.genome.damage) * GameConstants.OFFSCREEN_RAID_HITS
	var guards := _state.residents(kingdom.id).filter(func(p: Dictionary) -> bool:
		return int(p.profession) == GameConstants.Profession.GUARD and SocietyRules.is_adult(p)).size()
	strength = raid_strength(strength, guards)
	var center: Vector3 = kingdom.center
	var targets := _state.all_buildings().filter(func(b: Dictionary) -> bool:
		return b.id != kingdom.seat_id and b.type != GameConstants.Building.FLAG and b.type != GameConstants.Building.STAKE \
				and not b.get("site", false) and _flat_dist(b.pos, center) <= kingdom.radius)
	var den: Vector3 = pack.den
	targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _flat_dist(a.pos, den) < _flat_dist(b.pos, den))
	var destroyed: Array[String] = []
	for b: Dictionary in targets:
		if strength <= 0.0:
			break
		var hp := _state.building_hp(b.id)
		var hit := minf(hp, strength)
		strength -= hit
		if _state.damage_building(b.id, hit):
			building_destroyed.emit(b)
			destroyed.append(GameConstants.BUILD_NAMES[b.type])
	var plural := PackMotives.species_plural(pack.species)
	if destroyed.is_empty():
		pending_messages.append(GameConstants.OFFSCREEN_RAID_NOTHING_MSG % [plural, kingdom.name])
	else:
		pending_messages.append(GameConstants.OFFSCREEN_RAID_MSG % [plural, _join(destroyed), kingdom.name])
	PackMotives.after_raid(pack, now_hours())
	return destroyed


func take_messages() -> Array[String]:
	var out := pending_messages
	pending_messages = []
	return out


func _maybe_raid(pack: Dictionary, members: Array) -> void:
	if now_hours() < pack.next_raid_hour:
		return
	var sp: Dictionary = GameConstants.SPECIES[pack.species]
	var carnivore: bool = sp.diet == GameConstants.Diet.CARNIVORE
	if carnivore != is_night(): # carnivores raid at night, territorial herbivores by day
		return
	if not PackMotives.wants_raid(pack, pack_aggression(members)):
		return
	var kingdom := _nearest_kingdom(pack.den)
	if kingdom.is_empty():
		return
	var mode: String = raid_mode.call(pack, kingdom)
	if mode == "none":
		return
	pack.raid_kingdom = kingdom.id
	kingdom.last_raid_hour = now_hours() # villagers fear a raided kingdom for a while
	pack.raid_hour = now_hours()
	var motive := PackMotives.dominant(pack)
	raid_started.emit(pack, kingdom, motive)
	if mode == "offscreen":
		resolve_offscreen_raid(pack, kingdom)


func _context(pack: Dictionary, members: Array) -> Dictionary:
	var den: Vector3 = pack.den
	var prey := 0
	for c: Dictionary in _state.all_creatures():
		if c.pack_id != pack.id and c.genome.diet == GameConstants.Diet.HERBIVORE \
				and _flat_dist(c.pos, den) <= GameConstants.PREY_RADIUS:
			prey += 1
	# Land nobody has visited yet has no records, but it is not empty of game.
	var reach := ceili(GameConstants.PREY_RADIUS / GameConstants.CHUNK_SIZE)
	for c in ChunkMath.chunks_in_radius(ChunkMath.world_to_chunk(den), reach):
		var center := ChunkMath.chunk_origin(c) + Vector3.ONE * GameConstants.CHUNK_SIZE * 0.5
		if ChunkMath.is_playable(c) and not _state.visited(c) and _flat_dist(center, den) <= GameConstants.PREY_RADIUS:
			prey += GameConstants.UNVISITED_CHUNK_PREY
	var buildings := 0
	for b: Dictionary in _state.all_buildings():
		if _flat_dist(b.pos, den) <= GameConstants.TERRITORY_RADIUS:
			buildings += 1
	var cubs := members.filter(func(m: Dictionary) -> bool: return float(m.age) < 1.0).size()
	var near := is_instance_valid(player) and _flat_dist(player.global_position, den) <= GameConstants.CUB_ALARM_RADIUS
	return { prey_count = prey, buildings_in_territory = buildings, player_near_den = near, cubs = cubs }


func _nearest_kingdom(pos: Vector3) -> Dictionary:
	var best := {}
	var best_d := GameConstants.RAID_RANGE
	for k in _state.kingdoms():
		var d := _flat_dist(k.center, pos)
		if d <= best_d:
			best = k
			best_d = d
	return best


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## "Cerca", "Cerca e Poço", "Cerca, Poço e Fogueira".
static func _join(names: Array[String]) -> String:
	if names.size() == 1:
		return names[0]
	return ", ".join(names.slice(0, names.size() - 1)) + " e " + names[-1]


## Strength of a summarized raid after the kingdom's guards fight back.
static func raid_strength(base: float, guards: int) -> float:
	return base * maxf(GameConstants.GUARD_RAID_FLOOR, 1.0 - guards * GameConstants.GUARD_RAID_REDUCTION)
