extends Node

## HTTP client for the Debris server (the stateless MongoDB proxy).
## Registered as the `Backend` autoload. Each public method POSTs a JSON body to
## an /api endpoint and awaits the reply, returning a result Dictionary shaped as
## { ok: bool, data: Variant, error: String }. Connection details (host, port,
## credentials) are sent with every request; nothing is stored server-side.

const DEFAULT_BASE_URL := "http://127.0.0.1:4020"
const REQUEST_TIMEOUT_SECONDS := 15.0

var base_url := DEFAULT_BASE_URL

## When set, requests are answered from local fixtures instead of the network.
## Auto-enabled under the headless validation runner (DEBRIS_HEADLESS); the dev
## harness may also assign it directly. See dev/mocks/backend_mock.gd.
var _mock = null


func _ready() -> void:
	# Allow pointing at a non-default server (e.g. a different PORT) for testing.
	var env := OS.get_environment("DEBRIS_SERVER_URL")
	if env != "":
		base_url = env
	if not OS.get_environment("DEBRIS_HEADLESS").is_empty():
		_mock = load("res://dev/mocks/backend_mock.gd").new()


# Public API ------------------------------------------------------------------
func list_databases(connection: Dictionary) -> Dictionary:
	return await _post("/api/databases", {"connection": connection})


func list_collections(connection: Dictionary, database: String) -> Dictionary:
	return await _post("/api/collections", {"connection": connection, "database": database})


func find(
	connection: Dictionary,
	database: String,
	collection: String,
	filter: Dictionary = {},
	limit: int = 0,
	skip: int = 0,
	options: Dictionary = {},
) -> Dictionary:
	var body := {
		"connection": connection,
		"database": database,
		"collection": collection,
		"filter": filter,
	}
	if limit > 0:
		body["limit"] = limit
	if skip > 0:
		body["skip"] = skip
	# Any driver find options the user typed in the query tab, passed through.
	if not options.is_empty():
		body["options"] = options
	return await _post("/api/find", body)


func find_one(
	connection: Dictionary,
	database: String,
	collection: String,
	filter: Dictionary = {},
	options: Dictionary = {},
) -> Dictionary:
	var body := {
		"connection": connection,
		"database": database,
		"collection": collection,
		"filter": filter,
	}
	if not options.is_empty():
		body["options"] = options
	return await _post("/api/findOne", body)


func count(
	connection: Dictionary,
	database: String,
	collection: String,
	filter: Dictionary = {},
) -> Dictionary:
	return await _post("/api/count", {
		"connection": connection,
		"database": database,
		"collection": collection,
		"filter": filter,
	})


func explain(
	connection: Dictionary,
	database: String,
	collection: String,
	filter: Dictionary = {},
	options: Dictionary = {},
) -> Dictionary:
	var body := {
		"connection": connection,
		"database": database,
		"collection": collection,
		"filter": filter,
	}
	if not options.is_empty():
		body["options"] = options
	return await _post("/api/explain", body)


func list_indexes(connection: Dictionary, database: String, collection: String) -> Dictionary:
	return await _post("/api/listIndexes", {
		"connection": connection,
		"database": database,
		"collection": collection,
	})


func ping(connection: Dictionary) -> Dictionary:
	return await _post("/api/ping", {"connection": connection})


## Call a @rocket.chat/models method on a running Rocket.Chat server via the
## server's bridge. `target` names the RC instance ({ meteorDir, url? }); `args` is
## the argument list, spread into the call. The result's `data` is `{ result }`,
## the method's return value as canonical Extended JSON (parses to plain nested
## dictionaries, same as the Mongo routes).
func rocketchat_call(target: Dictionary, model: String, method: String, args: Array) -> Dictionary:
	return await _post("/api/rocketchat/call", {
		"target": target,
		"model": model,
		"method": method,
		"args": args,
	})


## Inject (or refresh) the Server Models bridge endpoint into the running Rocket.Chat
## server named by `target` ({ meteorDir, url }). This is the only step that uses the
## meteor dir; queries then post to the installed endpoint. Logged as its own action.
func rocketchat_install(target: Dictionary) -> Dictionary:
	return await _post("/api/rocketchat/install", {"target": target})


## List a model's public methods (from @rocket.chat/model-typings). Metadata for the
## sidebar tree; only the target's meteor dir is used (no running server needed).
func rocketchat_model_methods(target: Dictionary, model: String) -> Dictionary:
	return await _post("/api/rocketchat/model-methods", {"target": target, "model": model})


## Convert a stored connection config (name / "host:port" / optional auth) into
## the discrete connection spec the server expects.
static func to_spec(conn: Dictionary) -> Dictionary:
	var host_port: String = conn.get("host", "")
	var host := host_port
	var port := 27017
	var colon := host_port.rfind(":")
	if colon != -1:
		host = host_port.substr(0, colon)
		port = host_port.substr(colon + 1).to_int()
		if port == 0:
			port = 27017

	var spec := {
		"host": host,
		"port": port,
		"directConnection": true,
	}

	var auth: Dictionary = conn.get("auth", {})
	if auth.get("enabled", false):
		spec["username"] = auth.get("username", "")
		spec["password"] = auth.get("password", "")
		spec["authSource"] = auth.get("database", "admin")
		spec["authMechanism"] = auth.get("mechanism", "SCRAM-SHA-256")
	return spec


