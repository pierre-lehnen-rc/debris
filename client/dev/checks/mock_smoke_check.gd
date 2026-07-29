extends "res://dev/check_base.gd"

## End-to-end smoke check for the headless mock layer: exercises Backend and
## RocketChat through their public APIs and asserts the fixture data flows back
## in the real { ok, data, error } shape. Also confirms the real OpenAPI spec
## parses into the endpoint catalog.

const CONN := {"host": "localhost:27017"}


func _run() -> void:
	await _check_backend()
	await _check_rocketchat()


func _check_backend() -> void:
	var dbs: Dictionary = await backend.list_databases(CONN)
	expect(bool(dbs.get("ok", false)), "list_databases ok")
	var db_data: Variant = dbs.get("data")
	var databases: Array = (db_data as Dictionary).get("databases", []) if db_data is Dictionary else []
	expect_eq(databases.size(), 4, "4 databases")

	var cols: Dictionary = await backend.list_collections(CONN, "rocketchat")
	expect(bool(cols.get("ok", false)), "list_collections ok")
	var names: Array = []
	var col_data: Variant = cols.get("data", [])
	if col_data is Array:
		for c in col_data:
			if c is Dictionary:
				names.append((c as Dictionary).get("name", ""))
	expect(names.has("users") and names.has("rooms") and names.has("subscriptions"),
		"collections include users/rooms/subscriptions")

	# Dedicated fixture: users -> 4 docs, first is rocket.cat.
	var users: Dictionary = await backend.find(CONN, "rocketchat", "users")
	expect(bool(users.get("ok", false)), "find users ok")
	var user_docs: Array = users.get("data") if users.get("data") is Array else []
	expect_eq(user_docs.size(), 4, "4 users")
	if not user_docs.is_empty():
		expect_eq((user_docs[0] as Dictionary).get("username"), "rocket.cat", "first user is rocket.cat")

	# Unknown collection falls back to the generic fixture (2 docs).
	var other: Dictionary = await backend.find(CONN, "rocketchat", "no_such_collection")
	var other_docs: Array = other.get("data") if other.get("data") is Array else []
	expect_eq(other_docs.size(), 2, "generic fixture for unknown collection")

	# count reflects the fixture size.
	var counted: Dictionary = await backend.count(CONN, "rocketchat", "users")
	var count_data: Variant = counted.get("data")
	var count_value: Variant = (count_data as Dictionary).get("count") if count_data is Dictionary else -1
	expect_eq(count_value, 4, "count users == 4")

	# force-error sentinel exercises the failure path.
	var failed: Dictionary = await backend.find({"host": "force-error"}, "rocketchat", "users")
	expect(not bool(failed.get("ok", true)), "force-error connection fails")
	expect(not String(failed.get("error", "")).is_empty(), "force-error carries a message")


func _check_rocketchat() -> void:
	var ws := {"url": "https://chat.example.com", "users": []}

	var spec: Dictionary = await rocketchat.fetch_openapi(ws)
	expect(bool(spec.get("ok", false)), "fetch_openapi ok")
	var doc: Variant = spec.get("data")
	expect(doc is Dictionary and (doc as Dictionary).has("paths"), "spec has paths")

	# The real spec must parse into a non-trivial endpoint catalog.
	var endpoints: Array = OpenApiParser.parse(doc)
	expect(endpoints.size() > 50, "OpenApiParser yields many endpoints (got %d)" % endpoints.size())
	expect(not endpoints.is_empty() and endpoints[0] is ApiEndpoint, "parser returns ApiEndpoint instances")

	var creds: Dictionary = await rocketchat.login(ws, "admin", "secret")
	expect(bool(creds.get("ok", false)), "login ok")
	expect_eq(creds.get("user_id"), "mock-user-id", "login returns mocked user_id")
	expect_eq(creds.get("token"), "mock-auth-token", "login returns mocked token")

	# Per-path fixture (endpoints/users.list.json).
	var listed: Dictionary = await rocketchat.request(ws, HTTPClient.METHOD_GET, "/api/v1/users.list")
	expect(bool(listed.get("ok", false)), "users.list ok")
	var listed_data: Variant = listed.get("data")
	var listed_users: Array = (listed_data as Dictionary).get("users", []) if listed_data is Dictionary else []
	expect_eq(listed_users.size(), 3, "users.list returns 3 users")

	# Unknown path -> generic envelope.
	var generic: Dictionary = await rocketchat.request(ws, HTTPClient.METHOD_GET, "/api/v1/something.else")
	var generic_data: Variant = generic.get("data")
	expect(generic_data is Dictionary and (generic_data as Dictionary).has("items"),
		"unknown path uses generic fixture")
