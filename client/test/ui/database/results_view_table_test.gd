class_name ResultsViewTableTest
extends "res://test/test_suite.gd"

# Behavioural tests for the raw-mode Table option (set_raw_mode(enabled, allow_table)):
# the models console keeps the Table mode button always available (not blinking in
# and out per result), array results default to it, and the table renders arrays and
# single objects without choking on scalars. Endpoints (allow_table off) hide it.
# See res://source/ui/database/results_view.gd

const RESULTS_VIEW_SCENE := preload("res://source/ui/database/results_view.tscn")


func _view() -> ResultsView:
	var v: ResultsView = RESULTS_VIEW_SCENE.instantiate()
	add_child(v)  # runs _ready synchronously (suite is in the tree)
	auto_free(v)
	return v


func _table_visible(v: ResultsView) -> bool:
	return v._mode_buttons[ResultsView.ViewMode.TABLE].visible


func test_models_table_button_always_visible() -> void:
	# The button is present regardless of the result shape (arrays, single object,
	# scalar) — it never appears/disappears based on what came back.
	var v := _view()
	v.set_raw_mode(true, true)
	assert_bool(_table_visible(v)).is_true()
	v.show_raw([{"_id": "a"}, {"_id": "b"}], [], 2)
	assert_bool(_table_visible(v)).is_true()
	v.show_raw({"_id": "a"}, [], 0)
	assert_bool(_table_visible(v)).is_true()
	v.show_raw(42, [], 0)
	assert_bool(_table_visible(v)).is_true()


func test_result_never_changes_the_selected_mode() -> void:
	# The view stays on whatever mode is selected — an array result (or any other)
	# must not auto-switch to Table. A fresh view starts on Tree.
	var v := _view()
	v.set_raw_mode(true, true)
	v.show_raw([{"_id": "a"}, {"_id": "b"}], [], 2)
	assert_int(v._mode).is_equal(ResultsView.ViewMode.TREE)
	# And it stays put when the user has picked Table across further results.
	v._set_mode(ResultsView.ViewMode.TABLE)
	v.show_raw({"_id": "c"}, [], 0)
	assert_int(v._mode).is_equal(ResultsView.ViewMode.TABLE)


func test_table_renders_every_shape_safely() -> void:
	# Selecting Table must not choke on any result shape: an array of documents, a
	# single object (one row), or scalars (filtered to an empty table).
	var v := _view()
	v.set_raw_mode(true, true)
	v._set_mode(ResultsView.ViewMode.TABLE)
	v.show_raw([{"_id": "a", "n": 1}, {"_id": "b", "n": 2}], [], 2)
	v.show_raw({"_id": "solo"}, [], 0)
	v.show_raw(["x", "y", "z"], [], 3)
	v.show_raw(42, [], 0)
	assert_int(v._mode).is_equal(ResultsView.ViewMode.TABLE)


func test_endpoint_raw_hides_table_button() -> void:
	# Endpoint-style raw mode (allow_table off) never shows the Table.
	var v := _view()
	v.set_raw_mode(true, false)
	v.show_raw([{"_id": "a"}], [], 1)
	assert_bool(_table_visible(v)).is_false()


func test_non_raw_mode_keeps_table() -> void:
	# Document pages (DB query tabs) always offer the Table.
	var v := _view()
	v.set_raw_mode(false)
	assert_bool(_table_visible(v)).is_true()
