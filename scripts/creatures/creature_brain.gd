class_name CreatureBrain
extends RefCounted
## Pure decision function: given what a creature knows about itself (`me`) and what it senses
## (`ctx.nearby`), returns what it wants to do. No nodes, so every rule is unit-testable.
##
## me: {id, genome, pos, hp_ratio, hunger, is_night, pack_leader_pos (Vector3 or null), den_pos,
##      mate ({id, pos} or {}), raid_target ({id, pos} or {}), hostile_to_player, wander_pos?}
## ctx.nearby: Array of {id, kind ("creature" | "player"), pos, diet, species, is_cub}

enum State { WANDER, GRAZE, HUNT, ATTACK, FLEE, SLEEP, FOLLOW, MATE, RAID, RETURN }

const _TARGET_RADIUS := 0.5 ## Rough body radius of whatever is being bitten.


static func decide(me: Dictionary, ctx: Dictionary) -> Dictionary:
	var g: Dictionary = me.genome
	var pos: Vector3 = me.pos
	var perception: float = g.perception
	var nearby: Array = ctx.get("nearby", [])
	var carnivore: bool = g.diet == GameConstants.Diet.CARNIVORE

	var threat := _nearest(pos, nearby, func(o: Dictionary) -> bool: return _is_threat(me, o), perception)
	if me.hp_ratio < GameConstants.FLEE_HP_RATIO:
		var danger := _nearest(pos, nearby, func(o: Dictionary) -> bool:
			return o.kind == "player" or (o.diet == GameConstants.Diet.CARNIVORE and o.species != g.species), perception)
		if not danger.is_empty():
			return _flee(pos, danger)

	var sleepy: bool = g.nocturnal != me.is_night
	if sleepy and me.raid_target.is_empty():
		if threat.is_empty() or pos.distance_to(threat.pos) > perception * GameConstants.WAKE_SHARE:
			return _result(State.SLEEP, pos)

	var player := _nearest(pos, nearby, func(o: Dictionary) -> bool: return o.kind == "player", perception)
	if not player.is_empty() and me.hostile_to_player:
		return _chase(me, player)
	if not me.raid_target.is_empty():
		return _result(State.RAID, me.raid_target.pos, me.raid_target.id)

	if not carnivore:
		if not player.is_empty() and g.aggression >= GameConstants.PLAYER_DEFENSE_AGGRESSION \
				and pos.distance_to(player.pos) <= perception * GameConstants.PLAYER_DEFENSE_SHARE:
			return _chase(me, player)
		if not threat.is_empty() and pos.distance_to(threat.pos) <= perception * GameConstants.THREAT_SHARE:
			return _flee(pos, threat)
	else:
		if me.hunger >= GameConstants.HUNT_HUNGER:
			var prey := _nearest(pos, nearby, func(o: Dictionary) -> bool:
				return o.kind == "creature" and o.diet == GameConstants.Diet.HERBIVORE, perception)
			if not prey.is_empty():
				return _chase(me, prey)
		if g.territorial and g.aggression >= GameConstants.TERRITORY_FIGHT_AGGRESSION:
			var rival := _nearest(pos, nearby, func(o: Dictionary) -> bool:
				return o.kind == "creature" and o.diet == GameConstants.Diet.CARNIVORE and o.species != g.species,
				perception * GameConstants.TERRITORY_FIGHT_SHARE)
			if not rival.is_empty():
				return _chase(me, rival)

	if not me.mate.is_empty():
		return _result(State.MATE, me.mate.pos, me.mate.id)
	if me.pack_leader_pos != null and pos.distance_to(me.pack_leader_pos) > GameConstants.FOLLOW_DISTANCE:
		return _result(State.FOLLOW, me.pack_leader_pos)
	if not carnivore and me.hunger >= GameConstants.GRAZE_HUNGER:
		return _result(State.GRAZE, pos)
	return _result(State.WANDER, me.get("wander_pos", pos))


static func attack_reach(g: Dictionary) -> float:
	return GameConstants.CREATURE_ATTACK_RANGE * float(g.size) + _TARGET_RADIUS


static func _is_threat(me: Dictionary, o: Dictionary) -> bool:
	if me.genome.diet == GameConstants.Diet.CARNIVORE:
		return false
	return o.kind == "player" or (o.kind == "creature" and o.diet == GameConstants.Diet.CARNIVORE)


static func _chase(me: Dictionary, target: Dictionary) -> Dictionary:
	var dist: float = (me.pos as Vector3).distance_to(target.pos)
	return _result(State.ATTACK if dist <= attack_reach(me.genome) else State.HUNT, target.pos, target.id)


static func _flee(pos: Vector3, threat: Dictionary) -> Dictionary:
	var away: Vector3 = pos - threat.pos
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = Vector3.FORWARD
	return _result(State.FLEE, pos + away.normalized() * GameConstants.FLEE_DISTANCE, threat.id)


static func _nearest(pos: Vector3, nearby: Array, accept: Callable, max_dist: float) -> Dictionary:
	var best := {}
	var best_d := max_dist
	for o: Dictionary in nearby:
		var d := pos.distance_to(o.pos)
		if d <= best_d and accept.call(o):
			best = o
			best_d = d
	return best


static func _result(state: State, target_pos: Vector3, target_id := -1) -> Dictionary:
	return { state = state, target_pos = target_pos, target_id = target_id }
