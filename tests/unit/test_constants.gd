extends GameTest


func test_map_fits_spawn_margin() -> void:
	assert_true(GameConstants.SPAWN_EDGE_MARGIN * 2.0 < GameConstants.MAP_CHUNKS * GameConstants.CHUNK_SIZE)


func test_run_faster_than_walk() -> void:
	assert_true(GameConstants.RUN_SPEED > GameConstants.WALK_SPEED)


func test_runner_reports_failure_sanity() -> void:
	assert_eq(1 + 1, 2)
