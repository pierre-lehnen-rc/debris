extends "res://dev/check_base.gd"

## Unit check for ServerManager.await_ready() — the readiness gate that keeps the
## first Backend requests after a cold launch from racing server startup.
##
## Exercised on bare script instances (never added to the tree, so _ready/_start
## don't fire and no network is touched); we drive _finish_startup() by hand and
## assert await_ready() resolves as specified.

# server_manager.gd references the Backend autoload, so it can't be preload()ed
# here — the `-s` main-loop script compiles before autoloads register. Load it at
# runtime (inside _run), by which point they exist.
var _script: GDScript = null


func _run() -> void:
	# load() at runtime (not preload) so the autoload globals are already registered.
	_script = load("res://source/data/server_manager.gd")
	await _resolves_true_when_available()
	await _resolves_false_when_unavailable()
	await _is_idempotent()
	await _pending_waiter_unblocks_on_resolve()


## Once startup resolves as available, await_ready() returns true immediately.
func _resolves_true_when_available() -> void:
	var sm: Object = _script.new()
	sm._finish_startup(true)
	expect(await sm.await_ready() == true, "await_ready true after resolved available")
	sm.free()


## A give-up (Node missing, poll exhausted) resolves false — the caller then makes
## its request and fails with a clear error, exactly as before the gate existed.
func _resolves_false_when_unavailable() -> void:
	var sm: Object = _script.new()
	sm._finish_startup(false)
	expect(await sm.await_ready() == false, "await_ready false after resolved unavailable")
	sm.free()


## Only the first _finish_startup wins, so a late failure path can't flip an
## earlier success (and repeated await_ready() calls stay stable).
func _is_idempotent() -> void:
	var sm: Object = _script.new()
	sm._finish_startup(true)
	sm._finish_startup(false)
	expect(await sm.await_ready() == true, "first resolution wins over a later one")
	expect(await sm.await_ready() == true, "await_ready is repeatable")
	sm.free()


## A caller that starts waiting before startup resolves stays blocked, then
## unblocks with the resolved value — the actual cold-start scenario.
func _pending_waiter_unblocks_on_resolve() -> void:
	var sm: Object = _script.new()
	var box := {"done": false, "value": null}
	_wait_for(sm, box)  # fire-and-forget coroutine; suspends inside await_ready()
	expect(box["done"] == false, "waiter stays blocked until startup resolves")
	sm._finish_startup(true)
	# Signal-driven resume is synchronous, but settle a frame to be safe.
	await create_timer(0.05).timeout
	expect(box["done"] == true, "pending waiter unblocks once startup resolves")
	expect(box["value"] == true, "pending waiter receives the resolved value")
	sm.free()


func _wait_for(sm: Object, box: Dictionary) -> void:
	box["value"] = await sm.await_ready()
	box["done"] = true
