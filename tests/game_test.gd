class_name GameTest
extends Node
## Base class for tests run by tests/run_tests.gd.

var failures: Array[String] = []


func assert_true(cond: bool, msg := "") -> void:
	if not cond:
		failures.append(msg if msg != "" else "assert_true failed")


func assert_eq(a: Variant, b: Variant, msg := "") -> void:
	if a != b:
		failures.append("%sexpected %s == %s" % [msg + ": " if msg != "" else "", str(a), str(b)])


func assert_near(a: float, b: float, eps: float, msg := "") -> void:
	if absf(a - b) > eps:
		failures.append("%sexpected %f ≈ %f (±%f)" % [msg + ": " if msg != "" else "", a, b, eps])


func wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func wait_physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
