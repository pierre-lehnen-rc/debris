# GdUnit generated TestSuite
class_name OpenApiParserTest
extends "res://test/test_suite.gd"

# Tests for OpenApiParser — turns an OpenAPI 3 document into ApiEndpoint objects.
# See res://source/classes/openapi_parser.gd


func _parse_one(path: String, method: String, op: Dictionary) -> ApiEndpoint:
	# Wrap a single operation in a minimal doc, parse it, and return the one
	# ApiEndpoint produced.
	var out := OpenApiParser.parse({"paths": {path: {method: op}}})
	assert_array(out).override_failure_message("expected exactly one endpoint").has_size(1)
	return out[0]


func _param_named(e: ApiEndpoint, name: String) -> Dictionary:
	# Find a parsed param dict by name (or {} if absent).
	for p in e.params:
		if p.get("name", "") == name:
			return p
	return {}


func _ok_json_response(schema: Dictionary) -> Dictionary:
	# Build a `responses` block whose 200 carries the given JSON schema.
	return {"200": {"content": {"application/json": {"schema": schema}}}}


# Empty / malformed documents -------------------------------------------------
func test_empty_doc_returns_empty() -> void:
	assert_array(OpenApiParser.parse({})).is_empty()


func test_paths_not_a_dictionary_returns_empty() -> void:
	assert_array(OpenApiParser.parse({"paths": "nope"})).is_empty()


func test_no_paths_returns_empty() -> void:
	assert_array(OpenApiParser.parse({"paths": {}})).is_empty()


func test_path_item_not_a_dictionary_is_skipped() -> void:
	assert_array(OpenApiParser.parse({"paths": {"/api/v1/x": "nope"}})).is_empty()


func test_path_item_without_http_method_yields_no_endpoint() -> void:
	assert_array(OpenApiParser.parse({"paths": {"/api/v1/x": {"description": "d"}}})).is_empty()


# Multiple methods / endpoint counting ---------------------------------------
func test_multiple_methods_on_one_path_produce_multiple_endpoints() -> void:
	var doc := {"paths": {"/api/v1/channels.foo": {
		"get": {"responses": _ok_json_response({})},
		"post": {"responses": _ok_json_response({})},
	}}}
	var out := OpenApiParser.parse(doc)
	assert_array(out).has_size(2)
	var methods := [out[0].method, out[1].method]
	assert_array(methods).contains(["GET", "POST"])


# Id / tag derivation from path ----------------------------------------------
func test_id_strips_api_v1_prefix() -> void:
	var e := _parse_one("/api/v1/channels.list", "get", {"responses": _ok_json_response({})})
	assert_str(e.id).is_equal("channels.list")


func test_id_strips_bare_api_prefix() -> void:
	var e := _parse_one("/api/some.thing", "get", {"responses": _ok_json_response({})})
	assert_str(e.id).is_equal("some.thing")


func test_tag_derived_from_dotted_id() -> void:
	var e := _parse_one("/api/v1/channels.list", "get", {"responses": _ok_json_response({})})
	assert_str(e.tag).is_equal("Channels")


func test_tag_from_dotless_single_segment_id() -> void:
	var e := _parse_one("/api/v1/info", "get", {"responses": _ok_json_response({})})
	assert_str(e.id).is_equal("info")
	assert_str(e.tag).is_equal("Info")


func test_tag_from_first_path_segment_when_no_dot() -> void:
	var e := _parse_one("/api/v1/livechat/rooms", "get", {"responses": _ok_json_response({})})
	assert_str(e.id).is_equal("livechat/rooms")
	assert_str(e.tag).is_equal("Livechat")


# Summary fallback ------------------------------------------------------------
func test_summary_uses_summary_field() -> void:
	var e := _parse_one("/api/v1/x", "get",
		{"summary": "A summary", "responses": _ok_json_response({})})
	assert_str(e.summary).is_equal("A summary")


func test_summary_falls_back_to_description() -> void:
	var e := _parse_one("/api/v1/x", "get",
		{"description": "A description", "responses": _ok_json_response({})})
	assert_str(e.summary).is_equal("A description")


func test_summary_empty_when_neither_present() -> void:
	var e := _parse_one("/api/v1/x", "get", {"responses": _ok_json_response({})})
	assert_str(e.summary).is_empty()


