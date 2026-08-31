extends RefCounted

## Fixture-backed stand-in for a Rocket.Chat workspace's REST API, used by the
## headless validation runner (see dev/harness.sh).
##
## RocketChat routes every call through _do_request(workspace, method, path, …);
## when RocketChat._mock is set, that method calls respond() here instead of
## hitting the network. The return value matches the real client's
## { ok, data, error, status } contract, so login()/fetch_openapi() parsing runs
## unchanged.
##
## The OpenAPI document is the real spec captured from a workspace (openapi.json) —
## it drives the endpoint catalog. Endpoint result payloads don't matter, so a
## per-path fixture is returned when one exists, else a generic list envelope.

const DIR := "res://dev/mocks/rocketchat/"
const ENDPOINTS_DIR := "endpoints/"

var _cache := {}


## Answer a RocketChat request. `method` is an HTTPClient.METHOD_* constant.
## Put "offline" in a workspace's URL to make every call to it fail, the way an
## unreachable server does — the counterpart of the backend mock's "force-error"
## host, and how the checks exercise a workspace that isn't there.
func respond(
	workspace: Dictionary, _method: int, path: String, _query: Dictionary, _body: Dictionary
) -> Dictionary:
	var url := String(workspace.get("url", ""))
	if url.contains("offline"):
		return {"ok": false, "data": null, "error": "Cannot reach %s" % url, "status": 0}
	if path == "/api/docs/json":
		return _ok(_load("openapi.json"))
	if path == "/api/info":
		# What an unauthenticated caller gets from a real workspace: the version,
		# and nothing else.
		return _ok({"version": "7.4.0", "success": true})
	if path == "/api/v1/login":
		# Shape mirrors Rocket.Chat: { status, data: { authToken, userId, me } }.
		return _ok({
			"status": "success",
			"data": {
				"authToken": "mock-auth-token",
				"userId": "mock-user-id",
				"me": {"_id": "mock-user-id", "username": "admin", "name": "Administrator"},
			},
		})
	return _ok(_endpoint_payload(path))


## Fixture for an endpoint: endpoints/<path>.json when present (e.g.
## endpoints/users.list.json for /api/v1/users.list), otherwise the generic one.
func _endpoint_payload(path: String) -> Variant:
	var leaf := path.trim_prefix("/api/v1/").trim_prefix("/api/").replace("/", ".")
	var specific := ENDPOINTS_DIR + "%s.json" % leaf
	if not leaf.is_empty() and FileAccess.file_exists(DIR + specific):
		return _load(specific)
	return _load(ENDPOINTS_DIR + "_generic.json")


func _ok(data: Variant) -> Dictionary:
	return {"ok": true, "data": data, "error": "", "status": 200}


## Load and cache a fixture file relative to DIR.
func _load(name: String) -> Variant:
	if _cache.has(name):
		return _cache[name]
	var path := DIR + name
	if not FileAccess.file_exists(path):
		push_error("MockRocketChat: fixture not found: %s" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_error("MockRocketChat: invalid JSON in %s" % path)
	_cache[name] = parsed
	return parsed
