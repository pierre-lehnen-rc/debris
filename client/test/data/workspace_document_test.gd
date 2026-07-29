# GdUnit generated TestSuite
class_name WorkspaceDocumentTest
extends "res://test/test_suite.gd"

# Tests for WorkspaceDoc — an in-memory Debris project binding one Mongo DB
# and/or one Rocket.Chat API. See res://source/data/workspace_document.gd


func _doc() -> WorkspaceDoc:
	return WorkspaceDoc.new()


# Defaults --------------------------------------------------------------------
func test_new_doc_defaults() -> void:
	var d := _doc()
	assert_str(d.name).is_equal("")
	assert_bool(d.has_mongo()).is_false()
	assert_bool(d.has_rocketchat()).is_false()
	assert_bool(d.dirty).is_false()
	assert_str(d.file_path).is_equal("")
	assert_dict(d.mongo_connection()).is_empty()
	assert_str(d.mongo_database()).is_equal("")


# Mongo -----------------------------------------------------------------------
func test_set_mongo() -> void:
	var d := _doc()
	d.set_mongo({"host": "localhost"}, "mydb")
	assert_bool(d.has_mongo()).is_true()
	assert_dict(d.mongo_connection()).is_equal({"host": "localhost"})
	assert_str(d.mongo_database()).is_equal("mydb")
	assert_bool(d.dirty).is_true()


func test_clear_mongo() -> void:
	var d := _doc()
	d.set_mongo({"host": "localhost"}, "mydb")
	d.dirty = false
	d.clear_mongo()
	assert_bool(d.has_mongo()).is_false()
	assert_bool(d.dirty).is_true()


# Rocket.Chat -----------------------------------------------------------------
func test_set_rocketchat() -> void:
	var d := _doc()
	d.set_name("work")
	d.set_rocketchat("https://chat.example", [])
	assert_bool(d.has_rocketchat()).is_true()
	var cfg := d.rocketchat_config()
	assert_dict(cfg).is_equal({
		"name": "work",
		"url": "https://chat.example",
		"users": [],
	})
	assert_bool(d.dirty).is_true()


func test_rocketchat_config_when_absent() -> void:
	var d := _doc()
	d.set_name("empty")
	assert_dict(d.rocketchat_config()).is_equal({
		"name": "empty",
		"url": "",
		"users": [],
	})


func test_set_rocketchat_cleans_users() -> void:
	var d := _doc()
	# Raw user carries runtime-only session fields that must be dropped.
	d.set_rocketchat("https://chat", [{
		"username": "alice",
		"user_id": "u1",
		"token": "tok",
		"password": "pw",
		"session_user_id": "live",
		"session_token": "livetok",
	}])
	var users: Array = d.rocketchat_config()["users"]
	assert_array(users).has_size(1)
	var u: Dictionary = users[0]
	assert_dict(u).contains_keys(["auth", "user_id", "username", "token", "password"])
	assert_bool(u.has("session_user_id")).is_false()
	assert_bool(u.has("session_token")).is_false()
	# auth inferred as "token" because a token is present.
	assert_str(u["auth"]).is_equal("token")


func test_clear_rocketchat() -> void:
	var d := _doc()
	d.set_rocketchat("https://chat", [])
	d.dirty = false
	d.clear_rocketchat()
	assert_bool(d.has_rocketchat()).is_false()
	assert_bool(d.dirty).is_true()


# sync_rocketchat_users -------------------------------------------------------
func test_sync_users_returns_false_without_rocketchat() -> void:
	var d := _doc()
	assert_bool(d.sync_rocketchat_users([{"username": "x"}])).is_false()


func test_sync_users_returns_false_when_unchanged() -> void:
	var d := _doc()
	d.set_rocketchat("https://chat", [{"username": "alice", "auth": "password"}])
	d.dirty = false
	# Same cleaned list -> no change.
	var changed := d.sync_rocketchat_users([{"username": "alice", "auth": "password"}])
	assert_bool(changed).is_false()
	assert_bool(d.dirty).is_false()


func test_sync_users_returns_true_when_changed() -> void:
	var d := _doc()
	d.set_rocketchat("https://chat", [])
	d.dirty = false
	var changed := d.sync_rocketchat_users([{"username": "bob", "auth": "password"}])
	assert_bool(changed).is_true()
	assert_bool(d.dirty).is_true()
	var users: Array = d.rocketchat_config()["users"]
	assert_str(users[0]["username"]).is_equal("bob")


func test_sync_users_ignores_login_token_only_change() -> void:
	# Login adds only a session token, which is stripped, so no persisted change.
	var d := _doc()
	d.set_rocketchat("https://chat", [{"username": "alice", "auth": "password"}])
	d.dirty = false
	var changed := d.sync_rocketchat_users([{
		"username": "alice",
		"auth": "password",
		"session_token": "livetok",
		"session_user_id": "live",
	}])
	assert_bool(changed).is_false()
	assert_bool(d.dirty).is_false()


