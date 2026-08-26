class_name QueryTabSortTest
extends "res://test/test_suite.gd"

# Tests for the "Sort by this field" handoff: a results-view sort request folds the
# attribute into the query's options JSON (compound, in place) and reveals the
# options editor without running. A restored blank tab never auto-runs, so no
# backend is touched. See res://source/ui/database/query_tab.gd

const QUERY_TAB_SCENE := preload("res://source/ui/database/query_tab.tscn")

const CONNECTION := {"name": "local", "host": "localhost:27017"}


func _tab(options := "", options_visible := false) -> QueryTab:
	var tab: QueryTab = QUERY_TAB_SCENE.instantiate()
	tab.configure_restore(CONNECTION, "mydb", {
		"kind": "query", "database": "mydb", "collection": "",
		"function": "find", "filter": "", "options": options, "options_visible": options_visible,
	})
	add_child(tab)
	auto_free(tab)
	return tab


## Parse the tab's current options editor text into a dict. Uses LaxJson (like the
## app) so integers stay ints — sort directions are 1 / -1, not 1.0 / -1.0.
func _options(tab: QueryTab) -> Dictionary:
	var text: String = tab.to_state()["options"]
	var parsed: Dictionary = LaxJson.parse_string(text)
	return parsed["value"] if parsed.get("ok", false) and parsed["value"] is Dictionary else {}


func test_sort_added_to_empty_options() -> void:
	var tab := _tab()
	tab._on_sort_requested("name", 1)
	assert_bool(tab.to_state()["options_visible"]).is_true()
	assert_dict(_options(tab)).is_equal({"sort": {"name": 1}})


func test_sort_descending() -> void:
	var tab := _tab()
	tab._on_sort_requested("age", -1)
	assert_dict(_options(tab)).is_equal({"sort": {"age": -1}})


func test_sort_is_compound_and_preserves_other_options() -> void:
	var tab := _tab("{\"projection\": {\"name\": 1}, \"sort\": {\"name\": 1}}", true)
	tab._on_sort_requested("age", -1)
	var opts := _options(tab)
	assert_dict(opts["sort"]).is_equal({"name": 1, "age": -1})
	assert_dict(opts["projection"]).is_equal({"name": 1})


func test_re_sorting_same_field_updates_direction() -> void:
	var tab := _tab("{\"sort\": {\"name\": 1}}", true)
	tab._on_sort_requested("name", -1)
	assert_dict(_options(tab)["sort"]).is_equal({"name": -1})


func test_invalid_options_json_is_left_untouched() -> void:
	# A broken options editor must not be silently rewritten.
	var tab := _tab("{ not valid json", true)
	tab._on_sort_requested("name", 1)
	assert_str(tab.to_state()["options"]).is_equal("{ not valid json")


func test_sort_reveals_hidden_options_editor() -> void:
	var tab := _tab("", false)
	tab._on_sort_requested("name", 1)
	assert_bool(tab.to_state()["options_visible"]).is_true()


func test_sort_merges_into_array_form_sort() -> void:
	# Mongo tuple-array sort form: a prior entry for the field is replaced, the new
	# one appended, and other keys kept.
	var tab := _tab("{\"sort\": [[\"name\", 1]]}", true)
	tab._on_sort_requested("name", -1)
	assert_array(_options(tab)["sort"]).is_equal([["name", -1]])
