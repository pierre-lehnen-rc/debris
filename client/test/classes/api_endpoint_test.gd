# GdUnit generated TestSuite
class_name ApiEndpointTest
extends "res://test/test_suite.gd"

# Tests for ApiEndpoint — one modelled Rocket.Chat REST endpoint.
# See res://source/classes/api_endpoint.gd


# from_dict round-trip --------------------------------------------------------
func test_from_dict_populates_all_fields() -> void:
	var params := [{"name": "roomId", "in": "query", "type": "string"}]
	var e := ApiEndpoint.from_dict({
		"id": "channels.members",
		"tag": "Channels",
		"summary": "List members",
		"method": "GET",
		"path": "/api/v1/channels.members",
		"params": params,
		"result_key": "members",
		"single": false,
		"paginated": true,
		"offset_param": "off",
		"count_param": "cnt",
		"item_noun": "member",
	})
	assert_str(e.id).is_equal("channels.members")
	assert_str(e.tag).is_equal("Channels")
	assert_str(e.summary).is_equal("List members")
	assert_str(e.method).is_equal("GET")
	assert_str(e.path).is_equal("/api/v1/channels.members")
	assert_array(e.params).is_equal(params)
	assert_str(e.result_key).is_equal("members")
	assert_bool(e.single).is_false()
	assert_bool(e.paginated).is_true()
	assert_str(e.offset_param).is_equal("off")
	assert_str(e.count_param).is_equal("cnt")
	assert_str(e.item_noun).is_equal("member")


# to_dict round-trip ----------------------------------------------------------
func test_to_dict_round_trips_through_from_dict() -> void:
	# A cached endpoint (used by the .debris-workspace endpoint cache) must survive
	# a to_dict → from_dict cycle unchanged, so an offline reload is faithful.
	var original := ApiEndpoint.from_dict({
		"id": "channels.members",
		"tag": "Channels",
		"summary": "List members",
		"method": "GET",
		"path": "/api/v1/channels.members",
		"params": [{"name": "roomId", "in": "query", "type": "string"}],
		"result_key": "members",
		"single": false,
		"paginated": true,
		"offset_param": "offset",
		"count_param": "count",
		"item_noun": "member",
	})
	var round_tripped := ApiEndpoint.from_dict(original.to_dict())
	assert_dict(round_tripped.to_dict()).is_equal(original.to_dict())


func test_to_dict_survives_json_round_trip() -> void:
	# The cache is stored as JSON, so a stringify/parse cycle must not change it.
	var original := ApiEndpoint.from_dict({"id": "users.list", "paginated": true})
	var json: Variant = JSON.parse_string(JSON.stringify(original.to_dict()))
	assert_dict(ApiEndpoint.from_dict(json).to_dict()).is_equal(original.to_dict())


# Defaults --------------------------------------------------------------------
func test_from_dict_empty_uses_defaults() -> void:
	var e := ApiEndpoint.from_dict({})
	assert_str(e.id).is_empty()
	assert_str(e.tag).is_equal("General")
	assert_str(e.summary).is_empty()
	assert_str(e.method).is_equal("GET")
	assert_str(e.path).is_equal("/api/v1/")
	assert_array(e.params).is_empty()
	assert_str(e.result_key).is_empty()
	assert_bool(e.single).is_false()
	assert_bool(e.paginated).is_false()
	assert_str(e.offset_param).is_equal("offset")
	assert_str(e.count_param).is_equal("count")
	assert_str(e.item_noun).is_empty()


func test_path_defaults_from_id_when_absent() -> void:
	var e := ApiEndpoint.from_dict({"id": "channels.list"})
	assert_str(e.path).is_equal("/api/v1/channels.list")


# form_params -----------------------------------------------------------------
func test_form_params_excludes_pagination_params_when_paginated() -> void:
	var e := ApiEndpoint.from_dict({
		"paginated": true,
		"params": [
			{"name": "offset"}, {"name": "count"}, {"name": "sort"},
		],
	})
	var out := e.form_params()
	assert_array(out).has_size(1)
	assert_str(out[0]["name"]).is_equal("sort")


func test_form_params_keeps_pagination_params_when_not_paginated() -> void:
	var e := ApiEndpoint.from_dict({
		"paginated": false,
		"params": [
			{"name": "offset"}, {"name": "count"}, {"name": "sort"},
		],
	})
	assert_array(e.form_params()).has_size(3)


func test_form_params_uses_custom_pagination_names() -> void:
	var e := ApiEndpoint.from_dict({
		"paginated": true,
		"offset_param": "skip",
		"count_param": "limit",
		"params": [
			{"name": "skip"}, {"name": "limit"}, {"name": "roomId"},
		],
	})
	var out := e.form_params()
	assert_array(out).has_size(1)
	assert_str(out[0]["name"]).is_equal("roomId")


func test_form_params_empty_when_no_params() -> void:
	assert_array(ApiEndpoint.from_dict({}).form_params()).is_empty()


# noun ------------------------------------------------------------------------
func test_noun_prefers_item_noun() -> void:
	var e := ApiEndpoint.from_dict({"item_noun": "DM", "result_key": "ims"})
	assert_str(e.noun()).is_equal("DM")


func test_noun_trims_trailing_s_from_result_key() -> void:
	var e := ApiEndpoint.from_dict({"result_key": "channels"})
	assert_str(e.noun()).is_equal("channel")


func test_noun_keeps_result_key_without_trailing_s() -> void:
	var e := ApiEndpoint.from_dict({"result_key": "user"})
	assert_str(e.noun()).is_equal("user")


func test_noun_defaults_to_result_when_no_key() -> void:
	assert_str(ApiEndpoint.from_dict({}).noun()).is_equal("result")


# label -----------------------------------------------------------------------
func test_label_uses_id_when_present() -> void:
	var e := ApiEndpoint.from_dict({"id": "channels.list", "path": "/api/v1/channels.list"})
	assert_str(e.label()).is_equal("channels.list")


func test_label_falls_back_to_path_when_id_empty() -> void:
	var e := ApiEndpoint.from_dict({"id": "", "path": "/api/v1/thing"})
	assert_str(e.label()).is_equal("/api/v1/thing")


# segments --------------------------------------------------------------------
func test_segments_splits_dotted_leaf() -> void:
	var e := ApiEndpoint.from_dict({"id": "channels.list"})
	assert_array(Array(e.segments())).is_equal(["channels", "list"])


func test_segments_folder_chain_with_dotted_leaf() -> void:
	var e := ApiEndpoint.from_dict({"id": "livechat/rooms.delete"})
	assert_array(Array(e.segments())).is_equal(["livechat", "rooms", "delete"])


func test_segments_plain_path_chain() -> void:
	var e := ApiEndpoint.from_dict({"id": "livechat/config/routing"})
	assert_array(Array(e.segments())).is_equal(["livechat", "config", "routing"])


func test_segments_preserves_placeholder_segment() -> void:
	var e := ApiEndpoint.from_dict({"id": "apps/:id/logs"})
	assert_array(Array(e.segments())).is_equal(["apps", ":id", "logs"])


func test_segments_falls_back_to_path_when_id_empty() -> void:
	var e := ApiEndpoint.from_dict({"id": "", "path": "/api/v1/channels.list"})
	assert_array(Array(e.segments())).is_equal(["api", "v1", "channels", "list"])
