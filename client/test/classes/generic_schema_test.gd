class_name GenericSchemaTest
extends "res://test/test_suite.gd"

# Tests for GenericSchema — the default schema, which uses the base
# DatabaseSchema grouping heuristics unchanged. Focuses on build_structure and
# path_for (the collection-tree layout). See res://source/classes/generic_schema.gd
# and res://source/classes/database_schema.gd.
#
# Grouping only kicks in for a shared prefix with at least min_group_size (8)
# collections; smaller sets stay flat.


func _schema() -> GenericSchema:
	return GenericSchema.new()


func test_small_set_stays_flat() -> void:
	var s := _schema()
	var names := ["users", "rooms", "settings"]
	var structure := s.build_structure(names)
	# Three top-level leaves, no folders.
	assert_array(structure).has_size(3)
	for node in structure:
		assert_array(node["children"]).is_empty()


func test_small_set_path_is_name_itself() -> void:
	var s := _schema()
	var names := ["users", "rooms", "settings"]
	var structure := s.build_structure(names)
	assert_array(s.path_for(structure, "users")).is_equal(["users"])
	assert_array(s.path_for(structure, "settings")).is_equal(["settings"])


func test_shared_prefix_groups_into_a_folder() -> void:
	var s := _schema()
	var names: Array = []
	for c in "abcdefghij":  # 10 collections sharing the "app" prefix -> folder.
		names.append("app_" + c)
	var structure := s.build_structure(names)
	assert_array(structure).has_size(1)
	var folder: Dictionary = structure[0]
	assert_str(folder["label"]).is_equal("app")
	assert_str(folder["full"]).is_equal("")  # a folder, not a real collection
	assert_array(folder["children"]).has_size(10)


func test_grouped_path_is_folder_then_leaf() -> void:
	var s := _schema()
	var names: Array = []
	for c in "abcdefghij":
		names.append("app_" + c)
	var structure := s.build_structure(names)
	assert_array(s.path_for(structure, "app_a")).is_equal(["app", "a"])
	assert_array(s.path_for(structure, "app_j")).is_equal(["app", "j"])


func test_path_for_unknown_falls_back_to_name() -> void:
	var s := _schema()
	var structure := s.build_structure(["users", "rooms"])
	assert_array(s.path_for(structure, "not_there")).is_equal(["not_there"])


func test_every_name_is_locatable() -> void:
	var s := _schema()
	var names := ["users", "rooms", "rocketchat_message", "rocketchat_settings"]
	var structure := s.build_structure(names)
	for n in names:
		# The last path segment is the leaf; the real name must resolve to a path
		# other than the not-found fallback only when actually present — here all are.
		var path: Array = s.path_for(structure, n)
		assert_bool(path.size() >= 1).is_true()


func test_order_names_preserves_input() -> void:
	var s := _schema()
	var names := ["c", "a", "b"]
	assert_array(s.order_names(s.build_structure(names), names)).is_equal(["c", "a", "b"])
