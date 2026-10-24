extends GameTest

var _sun: DirectionalLight3D
var _env: Environment
var _sky: ProceduralSkyMaterial


func _make() -> DayNight:
	_sun = DirectionalLight3D.new()
	add_child(_sun)
	_env = Environment.new()
	_sky = ProceduralSkyMaterial.new()
	var dn := DayNight.new()
	dn.setup(_sun, _env, _sky)
	add_child(dn)
	dn.set_process(false) # tests drive time explicitly
	return dn


func _at(dn: DayNight, t: float) -> void:
	dn.time_of_day = t
	dn.apply()


func test_noon_brighter_than_midnight() -> void:
	var dn := _make()
	_at(dn, 0.5)
	var noon_sun := _sun.light_energy
	var noon_ambient := _env.ambient_light_energy
	_at(dn, 0.0)
	assert_true(noon_sun > _sun.light_energy, "sun noon %.2f vs midnight %.2f" % [noon_sun, _sun.light_energy])
	assert_true(noon_ambient > _env.ambient_light_energy)
	assert_true(_env.ambient_light_energy >= GameConstants.NIGHT_MIN_AMBIENT - 0.001, "night too dark")


func test_sky_darker_at_night() -> void:
	var dn := _make()
	_at(dn, 0.5)
	var day_top := _sky.sky_top_color.get_luminance()
	_at(dn, 0.0)
	assert_true(_sky.sky_top_color.get_luminance() < day_top * 0.5)


func test_wraps_and_counts_days() -> void:
	var dn := _make()
	dn.time_of_day = 0.9
	dn.day = 1
	dn.advance(0.2 * GameConstants.DAY_LENGTH_SEC)
	assert_near(dn.time_of_day, 0.1, 0.0001)
	assert_eq(dn.day, 2)


func test_clock_text() -> void:
	var dn := _make()
	dn.day = 2
	dn.time_of_day = 0.5
	assert_eq(dn.clock_text(), "Dia 2 · 12:00")
	dn.time_of_day = 0.25 + 0.5 / 24.0
	assert_eq(dn.clock_text(), "Dia 2 · 06:30")


func test_sun_points_down_at_noon() -> void:
	var dn := _make()
	_at(dn, 0.5)
	assert_true((-_sun.global_transform.basis.z).y < -0.5, "sun dir %s" % -_sun.global_transform.basis.z)
	assert_true(dn.sun_elevation() > 0.99)
	_at(dn, 0.0)
	assert_true(dn.sun_elevation() < -0.99)
