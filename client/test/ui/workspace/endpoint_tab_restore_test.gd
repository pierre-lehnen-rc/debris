class_name EndpointTabRestoreTest
extends "res://test/test_suite.gd"

# Behavioural tests for EndpointTab's sidecar round-trip: a saved tab reopens with
# its chosen user, form values, and raw-JSON body re-applied to the rebuilt form,
# and to_state() captures exactly what would be persisted (never results).
# See res://source/ui/workspace/endpoint_tab.gd

const ENDPOINT_TAB_SCENE := preload("res://source/ui/workspace/endpoint_tab.tscn")


func _endpoint() -> ApiEndpoint:
	return ApiEndpoint.from_dict({
		"id": "channels.info",
		"method": "GET",
		"path": "/api/v1/channels.info",
		"params": [
			{"name": "roomName", "in": "query", "type": "string"},
			{"name": "includeAll", "in": "query", "type": "bool"},
			{"name": "kind", "in": "query", "type": "string", "enum": ["c", "p"]},
		],
	})


func _session() -> WorkspaceSession:
	# One config user, id 1 (first assigned id), with a token so it authenticates.
	return WorkspaceSession.new({
		"url": "https://chat.example",
		"users": [{"username": "alice", "auth": "token", "user_id": "u1", "token": "tok"}],
	})


func _restored_tab(state: Dictionary) -> EndpointTab:
	var tab: EndpointTab = ENDPOINT_TAB_SCENE.instantiate()
	tab.configure_restore(_session(), _endpoint(), state)
	add_child(tab)  # runs _ready synchronously, building + restoring the form
	auto_free(tab)
	return tab


func test_restore_round_trips_form_values() -> void:
	# kind is an optional enum: index 0 = "", 1 = "c", 2 = "p".
	var state := {
		"kind": "endpoint",
		"endpoint_id": "channels.info",
		"user_id": 1,
		"raw": false,
		"form": {"roomName": "general", "includeAll": true, "kind": 2},
		"json_text": "",
	}
	var captured := _restored_tab(state).to_state()
	assert_str(captured["endpoint_id"]).is_equal("channels.info")
	assert_int(captured["user_id"]).is_equal(1)
	assert_bool(captured["raw"]).is_false()
	var form: Dictionary = captured["form"]
	assert_str(str(form["roomName"])).is_equal("general")
	assert_bool(form["includeAll"]).is_true()
	assert_int(int(form["kind"])).is_equal(2)


func test_restore_anonymous_user() -> void:
	var captured := _restored_tab({
		"kind": "endpoint", "endpoint_id": "channels.info", "user_id": -1,
		"raw": false, "form": {}, "json_text": "",
	}).to_state()
	assert_int(captured["user_id"]).is_equal(-1)


func test_restore_raw_json_mode_preserves_body() -> void:
	# In raw mode the saved body text must survive verbatim — the toggle is applied
	# without its signal so it isn't overwritten by a re-seed from the form.
	var body := "{\n\t\"roomName\": \"custom\"\n}"
	var captured := _restored_tab({
		"kind": "endpoint", "endpoint_id": "channels.info", "user_id": 1,
		"raw": true, "form": {}, "json_text": body,
	}).to_state()
	assert_bool(captured["raw"]).is_true()
	assert_str(captured["json_text"]).is_equal(body)


func test_missing_param_in_saved_form_is_ignored() -> void:
	# A saved value for a param the endpoint no longer has is skipped, not an error.
	var captured := _restored_tab({
		"kind": "endpoint", "endpoint_id": "channels.info", "user_id": 1,
		"raw": false, "form": {"roomName": "x", "gone": "y"}, "json_text": "",
	}).to_state()
	assert_bool((captured["form"] as Dictionary).has("gone")).is_false()
	assert_str(str((captured["form"] as Dictionary)["roomName"])).is_equal("x")
