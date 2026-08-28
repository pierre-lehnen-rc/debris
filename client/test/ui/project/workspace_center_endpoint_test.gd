class_name WorkspaceCenterEndpointTest
extends "res://test/test_suite.gd"

# Behavioural tests for how the workspace center stacks endpoint tabs: opening the
# same endpoint twice gives two independent tabs (like collections and model
# functions), each holding its own params, and both survive a sidecar round-trip.
# See res://source/ui/project/workspace_center.gd

const CENTER_SCENE := preload("res://source/ui/project/workspace_center.tscn")
const ENDPOINT_ID := "channels.info"


func _endpoint() -> ApiEndpoint:
	return ApiEndpoint.from_dict({
		"id": ENDPOINT_ID,
		"method": "GET",
		"path": "/api/v1/%s" % ENDPOINT_ID,
		"params": [{"name": "roomName", "in": "query", "type": "string"}],
	})


func _center() -> WorkspaceCenter:
	var center: WorkspaceCenter = CENTER_SCENE.instantiate()
	add_child(center)  # runs _ready synchronously
	auto_free(center)
	center.bind_session(WorkspaceSession.new({
		"url": "https://chat.example",
		"users": [{"username": "alice", "auth": "token", "user_id": "u1", "token": "tok"}],
	}))
	return center


## A sidecar state for this endpoint with `room` typed into its only param.
func _state(room: String) -> Dictionary:
	return {
		"kind": "endpoint",
		"endpoint_id": ENDPOINT_ID,
		"user_id": 1,
		"raw": false,
		"form": {"roomName": room},
		"json_text": "",
	}


func test_same_endpoint_opens_a_second_tab() -> void:
	var center := _center()
	var first := center.open_endpoint(_endpoint())
	var second := center.open_endpoint(_endpoint())
	assert_bool(second == first).is_false()
	assert_array(center.capture_tabs()).has_size(2)
	# The newest tab is the focused one, as with any freshly opened tab.
	assert_int(center.active_tab_index()).is_equal(1)


func test_duplicate_tabs_hold_independent_params() -> void:
	var center := _center()
	center.open_endpoint(_endpoint(), _state("general"))
	center.open_endpoint(_endpoint(), _state("random"))
	var tabs := center.capture_tabs()
	assert_array(tabs).has_size(2)
	assert_str(str(tabs[0]["form"]["roomName"])).is_equal("general")
	assert_str(str(tabs[1]["form"]["roomName"])).is_equal("random")


func test_both_tabs_survive_a_sidecar_round_trip() -> void:
	var center := _center()
	center.open_endpoint(_endpoint(), _state("general"))
	center.open_endpoint(_endpoint(), _state("random"))

	var restored := _center()
	restored.restore_tabs(center.capture_tabs(), 1, {ENDPOINT_ID: _endpoint()})
	var tabs := restored.capture_tabs()
	assert_array(tabs).has_size(2)
	assert_str(str(tabs[0]["form"]["roomName"])).is_equal("general")
	assert_str(str(tabs[1]["form"]["roomName"])).is_equal("random")
	assert_int(restored.active_tab_index()).is_equal(1)
