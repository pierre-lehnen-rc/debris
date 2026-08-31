extends Node

## Direct HTTP client for a Rocket.Chat workspace's REST API. Unlike Backend
## (which proxies MongoDB through the Debris server), this talks straight to
## the configured Rocket.Chat server. Registered as the `RocketChat` autoload.
##
## Every call takes a workspace config ({ url, users: [{name, user_id, token}], … })
## and returns a result Dictionary shaped as { ok: bool, data: Variant, error:
## String, status: int }. Auth headers (X-User-Id / X-Auth-Token) are attached from
## the credentials on the workspace dict (see _headers).

const REQUEST_TIMEOUT_SECONDS := 20.0
const OPENAPI_PATH := "/api/docs/json"
const LOGIN_PATH := "/api/v1/login"
## Public, unauthenticated: answers with the server's version. Used to see whether
## a workspace is up at all.
const INFO_PATH := "/api/info"

## Emitted when a probe result lands, carrying the workspace URL it was about and
## the state (see probe). A project shows this same line under Endpoints, Users
## and Server Models, so they all listen and move together — re-checking from any
## one of them repaints the rest. Keyed by URL because separate project tabs watch
## separate workspaces; match it with workspace_url().
signal workspace_probed(url: String, state: Dictionary)

## Probes in flight, keyed by workspace URL. Opening a project configures all
## three of its workspace views in the same frame and each asks; they share one
## request rather than making three identical ones.
var _probes: Dictionary = {}

## When set, requests are answered from local fixtures instead of the network.
## Auto-enabled under the headless validation runner (DEBRIS_HEADLESS); the dev
## harness may also assign it directly. See dev/mocks/rocketchat_mock.gd.
var _mock = null


func _ready() -> void:
	if not OS.get_environment("DEBRIS_HEADLESS").is_empty():
		_mock = load("res://dev/mocks/rocketchat_mock.gd").new()


# Public API ------------------------------------------------------------------
## Fetch the workspace's OpenAPI document (the source of the endpoint catalog).
## `quiet` marks the call as a background side effect of opening a project rather
## than something the user asked for: still recorded in the Activity Log, but a
## failure won't interrupt them with an error popup.
func fetch_openapi(workspace: Dictionary, quiet := false) -> Dictionary:
	return await _request(workspace, HTTPClient.METHOD_GET, OPENAPI_PATH, {}, {}, quiet)


## Probe the workspace: GET /api/info, which needs no auth, purely to see whether
## the server is answering. Returns { running, version, url, error } — `running`
## is whether it answered at all, `version` what it reported (empty on a server
## that withholds it), `error` why it didn't when it didn't.
##
## Deliberately not recorded in the Activity Log: this is a status check the UI
## runs for itself on a timer of the user's choosing, not an action they took —
## logging it would bury their real requests and pop dialogs for a dead workspace
## they can already see is dead.
##
## The result is also broadcast on workspace_probed, so every panel showing this
## workspace repaints from one check; simultaneous asks share a single request.
func probe(workspace: Dictionary) -> Dictionary:
	var url := workspace_url(workspace)
	# One in flight for this workspace already: take its answer rather than asking
	# the same question again.
	if _probes.has(url):
		return await _joined_probe(url)
	_probes[url] = true
	var state := await _run_probe(workspace, url)
	_probes.erase(url)
	workspace_probed.emit(url, state)
	return state


## The workspace's base URL, trailing slash removed — the form probe results and
## workspace_probed are keyed by. Listeners use it to tell whether a broadcast is
## about the workspace they're showing.
func workspace_url(workspace: Dictionary) -> String:
	return _base_url(workspace)


## Wait for the probe already running against `url` and take its answer. The
## signal carries every workspace, so results meant for others are skipped.
func _joined_probe(url: String) -> Dictionary:
	var state: Dictionary = {}
	while true:
		var probed: Array = await workspace_probed
		if String(probed[0]) == url:
			state = probed[1]
			break
	return state


