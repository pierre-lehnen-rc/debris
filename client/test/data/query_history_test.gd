class_name QueryHistoryTest
extends "res://test/test_suite.gd"

# Tests for QueryHistory — the coordinator over a project's recents (WorkspaceState
# sidecar) and favorites (WorkspaceDoc project file). See
# res://source/data/query_history.gd


func _history() -> Array:
	# Returns [history, state, doc] wired together.
	var state := WorkspaceState.new()
	var doc := WorkspaceDoc.new()
	var h := QueryHistory.new()
	h.setup(state, doc)
	return [h, state, doc]


func _entry(filter: String, function := "find", options := "") -> Dictionary:
	return {"function": function, "filter": filter, "options": options}


# same_query ------------------------------------------------------------------
func test_same_query_matches_ignoring_whitespace() -> void:
	assert_bool(QueryHistory.same_query(_entry("{\"a\": 1}"), _entry(" {\"a\": 1}\n"))).is_true()


func test_same_query_differs_by_function() -> void:
	assert_bool(QueryHistory.same_query(_entry("{}", "find"), _entry("{}", "findOne"))).is_false()


func test_same_query_differs_by_options() -> void:
	assert_bool(QueryHistory.same_query(
		_entry("{}", "find", ""), _entry("{}", "find", "{\"sort\": {}}"))).is_false()


# preview ---------------------------------------------------------------------
func test_preview_collapses_whitespace() -> void:
	assert_str(QueryHistory.preview(_entry("{\n\t\"a\": 1\n}"))).is_equal("{ \"a\": 1 }")


func test_preview_blank_filter_shows_braces() -> void:
	assert_str(QueryHistory.preview(_entry("   "))).is_equal("{}")


func test_preview_prefixes_non_find_function() -> void:
	assert_str(QueryHistory.preview(_entry("{}", "countDocuments"))).contains("countDocuments")


func test_preview_shows_options_content() -> void:
	# The options object is shown, not just flagged.
	var text := QueryHistory.preview(_entry("{}", "find", "{\"sort\": {\"_id\": -1}}"))
	assert_str(text).contains("options")
	assert_str(text).contains("{\"sort\": {\"_id\": -1}}")


func test_preview_shows_options_over_empty_filter() -> void:
	# An entry with only options still renders its filter as {} plus the options.
	var text := QueryHistory.preview(_entry("", "find", "{\"limit\": 5}"))
	assert_str(text).contains("{}")
	assert_str(text).contains("{\"limit\": 5}")


# recents (sidecar) -----------------------------------------------------------
func test_record_writes_to_state_and_signals() -> void:
	var wired := _history()
	var h: QueryHistory = wired[0]
	var state: WorkspaceState = wired[1]
	monitor_signals(h)
	h.record("users", _entry("{\"a\": 1}"))
	await assert_signal(h).is_emitted("recents_changed")
	assert_int(state.recent_queries("users").size()).is_equal(1)
	assert_int(h.recents("users").size()).is_equal(1)


func test_record_ignores_empty_collection() -> void:
	var wired := _history()
	var h: QueryHistory = wired[0]
	monitor_signals(h)
	h.record("", _entry("{\"a\": 1}"))
	await assert_signal(h).is_not_emitted("recents_changed")


func test_remove_recent_signals() -> void:
	var wired := _history()
	var h: QueryHistory = wired[0]
	h.record("users", _entry("{\"a\": 1}"))
	monitor_signals(h)
	h.remove_recent("users", 0)
	await assert_signal(h).is_emitted("recents_changed")
	assert_int(h.recents("users").size()).is_equal(0)


# favorites (project doc) -----------------------------------------------------
func test_add_favorite_writes_to_doc_and_signals() -> void:
	var wired := _history()
	var h: QueryHistory = wired[0]
	var doc: WorkspaceDoc = wired[2]
	monitor_signals(h)
	h.add_favorite("users", _entry("{\"a\": 1}"))
	await assert_signal(h).is_emitted("favorites_changed")
	assert_int(doc.favorite_queries_for("users").size()).is_equal(1)
	assert_bool(doc.dirty).is_true()


func test_add_favorite_duplicate_does_not_signal() -> void:
	var wired := _history()
	var h: QueryHistory = wired[0]
	h.add_favorite("users", _entry("{\"a\": 1}"))
	monitor_signals(h)
	h.add_favorite("users", _entry("{\"a\": 1}"))
	await assert_signal(h).is_not_emitted("favorites_changed")


func test_is_favorite_reflects_membership() -> void:
	var wired := _history()
	var h: QueryHistory = wired[0]
	assert_bool(h.is_favorite("users", _entry("{\"a\": 1}"))).is_false()
	h.add_favorite("users", _entry("{\"a\": 1}"))
	assert_bool(h.is_favorite("users", _entry("{\"a\": 1}"))).is_true()


func test_remove_favorite_signals() -> void:
	var wired := _history()
	var h: QueryHistory = wired[0]
	h.add_favorite("users", _entry("{\"a\": 1}"))
	monitor_signals(h)
	h.remove_favorite("users", _entry("{\"a\": 1}"))
	await assert_signal(h).is_emitted("favorites_changed")
	assert_bool(h.is_favorite("users", _entry("{\"a\": 1}"))).is_false()
