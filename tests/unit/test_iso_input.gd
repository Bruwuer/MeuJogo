extends GameTest


func test_up_yaw0() -> void:
	assert_true(IsoInput.to_world(Vector2(0, -1), 0).is_equal_approx(Vector3(0, 0, -1)))


func test_right_yaw0() -> void:
	assert_true(IsoInput.to_world(Vector2(1, 0), 0).is_equal_approx(Vector3(1, 0, 0)))


func test_up_yaw45() -> void:
	assert_true(IsoInput.to_world(Vector2(0, -1), 45).is_equal_approx(Vector3(-0.70710678, 0, -0.70710678)))


func test_right_yaw45() -> void:
	assert_true(IsoInput.to_world(Vector2(1, 0), 45).is_equal_approx(Vector3(0.70710678, 0, -0.70710678)))


func test_diagonal_is_normalized() -> void:
	assert_true(IsoInput.to_world(Vector2(1, -1), 45).length() <= 1.0001)


func test_no_input_is_zero() -> void:
	assert_eq(IsoInput.to_world(Vector2.ZERO, 45), Vector3.ZERO)
