class_name QueryTabHistoryTest
extends "res://test/test_suite.gd"

# Behavioural tests for applying a saved query to a QueryTab's editors. apply_entry
# fills the operation/filter/options WITHOUT running (consistent with tab restore),
# so it's verified through to_state() rather than any backend call.
# See res://source/ui/database/query_tab.gd

const QUERY_TAB_SCENE := preload("res://source/ui/database/query_tab.tscn")

const CONNECTION := {"name": "local", "host": "localhost:27017"}


func _blank_tab() -> QueryTab:
	# A restored blank-collection tab never auto-runs, so no backend is touched.
	var tab: QueryTab = QUERY_TAB_SCENE.instantiate()
	tab.configure_restore(CONNECTION, "mydb", {
		"kind": "query", "database": "mydb", "collection": "",
		"function": "find", "filter": "", "options": "", "options_visible": false,
	})
	add_child(tab)
	auto_free(tab)
	return tab


func test_apply_entry_fills_filter_and_function() -> void:
	var tab := _blank_tab()
	tab.apply_entry({
		"function": "findOne",
		"filter": "{\"active\": true}",
		"options": "",
		"options_visible": false,
	})
	var state := tab.to_state()
	assert_str(state["function"]).is_equal("findOne")
	assert_str(state["filter"]).is_equal("{\"active\": true}")
	assert_bool(state["options_visible"]).is_false()


func test_apply_entry_shows_and_fills_options() -> void:
	var tab := _blank_tab()
	tab.apply_entry({
		"function": "find",
		"filter": "{}",
		"options": "{\"sort\": {\"_id\": -1}}",
		"options_visible": true,
	})
	var state := tab.to_state()
	assert_bool(state["options_visible"]).is_true()
	assert_str(state["options"]).is_equal("{\"sort\": {\"_id\": -1}}")


func test_apply_entry_hides_options_when_flagged_hidden() -> void:
	var tab := _blank_tab()
	# First reveal options, then apply an entry that had them hidden.
	tab.apply_entry({"function": "find", "filter": "{}", "options": "{\"x\": 1}", "options_visible": true})
	tab.apply_entry({"function": "find", "filter": "{}", "options": "", "options_visible": false})
	assert_bool(tab.to_state()["options_visible"]).is_false()


func test_apply_entry_unknown_function_keeps_default() -> void:
	var tab := _blank_tab()
	tab.apply_entry({"function": "bogus", "filter": "{}", "options": "", "options_visible": false})
	# An unrecognised operation leaves the current selection untouched (find).
	assert_str(tab.to_state()["function"]).is_equal("find")
