# GdUnit generated TestSuite
class_name LaxJsonTest
extends "res://test/test_suite.gd"

# Tests for LaxJson — the lenient JSON5-flavoured filter parser.
# See res://source/data/lax_json.gd


func _value(text: String) -> Variant:
	# Parse `text`, assert it succeeded, and return the parsed value.
	var r := LaxJson.parse_string(text)
	assert_bool(r["ok"]).override_failure_message("parse failed: %s" % r["error"]).is_true()
	return r["value"]


func _error(text: String) -> String:
	# Parse `text`, assert it failed, and return the error message.
	var r := LaxJson.parse_string(text)
	assert_bool(r["ok"]).override_failure_message("expected parse to fail").is_false()
	assert_object(r["value"]).is_null()
	return r["error"]


# Empty / whitespace input ----------------------------------------------------
func test_empty_input_is_empty_object() -> void:
	assert_dict(_value("")).is_empty()


func test_whitespace_only_is_empty_object() -> void:
	assert_dict(_value("   \n\t  ")).is_empty()


func test_comment_only_is_empty_object() -> void:
	assert_dict(_value("// just a comment")).is_empty()


# Objects ---------------------------------------------------------------------
func test_empty_object() -> void:
	assert_dict(_value("{}")).is_empty()


func test_double_quoted_keys_and_values() -> void:
	assert_dict(_value('{"name": "quetzal"}')).is_equal({"name": "quetzal"})


func test_single_quoted_keys_and_values() -> void:
	assert_dict(_value("{'name': 'quetzal'}")).is_equal({"name": "quetzal"})


func test_unquoted_identifier_keys() -> void:
	assert_dict(_value("{name: 'quetzal', age: 3}")).is_equal({"name": "quetzal", "age": 3})


func test_mongo_operator_keys() -> void:
	assert_dict(_value("{age: {$gt: 18, $lte: 65}}")).is_equal({"age": {"$gt": 18, "$lte": 65}})


func test_nested_objects() -> void:
	assert_dict(_value("{a: {b: {c: 1}}}")).is_equal({"a": {"b": {"c": 1}}})


func test_trailing_comma_in_object() -> void:
	assert_dict(_value("{a: 1, b: 2,}")).is_equal({"a": 1, "b": 2})


# Arrays ----------------------------------------------------------------------
func test_empty_array() -> void:
	assert_array(_value("[]")).is_empty()


func test_array_of_numbers() -> void:
	assert_array(_value("[1, 2, 3]")).is_equal([1, 2, 3])


func test_array_with_trailing_comma() -> void:
	assert_array(_value("[1, 2,]")).is_equal([1, 2])


func test_mixed_array() -> void:
	assert_array(_value("[1, 'two', true, null]")).is_equal([1, "two", true, null])


func test_nested_arrays_and_objects() -> void:
	assert_dict(_value("{tags: ['a', 'b'], meta: {n: 1}}")).is_equal(
		{"tags": ["a", "b"], "meta": {"n": 1}}
	)


# Scalars ---------------------------------------------------------------------
func test_bare_integer() -> void:
	assert_int(_value("42")).is_equal(42)


func test_negative_integer() -> void:
	assert_int(_value("-7")).is_equal(-7)


func test_float() -> void:
	assert_float(_value("3.14")).is_equal_approx(3.14, 0.0001)


func test_float_with_exponent() -> void:
	assert_float(_value("1.5e3")).is_equal_approx(1500.0, 0.0001)


func test_negative_exponent() -> void:
	assert_float(_value("2e-2")).is_equal_approx(0.02, 0.0001)


func test_boolean_true() -> void:
	assert_bool(_value("true")).is_true()


func test_boolean_false() -> void:
	assert_bool(_value("false")).is_false()


func test_null_keyword() -> void:
	assert_object(_value("null")).is_null()


# String escapes --------------------------------------------------------------
func test_escape_sequences() -> void:
	assert_str(_value('"a\\nb\\tc"')).is_equal("a\nb\tc")


func test_escaped_quote() -> void:
	assert_str(_value('"say \\"hi\\""')).is_equal('say "hi"')


func test_unicode_escape() -> void:
	# A is 'A'
	assert_str(_value('"\\u0041"')).is_equal("A")


func test_unknown_escape_is_literal() -> void:
	# \x is not a recognised escape, so it collapses to the bare char.
	assert_str(_value('"a\\xb"')).is_equal("axb")


# Comments --------------------------------------------------------------------
func test_line_comment_between_fields() -> void:
	assert_dict(_value("{\n  a: 1, // first\n  b: 2\n}")).is_equal({"a": 1, "b": 2})


func test_block_comment() -> void:
	assert_dict(_value("{ a: /* inline */ 1 }")).is_equal({"a": 1})


# Errors ----------------------------------------------------------------------
func test_unterminated_object_after_comma_errors() -> void:
	assert_str(_error("{a: 1,")).contains("Unterminated object")


func test_missing_separator_errors() -> void:
	# End-of-input where a ',' or '}' was expected (no trailing comma).
	assert_str(_error("{a: 1")).contains("Expected ',' or '}'")


func test_unterminated_string_errors() -> void:
	assert_str(_error('{a: "oops}')).contains("Unterminated string")


func test_missing_colon_errors() -> void:
	assert_str(_error("{a 1}")).contains("Expected ':'")


func test_missing_value_name_errors() -> void:
	assert_str(_error("{: 1}")).contains("Expected a property name")


func test_trailing_text_errors() -> void:
	assert_str(_error("{a: 1} extra")).contains("Unexpected trailing text")


func test_unexpected_token_errors() -> void:
	assert_str(_error("{a: bogus}")).contains("Unexpected token 'bogus'")
