class_name RcModelsSidebarFilterTest
extends "res://test/test_suite.gd"

# Tests for the Server Models sidebar's list: the filter box narrows models by name
# and by the functions already loaded under them (never costing a refetch), and each
# model's functions are bucketed into sub-groups — "base" for the inherited IBaseModel
# API, then one per first word shared by GROUP_MIN of the model's own methods, then
# "others" for the rest.
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


# Function sub-groups ---------------------------------------------------------
## Four "find" methods (enough for their own group), two rarer words, and two
## inherited from IBaseModel, as the server tags them.
const METHODS := [
	{"name": "countByRole", "signature": "(role)", "base": false},
	{"name": "findOneById", "signature": "(_id)", "base": true},
	{"name": "findByIds", "signature": "(ids)", "base": false},
	{"name": "findOneByUsername", "signature": "(username)", "base": false},
	{"name": "findPaginated", "signature": "(q)", "base": true},
	{"name": "findActive", "signature": "()", "base": false},
	{"name": "findOneAdmin", "signature": "()", "base": false},
	{"name": "updateStatusById", "signature": "(id, status)", "base": false},
]


func _loaded() -> RcModelsSidebar:
	var sb := _sidebar()
	sb.set_model_functions("Users", METHODS.duplicate(true))
	return sb


func _group_names(sb: RcModelsSidebar, model: String) -> Array:
	var out: Array = []
	for group in sb.listed_function_groups(model):
		out.append(group["name"])
	return out


func test_base_leads_then_word_groups_then_others() -> void:
	var sb := _loaded()
	assert_array(_group_names(sb, "Users")).is_equal(["base", "find", "others"])


func test_inherited_methods_go_under_base_whatever_their_name() -> void:
	# findOneById would otherwise land in the "find" group; being inherited wins.
	var sb := _loaded()
	var groups: Array = sb.listed_function_groups("Users")
	assert_array(groups[0]["functions"]).is_equal(["findOneById", "findPaginated"])


func test_a_word_group_holds_every_method_that_shares_the_word() -> void:
	var sb := _loaded()
	var groups: Array = sb.listed_function_groups("Users")
	assert_array(groups[1]["functions"]).is_equal(
		["findByIds", "findOneByUsername", "findActive", "findOneAdmin"]
	)


func test_words_below_the_threshold_fall_into_others() -> void:
	# "count" and "update" have one method each, so neither earns a group.
	var sb := _loaded()
	var groups: Array = sb.listed_function_groups("Users")
	assert_array(groups[2]["functions"]).is_equal(["countByRole", "updateStatusById"])


func test_a_model_with_only_inherited_methods_has_just_the_base_group() -> void:
	var sb := _sidebar()
	sb.set_model_functions("Rooms", [
		{"name": "findOneById", "signature": "(_id)", "base": true},
		{"name": "insertOne", "signature": "(doc)", "base": true},
	])
	assert_array(_group_names(sb, "Rooms")).is_equal(["base"])


func test_filtering_removes_rows_without_reshuffling_the_groups() -> void:
	# "findoneby" leaves one method in "find" and one in "base"; the surviving rows
	# keep the groups they had, and the emptied "others" group drops out.
	var sb := _loaded()
	sb.set_filter("findoneby")
	assert_array(_group_names(sb, "Users")).is_equal(["base", "find"])
	var groups: Array = sb.listed_function_groups("Users")
	assert_array(groups[0]["functions"]).is_equal(["findOneById"])
	assert_array(groups[1]["functions"]).is_equal(["findOneByUsername"])


func test_filtering_by_a_group_name_lists_that_group_whole() -> void:
	# "base" appears in no method name — it's the sub-group's own label.
	var sb := _loaded()
	sb.set_filter("base")
	assert_array(_group_names(sb, "Users")).is_equal(["base"])
	assert_array(sb.listed_function_groups("Users")[0]["functions"]).is_equal(
		["findOneById", "findPaginated"]
	)


func test_first_word_splits_on_the_case_boundary_only() -> void:
	assert_str(RcModelsSidebar._first_word("findOneByUsername")).is_equal("find")
	assert_str(RcModelsSidebar._first_word("create")).is_equal("create")
	assert_str(RcModelsSidebar._first_word("e2eKeys")).is_equal("e2e")
	assert_str(RcModelsSidebar._first_word("")).is_equal("")


func test_a_new_model_list_drops_the_cached_functions() -> void:
	# A fresh list means the bridge was reinstalled, so its methods are stale.
	var sb := _sidebar()
	sb.set_model_functions("Users", [{"name": "findOneByUsername"}])
	sb.set_models(MODELS.duplicate(true))
	assert_array(sb.listed_functions("Users")).is_empty()