# Method + path passthrough ---------------------------------------------------
func test_method_is_uppercased() -> void:
	var e := _parse_one("/api/v1/x", "post", {"responses": _ok_json_response({})})
	assert_str(e.method).is_equal("POST")


func test_path_is_preserved() -> void:
	var e := _parse_one("/api/v1/channels.list", "get", {"responses": _ok_json_response({})})
	assert_str(e.path).is_equal("/api/v1/channels.list")


# GET query-object flattening -------------------------------------------------
func _channels_list_op() -> Dictionary:
	return {
		"summary": "List channels",
		"parameters": [{
			"name": "query",
			"in": "query",
			"schema": {
				"type": "object",
				"properties": {
					"offset": {"type": "integer", "default": 0},
					"count": {"type": "integer", "default": 50},
					"sort": {"type": "string", "description": "sort spec"},
				},
				"required": ["count"],
			},
		}],
		"responses": _ok_json_response({
			"type": "object",
			"properties": {
				"channels": {"type": "array"},
				"count": {"type": "integer"},
				"offset": {"type": "integer"},
				"total": {"type": "integer"},
				"success": {"type": "boolean"},
			},
		}),
	}


func test_query_object_is_flattened_into_fields() -> void:
	var e := _parse_one("/api/v1/channels.list", "get", _channels_list_op())
	var names := []
	for p in e.params:
		names.append(p.get("name", ""))
	assert_array(names).is_equal(["offset", "count", "sort"])


func test_flattened_param_keeps_location_and_typing() -> void:
	var e := _parse_one("/api/v1/channels.list", "get", _channels_list_op())
	assert_dict(_param_named(e, "offset")).is_equal({
		"name": "offset", "in": "query", "type": "int",
		"required": false, "description": "", "default": 0,
	})


func test_flattened_required_comes_from_required_list() -> void:
	var e := _parse_one("/api/v1/channels.list", "get", _channels_list_op())
	assert_dict(_param_named(e, "count")).is_equal({
		"name": "count", "in": "query", "type": "int",
		"required": true, "description": "", "default": 50,
	})


func test_flattened_string_param_carries_description() -> void:
	var e := _parse_one("/api/v1/channels.list", "get", _channels_list_op())
	assert_dict(_param_named(e, "sort")).is_equal({
		"name": "sort", "in": "query", "type": "string",
		"required": false, "description": "sort spec",
	})


# Explicit (non-object) params + schema hints ---------------------------------
func _users_info_op() -> Dictionary:
	return {
		"summary": "Get user",
		"parameters": [
			{"name": "userId", "in": "query", "required": true,
				"schema": {"type": "string"}},
			{"name": "fields", "in": "query",
				"schema": {"type": "string", "enum": ["a", "b"],
					"format": "json", "default": "a"}},
			{"name": "limit", "in": "query",
				"schema": {"type": "integer", "minimum": 1, "maximum": 100}},
		],
		"responses": _ok_json_response({
			"type": "object",
			"properties": {"user": {"type": "object"}, "success": {"type": "boolean"}},
		}),
	}


func test_explicit_string_param_typed_and_required() -> void:
	var e := _parse_one("/api/v1/users.info", "get", _users_info_op())
	assert_dict(_param_named(e, "userId")).is_equal({
		"name": "userId", "in": "query", "type": "string",
		"required": true, "description": "",
	})


func test_param_carries_enum_format_and_default() -> void:
	var e := _parse_one("/api/v1/users.info", "get", _users_info_op())
	assert_dict(_param_named(e, "fields")).is_equal({
		"name": "fields", "in": "query", "type": "string",
		"required": false, "description": "",
		"format": "json", "enum": ["a", "b"], "default": "a",
	})


func test_integer_param_carries_bounds() -> void:
	var e := _parse_one("/api/v1/users.info", "get", _users_info_op())
	assert_dict(_param_named(e, "limit")).is_equal({
		"name": "limit", "in": "query", "type": "int",
		"required": false, "description": "",
		"minimum": 1, "maximum": 100,
	})