# set_name --------------------------------------------------------------------
func test_set_name_marks_dirty() -> void:
	var d := _doc()
	d.set_name("proj")
	assert_str(d.name).is_equal("proj")
	assert_bool(d.dirty).is_true()


# to_dict ---------------------------------------------------------------------
func test_to_dict_name_only() -> void:
	var d := _doc()
	d.set_name("solo")
	assert_dict(d.to_dict()).is_equal({"name": "solo"})


func test_to_dict_omits_empty_blocks() -> void:
	var d := _doc()
	d.set_name("solo")
	var data := d.to_dict()
	assert_bool(data.has("mongo")).is_false()
	assert_bool(data.has("rocketchat")).is_false()


func test_to_dict_does_not_serialize_runtime_fields() -> void:
	var d := _doc()
	d.set_name("solo")
	d.file_path = "/some/path"
	d.dirty = true
	var data := d.to_dict()
	assert_bool(data.has("file_path")).is_false()
	assert_bool(data.has("dirty")).is_false()


func test_to_dict_with_mongo_and_rocketchat() -> void:
	var d := _doc()
	d.set_name("full")
	d.set_mongo({"host": "h"}, "db")
	d.set_rocketchat("https://chat", [{"username": "a", "auth": "password"}])
	var data := d.to_dict()
	assert_dict(data).contains_keys(["name", "mongo", "rocketchat"])
	assert_dict(data["mongo"]).is_equal({"connection": {"host": "h"}, "database": "db"})
	assert_str(data["rocketchat"]["url"]).is_equal("https://chat")


# from_dict / round-trip ------------------------------------------------------
func test_from_dict_round_trip() -> void:
	var d := _doc()
	d.set_name("full")
	d.set_mongo({"host": "h"}, "db")
	d.set_rocketchat("https://chat", [{"username": "a", "auth": "password", "password": "pw"}])
	var restored := WorkspaceDoc.from_dict(d.to_dict())
	assert_str(restored.name).is_equal("full")
	assert_dict(restored.mongo_connection()).is_equal({"host": "h"})
	assert_str(restored.mongo_database()).is_equal("db")
	assert_dict(restored.to_dict()).is_equal(d.to_dict())


func test_from_dict_defaults_runtime_fields() -> void:
	var restored := WorkspaceDoc.from_dict({"name": "x"})
	assert_str(restored.file_path).is_equal("")
	assert_bool(restored.dirty).is_false()


func test_from_dict_empty() -> void:
	var restored := WorkspaceDoc.from_dict({})
	assert_str(restored.name).is_equal("")
	assert_bool(restored.has_mongo()).is_false()
	assert_bool(restored.has_rocketchat()).is_false()


func test_from_dict_ignores_empty_mongo_block() -> void:
	var restored := WorkspaceDoc.from_dict({"name": "x", "mongo": {}})
	assert_bool(restored.has_mongo()).is_false()


# _clean_users normalization via from_dict ------------------------------------
func test_from_dict_infers_token_auth() -> void:
	# No explicit auth, but a token present -> auth becomes "token".
	var restored := WorkspaceDoc.from_dict({
		"name": "x",
		"rocketchat": {"url": "u", "users": [{"username": "a", "token": "tok"}]},
	})
	var u: Dictionary = restored.rocketchat["users"][0]
	assert_str(u["auth"]).is_equal("token")


func test_from_dict_defaults_password_auth() -> void:
	# No auth and no token -> auth defaults to "password".
	var restored := WorkspaceDoc.from_dict({
		"name": "x",
		"rocketchat": {"url": "u", "users": [{"username": "a"}]},
	})
	var u: Dictionary = restored.rocketchat["users"][0]
	assert_str(u["auth"]).is_equal("password")


func test_from_dict_coerces_unknown_auth_to_token() -> void:
	# Any non-"password" auth normalizes to "token".
	var restored := WorkspaceDoc.from_dict({
		"name": "x",
		"rocketchat": {"url": "u", "users": [{"username": "a", "auth": "weird"}]},
	})
	var u: Dictionary = restored.rocketchat["users"][0]
	assert_str(u["auth"]).is_equal("token")


func test_from_dict_skips_non_dictionary_users() -> void:
	var restored := WorkspaceDoc.from_dict({
		"name": "x",
		"rocketchat": {"url": "u", "users": ["not-a-dict", {"username": "ok"}]},
	})
	var users: Array = restored.rocketchat["users"]
	assert_array(users).has_size(1)
	assert_str(users[0]["username"]).is_equal("ok")


func test_clean_users_fills_all_config_keys() -> void:
	var restored := WorkspaceDoc.from_dict({
		"name": "x",
		"rocketchat": {"url": "u", "users": [{"username": "a"}]},
	})
	var u: Dictionary = restored.rocketchat["users"][0]
	assert_dict(u).contains_keys(["auth", "user_id", "username", "token", "password"])
	assert_str(u["user_id"]).is_equal("")
	assert_str(u["token"]).is_equal("")
	assert_str(u["password"]).is_equal("")
