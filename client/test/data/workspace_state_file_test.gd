class_name WorkspaceStateFileTest
extends "res://test/test_suite.gd"

# Tests for WorkspaceStateFile — reads/writes a WorkspaceState as a
# .debris-workspace sidecar next to the project file.
# See res://source/data/workspace_state_file.gd


func _sample_state() -> WorkspaceState:
	var s := WorkspaceState.new()
	s.tabs = [
		{"kind": "query", "database": "mydb", "collection": "users", "function": "find",
			"filter": "{}", "options": "", "options_visible": false},
	]
	s.active_tab = 0
	s.set_endpoint_cache("https://chat.example",
		[ApiEndpoint.from_dict({"id": "channels.list", "paginated": true})], "t")
	return s


# path_for --------------------------------------------------------------------
func test_path_for_swaps_extension() -> void:
	assert_str(WorkspaceStateFile.path_for("/a/b/proj.debris-project")) \
		.is_equal("/a/b/proj.debris-workspace")


func test_path_for_empty_is_empty() -> void:
	assert_str(WorkspaceStateFile.path_for("")).is_equal("")


# save / load -----------------------------------------------------------------
func test_save_then_load_round_trip() -> void:
	var dir := create_temp_dir("wsstate")
	var path := dir + "/proj.debris-workspace"
	var save_result := WorkspaceStateFile.save(_sample_state(), path)
	assert_bool(save_result["ok"]).is_true()
	assert_bool(FileAccess.file_exists(path)).is_true()

	var load_result := WorkspaceStateFile.load(path)
	assert_bool(load_result["ok"]).is_true()
	var loaded: WorkspaceState = load_result["state"]
	assert_array(loaded.tabs).is_equal(_sample_state().tabs)
	assert_int(loaded.cached_endpoints("https://chat.example").size()).is_equal(1)


func test_save_empty_path_errors() -> void:
	var result := WorkspaceStateFile.save(_sample_state(), "")
	assert_bool(result["ok"]).is_false()


func test_save_bad_path_errors() -> void:
	var result := WorkspaceStateFile.save(_sample_state(), "/no/such/dir/proj.debris-workspace")
	assert_bool(result["ok"]).is_false()
	assert_str(result["error"]).contains("could not open")


# load edge cases -------------------------------------------------------------
func test_load_absent_is_marked_absent_not_fatal() -> void:
	# A missing sidecar is normal (Untitled / pre-feature project): distinguishable
	# from a corrupt one so the caller can proceed silently.
	var dir := create_temp_dir("wsstate")
	var result := WorkspaceStateFile.load(dir + "/nope.debris-workspace")
	assert_bool(result["ok"]).is_false()
	assert_str(result["error"]).is_equal("absent")
	assert_bool(result.has("state")).is_false()


func test_load_empty_path_is_absent() -> void:
	var result := WorkspaceStateFile.load("")
	assert_bool(result["ok"]).is_false()
	assert_str(result["error"]).is_equal("absent")


func test_load_malformed_reports_error() -> void:
	var dir := create_temp_dir("wsstate")
	var path := dir + "/bad.debris-workspace"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("not json {{{")
	f.close()
	var result := WorkspaceStateFile.load(path)
	assert_bool(result["ok"]).is_false()
	assert_str(result["error"]).contains("not a valid workspace file")
	assert_bool(result.has("state")).is_false()
