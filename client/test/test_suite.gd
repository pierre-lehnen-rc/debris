extends Node

## Minimal stand-in for GdUnit4's GdUnitTestSuite, so the test suites run through
## the project's own headless runner (test/runner.gd) without vendoring the
## GdUnit4 addon. It reimplements only the API the suites actually use:
##
##   assert_str / assert_bool / assert_int / assert_float / assert_array /
##   assert_dict / assert_object  -> a fluent assertion with is_equal, is_true,
##   is_false, is_null, is_not_null, is_empty, is_not_empty, has_size, contains,
##   contains_keys, is_equal_approx, is_instanceof, override_failure_message
##
##   assert_signal(obj).wait_until(ms).is_emitted/is_not_emitted(name[, arg])
##   monitor_signals(obj)
##   auto_free(obj) / add_child(node) / create_temp_dir(name)
##   before_test() / after_test()  (override in a suite)
##
## The runner resets the per-test state, invokes each test_* method, then calls
## _cleanup(). Assertions record into __failures, which the runner reads.

# Per-test state, managed by the runner. -------------------------------------
var __failures: Array = []
var __asserts: int = 0
var _to_free: Array = []
var _temp_dirs: Array = []
var _sig_counts: Dictionary = {}
var _sig_first_arg: Dictionary = {}
var _sig_conns: Array = []


# Overridable lifecycle -------------------------------------------------------
func before_test() -> void:
	pass


func after_test() -> void:
	pass


# Assertion entry points ------------------------------------------------------
func assert_str(v: Variant) -> Assertion: return Assertion.new(v, self)
func assert_bool(v: Variant) -> Assertion: return Assertion.new(v, self)
func assert_int(v: Variant) -> Assertion: return Assertion.new(v, self)
func assert_float(v: Variant) -> Assertion: return Assertion.new(v, self)
func assert_array(v: Variant) -> Assertion: return Assertion.new(v, self)
func assert_dict(v: Variant) -> Assertion: return Assertion.new(v, self)
func assert_object(v: Variant) -> Assertion: return Assertion.new(v, self)


func assert_signal(obj: Object) -> SignalAssertion:
	return SignalAssertion.new(obj, self)


# Helpers ---------------------------------------------------------------------
## Register an object to be freed after the current test.
func auto_free(obj: Variant) -> Variant:
	_to_free.append(obj)
	return obj


