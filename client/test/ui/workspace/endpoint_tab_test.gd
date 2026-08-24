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


# display_rows ----------------------------------------------------------------
func test_display_rows_passes_non_empty_extracted_through() -> void:
	var rows := EndpointTab.display_rows({"users": [1]}, [1], false)
	assert_array(rows).is_equal([1])


func test_display_rows_empty_non_paginated_falls_back_to_whole_response() -> void:
	# users.delete -> { deletedRooms: [], success: true }: the inferred payload key
	# is empty, so the whole envelope is shown rather than a blank results area.
	var raw := {"deletedRooms": [], "success": true}
	assert_array(EndpointTab.display_rows(raw, [], false)).is_equal([raw])


func test_display_rows_empty_paginated_stays_empty() -> void:
	# A paginated list past its end legitimately has no rows — don't show the envelope.
	assert_array(EndpointTab.display_rows({"users": [], "total": 0}, [], true)).is_empty()


func test_display_rows_empty_non_dictionary_stays_empty() -> void:
	assert_array(EndpointTab.display_rows(null, [], false)).is_empty()
