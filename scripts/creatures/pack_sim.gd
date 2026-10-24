class_name PackSim
extends Node
## Cheap hourly simulation of every pack, loaded or not: updates the motives from the world
## records (prey around the den, buildings in its territory, the player near the cubs) and starts
## raids when a motive is strong enough. Raids on kingdoms that are not loaded are summarized at
## once (buildings other than the seat take damage) and become messages for the player.

signal raid_started(pack: Dictionary, kingdom: Dictionary, motive: String)

const _RAID_MAX_HOURS := 6.0 ## A live raid that never ends on its own is called off after this.

## Messages about raids that happened away from the player (shown when the player returns).
var pending_messages: Array[String] = []
## Used when there is no DayNight (tests).
var is_night_override := false
## Set by World: whose position triggers the cubs alarm.
var player: Node3D
## kingdom -> bool; true when the kingdom is loaded and its raid is simulated live.
var kingdom_loaded: Callable = func(_k: Dictionary) -> bool: return false

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
	var center: Vector3 = kingdom.center
	var targets := _state.all_buildings().filter(func(b: Dictionary) -> bool:
		return b.id != kingdom.seat_id and b.type != GameConstants.Building.FLAG \
				and _flat_dist(b.pos, center) <= kingdom.radius)
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
	pack.raid_kingdom = kingdom.id
	pack.raid_hour = now_hours()
	var motive := PackMotives.dominant(pack)
	raid_started.emit(pack, kingdom, motive)
	if not kingdom_loaded.call(kingdom):
		resolve_offscreen_raid(pack, kingdom)


func _context(pack: Dictionary, members: Array) -> Dictionary:
	var den: Vector3 = pack.den
	var prey := 0
	for c: Dictionary in _state.all_creatures():
		if c.pack_id != pack.id and c.genome.diet == GameConstants.Diet.HERBIVORE \
				and _flat_dist(c.pos, den) <= GameConstants.PREY_RADIUS:
			prey += 1
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
