# GdUnit generated TestSuite
class_name ApiCatalogTest
extends "res://test/test_suite.gd"

# Tests for ApiCatalog — the curated set of built-in endpoints and the
# Dictionary → ApiEndpoint bulk parser.
# See res://source/classes/api_catalog.gd


# from_dicts ------------------------------------------------------------------
func test_from_dicts_empty_returns_empty() -> void:
	assert_array(ApiCatalog.from_dicts([])).is_empty()


func test_from_dicts_builds_api_endpoints() -> void:
	var out := ApiCatalog.from_dicts([{"id": "a"}, {"id": "b"}])
	assert_array(out).has_size(2)
	assert_object(out[0]).is_instanceof(ApiEndpoint)
	assert_str(out[0].id).is_equal("a")
	assert_str(out[1].id).is_equal("b")


func test_from_dicts_skips_malformed_entries() -> void:
	var out := ApiCatalog.from_dicts([{"id": "a"}, "not a dict", 42, null, {"id": "b"}])
	assert_array(out).has_size(2)
	assert_str(out[0].id).is_equal("a")
	assert_str(out[1].id).is_equal("b")


# builtin ---------------------------------------------------------------------
func test_builtin_is_non_empty() -> void:
	assert_array(ApiCatalog.builtin()).has_size(7)


func test_builtin_entries_are_api_endpoints() -> void:
	for e in ApiCatalog.builtin():
		assert_object(e).is_instanceof(ApiEndpoint)


func test_builtin_first_entry_is_channels_list() -> void:
	var e: ApiEndpoint = ApiCatalog.builtin()[0]
	assert_str(e.id).is_equal("channels.list")
	assert_str(e.tag).is_equal("Channels")
	assert_str(e.result_key).is_equal("channels")
	assert_bool(e.paginated).is_true()


func test_builtin_ids_cover_expected_endpoints() -> void:
	var ids := []
	for e in ApiCatalog.builtin():
		ids.append(e.id)
	assert_array(ids).contains([
		"channels.list", "channels.info", "channels.members",
		"users.list", "users.info", "chat.getMessage", "im.list",
	])


func test_builtin_carries_item_noun_where_declared() -> void:
	# channels.members declares an explicit singular noun.
	var members: ApiEndpoint = null
	for e in ApiCatalog.builtin():
		if e.id == "channels.members":
			members = e
	assert_object(members).is_not_null()
	assert_str(members.item_noun).is_equal("member")
	assert_str(members.noun()).is_equal("member")
