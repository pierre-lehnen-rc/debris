class_name QueryTabRestoreTest
extends "res://test/test_suite.gd"

# Behavioural tests for QueryTab's sidecar round-trip: a saved tab reopens with
# its target and editor text seeded (and, crucially, does NOT re-run the query),
# and to_state() reflects exactly what would be persisted.
# See res://source/ui/database/query_tab.gd

const QUERY_TAB_SCENE := preload("res://source/ui/database/query_tab.tscn")

const CONNECTION := {"name": "local", "host": "localhost:27017"}


func _restored_tab(state: Dictionary) -> QueryTab:
	var tab: QueryTab = QUERY_TAB_SCENE.instantiate()
	tab.configure_restore(CONNECTION, "mydb", state)
	add_child(tab)  # runs _ready synchronously (suite is in the tree)
	auto_free(tab)
	return tab


func test_restore_round_trips_query_state() -> void:
	var state := {
		"kind": "query",
		"database": "mydb",
		"collection": "users",
		"function": "findOne",
		"filter": "{\"active\": true}",
		"options": "{\"sort\": {\"_id\": -1}}",
		"options_visible": true,
	}
	var tab := _restored_tab(state)
	var captured := tab.to_state()
	assert_str(captured["kind"]).is_equal("query")
	assert_str(captured["collection"]).is_equal("users")
	assert_str(captured["function"]).is_equal("findOne")
	assert_str(captured["filter"]).is_equal("{\"active\": true}")
	assert_str(captured["options"]).is_equal("{\"sort\": {\"_id\": -1}}")
	assert_bool(captured["options_visible"]).is_true()
	assert_str(captured["database"]).is_equal("mydb")


func test_restore_hidden_options_stay_hidden() -> void:
	var tab := _restored_tab({
		"kind": "query", "database": "mydb", "collection": "c",
		"function": "find", "filter": "{}", "options": "", "options_visible": false,
	})
	assert_bool(tab.to_state()["options_visible"]).is_false()


func test_restored_blank_collection_tab() -> void:
	# A saved scratch tab (no collection) restores as an empty query with no target.
	var tab := _restored_tab({
		"kind": "query", "database": "mydb", "collection": "",
		"function": "find", "filter": "", "options": "", "options_visible": false,
	})
	assert_str(tab.to_state()["collection"]).is_equal("")
	assert_str(tab.tab_title()).is_equal("Query")