# Request body flattening (POST) ----------------------------------------------
func _channels_create_op() -> Dictionary:
	return {
		"description": "Create channel",
		"requestBody": {"content": {"application/json": {"schema": {
			"type": "object",
			"properties": {
				"name": {"type": "string", "description": "channel name"},
				"members": {"type": "array", "items": {"type": "string"}},
				"readOnly": {"type": "boolean", "default": false},
			},
			"required": ["name"],
		}}}},
		"responses": _ok_json_response({
			"type": "object",
			"properties": {"success": {"type": "boolean"}, "channel": {"type": "object"}},
		}),
	}


func test_request_body_is_flattened_into_body_params() -> void:
	var e := _parse_one("/api/v1/channels.create", "post", _channels_create_op())
	assert_dict(_param_named(e, "name")).is_equal({
		"name": "name", "in": "body", "type": "string",
		"required": true, "description": "channel name",
	})


func test_array_property_is_typed_as_array_with_item_type() -> void:
	var e := _parse_one("/api/v1/channels.create", "post", _channels_create_op())
	assert_dict(_param_named(e, "members")).is_equal({
		"name": "members", "in": "body", "type": "array",
		"required": false, "description": "", "item_type": "string",
	})


func test_array_of_integers_carries_int_item_type() -> void:
	var op := {"requestBody": {"content": {"application/json": {"schema": {
		"type": "object",
		"properties": {"ids": {"type": "array", "items": {"type": "integer"}}},
	}}}}, "responses": _ok_json_response({})}
	var e := _parse_one("/api/v1/x.create", "post", op)
	assert_str(_param_named(e, "ids")["item_type"]).is_equal("int")


func test_array_without_items_defaults_item_type_to_string() -> void:
	var op := {"requestBody": {"content": {"application/json": {"schema": {
		"type": "object",
		"properties": {"tags": {"type": "array"}},
	}}}}, "responses": _ok_json_response({})}
	var e := _parse_one("/api/v1/x.create", "post", op)
	assert_str(_param_named(e, "tags")["item_type"]).is_equal("string")


func test_boolean_property_maps_to_bool() -> void:
	var e := _parse_one("/api/v1/channels.create", "post", _channels_create_op())
	assert_dict(_param_named(e, "readOnly")).is_equal({
		"name": "readOnly", "in": "body", "type": "bool",
		"required": false, "description": "", "default": false,
	})


# Pagination inference --------------------------------------------------------
func test_paginated_when_offset_and_count_present() -> void:
	var e := _parse_one("/api/v1/channels.list", "get", _channels_list_op())
	assert_bool(e.paginated).is_true()
	assert_str(e.offset_param).is_equal("offset")
	assert_str(e.count_param).is_equal("count")


func test_not_paginated_without_both_params() -> void:
	var e := _parse_one("/api/v1/channels.create", "post", _channels_create_op())
	assert_bool(e.paginated).is_false()


# Result-key inference from the 200 response ----------------------------------
func test_list_result_uses_first_array_property() -> void:
	var e := _parse_one("/api/v1/channels.list", "get", _channels_list_op())
	assert_str(e.result_key).is_equal("channels")
	assert_bool(e.single).is_false()


func test_single_result_uses_first_non_meta_property() -> void:
	var e := _parse_one("/api/v1/channels.create", "post", _channels_create_op())
	assert_str(e.result_key).is_equal("channel")
	assert_bool(e.single).is_true()


func test_array_property_wins_over_earlier_object_property() -> void:
	# The array-preference loop scans all props, so a later array beats an
	# earlier single object.
	var e := _parse_one("/api/v1/x", "get", {"responses": _ok_json_response({
		"type": "object",
		"properties": {"user": {"type": "object"}, "assets": {"type": "array"}},
	})})
	assert_str(e.result_key).is_equal("assets")
	assert_bool(e.single).is_false()


func test_meta_only_response_has_no_result_key() -> void:
	var e := _parse_one("/api/v1/ping", "get", {"responses": _ok_json_response({
		"type": "object",
		"properties": {"success": {"type": "boolean"}},
	})})
	assert_str(e.result_key).is_empty()
	assert_bool(e.single).is_false()


func test_missing_response_schema_has_no_result_key() -> void:
	var e := _parse_one("/api/v1/x", "get", {"responses": {}})
	assert_str(e.result_key).is_empty()
