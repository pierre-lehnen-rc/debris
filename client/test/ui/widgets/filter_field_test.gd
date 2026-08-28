class_name FilterFieldTest
extends "res://test/test_suite.gd"

# Tests for the sidebar filter box: the term matching every list shares, and the
# debounce that turns a burst of typing into one filter_changed.
# See res://source/ui/widgets/filter_field.gd


# Matching --------------------------------------------------------------------
func test_blank_filter_has_no_terms_and_matches_everything() -> void:
	assert_int(FilterField.terms_of("   ").size()).is_equal(0)
	assert_bool(FilterField.matches("anything", FilterField.terms_of(""))).is_true()


func test_single_term_is_a_case_insensitive_substring() -> void:
	var terms := FilterField.terms_of("USERS")
	assert_bool(FilterField.matches("rocketchat_users", terms)).is_true()
	assert_bool(FilterField.matches("rocketchat_rooms", terms)).is_false()


func test_every_term_must_match_in_any_order() -> void:
	# The point of multiple terms: "users update" finds /api/v1/users.update, which
	# no single substring of the typed text would.
	var terms := FilterField.terms_of("users update")
	assert_bool(FilterField.matches("POST /api/v1/users.update", terms)).is_true()
	assert_bool(FilterField.matches("POST /api/v1/update.users", terms)).is_true()
	assert_bool(FilterField.matches("POST /api/v1/users.create", terms)).is_false()


func test_repeated_spaces_do_not_add_empty_terms() -> void:
	assert_int(FilterField.terms_of("  a   b  ").size()).is_equal(2)


func test_a_matching_folder_keeps_a_child_that_does_not_match() -> void:
	# Filtering by a group name shows that group intact, rather than stripping it
	# down to the rows that happen to repeat the name.
	var terms := FilterField.terms_of("rocketchat")
	assert_bool(FilterField.matches_in("message", ["rocketchat"], terms)).is_true()
	assert_bool(FilterField.matches_in("message", ["settings"], terms)).is_false()


func test_matches_in_still_matches_the_leaf_itself() -> void:
	var terms := FilterField.terms_of("message")
	assert_bool(FilterField.matches_in("rocketchat_message", [], terms)).is_true()


# Debounce --------------------------------------------------------------------
func _field() -> FilterField:
	var field := FilterField.new()
	add_child(field)  # runs _ready, which builds the debounce timer
	auto_free(field)
	return field


func test_typing_emits_once_with_the_final_text() -> void:
	var field := _field()
	monitor_signals(field)
	# Three keystrokes inside one debounce window.
	field.text = "u"
	field.text_changed.emit("u")
	field.text = "us"
	field.text_changed.emit("us")
	field.text = "use"
	field.text_changed.emit("use")
	await assert_signal(field).wait_until(500).is_emitted("filter_changed", "use")
	assert_int(int(_sig_counts.get("filter_changed", 0))).is_equal(1)


func test_flush_applies_immediately() -> void:
	var field := _field()
	monitor_signals(field)
	field.text = "  rooms  "
	field.flush()
	# No await: flush skips the debounce, and the text is handed over stripped.
	await assert_signal(field).wait_until(50).is_emitted("filter_changed", "rooms")


func test_unchanged_effective_text_is_not_re_emitted() -> void:
	var field := _field()
	field.text = "rooms"
	field.flush()
	monitor_signals(field)
	# A trailing space leaves the effective filter alone, so the list isn't rebuilt.
	field.text = "rooms "
	field.flush()
	await assert_signal(field).wait_until(50).is_not_emitted("filter_changed")