## Ask the workspace, and shape the answer. See probe() for the contract.
func _run_probe(workspace: Dictionary, url: String) -> Dictionary:
	var state := {"running": false, "version": "", "url": url, "error": ""}
	if url.is_empty():
		state["error"] = "Workspace has no URL"
		return state
	var result := await _do_request(workspace, HTTPClient.METHOD_GET, INFO_PATH, {}, {})
	if not result.get("ok", false):
		state["error"] = result.get("error", "")
		return state
	state["running"] = true
	state["version"] = _version_from(result.get("data"))
	return state


## The version out of an /api/info payload. Answered flat ({ version }) to an
## anonymous caller; an authenticated one gets the whole build under { info }.
## Neither is guaranteed — a workspace may withhold it, and "" reads as unknown.
static func _version_from(data: Variant) -> String:
	if not (data is Dictionary):
		return ""
	var payload: Dictionary = data
	if payload.get("version") is String:
		return payload["version"]
	var info: Variant = payload.get("info")
	if info is Dictionary and (info as Dictionary).get("version") is String:
		return (info as Dictionary)["version"]
	return ""


## Exchange a username/email + password for a temporary access token via the
## login endpoint. Sent without auth headers (only the workspace URL is used).
## Returns { ok, user_id, token, error }; user_id/token are the credentials to
## put in X-User-Id / X-Auth-Token for later calls.
func login(workspace: Dictionary, user: String, password: String) -> Dictionary:
	var anon := {"url": workspace.get("url", "")}
	var result := await _request(
		anon, HTTPClient.METHOD_POST, LOGIN_PATH, {}, {"user": user, "password": password}
	)
	var raw: Variant = result.get("data")
	if not result.get("ok", false):
		var message: String = result.get("error", "login failed")
		if raw is Dictionary and raw.get("error") is String:
			message = raw["error"]
		elif raw is Dictionary and raw.get("message") is String:
			message = raw["message"]
		return {"ok": false, "user_id": "", "token": "", "error": message}

	var data: Variant = raw.get("data") if raw is Dictionary else null
	if not (data is Dictionary) or not data.has("authToken") or not data.has("userId"):
		return {"ok": false, "user_id": "", "token": "", "error": "unexpected login response"}
	return {
		"ok": true,
		"user_id": String(data["userId"]),
		"token": String(data["authToken"]),
		"error": "",
	}


## Issue an arbitrary REST call. `query` becomes the URL query string (GET-style
## endpoints), `body` becomes a JSON request body (POST/PUT/…). Either may be
## empty. `method` is an HTTPClient.METHOD_* constant.
func request(
	workspace: Dictionary,
	method: int,
	path: String,
	query: Dictionary = {},
	body: Dictionary = {},
) -> Dictionary:
	return await _request(workspace, method, path, query, body)


# Internals -------------------------------------------------------------------
func _request(
	workspace: Dictionary,
	method: int,
	path: String,
	query: Dictionary,
	body: Dictionary,
	quiet := false,
) -> Dictionary:
	var started := Time.get_ticks_msec()
	var outcome := await _do_request(workspace, method, path, query, body)
	var params := {}
	if not query.is_empty():
		params["query"] = query
	if not body.is_empty():
		params["body"] = body
	ActivityLog.record({
		"source": "rocketchat",
		"action": _method_name(method),
		"target": path,
		"params": params,
		"ok": outcome.get("ok", false),
		"result": "HTTP %d" % outcome.get("status", 0) if outcome.get("ok", false) else "",
		"error": outcome.get("error", ""),
		"ms": Time.get_ticks_msec() - started,
		"quiet": quiet,
	})
	return outcome


