class_name ResultsViewJsonTest
extends "res://test/test_suite.gd"

# Behavioural tests for the results view's "open in a JSON tab" actions:
#   - _is_container classifies objects/arrays vs scalars and EJSON wrappers;
#   - VIEW_JSON emits the selected object/array as pretty JSON;
#   - VIEW_STRING_JSON emits an untyped string's contents verbatim.
# See res://source/ui/database/results/doc_results_view.gd

const TREE_VIEW_SCENE := preload("res://source/ui/database/results/tree_results_view.tscn")


func _tree() -> TreeResultsView:
	var view: TreeResultsView = TREE_VIEW_SCENE.instantiate()
	add_child(view)  # runs _ready synchronously (suite is in the tree)
	auto_free(view)
	return view


## The direct child of `item` whose metadata key equals `key`, or null.
func _field_child(item: TreeItem, key: String) -> TreeItem:
	var child := item.get_first_child()
	while child != null:
		var meta: Variant = child.get_metadata(0)
		if meta is Dictionary and str((meta as Dictionary).get("key", "")) == key:
			return child
		child = child.get_next()
	return null


func test_is_container_classifies_values() -> void:
	var view := _tree()
	assert_bool(view._is_container({"a": 1})).is_true()
	assert_bool(view._is_container([1, 2, 3])).is_true()
	assert_bool(view._is_container("hello")).is_false()
	assert_bool(view._is_container(42)).is_false()
	# An EJSON scalar wrapper (ObjectId) is a scalar, not a container.
	assert_bool(view._is_container({"$oid": "abc"})).is_false()


func test_view_json_emits_object_as_pretty_json() -> void:
	var view := _tree()
	var doc := {"_id": "a", "nested": {"x": 1}}
	view.display([doc], 0)
	var doc_item := view.get_root().get_first_child()
	view._menu_item = doc_item
	monitor_signals(view)
	view._on_doc_action(DocResultsView.DocAction.VIEW_JSON)
	await assert_signal(view).wait_until(50).is_emitted(
		"open_json_requested", JSON.stringify(doc, "  ")
	)


func test_display_raw_top_level_ejson_scalar_renders_as_value() -> void:
	# A raw response that is itself an Extended JSON scalar (e.g. countByRole ->
	# {"$numberInt": "28"}) shows as the value 28, not an object with a $numberInt
	# field. Regression for the models console's scalar results.
	var view := _tree()
	view.display_raw({"$numberInt": "28"}, [])
	var item := view.get_root().get_first_child()
	assert_object(item).is_not_null()
	assert_str(item.get_text(1)).is_equal("28")
	assert_str(item.get_text(2)).is_equal("Int32")
	assert_int(item.get_child_count()).is_equal(0)


func test_view_string_json_emits_raw_string() -> void:
	var view := _tree()
	# A field whose value is a string that itself contains JSON.
	view.display([{"_id": "a", "payload": "{\"x\": 1}"}], 0)
	var doc_item := view.get_root().get_first_child()
	var field := _field_child(doc_item, "payload")
	assert_object(field).is_not_null()
	view._menu_item = field
	monitor_signals(view)
	view._on_doc_action(DocResultsView.DocAction.VIEW_STRING_JSON)
	await assert_signal(view).wait_until(50).is_emitted("open_json_requested", "{\"x\": 1}")
