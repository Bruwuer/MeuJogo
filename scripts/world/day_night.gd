class_name DayNight
extends Node
## Day/night cycle: moves the sun and blends sun, sky and ambient light between day, dusk and
## night. time_of_day is 0 at midnight, 0.25 at sunrise, 0.5 at noon, 0.75 at sunset.

var time_of_day := GameConstants.START_TIME_OF_DAY
var day := 1
## Under rain clouds (stage 11): dimmer sun, grey sky.
var overcast := false

var _sun: DirectionalLight3D
var _env: Environment
var _sky: ProceduralSkyMaterial


func setup(sun: DirectionalLight3D, env: Environment, sky: ProceduralSkyMaterial) -> void:
	_sun = sun
	_env = env
	_sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	apply()


func _process(delta: float) -> void:
	advance(delta)


func advance(seconds: float) -> void:
	time_of_day += seconds / GameConstants.DAY_LENGTH_SEC
	while time_of_day >= 1.0:
		time_of_day -= 1.0
		day += 1
	apply()


## 1 at noon, 0 at sunrise/sunset, -1 at midnight.
func sun_elevation() -> float:
	return sin((time_of_day - 0.25) * TAU)


func apply() -> void:
	var e := sun_elevation()
	var daylight := smoothstep(-0.15, 0.3, e) # 0 night .. 1 day
	var sun_up := clampf(e * 2.0, 0.0, 1.0)
	var dusk := clampf(1.0 - absf(e) * 3.0, 0.0, 1.0) # peaks at sunrise/sunset

	# The same light is the sun by day and the moon by night. Pitch follows the arc:
	# horizontal at sunrise/sunset, straight down at noon (sun) and midnight (moon).
	var yaw := deg_to_rad(GameConstants.SUN_YAW_DEG)
	if e >= 0.0:
		_sun.rotation = Vector3(-(time_of_day - 0.25) * TAU, yaw, 0.0)
		_sun.light_energy = GameConstants.SUN_MAX_ENERGY * sun_up
		_sun.light_color = GameConstants.SUN_DUSK_COLOR.lerp(GameConstants.SUN_DAY_COLOR, sun_up)
	else:
		var moon_up := clampf(-e * 2.0, 0.0, 1.0)
		_sun.rotation = Vector3(-(time_of_day - 0.75) * TAU, yaw, 0.0)
		_sun.light_energy = GameConstants.MOON_ENERGY * moon_up
		_sun.light_color = GameConstants.MOON_COLOR
	_sun.shadow_enabled = _sun.light_energy > 0.0

	_sky.sky_top_color = GameConstants.SKY_NIGHT_TOP.lerp(GameConstants.SKY_DAY_TOP, daylight)
	var horizon := GameConstants.SKY_NIGHT_HORIZON.lerp(GameConstants.SKY_DAY_HORIZON, daylight)
	horizon = horizon.lerp(GameConstants.SKY_DUSK_HORIZON, dusk * 0.8)
	_sky.sky_horizon_color = horizon
	_sky.ground_horizon_color = horizon

	if overcast:
		_sun.light_energy *= GameConstants.RAIN_DIM
		_sky.sky_top_color = _sky.sky_top_color.lerp(GameConstants.RAIN_SKY, 0.6 * daylight)
		_sky.sky_horizon_color = _sky.sky_horizon_color.lerp(GameConstants.RAIN_SKY, 0.6 * daylight)
		_sky.ground_horizon_color = _sky.sky_horizon_color
	_env.ambient_light_color = GameConstants.AMBIENT_NIGHT_COLOR.lerp(GameConstants.AMBIENT_DAY_COLOR, daylight)
	_env.ambient_light_energy = lerpf(GameConstants.NIGHT_MIN_AMBIENT, GameConstants.DAY_AMBIENT, daylight)


func clock_text() -> String:
	var minutes := int(round(time_of_day * 24.0 * 60.0)) % (24 * 60)
	return "Dia %d · %02d:%02d" % [day, minutes / 60, minutes % 60]


func is_night() -> bool:
	return sun_elevation() < 0.0


## Game hours since the start of day 0 (keeps growing across days).
func total_hours() -> float:
	return (day + time_of_day) * 24.0
