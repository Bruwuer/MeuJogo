class_name Deeds
extends RefCounted
## Deeds (stage 7): a House decision is carried out by a person who walks to a place inside an hour
## window and works there for a while; only then the decision takes effect (HouseSim.complete_deed).
## Without a node the deed is settled as a summary at its start hour.
##
## deed: {kind, pos, reach, start_hour, end_hour, work_sec, data}


static func make(kind: String, pos: Vector3, reach: float, start_hour: float, end_hour: float, work_sec: float,
		data := {}) -> Dictionary:
	return {kind = kind, pos = pos, reach = reach, start_hour = start_hour, end_hour = end_hour, work_sec = work_sec,
			data = data}


static func is_due(deed: Dictionary, hour: float) -> bool:
	return not deed.is_empty() and hour >= float(deed.start_hour) and hour < float(deed.end_hour)


static func expired(deed: Dictionary, hour: float) -> bool:
	return not deed.is_empty() and hour >= float(deed.end_hour)


## Start and end (total hours) of the window [from_h, to_h) of the day that contains `hour` or comes
## next. A window may cross midnight (23 -> 3).
static func next_window(hour: float, from_h: float, to_h: float) -> Vector2:
	var length := fmod(to_h - from_h + 24.0, 24.0)
	var start := floorf(hour / 24.0) * 24.0 + from_h
	if start - 24.0 + length > hour: # yesterday's window is still open (after midnight)
		start -= 24.0
	elif start + length <= hour:
		start += 24.0
	return Vector2(start, start + length)


## Chance that someone notices a secret deed done offscreen, with `awake` outsiders around.
static func seen_chance(awake: int) -> float:
	return 1.0 - pow(1.0 - GameConstants.DEED_SEEN_PER_WATCHER, maxi(0, awake))
