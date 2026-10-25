class_name WeatherSim
extends RefCounted
## Rainy days (stage 11), run by VillageSim once per hour: every morning a seeded draw decides
## whether it rains that day, from when and for how long. While it rains, people go under a roof,
## work outdoors goes slower, and the world looks grey (World shows the drops).


var _state: WorldState


func setup(state: WorldState) -> void:
	_state = state


func tick_hour(hour: float) -> void:
	if int(fmod(hour, 24.0)) != int(GameConstants.RAIN_DECIDE_HOUR):
		return
	var day := floori(hour / 24.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_state.seed, "rain", day])
	if rng.randf() >= GameConstants.RAIN_CHANCE:
		return
	var start := day * 24.0 + rng.randi_range(GameConstants.RAIN_START.x, GameConstants.RAIN_START.y)
	_state.rain_from = start
	_state.rain_until = start + rng.randi_range(GameConstants.RAIN_HOURS.x, GameConstants.RAIN_HOURS.y)
