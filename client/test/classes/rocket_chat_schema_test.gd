# GdUnit generated TestSuite
class_name RocketChatSchemaTest
extends "res://test/test_suite.gd"

# Tests for RocketChatSchema — the Rocket.Chat-tuned DatabaseSchema.
# See res://source/classes/rocket_chat_schema.gd (extends DatabaseSchema).


var schema := RocketChatSchema.new()


# _init() tuning --------------------------------------------------------------
func test_init_sets_smaller_min_group_size_than_generic() -> void:
	# RocketChat subdivides groups more eagerly than the generic default (8).
	assert_int(schema.min_group_size).is_equal(3)
	assert_int(GenericSchema.new().min_group_size).is_equal(8)


func test_init_populates_highlighted_collections() -> void:
	assert_array(schema.highlighted_collections).is_equal(RocketChatSchema.HIGHLIGHTED_COLLECTIONS)
	assert_array(schema.highlighted_collections).contains(["users", "rocketchat_room"])


func test_init_populates_type_rules() -> void:
	# The generic base ships no rules; RocketChat populates many.
	assert_array(schema.type_rules).is_not_empty()
	assert_array(GenericSchema.new().type_rules).is_empty()


# is_highlighted (inherited, driven by _init) ---------------------------------
func test_is_highlighted_true_for_core_collections() -> void:
	assert_bool(schema.is_highlighted("users")).is_true()
	assert_bool(schema.is_highlighted("rocketchat_room")).is_true()
	assert_bool(schema.is_highlighted("rocketchat_settings")).is_true()


func test_is_highlighted_false_for_other_collections() -> void:
	assert_bool(schema.is_highlighted("rocketchat_apps")).is_false()
	assert_bool(schema.is_highlighted("call_history")).is_false()
	# Generic schema highlights nothing.
	assert_bool(GenericSchema.new().is_highlighted("users")).is_false()


# type_for (inherited, driven by RocketChat type_rules) -----------------------
func test_type_for_whole_document_types() -> void:
	assert_str(schema.type_for("users", "")).is_equal("User")
	assert_str(schema.type_for("rocketchat_room", "")).is_equal("Room")
	assert_str(schema.type_for("rocketchat_message", "")).is_equal("Message")


func test_type_for_field_level_types() -> void:
	assert_str(schema.type_for("rocketchat_message", "u._id")).is_equal("UserId")
	assert_str(schema.type_for("rocketchat_subscription", "rid")).is_equal("RoomId")
	assert_str(schema.type_for("users", "roles")).is_equal("RoleId")


func test_type_for_unknown_returns_empty() -> void:
	assert_str(schema.type_for("nope", "")).is_equal("")
	assert_str(schema.type_for("users", "nosuchfield")).is_equal("")


# Media-call actor object type (conditional id) -------------------------------
func test_media_call_actor_is_object_type() -> void:
	# Each actor field resolves to the MediaCallActor object type.
	for field in ["createdBy", "endedBy", "transferredBy", "divertedBy", "caller", "callee"]:
		assert_str(schema.type_for("rocketchat_media_calls", field)).is_equal("MediaCallActor")


func test_media_call_actor_id_follows_sibling_type() -> void:
	var user_call := {"caller": {"type": "user", "id": "u1"}, "callee": {"type": "sip", "id": "1001"}}
	# The caller is a user -> its id is a UserId; the callee is SIP -> a SIP extension.
	assert_str(schema.type_for("rocketchat_media_calls", "caller.id", user_call)).is_equal("UserId")
	assert_str(schema.type_for("rocketchat_media_calls", "callee.id", user_call)) \
		.is_equal("SipExtension")


func test_media_call_actor_type_excluded_from_scalar_types() -> void:
	# The object type isn't offered as an "unknown type" reinterpretation, but the
	# scalar id types it introduces are.
	assert_bool(schema.scalar_types().has("MediaCallActor")).is_false()
	assert_array(schema.scalar_types()).contains(["UserId", "SipExtension"])


func test_media_call_actor_sip_extension_is_unconditional() -> void:
	# sipExtension is always a SIP extension, no document/sibling needed.
	assert_str(schema.type_for("rocketchat_media_calls", "caller.sipExtension")).is_equal("SipExtension")
	assert_str(schema.type_for("rocketchat_media_calls", "callee.sipExtension")).is_equal("SipExtension")


func test_media_call_uids_is_user_id() -> void:
	assert_str(schema.type_for("rocketchat_media_calls", "uids")).is_equal("UserId")


func test_user_free_switch_extension_is_sip_extension() -> void:
	assert_str(schema.type_for("users", "freeSwitchExtension")).is_equal("SipExtension")


