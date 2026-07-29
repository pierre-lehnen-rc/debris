# GdUnit generated TestSuite
class_name StoreTest
extends "res://test/test_suite.gd"

# Tests for Store — persists app state to user://settings.json.
# See res://source/data/store.gd


func _delete_settings() -> void:
	if FileAccess.file_exists(Store.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Store.PATH))


func before_test() -> void:
	_delete_settings()


func after_test() -> void:
	_delete_settings()


# recent_workspaces / add_recent_workspace ------------------------------------
func test_recent_workspaces_empty_when_no_file() -> void:
	assert_array(Store.recent_workspaces()).is_empty()


func test_add_recent_workspace_records_path() -> void:
	Store.add_recent_workspace("/a.debris-project")
	assert_array(Store.recent_workspaces()).is_equal(["/a.debris-project"])


func test_add_recent_workspace_most_recent_first() -> void:
	Store.add_recent_workspace("/a")
	Store.add_recent_workspace("/b")
	Store.add_recent_workspace("/c")
	assert_array(Store.recent_workspaces()).is_equal(["/c", "/b", "/a"])


func test_add_recent_workspace_dedupes_and_promotes() -> void:
	Store.add_recent_workspace("/a")
	Store.add_recent_workspace("/b")
	Store.add_recent_workspace("/a")
	assert_array(Store.recent_workspaces()).is_equal(["/a", "/b"])


func test_add_recent_workspace_ignores_empty_path() -> void:
	Store.add_recent_workspace("")
	assert_array(Store.recent_workspaces()).is_empty()


func test_add_recent_workspace_caps_at_limit() -> void:
	for i in range(15):
		Store.add_recent_workspace("/p%d" % i)
	var list := Store.recent_workspaces()
	assert_array(list).has_size(10)
	# Newest first, oldest 5 dropped.
	assert_str(list[0]).is_equal("/p14")
	assert_str(list[9]).is_equal("/p5")


func test_add_recent_workspace_custom_limit() -> void:
	Store.add_recent_workspace("/a", 2)
	Store.add_recent_workspace("/b", 2)
	Store.add_recent_workspace("/c", 2)
	assert_array(Store.recent_workspaces()).is_equal(["/c", "/b"])


# open_workspaces / save_open_workspaces --------------------------------------
func test_open_workspaces_empty_when_no_file() -> void:
	assert_array(Store.open_workspaces()).is_empty()


func test_save_open_workspaces_round_trip() -> void:
	Store.save_open_workspaces(["/x", "/y"])
	assert_array(Store.open_workspaces()).is_equal(["/x", "/y"])


func test_save_open_workspaces_overwrites() -> void:
	Store.save_open_workspaces(["/x"])
	Store.save_open_workspaces(["/y", "/z"])
	assert_array(Store.open_workspaces()).is_equal(["/y", "/z"])


# get_preference / set_preference ---------------------------------------------
func test_get_preference_default_when_unset() -> void:
	assert_object(Store.get_preference("missing")).is_null()


func test_get_preference_custom_default() -> void:
	assert_str(Store.get_preference("missing", "fallback")).is_equal("fallback")


func test_set_and_get_preference() -> void:
	Store.set_preference("theme", "dark")
	assert_str(Store.get_preference("theme")).is_equal("dark")


func test_set_preference_overwrites() -> void:
	Store.set_preference("theme", "dark")
	Store.set_preference("theme", "light")
	assert_str(Store.get_preference("theme")).is_equal("light")


func test_set_preference_keeps_other_keys() -> void:
	Store.set_preference("a", 1)
	Store.set_preference("b", 2)
	assert_int(Store.get_preference("a")).is_equal(1)
	assert_int(Store.get_preference("b")).is_equal(2)


# Cross-section isolation -----------------------------------------------------
func test_preferences_and_recents_coexist() -> void:
	Store.add_recent_workspace("/a")
	Store.set_preference("theme", "dark")
	Store.save_open_workspaces(["/a"])
	assert_array(Store.recent_workspaces()).is_equal(["/a"])
	assert_str(Store.get_preference("theme")).is_equal("dark")
	assert_array(Store.open_workspaces()).is_equal(["/a"])