## A unique, auto-cleaned temp directory; returns its absolute (OS) path.
func create_temp_dir(name: String) -> String:
	var rel := "user://__test_tmp/%s_%d" % [name, _temp_dirs.size() + Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(rel)
	_temp_dirs.append(rel)
	return ProjectSettings.globalize_path(rel)


## Record every emission of every signal on `obj` from now until test end.
func monitor_signals(obj: Object) -> void:
	for s in obj.get_signal_list():
		var sname: String = s["name"]
		var argc: int = (s["args"] as Array).size()
		_sig_counts[sname] = 0
		var cb: Callable
		if argc == 0:
			cb = Callable(self, "_on_sig_0").bind(sname)
		elif argc == 1:
			cb = Callable(self, "_on_sig_1").bind(sname)
		else:
			continue  # signals with >1 arg aren't monitored (none are needed)
		obj.connect(sname, cb)
		_sig_conns.append([obj, sname, cb])


func _on_sig_0(sname: String) -> void:
	_sig_counts[sname] = int(_sig_counts.get(sname, 0)) + 1


func _on_sig_1(arg: Variant, sname: String) -> void:
	_sig_counts[sname] = int(_sig_counts.get(sname, 0)) + 1
	_sig_first_arg[sname] = arg


# Recording + cleanup (called by the runner) ---------------------------------
func _record(passed: bool, detail: String) -> void:
	__asserts += 1
	if not passed:
		__failures.append(detail)


func _reset_test() -> void:
	__failures = []
	__asserts = 0
	_to_free = []
	_temp_dirs = []
	_sig_counts = {}
	_sig_first_arg = {}
	_sig_conns = []


func _cleanup() -> void:
	for entry in _sig_conns:
		var obj: Object = entry[0]
		if is_instance_valid(obj) and obj.is_connected(entry[1], entry[2]):
			obj.disconnect(entry[1], entry[2])
	_sig_conns = []
	for o in _to_free:
		if o is Node and is_instance_valid(o):
			o.free()
	_to_free = []
	for rel in _temp_dirs:
		_rm_rf(rel)
	_temp_dirs = []


func _rm_rf(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := path.path_join(name)
		if dir.current_is_dir():
			_rm_rf(full)
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(full))
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# Fluent value assertion ------------------------------------------------------
class Assertion:
	var _v: Variant
	var _suite: Object
	var _msg: String = ""

	func _init(value: Variant, suite: Object) -> void:
		_v = value
		_suite = suite

	func override_failure_message(msg: String) -> Assertion:
		_msg = msg
		return self

	func _check(passed: bool, detail: String) -> Assertion:
		_suite._record(passed, _msg if not _msg.is_empty() else detail)
		return self

	func is_equal(expected: Variant) -> Assertion:
		return _check(_v == expected, "expected %s, got %s" % [expected, _v])

	func is_not_equal(expected: Variant) -> Assertion:
		return _check(_v != expected, "expected not %s" % [expected])

	func is_true() -> Assertion:
		return _check(_v == true, "expected true, got %s" % [_v])

	func is_false() -> Assertion:
		return _check(_v == false, "expected false, got %s" % [_v])

	func is_null() -> Assertion:
		return _check(_v == null, "expected null, got %s" % [_v])

	func is_not_null() -> Assertion:
		return _check(_v != null, "expected non-null")

	func is_empty() -> Assertion:
		return _check(_is_empty(_v), "expected empty, got %s" % [_v])

	func is_not_empty() -> Assertion:
		return _check(not _is_empty(_v), "expected non-empty")

	func has_size(n: int) -> Assertion:
		return _check(_size(_v) == n, "expected size %d, got %d" % [n, _size(_v)])

	func contains(expected: Variant) -> Assertion:
		return _check(_contains(_v, expected), "expected %s to contain %s" % [_v, expected])

	func contains_keys(keys: Array) -> Assertion:
		var ok := _v is Dictionary
		if ok:
			for k in keys:
				if not (_v as Dictionary).has(k):
					ok = false
					break
		return _check(ok, "expected %s to contain keys %s" % [_v, keys])

	func is_equal_approx(expected: float, eps: float) -> Assertion:
		return _check(absf(float(_v) - expected) <= eps,
			"expected ~%s (±%s), got %s" % [expected, eps, _v])

	func is_instanceof(type: Variant) -> Assertion:
		return _check(is_instance_of(_v, type), "expected instance of %s, got %s" % [type, _v])

	func _is_empty(v: Variant) -> bool:
		if v is String or v is Array or v is Dictionary or v is PackedStringArray:
			return v.is_empty()
		return v == null

	func _size(v: Variant) -> int:
		if v is String or v is Array or v is Dictionary or v is PackedStringArray:
			return v.size() if not (v is String) else (v as String).length()
		return -1

	func _contains(container: Variant, expected: Variant) -> bool:
		if container is String:
			return (container as String).contains(str(expected))
		if container is Array:
			if expected is Array:
				for e in expected:
					if not (container as Array).has(e):
						return false
				return true
			return (container as Array).has(expected)
		return false


# Signal assertion ------------------------------------------------------------
class SignalAssertion:
	var _obj: Object
	var _suite: Object
	var _wait_ms: int = 0

	func _init(obj: Object, suite: Object) -> void:
		_obj = obj
		_suite = suite

	func wait_until(ms: int) -> SignalAssertion:
		_wait_ms = ms
		return self

	func is_emitted(name: String, expected_arg: Variant = null) -> void:
		await _settle()
		var count: int = int(_suite._sig_counts.get(name, 0))
		var ok := count > 0
		if ok and expected_arg != null:
			ok = _suite._sig_first_arg.get(name) == expected_arg
		_suite._record(ok, "expected signal '%s' to be emitted" % name)

	func is_not_emitted(name: String) -> void:
		await _settle()
		var count: int = int(_suite._sig_counts.get(name, 0))
		_suite._record(count == 0, "expected signal '%s' NOT to be emitted (got %d)" % [name, count])

	func _settle() -> void:
		var tree := (_suite as Node).get_tree()
		if _wait_ms > 0:
			await tree.create_timer(_wait_ms / 1000.0).timeout
		else:
			await tree.process_frame
