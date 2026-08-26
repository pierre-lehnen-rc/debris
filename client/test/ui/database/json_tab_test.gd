class_name JsonTabTest
extends "res://test/test_suite.gd"

# Behavioural tests for JsonTab: it seeds and re-parses its editor text, reports
# what it rendered via status_changed, round-trips its sidecar state, and relabels
# itself when a file is saved from it.
# See res://source/ui/database/json_tab.gd

const JSON_TAB_SCENE := preload("res://source/ui/database/json_tab.tscn")


func test_restore_round_trips_json_state() -> void:
	var tab: JsonTab = JSON_TAB_SCENE.instantiate()
	tab.configure_restore({"kind": "json", "text": "{\"a\": 1}", "title": "data.json"})
	add_child(tab)  # runs _ready synchronously (suite is in the tree)
	auto_free(tab)
	var state := tab.to_state()
	assert_str(state["kind"]).is_equal("json")
	assert_str(state["text"]).is_equal("{\"a\": 1}")
	assert_str(state["title"]).is_equal("data.json")
	assert_str(tab.tab_title()).is_equal("data.json")


func test_configure_seeds_text_and_default_title() -> void:
	var tab: JsonTab = JSON_TAB_SCENE.instantiate()
	tab.configure("[1, 2, 3]")
	add_child(tab)
	auto_free(tab)
	assert_str(tab.json_text()).is_equal("[1, 2, 3]")
	assert_str(tab.tab_title()).is_equal("JSON")


func test_array_reports_item_count() -> void:
	# Monitor before add_child so the parse-on-open status emit is captured.
	var tab: JsonTab = JSON_TAB_SCENE.instantiate()
	tab.configure("[{\"a\": 1}, {\"a\": 2}]")
	monitor_signals(tab)
	add_child(tab)
	auto_free(tab)
	await assert_signal(tab).wait_until(50).is_emitted("status_changed", "Parsed JSON — 2 items")


func test_object_reports_success_without_count() -> void:
	var tab: JsonTab = JSON_TAB_SCENE.instantiate()
	tab.configure("{\"a\": 1}")
	monitor_signals(tab)
	add_child(tab)
	auto_free(tab)
	await assert_signal(tab).wait_until(50).is_emitted("status_changed", "Parsed JSON")


func test_lenient_json5_is_accepted() -> void:
	# Same leniency as the query filter/options editors: unquoted keys, single
	# quotes, a comment and a trailing comma all parse rather than erroring.
	var tab: JsonTab = JSON_TAB_SCENE.instantiate()
	tab.configure("{ a: 1, /* note */ b: 'two', }")
	monitor_signals(tab)
	add_child(tab)
	auto_free(tab)
	await assert_signal(tab).wait_until(50).is_emitted("status_changed", "Parsed JSON")


func test_invalid_json_is_reported_not_parsed() -> void:
	var tab: JsonTab = JSON_TAB_SCENE.instantiate()
	tab.configure("{ not valid ]")
	monitor_signals(tab)
	add_child(tab)
	auto_free(tab)
	# The invalid input is reported, and the "Parsed JSON" success path never runs.
	await get_tree().process_frame
	assert_str(_sig_first_arg.get("status_changed", "")).contains("Invalid JSON")


func test_mark_saved_adopts_filename_as_title() -> void:
	var tab: JsonTab = JSON_TAB_SCENE.instantiate()
	tab.configure("{}")
	add_child(tab)
	auto_free(tab)
	monitor_signals(tab)
	tab.mark_saved("/tmp/export/report.json")
	assert_str(tab.tab_title()).is_equal("report.json")
	await assert_signal(tab).wait_until(50).is_emitted("title_changed", "report.json")
