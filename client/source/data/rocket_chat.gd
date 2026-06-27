extends Node

## Direct HTTP client for a Rocket.Chat workspace's REST API. Unlike Backend
## (which proxies MongoDB through the Quetzalcoatl server), this talks straight to
## the configured Rocket.Chat server. Registered as the `RocketChat` autoload.
##
## Every call takes a workspace config ({ url, user_id, token, … }) and returns a
## result Dictionary shaped as { ok: bool, data: Variant, error: String, status:
## int }. Auth headers (X-User-Id / X-Auth-Token) are attached when the workspace
## carries credentials.

const REQUEST_TIMEOUT_SECONDS := 20.0
const OPENAPI_PATH := "/api/docs/json"


# Public API ------------------------------------------------------------------
## Fetch the workspace's OpenAPI document (the source of the endpoint catalog).
func fetch_openapi(workspace: Dictionary) -> Dictionary:
	return await _request(workspace, HTTPClient.METHOD_GET, OPENAPI_PATH, {}, {})


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
	workspace: Dictionary, method: int, path: String, query: Dictionary, body: Dictionary
) -> Dictionary:
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


func _headers(workspace: Dictionary) -> PackedStringArray:
	var headers := PackedStringArray(["Content-Type: application/json"])
	var user_id := String(workspace.get("user_id", ""))
	var token := String(workspace.get("token", ""))
	if not user_id.is_empty() and not token.is_empty():
		headers.append("X-User-Id: " + user_id)
		headers.append("X-Auth-Token: " + token)
	return headers


## Build a "?a=1&b=2" string from a Dictionary, URL-encoding keys and values.
func _query_string(query: Dictionary) -> String:
	if query.is_empty():
		return ""
	var parts: PackedStringArray = []
	for key in query:
		var value: Variant = query[key]
		if value == null:
			continue
		parts.append("%s=%s" % [
			String(key).uri_encode(), str(value).uri_encode(),
		])
	return "?" + "&".join(parts) if parts.size() > 0 else ""


func _err(message: String, status: int) -> Dictionary:
	return {"ok": false, "data": null, "error": message, "status": status}
