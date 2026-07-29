# GdUnit generated TestSuite
class_name WorkspaceFileTest
extends "res://test/test_suite.gd"

# Tests for WorkspaceFile — reads/writes a WorkspaceDoc as a .debris-project
# JSON file. See res://source/data/workspace_file.gd


func _sample_doc() -> WorkspaceDoc:
	var d := WorkspaceDoc.new()
	d.set_name("sample")
	# Mirror the real stored connection shape (see connection_dialog._gather):
	# the address is a single "host:port" string; there is no bare numeric field
	# (a stray int would silently become a float across the JSON round-trip).
	d.set_mongo({"host": "localhost:27017", "auth": {"enabled": false}}, "mydb")
	d.set_rocketchat("https://chat.example", [
		{"username": "alice", "auth": "password", "password": "pw"},
	])
	return d


# save ------------------------------------------------------------------------
func test_save_returns_ok() -> void:
	var dir := create_temp_dir("wsfile")
	var path := dir + "/proj.debris-project"
	var result := WorkspaceFile.save(_sample_doc(), path)
	assert_bool(result["ok"]).is_true()
	assert_str(result["error"]).is_equal("")
	assert_bool(FileAccess.file_exists(path)).is_true()


func test_save_updates_doc_state() -> void:
	var dir := create_temp_dir("wsfile")
	var path := dir + "/proj.debris-project"
	var doc := _sample_doc()
	assert_bool(doc.dirty).is_true()
	WorkspaceFile.save(doc, path)
	assert_str(doc.file_path).is_equal(path)
	assert_bool(doc.dirty).is_false()


func test_save_bad_path_returns_error() -> void:
	var result := WorkspaceFile.save(_sample_doc(), "/no/such/dir/proj.debris-project")
	assert_bool(result["ok"]).is_false()
	assert_str(result["error"]).contains("could not open")
	assert_bool(result.has("doc")).is_false()


# load ------------------------------------------------------------------------
func test_load_missing_file() -> void:
	var dir := create_temp_dir("wsfile")
	var result := WorkspaceFile.load(dir + "/nope.debris-project")
	assert_bool(result["ok"]).is_false()
	assert_str(result["error"]).contains("no such file")
	assert_bool(result.has("doc")).is_false()


func test_load_malformed_file() -> void:
	var dir := create_temp_dir("wsfile")
	var path := dir + "/bad.debris-project"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("this is not json {{{")
	f.close()
	var result := WorkspaceFile.load(path)
	assert_bool(result["ok"]).is_false()
	assert_str(result["error"]).contains("not a valid project file")
	assert_bool(result.has("doc")).is_false()


func test_load_non_object_json() -> void:
	# Valid JSON, but a top-level array is not a project dictionary.
	var dir := create_temp_dir("wsfile")
	var path := dir + "/arr.debris-project"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("[1, 2, 3]")
	f.close()
	var result := WorkspaceFile.load(path)
	assert_bool(result["ok"]).is_false()
	assert_str(result["error"]).contains("not a valid project file")


func test_load_returns_doc() -> void:
	var dir := create_temp_dir("wsfile")
	var path := dir + "/proj.debris-project"
	WorkspaceFile.save(_sample_doc(), path)
	var result := WorkspaceFile.load(path)
	assert_bool(result["ok"]).is_true()
	assert_object(result["doc"]).is_not_null()
	var doc: WorkspaceDoc = result["doc"]
	assert_str(doc.file_path).is_equal(path)
	assert_bool(doc.dirty).is_false()


# round-trip ------------------------------------------------------------------
func test_save_then_load_round_trip() -> void:
	var dir := create_temp_dir("wsfile")
	var path := dir + "/proj.debris-project"
	var original := _sample_doc()
	WorkspaceFile.save(original, path)
	var loaded: WorkspaceDoc = WorkspaceFile.load(path)["doc"]
	assert_str(loaded.name).is_equal("sample")
	assert_dict(loaded.mongo_connection()).is_equal({"host": "localhost:27017", "auth": {"enabled": false}})
	assert_str(loaded.mongo_database()).is_equal("mydb")
	assert_dict(loaded.to_dict()).is_equal(original.to_dict())


func test_round_trip_strips_session_fields() -> void:
	var dir := create_temp_dir("wsfile")
	var path := dir + "/proj.debris-project"
	var original := WorkspaceDoc.new()
	original.set_name("s")
	original.set_rocketchat("https://chat", [{
		"username": "alice",
		"auth": "password",
		"session_token": "livetok",
		"session_user_id": "live",
	}])
	WorkspaceFile.save(original, path)
	var loaded: WorkspaceDoc = WorkspaceFile.load(path)["doc"]
	var u: Dictionary = loaded.rocketchat["users"][0]
	assert_bool(u.has("session_token")).is_false()
	assert_bool(u.has("session_user_id")).is_false()
