class_name EndpointTabTest
extends "res://test/test_suite.gd"

# Tests for EndpointTab's pure request-building helpers — array coercion (so
# params like `roles` go out as real JSON arrays) and arg routing across the
# path/query/body. These are static, so no scene tree is needed.
# See res://source/ui/workspace/endpoint_tab.gd


# coerce_array ----------------------------------------------------------------
func test_coerce_array_splits_comma_separated_strings() -> void:
	assert_array(EndpointTab.coerce_array("admin, user", "string")).is_equal(["admin", "user"])


func test_coerce_array_trims_and_drops_blank_pieces() -> void:
	assert_array(EndpointTab.coerce_array(" admin ,, user , ", "string")).is_equal(["admin", "user"])


func test_coerce_array_single_value_becomes_one_element_array() -> void:
	assert_array(EndpointTab.coerce_array("admin", "string")).is_equal(["admin"])


func test_coerce_array_blank_text_returns_null() -> void:
	assert_object(EndpointTab.coerce_array("   ", "string")).is_null()


func test_coerce_array_parses_literal_json_array() -> void:
	assert_array(EndpointTab.coerce_array('["admin", "user"]', "string")).is_equal(["admin", "user"])


func test_coerce_array_json_is_taken_verbatim() -> void:
	# A JSON array is used as-is (not re-split by commas), regardless of item_type.
	assert_array(EndpointTab.coerce_array('["a,b", "c"]', "string")).is_equal(["a,b", "c"])


func test_coerce_array_invalid_json_falls_back_to_comma_split() -> void:
	# Leading "[" but not valid JSON — split on commas instead of dropping the input.
	assert_array(EndpointTab.coerce_array("[oops, two", "string")).is_equal(["[oops", "two"])


func test_coerce_array_int_items_become_numbers() -> void:
	assert_array(EndpointTab.coerce_array("1, 2, 3", "int")).is_equal([1, 2, 3])


func test_coerce_array_bool_items_become_bools() -> void:
	assert_array(EndpointTab.coerce_array("true, false", "bool")).is_equal([true, false])


func test_coerce_array_non_numeric_int_item_stays_string() -> void:
	assert_array(EndpointTab.coerce_array("x", "int")).is_equal(["x"])


# route_args ------------------------------------------------------------------
func test_route_args_fills_colon_path_placeholder() -> void:
	var out := EndpointTab.route_args("/api/v1/apps/:id/logs", {"id": "abc"}, {}, "query")
	assert_str(out["path"]).is_equal("/api/v1/apps/abc/logs")
	assert_dict(out["query"]).is_empty()
	assert_dict(out["body"]).is_empty()


func test_route_args_fills_brace_path_placeholder() -> void:
	var out := EndpointTab.route_args("/api/v1/x/{id}", {"id": "42"}, {}, "query")
	assert_str(out["path"]).is_equal("/api/v1/x/42")


func test_route_args_uri_encodes_path_value() -> void:
	var out := EndpointTab.route_args("/api/v1/x/:id", {"id": "a b/c"}, {}, "query")
	assert_str(out["path"]).is_equal("/api/v1/x/a%20b%2Fc")


func test_route_args_routes_by_declared_location() -> void:
	var out := EndpointTab.route_args(
		"/api/v1/users.create",
		{"username": "bob", "roles": ["admin"]},
		{"username": "body", "roles": "body"},
		"query",
	)
	assert_dict(out["body"]).is_equal({"username": "bob", "roles": ["admin"]})
	assert_dict(out["query"]).is_empty()


func test_route_args_unlisted_name_uses_default_location_body() -> void:
	# Raw JSON mode passes no locations and a "body" default, so every key lands in
	# the body — this is what makes custom test payloads route correctly for POSTs.
	var out := EndpointTab.route_args(
		"/api/v1/users.create", {"custom": 1, "roles": ["admin"]}, {}, "body"
	)
	assert_dict(out["body"]).is_equal({"custom": 1, "roles": ["admin"]})
	assert_dict(out["query"]).is_empty()


func test_route_args_unlisted_name_uses_default_location_query() -> void:
	var out := EndpointTab.route_args("/api/v1/users.list", {"count": 50}, {}, "query")
	assert_dict(out["query"]).is_equal({"count": 50})
	assert_dict(out["body"]).is_empty()


func test_route_args_path_key_is_not_also_sent_as_query_or_body() -> void:
	var out := EndpointTab.route_args("/api/v1/x/:id", {"id": "7", "n": 1}, {}, "query")
	assert_str(out["path"]).is_equal("/api/v1/x/7")
	assert_dict(out["query"]).is_equal({"n": 1})


# collect_entities ------------------------------------------------------------
func test_collect_entities_list_response() -> void:
	# users.list -> { users: [ … ] }: the array's entities are the rows.
	var raw := {"users": [{"_id": "a"}, {"_id": "b"}], "count": 2, "total": 2, "success": true}
	assert_array(EndpointTab.collect_entities(raw)).is_equal([{"_id": "a"}, {"_id": "b"}])


func test_collect_entities_wrapped_single_object() -> void:
	# channels.info -> { channel: {…} }: the wrapped entity is the single row.
	var raw := {"channel": {"_id": "r1"}, "success": true}
	assert_array(EndpointTab.collect_entities(raw)).is_equal([{"_id": "r1"}])


func test_collect_entities_bare_single_object() -> void:
	# …getRoom returns the entity itself; its own array fields (uids) aren't entities.
	var raw := {"_id": "r1", "name": "general", "uids": ["u1", "u2"], "success": true}
	assert_array(EndpointTab.collect_entities(raw)).is_equal([raw])


func test_collect_entities_multiple_sections() -> void:
	# rooms.get -> { update: [...], remove: [...] }: entities from both sections.
	var raw := {"update": [{"_id": "r1"}], "remove": [{"_id": "r2"}], "success": true}
	assert_array(EndpointTab.collect_entities(raw)).is_equal([{"_id": "r1"}, {"_id": "r2"}])


func test_collect_entities_array_response() -> void:
	assert_array(EndpointTab.collect_entities([{"_id": "a"}, {"nope": 1}])).is_equal([{"_id": "a"}])


func test_collect_entities_none_for_action_response() -> void:
	# An action response with no _id-bearing objects yields no entity rows.
	assert_array(EndpointTab.collect_entities({"success": true, "deletedRooms": []})).is_empty()
