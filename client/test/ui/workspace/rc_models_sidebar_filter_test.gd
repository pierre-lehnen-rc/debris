class_name RcModelsSidebarFilterTest
extends "res://test/test_suite.gd"

# Tests for the Server Models sidebar's filter box: models are narrowed by name and
# by the functions already loaded under them, and a filter change never costs the
# user a refetch of what was loaded.
# See res://source/ui/workspace/rc_models_sidebar.gd

const SIDEBAR_SCENE := preload("res://source/ui/workspace/rc_models_sidebar.tscn")
const MODELS := [
	{"name": "Users", "collection": "users"},
	{"name": "Rooms", "collection": "rocketchat_room"},
	{"name": "Subscriptions", "collection": "rocketchat_subscription"},
]


func _sidebar() -> RcModelsSidebar:
	var sb: RcModelsSidebar = SIDEBAR_SCENE.instantiate()
	add_child(sb)  # runs _ready synchronously
	auto_free(sb)
	sb.set_configured(true)
	sb.set_models(MODELS.duplicate(true))
	return sb


func test_no_filter_lists_every_model() -> void:
	assert_array(_sidebar().listed_models()).is_equal(["Users", "Rooms", "Subscriptions"])


func test_typing_in_the_filter_box_narrows_the_list() -> void:
	# End-to-end through the header widget: set_filter() working on its own says
	# nothing about whether the box is connected to it.
	var sb := _sidebar()
	var box: FilterField = sb.get_node("%Filter")
	box.text = "room"
	box.flush()
	assert_array(sb.listed_models()).is_equal(["Rooms"])


func test_filter_narrows_by_model_name() -> void:
	var sb := _sidebar()
	sb.set_filter("room")
	assert_array(sb.listed_models()).is_equal(["Rooms"])


func test_filter_matching_nothing_lists_nothing() -> void:
	var sb := _sidebar()
	sb.set_filter("nope")
	assert_array(sb.listed_models()).is_empty()


func test_loaded_functions_are_matched_too() -> void:
	var sb := _sidebar()
	sb.set_model_functions("Users", [
		{"name": "findOneByUsername", "signature": "(username)"},
		{"name": "removeById", "signature": "(id)"},
	])
	# "Users" doesn't contain "username", so this model is listed on its function.
	sb.set_filter("username")
	assert_array(sb.listed_models()).is_equal(["Users"])
	assert_array(sb.listed_functions("Users")).is_equal(["findOneByUsername"])


func test_model_name_match_keeps_all_its_functions() -> void:
	var sb := _sidebar()
	sb.set_model_functions("Users", [{"name": "findOneByUsername"}, {"name": "removeById"}])
	sb.set_filter("users")
	assert_array(sb.listed_functions("Users")).is_equal(["findOneByUsername", "removeById"])


func test_filtering_does_not_refetch_loaded_functions() -> void:
	# Re-rendering for a filter rebuilds the tree, so the functions must be cached
	# outside it — otherwise every keystroke would drop the user back to unloaded.
	var sb := _sidebar()
	sb.set_model_functions("Users", [{"name": "findOneByUsername"}])
	monitor_signals(sb)
	sb.set_filter("user")
	sb.set_filter("")
	await assert_signal(sb).wait_until(50).is_not_emitted("functions_requested")
	assert_array(sb.listed_functions("Users")).is_equal(["findOneByUsername"])


func test_a_new_model_list_drops_the_cached_functions() -> void:
	# A fresh list means the bridge was reinstalled, so its methods are stale.
	var sb := _sidebar()
	sb.set_model_functions("Users", [{"name": "findOneByUsername"}])
	sb.set_models(MODELS.duplicate(true))
	assert_array(sb.listed_functions("Users")).is_empty()