## Turn an HTTPClient.METHOD_* constant into its HTTP verb for the log.
func _method_name(method: int) -> String:
	match method:
		HTTPClient.METHOD_GET: return "GET"
		HTTPClient.METHOD_POST: return "POST"
		HTTPClient.METHOD_PUT: return "PUT"
		HTTPClient.METHOD_DELETE: return "DELETE"
		HTTPClient.METHOD_PATCH: return "PATCH"
		_: return "HTTP"


func _do_request(
	workspace: Dictionary, method: int, path: String, query: Dictionary, body: Dictionary
) -> Dictionary:
	if _mock != null:
		return _mock.respond(method, path, query, body)

	var base := _base_url(workspace)
	if base.is_empty():
		return _err("Workspace has no URL", 0)

	var url := base + path + _query_string(query)

	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT_SECONDS
	add_child(http)

	var headers := _headers(workspace)
	var payload := JSON.stringify(body) if not body.is_empty() else ""
	var err := http.request(url, headers, method, payload)
	if err != OK:
		http.queue_free()
		return _err("Could not start request (error %d)" % err, 0)

	var result: Array = await http.request_completed
	http.queue_free()

	var outcome: int = result[0]
	var status: int = result[1]
	var bytes: PackedByteArray = result[3]

	if outcome != HTTPRequest.RESULT_SUCCESS:
		return _err("Cannot reach %s" % base, 0)

	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())

	if status >= 200 and status < 300:
		return {"ok": true, "data": parsed, "error": "", "status": status}

	# Rocket.Chat error bodies look like { success: false, error: "…" }.
	var message := "HTTP %d" % status
	if parsed is Dictionary and parsed.get("error") is String:
		message = parsed["error"]
	return {"ok": false, "data": parsed, "error": message, "status": status}


## The workspace base URL with any trailing slash removed.
func _base_url(workspace: Dictionary) -> String:
	var url := String(workspace.get("url", "")).strip_edges()
	while url.ends_with("/"):
		url = url.substr(0, url.length() - 1)
	return url


## Attach auth headers for the request. An explicit user_id/token on the workspace
## dict wins (the endpoint tab sets these from the user picked for that tab, and
## clears them for an anonymous call); otherwise fall back to the first configured
## user so workspace-level calls like the OpenAPI fetch stay authenticated. The two
## headers go out independently: a request needs both to authenticate, but sending
## just one is allowed so it can be exercised in isolation for targeted tests.
func _headers(workspace: Dictionary) -> PackedStringArray:
	var headers := PackedStringArray(["Content-Type: application/json"])
	var user_id := String(workspace.get("user_id", ""))
	var token := String(workspace.get("token", ""))
	if user_id.is_empty() and token.is_empty():
		var users: Variant = workspace.get("users", [])
		if users is Array and not (users as Array).is_empty() and users[0] is Dictionary:
			user_id = String(users[0].get("user_id", ""))
			token = String(users[0].get("token", ""))
	if not user_id.is_empty():
		headers.append("X-User-Id: " + user_id)
	if not token.is_empty():
		headers.append("X-Auth-Token: " + token)
	return headers


## Build a "?a=1&b=2" string from a Dictionary, URL-encoding keys and values. An
## array value is expanded into repeated "key[]=v" pairs (the convention the
## Rocket.Chat REST API accepts for list-valued query params).
func _query_string(query: Dictionary) -> String:
	if query.is_empty():
		return ""
	var parts: PackedStringArray = []
	for key in query:
		var value: Variant = query[key]
		if value == null:
			continue
		if value is Array:
			var array_key := (String(key) + "[]").uri_encode()
			for item in (value as Array):
				parts.append("%s=%s" % [array_key, str(item).uri_encode()])
		else:
			parts.append("%s=%s" % [
				String(key).uri_encode(), str(value).uri_encode(),
			])
	return "?" + "&".join(parts) if parts.size() > 0 else ""


func _err(message: String, status: int) -> Dictionary:
	return {"ok": false, "data": null, "error": message, "status": status}