# collection_for_endpoint (endpoint response typing) --------------------------
func test_collection_for_endpoint_maps_by_result_key() -> void:
	assert_str(schema.collection_for_endpoint("user", "users.info")).is_equal("users")
	assert_str(schema.collection_for_endpoint("users", "users.list")).is_equal("users")
	# A sub-entity list types by its payload key, not its namespace.
	assert_str(schema.collection_for_endpoint("members", "channels.members")).is_equal("users")
	assert_str(schema.collection_for_endpoint("message", "chat.getMessage")).is_equal("rocketchat_message")


func test_collection_for_endpoint_falls_back_to_namespace() -> void:
	# Generic payload keys ("update"/"remove") or bare objects fall back to the
	# operationId namespace so the entity is still recognised.
	assert_str(schema.collection_for_endpoint("update", "rooms.get")).is_equal("rocketchat_room")
	assert_str(schema.collection_for_endpoint("", "rooms.adminRooms.getRoom")).is_equal("rocketchat_room")
	assert_str(schema.collection_for_endpoint("update", "subscriptions.get")) \
		.is_equal("rocketchat_subscription")
	assert_str(schema.collection_for_endpoint("", "chat.getMessage")).is_equal("rocketchat_message")


func test_collection_for_endpoint_is_case_insensitive() -> void:
	assert_str(schema.collection_for_endpoint("User", "")).is_equal("users")
	assert_str(schema.collection_for_endpoint("", "Rooms.Get")).is_equal("rocketchat_room")


func test_collection_for_endpoint_unmapped_is_empty() -> void:
	assert_str(schema.collection_for_endpoint("", "")).is_equal("")
	assert_str(schema.collection_for_endpoint("bananas", "bananas.list")).is_equal("")


func test_media_call_actor_action_is_picker_keyed_by_type_and_id() -> void:
	# "List Media Calls by <actor>" is an attribute picker defaulting to type + id;
	# its fallback filter matches by those two with dot notation, not the whole object.
	var action := {}
	for a in schema.actions_for_type("MediaCallActor"):
		if a["filter"].has("callee.id"):
			action = a
			break
	assert_dict(action).is_not_empty()
	assert_bool(action["pick_fields"]).is_true()
	assert_array(action["key_fields"]).is_equal(["type", "id"])
	assert_dict(action["filter"]).is_equal({"callee.type": "$type", "callee.id": "$id"})
	var actor := {"type": "user", "id": "RWWhjYadQicPFPQfq", "sipExtension": "2002", "username": "u2"}
	assert_dict(DatabaseSchema.resolve_filter(action["filter"], actor)) \
		.is_equal({"callee.type": "user", "callee.id": "RWWhjYadQicPFPQfq"})


func test_media_call_user_action_carries_type_condition() -> void:
	# The "List MediaCalls by caller.id" UserId action folds in the sibling
	# condition, so resolving it against a clicked id yields both constraints.
	var action := {}
	for a in schema.actions_for_type("UserId"):
		if a.get("target_collection") == "rocketchat_media_calls" and a["filter"].has("caller.id"):
			action = a
			break
	assert_dict(action).is_not_empty()
	assert_dict(DatabaseSchema.resolve_filter(action["filter"], "RWWhjYadQicPFPQfq")) \
		.is_equal({"caller.id": "RWWhjYadQicPFPQfq", "caller.type": "user"})


# mutate_collection_name ------------------------------------------------------
func test_mutate_name_leaves_plain_core_collection_unchanged() -> void:
	# "rocketchat_room" -> drop prefix -> "room" -> re-add prefix -> "rocketchat_room".
	assert_str(schema.mutate_collection_name("rocketchat_room")).is_equal("rocketchat_room")
	# No prefix, no rule: untouched.
	assert_str(schema.mutate_collection_name("users")).is_equal("users")


func test_mutate_name_rehomes_livechat_under_omnichannel() -> void:
	# rocketchat_livechat_visitor -> omnichannel_livechat_visitor -> re-prefixed.
	assert_str(schema.mutate_collection_name("rocketchat_livechat_visitor")) \
		.is_equal("rocketchat_omnichannel_livechat_visitor")
	# Without the rocketchat_ prefix the re-home still happens, no re-prefix.
	assert_str(schema.mutate_collection_name("livechat_department")) \
		.is_equal("omnichannel_livechat_department")


func test_mutate_name_rehomes_matrix_under_federation() -> void:
	assert_str(schema.mutate_collection_name("rocketchat_matrix_bridged_rooms")) \
		.is_equal("rocketchat_federation_matrix_bridged_rooms")


