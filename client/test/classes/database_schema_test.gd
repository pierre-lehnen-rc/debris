class_name DatabaseSchemaTest
extends "res://test/test_suite.gd"

# Tests for DatabaseSchema — the base schema's UI-free helpers: word shaping,
# dotted-path resolution, and the custom type/action system.
# See res://source/classes/database_schema.gd
# (Collection grouping via build_structure/path_for is covered in
# generic_schema_test.gd; RocketChat-specific overrides in rocket_chat_schema_test.gd.)


func _schema() -> DatabaseSchema:
	return DatabaseSchema.new()


## A schema with a small representative rule set: two whole-document types
## (Room, VideoConference, User) and a UserId field type used once on rooms and
## twice on video_conference.
func _typed_schema() -> DatabaseSchema:
	var s := DatabaseSchema.new()
	s.type_rules = [
		{"collection": "rooms", "field": "", "type": "Room"},
		{"collection": "rooms", "field": "u._id", "type": "UserId"},
		{"collection": "video_conference", "field": "", "type": "VideoConference"},
		{"collection": "video_conference", "field": "createdBy._id", "type": "UserId"},
		{"collection": "video_conference", "field": "endedBy._id", "type": "UserId"},
		{"collection": "users", "field": "", "type": "User"},
	]
	s.type_actions = {"User": [{"id": "open_user", "label": "Open user"}]}
	return s


# _humanize -------------------------------------------------------------------
func test_humanize_splits_camel_case() -> void:
	assert_str(_schema()._humanize("VideoConference")).is_equal("Video Conference")


func test_humanize_multi_word() -> void:
	assert_str(_schema()._humanize("MediaCall")).is_equal("Media Call")
	assert_str(_schema()._humanize("AppLog")).is_equal("App Log")


func test_humanize_single_word_unchanged() -> void:
	assert_str(_schema()._humanize("User")).is_equal("User")


func test_humanize_splits_after_digit() -> void:
	assert_str(_schema()._humanize("read2Receipt")).is_equal("read2 Receipt")


func test_humanize_leaves_acronyms_and_lowercase() -> void:
	assert_str(_schema()._humanize("ABC")).is_equal("ABC")
	assert_str(_schema()._humanize("abc")).is_equal("abc")


# _pluralize ------------------------------------------------------------------
func test_pluralize_regular() -> void:
	assert_str(_schema()._pluralize("Room")).is_equal("Rooms")


func test_pluralize_sibilant_endings_add_es() -> void:
	assert_str(_schema()._pluralize("Box")).is_equal("Boxes")
	assert_str(_schema()._pluralize("Match")).is_equal("Matches")
	assert_str(_schema()._pluralize("Dish")).is_equal("Dishes")
	assert_str(_schema()._pluralize("Buzz")).is_equal("Buzzes")
	assert_str(_schema()._pluralize("Bus")).is_equal("Buses")


func test_pluralize_consonant_y_becomes_ies() -> void:
	assert_str(_schema()._pluralize("Inquiry")).is_equal("Inquiries")
	assert_str(_schema()._pluralize("Company")).is_equal("Companies")


func test_pluralize_vowel_y_adds_s() -> void:
	assert_str(_schema()._pluralize("Key")).is_equal("Keys")


func test_pluralize_multi_word_operates_on_tail() -> void:
	assert_str(_schema()._pluralize("Video Conference")).is_equal("Video Conferences")
	assert_str(_schema()._pluralize("Livechat Inquiry")).is_equal("Livechat Inquiries")


func test_pluralize_empty() -> void:
	assert_str(_schema()._pluralize("")).is_equal("")


# _singularize ----------------------------------------------------------------
func test_singularize_drops_trailing_s() -> void:
	assert_str(_schema()._singularize("calls")).is_equal("call")
	assert_str(_schema()._singularize("channels")).is_equal("channel")
	assert_str(_schema()._singularize("sessions")).is_equal("session")


func test_singularize_ies_to_y() -> void:
	assert_str(_schema()._singularize("categories")).is_equal("category")


func test_singularize_sibilant_es() -> void:
	assert_str(_schema()._singularize("boxes")).is_equal("box")
	assert_str(_schema()._singularize("matches")).is_equal("match")
	assert_str(_schema()._singularize("dishes")).is_equal("dish")
	assert_str(_schema()._singularize("buses")).is_equal("bus")


func test_singularize_leaves_non_plural_s_endings() -> void:
	assert_str(_schema()._singularize("class")).is_equal("class")
	assert_str(_schema()._singularize("status")).is_equal("status")
	assert_str(_schema()._singularize("analysis")).is_equal("analysis")


func test_singularize_leaves_short_words() -> void:
	assert_str(_schema()._singularize("s")).is_equal("s")
	assert_str(_schema()._singularize("bus")).is_equal("bus")


func test_singularize_operates_on_whole_token() -> void:
	assert_str(_schema()._singularize("media_calls")).is_equal("media_call")


# _tokenize -------------------------------------------------------------------
func test_tokenize_underscore() -> void:
	assert_array(_schema()._tokenize("read_receipt")).is_equal([
		{"sep": "", "token": "read"}, {"sep": "_", "token": "receipt"},
	])


func test_tokenize_camel_case_when_no_separator() -> void:
	assert_array(_schema()._tokenize("VideoConference")).is_equal([
		{"sep": "", "token": "Video"}, {"sep": "", "token": "Conference"},
	])


func test_tokenize_leading_separator_kept_literal() -> void:
	assert_array(_schema()._tokenize("_queue")).is_equal([{"sep": "", "token": "_queue"}])


