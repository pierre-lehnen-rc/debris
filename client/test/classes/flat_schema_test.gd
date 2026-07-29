class_name FlatSchemaTest
extends "res://test/test_suite.gd"

# Tests for FlatSchema — no grouping at all: every collection sits at the root.
# See res://source/classes/flat_schema.gd


func _schema() -> FlatSchema:
	return FlatSchema.new()


func test_build_structure_is_empty() -> void:
	# FlatSchema needs no tree; path_for maps names straight to top-level leaves.
	assert_array(_schema().build_structure(["a", "b", "c"])).is_empty()


func test_path_for_is_always_the_name() -> void:
	var s := _schema()
	assert_array(s.path_for([], "users")).is_equal(["users"])
	# Even a name that WOULD group under GenericSchema stays flat here.
	assert_array(s.path_for([], "rocketchat_apps_packages")).is_equal(["rocketchat_apps_packages"])


func test_no_grouping_for_shared_prefix() -> void:
	var s := _schema()
	var names: Array = []
	for c in "abcdefghij":
		names.append("app_" + c)
	assert_array(s.build_structure(names)).is_empty()
	for n in names:
		assert_array(s.path_for(s.build_structure(names), n)).is_equal([n])


func test_order_names_preserves_input() -> void:
	var s := _schema()
	var names := ["z", "a", "m"]
	assert_array(s.order_names([], names)).is_equal(["z", "a", "m"])
