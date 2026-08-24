class_name RocketChatTest
extends "res://test/test_suite.gd"

# Tests for RocketChat's query-string builder — in particular that array-valued
# params expand into repeated "key[]=v" pairs so list params serialize correctly.
# See res://source/data/rocket_chat.gd


func test_empty_query_yields_empty_string() -> void:
	assert_str(RocketChat._query_string({})).is_equal("")


func test_scalar_params_are_encoded() -> void:
	assert_str(RocketChat._query_string({"count": 50})).is_equal("?count=50")


func test_null_values_are_skipped() -> void:
	assert_str(RocketChat._query_string({"a": null})).is_equal("")


func test_special_characters_are_uri_encoded() -> void:
	assert_str(RocketChat._query_string({"q": "a b/c"})).is_equal("?q=a%20b%2Fc")


func test_array_value_expands_to_bracket_pairs() -> void:
	assert_str(RocketChat._query_string({"roles": ["admin", "user"]})).is_equal(
		"?roles%5B%5D=admin&roles%5B%5D=user"
	)


func test_empty_array_contributes_nothing() -> void:
	assert_str(RocketChat._query_string({"roles": []})).is_equal("")
