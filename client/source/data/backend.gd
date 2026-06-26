extends Node

## HTTP client for the Quetzalcoatl server (the stateless MongoDB proxy).
## Registered as the `Backend` autoload. Each public method POSTs a JSON body to
## an /api endpoint and awaits the reply, returning a result Dictionary shaped as
## { ok: bool, data: Variant, error: String }. Connection details (host, port,
## credentials) are sent with every request; nothing is stored server-side.

const DEFAULT_BASE_URL := "http://127.0.0.1:4000"
const REQUEST_TIMEOUT_SECONDS := 15.0

var base_url := DEFAULT_BASE_URL


func _ready() -> void:
	# Allow pointing at a non-default server (e.g. a different PORT) for testing.
	var env := OS.get_environment("QUETZAL_SERVER_URL")
	if env != "":
		base_url = env


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
	return await _post("/api/find", body)


func ping(connection: Dictionary) -> Dictionary:
	return await _post("/api/ping", {"connection": connection})


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
