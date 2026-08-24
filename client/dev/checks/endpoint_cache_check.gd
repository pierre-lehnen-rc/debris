extends "res://dev/check_base.gd"

## Validates EndpointSidebar's cache-aware load order — the behaviour that lets the
## endpoint list load even when the Rocket.Chat workspace is down:
##
##   1. live reachable + cache present -> show cache immediately, then the live spec;
##   2. live down + cache present      -> keep the cache (never blank, never builtin);
##   3. live down + no cache           -> fall back to the built-in catalog.
##
## The default RocketChat mock always serves the OpenAPI doc, so a failing stub is
## swapped in to simulate a down server. See source/ui/workspace/endpoint_sidebar.gd

# Loaded at runtime, not preloaded: the sidebar's script references the RocketChat
# autoload, which isn't registered yet when this -s main-loop script is compiled.
const SIDEBAR_PATH := "res://source/ui/workspace/endpoint_sidebar.tscn"
const WORKSPACE := {"url": "https://chat.example", "users": []}


## A RocketChat mock whose OpenAPI fetch fails, standing in for an unreachable server.
class FailMock:
	func respond(_method: int, _path: String, _query: Dictionary, _body: Dictionary) -> Dictionary:
		return {"ok": false, "data": null, "error": "server down", "status": 0}


func _run() -> void:
	await _case_live_with_cache()
	await _case_down_with_cache()
	await _case_down_without_cache()


# 1. Live reachable, cache present: cache shows first, then the live spec wins.
func _case_live_with_cache() -> void:
	var events: Array = []
	var sb: Variant = _sidebar([ApiEndpoint.from_dict({"id": "cached.one"})], events)
	sb.configure(WORKSPACE)
	await _settle()
	expect(events.has("cache"), "live+cache: cache is emitted first")
	expect(events.has("live"), "live+cache: live is emitted after a successful fetch")
	expect(events.back() == "live", "live+cache: live is the final source")
	expect(sb.endpoints().size() > 1, "live+cache: the live spec (many endpoints) replaces the 1-item cache")
	sb.queue_free()


# 2. Server down, cache present: the cache is kept — never blanked, never builtin.
func _case_down_with_cache() -> void:
	var events: Array = []
	var sb: Variant = _sidebar([
		ApiEndpoint.from_dict({"id": "cached.one"}),
		ApiEndpoint.from_dict({"id": "cached.two"}),
	], events)
	var restore = rocketchat._mock
	rocketchat._mock = FailMock.new()
	sb.configure(WORKSPACE)
	await _settle()
	rocketchat._mock = restore
	expect_eq(events, ["cache"], "down+cache: only the cache source is emitted")
	expect_eq(sb.endpoints().size(), 2, "down+cache: the cached endpoints are kept")
	sb.queue_free()


# 3. Server down, no cache: fall back to the shipped catalog so the list isn't empty.
func _case_down_without_cache() -> void:
	var events: Array = []
	var sb: Variant = _sidebar([], events)
	var restore = rocketchat._mock
	rocketchat._mock = FailMock.new()
	sb.configure(WORKSPACE)
	await _settle()
	rocketchat._mock = restore
	expect_eq(events, ["builtin"], "down+no-cache: the builtin source is emitted")
	expect(sb.endpoints().size() > 0, "down+no-cache: the built-in catalog is shown")
	sb.queue_free()


# Helpers ---------------------------------------------------------------------
# Untyped (EndpointSidebar as a type would pull its RocketChat-referencing script
# into this script's compile, which fails before autoloads register).
func _sidebar(cache: Array, events: Array) -> Variant:
	var sb = load(SIDEBAR_PATH).instantiate()
	root.add_child(sb)
	sb.set_cache(cache)
	sb.endpoints_loaded.connect(func(_eps: Array, source: String) -> void: events.append(source))
	return sb


## Let the async _load coroutine run to completion (the mock resolves within a
## handful of idle frames).
func _settle() -> void:
	for _i in 12:
		await process_frame