# Internals -------------------------------------------------------------------
func _post(path: String, body: Dictionary) -> Dictionary:
	var started := Time.get_ticks_msec()
	var outcome := await _do_post(path, body)
	_log(path, body, outcome, Time.get_ticks_msec() - started)
	return outcome


func _do_post(path: String, body: Dictionary) -> Dictionary:
	if _mock != null:
		return _mock.respond(path, body)

	# On a cold launch the bundled server may still be starting; wait for it so the
	# first requests (e.g. restoring a project's collections) don't race startup and
	# fail. Resolves instantly once startup has concluded — and if the server never
	# came up, the request below still runs and fails with a clear error, as before.
	await ServerManager.await_ready()

	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT_SECONDS
	add_child(http)

	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := http.request(base_url + path, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		http.queue_free()
		return {"ok": false, "data": null, "error": "Could not start request (error %d)" % err}

	var result: Array = await http.request_completed
	http.queue_free()

	var outcome: int = result[0]
	var status: int = result[1]
	var bytes: PackedByteArray = result[3]

	if outcome != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "data": null, "error": "Cannot reach server at %s" % base_url}

	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())

	if status >= 200 and status < 300:
		return {"ok": true, "data": parsed, "error": ""}

	var message := "HTTP %d" % status
	if parsed is Dictionary and parsed.get("error") is Dictionary:
		message = parsed["error"].get("message", message)
	return {"ok": false, "data": parsed, "error": message}


## Record a completed MongoDB action in the shared ActivityLog. The action is the
## endpoint name (path minus the "/api/" prefix); the target is the collection
## (or database) the body addressed.
func _log(path: String, body: Dictionary, outcome: Dictionary, ms: int) -> void:
	# Listing a model's methods is metadata for the sidebar tree, not an action.
	if path == "/api/rocketchat/model-methods":
		return
	# Rocket.Chat model-bridge calls aren't Mongo actions; label them accordingly.
	if path == "/api/rocketchat/call":
		_log_rocketchat_call(body, outcome, ms)
		return
	if path == "/api/rocketchat/install":
		_log_rocketchat_install(body, outcome, ms)
		return
	var target: String = body.get("database", "")
	if body.has("collection"):
		target = "%s.%s" % [target, body["collection"]]
	ActivityLog.record({
		"source": "mongo",
		"action": path.trim_prefix("/api/"),
		"target": target,
		"params": _params_from(body),
		"ok": outcome.get("ok", false),
		"result": _summarize(outcome.get("data")) if outcome.get("ok", false) else "",
		"error": outcome.get("error", ""),
		"ms": ms,
	})


## Record a Rocket.Chat model-bridge call: the target is "Model.method", the args
## are the logged params, and the result summary unwraps the bridge's { result }.
func _log_rocketchat_call(body: Dictionary, outcome: Dictionary, ms: int) -> void:
	var data: Variant = outcome.get("data")
	var value: Variant = data.get("result") if (data is Dictionary and (data as Dictionary).has("result")) else data
	# The call posts to the endpoint's server URL (the meteor dir isn't used here — it
	# only drives the separate install step), so log the URL alongside the args.
	var call_target: Dictionary = body.get("target", {})
	ActivityLog.record({
		"source": "rocketchat",
		"action": "model call",
		"target": "%s.%s" % [body.get("model", ""), body.get("method", "")],
		"params": {
			"url": call_target.get("url", ""),
			"args": body.get("args", []),
		},
		"ok": outcome.get("ok", false),
		"result": _summarize(value) if outcome.get("ok", false) else "",
		"error": outcome.get("error", ""),
		"ms": ms,
	})


## Record a Server Models bridge install (startup / meteor-dir change / manual
## refresh): the meteor dir is the target here, since injection is what uses it.
func _log_rocketchat_install(body: Dictionary, outcome: Dictionary, ms: int) -> void:
	var target: Dictionary = body.get("target", {})
	ActivityLog.record({
		"source": "rocketchat",
		"action": "install bridge",
		"target": String(target.get("meteorDir", "")),
		"params": {"url": target.get("url", "")},
		"ok": outcome.get("ok", false),
		"result": "installed" if outcome.get("ok", false) else "",
		"error": outcome.get("error", ""),
		"ms": ms,
	})


## The query inputs sent with a request — the filter, options and pagination —
## as a standalone object so the log tree can collapse them under "params". The
## connection (with any credentials) and the database/collection (already shown
## as the target) are left out.
func _params_from(body: Dictionary) -> Dictionary:
	var params := body.duplicate(true)
	params.erase("connection")
	params.erase("database")
	params.erase("collection")
	return params


## Human-readable summary of a response payload for the log: arrays report their
## length, count-style objects report the number they carry, other objects count
## as one result, and null/empty as none.
func _summarize(data: Variant) -> String:
	if data is Array:
		var n: int = data.size()
		return "%d result%s" % [n, "" if n == 1 else "s"]
	if data is Dictionary:
		for key in ["count", "deletedCount", "modifiedCount", "insertedCount", "matchedCount"]:
			if data.has(key):
				return "%s: %s" % [key, data[key]]
		return "1 result"
	if data == null:
		return "no result"
	return "1 result"