func test_mutate_name_rehomes_freeswitch_under_media() -> void:
	assert_str(schema.mutate_collection_name("rocketchat_freeswitch_channels")) \
		.is_equal("rocketchat_media_freeswitch_channels")


func test_mutate_name_rehomes_read_receipt_under_message() -> void:
	assert_str(schema.mutate_collection_name("rocketchat_read_receipts")) \
		.is_equal("rocketchat_message_read_receipts")


func test_mutate_name_groups_standalone_media_collections() -> void:
	assert_str(schema.mutate_collection_name("call_history")).is_equal("media_call_history")
	assert_str(schema.mutate_collection_name("video_conference")).is_equal("media_video_conference")


func test_mutate_name_groups_standalone_omnichannel_collections() -> void:
	assert_str(schema.mutate_collection_name("canned_response")).is_equal("omnichannel_canned_response")


func test_mutate_name_custom_emoji_gets_rocketchat_prefix() -> void:
	# "custom_emoji" is flagged as prefixed, so it lands under a rocketchat_ folder.
	assert_str(schema.mutate_collection_name("custom_emoji")).is_equal("rocketchat_custom_emoji")


func test_mutate_name_omnichannel_prefixed_gets_rocketchat_prefix() -> void:
	assert_str(schema.mutate_collection_name("omnichannel_integrations")) \
		.is_equal("rocketchat_omnichannel_integrations")


func test_generic_schema_leaves_names_unchanged() -> void:
	var generic := GenericSchema.new()
	assert_str(generic.mutate_collection_name("rocketchat_livechat_visitor")) \
		.is_equal("rocketchat_livechat_visitor")


# mutate_collection_label -----------------------------------------------------
func test_label_strips_rocketchat_prefix_at_top_level() -> void:
	# Top-level leaf (no ancestors): only SKIPPED_LABEL_PREFIXES are stripped.
	assert_str(schema.mutate_collection_label("", "rocketchat_settings", [])).is_equal("settings")


func test_label_strips_meteor_prefix() -> void:
	assert_str(schema.mutate_collection_label("", "meteor_accounts", [])).is_equal("accounts")


func test_label_keeps_plain_name() -> void:
	assert_str(schema.mutate_collection_label("", "users", [])).is_equal("users")


func test_label_strips_grandparent_folders_but_keeps_parent_segment() -> void:
	# Docstring example: rocketchat_cron_history under rocketchat > cron -> cron_history.
	# Grandparents = ["rocketchat"] (all ancestors except the parent "cron").
	assert_str(schema.mutate_collection_label("", "rocketchat_cron_history", ["rocketchat", "cron"])) \
		.is_equal("cron_history")


func test_label_defensive_break_on_mismatch() -> void:
	# When the name doesn't start with the grandparent label, stripping stops.
	assert_str(schema.mutate_collection_label("", "foo_bar", ["xxx", "yyy"])).is_equal("foo_bar")


func test_generic_schema_label_is_identity() -> void:
	assert_str(GenericSchema.new().mutate_collection_label("keepme", "rocketchat_settings", [])) \
		.is_equal("keepme")


# _sort_key -------------------------------------------------------------------
func test_sort_key_top_level_loose_collection_ranks_last() -> void:
	# A single-segment leaf is a loose collection -> rank 2.
	assert_array(schema._sort_key(["users"])).is_equal([[2, "users"]])


func test_sort_key_folder_then_loose_leaf() -> void:
	# ["rocketchat", "room"]: folder segment rank 1, differing leaf rank 2.
	assert_array(schema._sort_key(["rocketchat", "room"])).is_equal([[1, "rocketchat"], [2, "room"]])


func test_sort_key_self_collection_leaf_ranks_first() -> void:
	# A leaf whose label equals its parent folder is the folder's own collection -> rank 0.
	assert_array(schema._sort_key(["apps", "apps"])).is_equal([[1, "apps"], [0, "apps"]])


# order_names -----------------------------------------------------------------
func test_order_names_sorts_flat_top_level_alphabetically() -> void:
	var names := ["zebra", "apple", "mango"]
	var structure := schema.build_structure(names)
	assert_array(schema.order_names(structure, names)).is_equal(["apple", "mango", "zebra"])


func test_order_names_is_a_permutation_of_input() -> void:
	var names := ["rocketchat_room", "rocketchat_message", "rocketchat_settings", "users"]
	var structure := schema.build_structure(names)
	var ordered := schema.order_names(structure, names)
	assert_array(ordered).has_size(names.size())
	for n in names:
		assert_array(ordered).contains([n])


func test_generic_order_names_preserves_input_order() -> void:
	# The base override just returns the input list unchanged.
	var names := ["zebra", "apple", "mango"]
	assert_array(GenericSchema.new().order_names([], names)).is_equal(names)
