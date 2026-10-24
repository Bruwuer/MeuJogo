class_name PersonBrain
extends RefCounted
## Pure decision of what a person does next. `decide` returns the goal and where it happens;
## while the person is not there yet, `act` is WALK (the goal stays in `goal`).
##
## me: {pos, status ("traveler" | "resident" | "leaving"), job, carrying, home_pos, door_pos
##      (Vector3 or null), is_work_time, is_sleep_time, raid, threat_pos (Vector3 or null),
##      idle_offset (optional Vector3, spreads people around the seat), deed ({pos, reach} or null:
##      a House errand due now, see Deeds)}
## ctx: {work_target ({pos, reach} or {}), deposit_pos, seat_pos, campfire_pos (or null), exit_pos}

enum Act { IDLE, WALK, WORK, SLEEP, FLEE, ENTER, DEPOSIT, EVALUATE, LEAVE, DEED }


static func decide(me: Dictionary, ctx: Dictionary) -> Dictionary:
	var pos: Vector3 = me.pos
	if me.threat_pos != null:
		var away: Vector3 = pos - (me.threat_pos as Vector3)
		away.y = 0.0
		if away.length() < 0.01:
			away = Vector3.FORWARD
		return {act = Act.FLEE, goal = Act.FLEE, target_pos = pos + away.normalized() * GameConstants.PERSON_FLEE_DIST}
	var offset: Vector3 = me.get("idle_offset", Vector3.ZERO)
	match me.status:
		"traveler":
			return _go(pos, Act.EVALUATE, ctx.seat_pos, GameConstants.PERSON_SEAT_RADIUS)
		"leaving":
			return _go(pos, Act.LEAVE, ctx.exit_pos, GameConstants.PERSON_ARRIVE * 3.0)
	var deed: Variant = me.get("deed")
	if deed != null:
		return _go(pos, Act.DEED, deed.pos, float(deed.reach))
	if me.raid:
		if me.door_pos != null:
			return _go(pos, Act.ENTER, me.door_pos, GameConstants.PERSON_ARRIVE)
		return _go(pos, Act.IDLE, ctx.seat_pos + offset.limit_length(2.0), GameConstants.PERSON_ARRIVE * 2.0)
	if me.is_sleep_time:
		if me.door_pos != null:
			return _go(pos, Act.ENTER, me.door_pos, GameConstants.PERSON_ARRIVE)
		var fire: Vector3 = ctx.campfire_pos if ctx.campfire_pos != null else ctx.seat_pos
		var spot := fire + offset.limit_length(GameConstants.PERSON_FIRE_SLEEP_RADIUS * 0.8)
		return _go(pos, Act.SLEEP, spot, GameConstants.PERSON_FIRE_SLEEP_RADIUS)
	if not (me.carrying as Dictionary).is_empty():
		return _go(pos, Act.DEPOSIT, ctx.deposit_pos, GameConstants.PERSON_ARRIVE)
	var work: Dictionary = ctx.work_target
	if me.is_work_time and not work.is_empty():
		return _go(pos, Act.WORK, work.pos, float(work.reach))
	return _go(pos, Act.IDLE, ctx.seat_pos + offset, GameConstants.PERSON_IDLE_RADIUS)


static func _go(pos: Vector3, goal: Act, target: Vector3, reach: float) -> Dictionary:
	var d := Vector2(target.x - pos.x, target.z - pos.z).length()
	return {act = goal if d <= reach else Act.WALK, goal = goal, target_pos = target}
