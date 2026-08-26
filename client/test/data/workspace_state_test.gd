class_name WorkspaceStateTest
extends "res://test/test_suite.gd"

# Tests for WorkspaceState — the in-memory model of the .debris-workspace sidecar
# (open tabs + offline endpoint cache). See res://source/data/workspace_state.gd


func _sample_tabs() -> Array:
	return [
		{"kind": "query", "database": "mydb", "collection": "users", "function": "find",
			"filter": "{\"active\": true}", "options": "", "options_visible": false},
		{"kind": "endpoint", "endpoint_id": "channels.list", "user_id": -1,
			"raw": false, "form": {"count": 50}, "json_text": ""},
	]


# to_dict / from_dict round-trip ----------------------------------------------
func test_round_trip_preserves_tabs_and_active() -> void:
	var s := WorkspaceState.new()
	s.tabs = _sample_tabs()
	s.active_tab = 1
	var loaded := WorkspaceState.from_dict(s.to_dict())
	assert_array(loaded.tabs).is_equal(_sample_tabs())
	assert_int(loaded.active_tab).is_equal(1)


func test_from_dict_defaults_on_empty() -> void:
	var s := WorkspaceState.from_dict({})
	assert_array(s.tabs).is_empty()
	assert_int(s.active_tab).is_equal(0)
	assert_dict(s.endpoints).is_empty()


func test_from_dict_ignores_non_array_tabs() -> void:
	var s := WorkspaceState.from_dict({"tabs": "not an array"})
	assert_array(s.tabs).is_empty()


func test_to_dict_carries_version() -> void:
	assert_int(int(WorkspaceState.new().to_dict()["version"])).is_equal(WorkspaceState.VERSION)


# endpoint cache --------------------------------------------------------------
func test_set_and_read_endpoint_cache() -> void:
	var s := WorkspaceState.new()
	var endpoints := [
		ApiEndpoint.from_dict({"id": "channels.list", "paginated": true}),
		ApiEndpoint.from_dict({"id": "users.info"}),
	]
	s.set_endpoint_cache("https://chat.example", endpoints, "2026-08-24T10:00:00")
	var cached := s.cached_endpoints("https://chat.example")
	assert_int(cached.size()).is_equal(2)
	assert_str((cached[0] as ApiEndpoint).id).is_equal("channels.list")
	assert_str(s.endpoints["fetched_at"]).is_equal("2026-08-24T10:00:00")


func test_cached_endpoints_ignores_other_url() -> void:
	# A cache belonging to a different URL must not be shown for the current one.
	var s := WorkspaceState.new()
	s.set_endpoint_cache("https://old.example", [ApiEndpoint.from_dict({"id": "x"})], "t")
	assert_array(s.cached_endpoints("https://new.example")).is_empty()


func test_cached_endpoints_empty_when_no_cache() -> void:
	assert_array(WorkspaceState.new().cached_endpoints("https://chat.example")).is_empty()


func test_endpoint_cache_survives_json_round_trip() -> void:
	var s := WorkspaceState.new()
	s.set_endpoint_cache("https://chat.example",
		[ApiEndpoint.from_dict({"id": "channels.list", "paginated": true})], "t")
	var json: Variant = JSON.parse_string(JSON.stringify(s.to_dict()))
	var loaded := WorkspaceState.from_dict(json)
	var cached := loaded.cached_endpoints("https://chat.example")
	assert_int(cached.size()).is_equal(1)
	assert_str((cached[0] as ApiEndpoint).id).is_equal("channels.list")
	assert_bool((cached[0] as ApiEndpoint).paginated).is_true()


# recent query history --------------------------------------------------------
func _entry(filter: String, function := "find", options := "") -> Dictionary:
	return {"function": function, "filter": filter, "options": options}


