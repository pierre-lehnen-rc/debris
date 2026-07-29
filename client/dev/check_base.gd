extends SceneTree

## Base for headless validation checks. A check extends this, implements _run(),
## and uses the expect_* helpers; the base handles booting, reporting, and the
## process exit code (0 = all passed, 1 = a failure or a script error).
##
## Run one with:  dev/harness.sh dev/checks/<name>.gd
##
## The project boots with DEBRIS_HEADLESS=1 (set by dev/harness.sh), so the
## ServerManager autoload stays quiet and Backend/RocketChat answer from the
## fixture mocks under dev/mocks/. Autoloads are reached by their global names
## (Backend, RocketChat, ActivityLog) just like in the running app.

## The app's autoloads, resolved from the tree at runtime. A `-s` main-loop
## script is compiled before autoload globals are registered, so the bare names
## (Backend, RocketChat, …) can't be used at compile time — reach them through
## these instead. Left untyped so their methods dispatch dynamically.
var backend
var rocketchat
var activity_log

var _passes := 0
var _failures: Array[String] = []
var _started := false


func _process(_delta: float) -> bool:
	# Run once, on the first frame — by now every autoload's _ready() has fired,
	# so Backend/RocketChat have picked up their mocks.
	if _started:
		return false
	_started = true
	backend = root.get_node_or_null("Backend")
	rocketchat = root.get_node_or_null("RocketChat")
	activity_log = root.get_node_or_null("ActivityLog")
	_run_all()
	return false  # _run_all() calls quit() when done.


func _run_all() -> void:
	print("── %s ──" % get_script().resource_path.get_file())
	await _run()
	print("  %d passed, %d failed" % [_passes, _failures.size()])
	if _failures.is_empty():
		print("PASS")
		quit(0)
	else:
		print("FAIL")
		quit(1)


## Override in the check. May be a coroutine (use `await`).
func _run() -> void:
	push_error("check did not override _run()")


# Assertions ------------------------------------------------------------------
func expect(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
	else:
		_failures.append(msg)
		printerr("  FAIL: %s" % msg)


func expect_eq(actual: Variant, expected: Variant, msg: String) -> void:
	expect(actual == expected, "%s — expected %s, got %s" % [msg, expected, actual])
