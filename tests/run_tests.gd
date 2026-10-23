extends SceneTree
## Headless test runner.
## Usage: godot --headless -s res://tests/run_tests.gd [-- <filter> ...]
## Runs every test_* method of every tests/{unit,integration}/test_*.gd file.
## A test fails on a failed assert or on any script/engine error logged while it runs.

const TEST_DIRS := ["res://tests/unit", "res://tests/integration"]


class ErrorCollector extends Logger:
	var _mutex := Mutex.new()
	var _errors: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		_errors.append("%s (%s:%d in %s)" % [rationale if rationale != "" else code, file, line, function])
		_mutex.unlock()

	func take() -> PackedStringArray:
		_mutex.lock()
		var out := _errors
		_errors = []
		_mutex.unlock()
		return out


var _passed := 0
var _failed := 0
var _collector := ErrorCollector.new()


func _initialize() -> void:
	OS.add_logger(_collector)
	_run.call_deferred()


func _run() -> void:
	var filters := OS.get_cmdline_user_args()
	for dir in TEST_DIRS:
		for path in _list_test_files(dir):
			if filters.size() > 0 and not Array(filters).any(func(f: String) -> bool: return path.contains(f)):
				continue
			await _run_file(path)
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	OS.remove_logger(_collector)
	quit(1 if _failed > 0 else 0)


func _list_test_files(dir: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir.path_join(f))
	out.sort()
	return out


func _run_file(path: String) -> void:
	_collector.take()
	var script: GDScript = load(path)
	if script == null or not script.can_instantiate():
		_report(path, "<load>", ["script failed to load"] + Array(_collector.take()))
		return
	var methods: PackedStringArray = []
	for m in script.get_script_method_list():
		var method_name: String = m["name"]
		if method_name.begins_with("test_") and not methods.has(method_name):
			methods.append(method_name)
	for method_name in methods:
		var test: Node = script.new()
		root.add_child(test)
		_collector.take()
		await test.call(method_name)
		var failures: Array = test.failures.duplicate()
		failures.append_array(Array(_collector.take()))
		test.free()
		await process_frame
		_report(path, method_name, failures)


func _report(path: String, method_name: String, failures: Array) -> void:
	var label := "%s::%s" % [path.get_file(), method_name]
	if failures.is_empty():
		_passed += 1
		print("PASS ", label)
	else:
		_failed += 1
		print("FAIL ", label, ": ", "; ".join(PackedStringArray(failures)))
