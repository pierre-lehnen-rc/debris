extends RefCounted

## Fixture-backed stand-in for the Debris server, used by the headless validation
## runner (see dev/harness.sh) so checks never touch a real MongoDB proxy.
##
## Backend routes every request through _do_post(path, body); when Backend._mock
## is set, that method calls respond() here instead of making an HTTP request. The
## return value matches the real server's { ok, data, error } contract, so all of
## Backend's parsing/logging code above the seam runs unchanged.
##
## Design (deliberately dumb): specific endpoints return specific fixtures; find
## returns a per-collection fixture when one exists, else a generic one. Filters,
## options, limit and skip are ignored. The one bit of request-awareness is the
## force-error sentinel, so error handling can be exercised.

const DIR := "res://dev/mocks/backend/"

## Set connection.host to this to make every request fail (tests error paths).
const FORCE_ERROR_HOST := "force-error"

var _cache := {}


## Answer a Backend request. `path` is the /api/* endpoint, `body` the POSTed
## dictionary (connection, database, collection, filter, …).
func respond(path: String, body: Dictionary) -> Dictionary:
	var connection: Dictionary = body.get("connection", {})
	if connection.get("host", "") == FORCE_ERROR_HOST:
		return _err("forced error (mock): host is '%s'" % FORCE_ERROR_HOST)

	var collection: String = body.get("collection", "")
	match path:
		"/api/databases":
			return _ok(_load("databases.json"))
		"/api/collections":
			return _ok(_load("collections.json"))
		"/api/find":
			return _ok(_find_docs(collection))
		"/api/findOne":
			var docs := _find_docs(collection)
			return _ok(docs[0] if not docs.is_empty() else null)
		"/api/count":
			return _ok({"count": _find_docs(collection).size()})
		"/api/listIndexes":
			return _ok(_load("indexes.json"))
		"/api/explain":
			return _ok(_load("explain.json"))
		"/api/ping":
			return _ok({"ok": 1})
		"/api/rocketchat/call":
			return _rc_call(body)
		"/api/rocketchat/install":
			return _ok({
				"installed": true,
				"url": body.get("target", {}).get("url", ""),
				"models": ["Messages", "Rooms", "Subscriptions", "Users"],
			})
	# Unknown endpoint: behave like a find so the caller still gets rows.
	return _ok(_find_docs(collection))


## Stand-in for the Rocket.Chat model bridge. Returns the bridge's { result: … }
## envelope: a count fixture for count* methods, else a sample user document.
## model "force-error" (or a missing model/method) exercises the failure path.
func _rc_call(body: Dictionary) -> Dictionary:
	var model: String = body.get("model", "")
	var method: String = body.get("method", "")
	if model == FORCE_ERROR_HOST or model.is_empty() or method.is_empty():
		return _err("forced error (mock): model '%s'" % model)
	if method.begins_with("count"):
		return _ok({"result": {"$numberInt": "3"}})
	# find* (bar findOne*) stand in for cursor methods, returning a list of docs.
	if method.begins_with("find") and not method.begins_with("findOne"):
		return _ok({"result": [
			_load("rocketchat_user.json"),
			{"_id": "user1", "username": "user1", "roles": ["user"]},
		]})
	return _ok({"result": _load("rocketchat_user.json")})


## Documents for a collection: its own fixture (find/<collection>.json) when
## present, otherwise the shared generic set.
func _find_docs(collection: String) -> Array:
	var specific := "find/%s.json" % collection
	if not collection.is_empty() and FileAccess.file_exists(DIR + specific):
		var data: Variant = _load(specific)
		if data is Array:
			return data
	var generic: Variant = _load("find/_generic.json")
	return generic if generic is Array else []


func _ok(data: Variant) -> Dictionary:
	return {"ok": true, "data": data, "error": ""}


func _err(message: String) -> Dictionary:
	return {"ok": false, "data": null, "error": message}


## Load and cache a fixture file relative to DIR. Pushes an error (so it shows in
## the harness output) and returns null if the file is missing or invalid.
func _load(name: String) -> Variant:
	if _cache.has(name):
		return _cache[name]
	var path := DIR + name
	if not FileAccess.file_exists(path):
		push_error("MockBackend: fixture not found: %s" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_error("MockBackend: invalid JSON in %s" % path)
	_cache[name] = parsed
	return parsed