func test_record_query_newest_first() -> void:
	var s := WorkspaceState.new()
	s.record_query("users", _entry("{\"a\": 1}"))
	s.record_query("users", _entry("{\"b\": 2}"))
	var recents := s.recent_queries("users")
	assert_int(recents.size()).is_equal(2)
	assert_str(recents[0]["filter"]).is_equal("{\"b\": 2}")
	assert_str(recents[1]["filter"]).is_equal("{\"a\": 1}")


func test_record_query_is_per_collection() -> void:
	var s := WorkspaceState.new()
	s.record_query("users", _entry("{\"a\": 1}"))
	s.record_query("rooms", _entry("{\"b\": 2}"))
	assert_int(s.recent_queries("users").size()).is_equal(1)
	assert_int(s.recent_queries("rooms").size()).is_equal(1)


func test_record_query_dedupes_identical_to_top() -> void:
	# Re-running an identical query resurfaces the existing recent instead of stacking.
	var s := WorkspaceState.new()
	s.record_query("users", _entry("{\"a\": 1}"))
	s.record_query("users", _entry("{\"b\": 2}"))
	s.record_query("users", _entry("{\"a\": 1}"))
	var recents := s.recent_queries("users")
	assert_int(recents.size()).is_equal(2)
	assert_str(recents[0]["filter"]).is_equal("{\"a\": 1}")


func test_record_query_dedupe_ignores_whitespace() -> void:
	var s := WorkspaceState.new()
	s.record_query("users", _entry("{\"a\": 1}"))
	s.record_query("users", _entry("  {\"a\": 1}\n"))
	assert_int(s.recent_queries("users").size()).is_equal(1)


func test_record_query_differs_by_options() -> void:
	# Same filter but different options is a distinct query, so both are kept.
	var s := WorkspaceState.new()
	s.record_query("users", _entry("{}", "find", ""))
	s.record_query("users", _entry("{}", "find", "{\"sort\": {\"_id\": -1}}"))
	assert_int(s.recent_queries("users").size()).is_equal(2)


func test_record_query_caps_at_limit() -> void:
	var s := WorkspaceState.new()
	for i in WorkspaceState.RECENT_LIMIT + 5:
		s.record_query("users", _entry("{\"i\": %d}" % i))
	var recents := s.recent_queries("users")
	assert_int(recents.size()).is_equal(WorkspaceState.RECENT_LIMIT)
	# The oldest entries were evicted; the newest is on top.
	assert_str(recents[0]["filter"]).is_equal("{\"i\": %d}" % (WorkspaceState.RECENT_LIMIT + 4))


func test_remove_recent() -> void:
	var s := WorkspaceState.new()
	s.record_query("users", _entry("{\"a\": 1}"))
	s.record_query("users", _entry("{\"b\": 2}"))
	assert_bool(s.remove_recent("users", 0)).is_true()
	var recents := s.recent_queries("users")
	assert_int(recents.size()).is_equal(1)
	assert_str(recents[0]["filter"]).is_equal("{\"a\": 1}")


func test_remove_recent_out_of_range() -> void:
	var s := WorkspaceState.new()
	s.record_query("users", _entry("{\"a\": 1}"))
	assert_bool(s.remove_recent("users", 5)).is_false()
	assert_bool(s.remove_recent("missing", 0)).is_false()


func test_remove_last_recent_clears_collection_key() -> void:
	var s := WorkspaceState.new()
	s.record_query("users", _entry("{\"a\": 1}"))
	assert_bool(s.remove_recent("users", 0)).is_true()
	assert_bool(s.query_history.has("users")).is_false()


func test_query_history_survives_round_trip() -> void:
	var s := WorkspaceState.new()
	s.record_query("users", _entry("{\"active\": true}", "findOne", "{\"limit\": 1}"))
	var loaded := WorkspaceState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	var recents := loaded.recent_queries("users")
	assert_int(recents.size()).is_equal(1)
	assert_str(recents[0]["function"]).is_equal("findOne")
	assert_str(recents[0]["options"]).is_equal("{\"limit\": 1}")