func test_tokenize_doubled_separator() -> void:
	assert_array(_schema()._tokenize("x__trash")).is_equal([
		{"sep": "", "token": "x"}, {"sep": "_", "token": "_trash"},
	])


# value_at_path (static) ------------------------------------------------------
func test_value_at_path_empty_returns_source() -> void:
	var doc := {"a": 1}
	assert_dict(DatabaseSchema.value_at_path(doc, "")).is_equal({"a": 1})


func test_value_at_path_scalar_source() -> void:
	assert_str(DatabaseSchema.value_at_path("xyz", "")).is_equal("xyz")


func test_value_at_path_dotted() -> void:
	var doc := {"u": {"_id": "abc"}}
	assert_str(DatabaseSchema.value_at_path(doc, "u._id")).is_equal("abc")


func test_value_at_path_missing_is_null() -> void:
	assert_object(DatabaseSchema.value_at_path({"u": {}}, "missing.x")).is_null()


func test_value_at_path_flattens_over_array() -> void:
	var doc := {"mentions": [{"_id": 1}, {"_id": 2}]}
	assert_array(DatabaseSchema.value_at_path(doc, "mentions._id")).is_equal([1, 2])


# resolve_filter (static) -----------------------------------------------------
func test_resolve_filter_literals_pass_through() -> void:
	assert_dict(DatabaseSchema.resolve_filter({"a": 1, "b": "x"}, {})).is_equal({"a": 1, "b": "x"})


func test_resolve_filter_substitutes_dollar_path() -> void:
	var doc := {"u": {"_id": "abc"}}
	assert_dict(DatabaseSchema.resolve_filter({"uid": "$u._id"}, doc)).is_equal({"uid": "abc"})


func test_resolve_filter_dollar_alone_is_source() -> void:
	assert_dict(DatabaseSchema.resolve_filter({"v": "$"}, "myval")).is_equal({"v": "myval"})


func test_resolve_filter_array_becomes_in() -> void:
	var doc := {"mentions": [{"_id": 1}, {"_id": 2}]}
	assert_dict(DatabaseSchema.resolve_filter({"id": "$mentions._id"}, doc)).is_equal(
		{"id": {"$in": [1, 2]}}
	)


func test_resolve_filter_recurses_into_nested() -> void:
	assert_dict(DatabaseSchema.resolve_filter({"o": {"k": "$n"}}, {"n": 5})).is_equal(
		{"o": {"k": 5}}
	)


# type_for --------------------------------------------------------------------
func test_type_for_whole_document() -> void:
	assert_str(_typed_schema().type_for("rooms", "")).is_equal("Room")


func test_type_for_field_level() -> void:
	assert_str(_typed_schema().type_for("rooms", "u._id")).is_equal("UserId")


func test_type_for_unknown_returns_empty() -> void:
	assert_str(_typed_schema().type_for("rooms", "nope")).is_equal("")
	assert_str(_typed_schema().type_for("other", "")).is_equal("")


# scalar_types ----------------------------------------------------------------
func test_scalar_types_are_field_only_types() -> void:
	# UserId is only ever a field type; Room/VideoConference/User are document types.
	assert_array(_typed_schema().scalar_types()).is_equal(["UserId"])


# typed_fields ----------------------------------------------------------------
func test_typed_fields_excludes_whole_document_rule() -> void:
	assert_array(_typed_schema().typed_fields("rooms")).is_equal([
		{"field": "u._id", "type": "UserId"},
	])


func test_typed_fields_lists_each_attribute() -> void:
	assert_array(_typed_schema().typed_fields("video_conference")).is_equal([
		{"field": "createdBy._id", "type": "UserId"},
		{"field": "endedBy._id", "type": "UserId"},
	])


func test_typed_fields_none_for_unknown_collection() -> void:
	assert_array(_typed_schema().typed_fields("nope")).is_empty()


# actions_for_type ------------------------------------------------------------
func test_actions_for_type_generates_one_per_field_usage() -> void:
	var actions := _typed_schema().actions_for_type("UserId")
	# rooms.u._id, video_conference.createdBy._id, video_conference.endedBy._id.
	assert_array(actions).has_size(3)


func test_actions_for_type_label_omits_field_when_unique() -> void:
	var actions := _typed_schema().actions_for_type("UserId")
	# rooms has a single UserId field, so no disambiguating "by <field>".
	assert_str(actions[0]["label"]).is_equal("List Rooms")
	assert_str(actions[0]["target_collection"]).is_equal("rooms")
	assert_dict(actions[0]["filter"]).is_equal({"u._id": "$"})
	assert_str(actions[0]["function"]).is_equal("find")


func test_actions_for_type_label_adds_field_when_ambiguous() -> void:
	var actions := _typed_schema().actions_for_type("UserId")
	# video_conference has two UserId fields, so each label carries its field.
	assert_str(actions[1]["label"]).is_equal("List Video Conferences by createdBy._id")
	assert_str(actions[2]["label"]).is_equal("List Video Conferences by endedBy._id")


func test_actions_for_type_includes_manual_actions() -> void:
	# User has a manual action and no field usages.
	var actions := _typed_schema().actions_for_type("User")
	assert_array(actions).has_size(1)
	assert_str(actions[0]["label"]).is_equal("Open user")


func test_actions_for_type_unknown_is_empty() -> void:
	assert_array(_typed_schema().actions_for_type("Nope")).is_empty()


# is_highlighted --------------------------------------------------------------
func test_is_highlighted() -> void:
	var s := _schema()
	s.highlighted_collections = ["users", "rooms"]
	assert_bool(s.is_highlighted("users")).is_true()
	assert_bool(s.is_highlighted("settings")).is_false()
