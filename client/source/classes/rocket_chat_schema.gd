class_name RocketChatSchema
extends DatabaseSchema

## Schema tuned for Rocket.Chat databases. It rewrites collection names before
## grouping so related collections land under meaningful feature folders
## (omnichannel, federation, media calls, admin, …). The rewrite affects only the
## grouping/display — the real collection name used to run queries is preserved.

# Collections grouped under a feature folder by an exact name match.
const MEDIA_COLLECTIONS := ["call_history", "video_conference"]
const OMNICHANNEL_COLLECTIONS := ["canned_response"]
const SKIPPED_LABEL_PREFIXES := ["rocketchat_", "omnichannel_", "livechat_", "meteor_"]

# The core collections worth spotting at a glance, by real collection name.
const HIGHLIGHTED_COLLECTIONS := [
	"users",
	"rocketchat_room",
	"rocketchat_message",
	"rocketchat_subscription",
	"rocketchat_settings",
]

## Rocket.Chat databases have many small feature folders, so subdivide groups
## more eagerly than the generic default. Also flag the core collections so they
## stand out in the list.
func _init() -> void:
	min_group_size = 3
	highlighted_collections = HIGHLIGHTED_COLLECTIONS
	type_rules = [
		# Whole-document types, shown in the tree's Type column.
		{"collection": "users", "field": "", "type": "User"},
		{"collection": "rocketchat_room", "field": "", "type": "Room"},
		{"collection": "rocketchat_media_calls", "field": "", "type": "MediaCall"},
		{"collection": "rocketchat_media_call_negotiations", "field": "", "type": "MediaCallNegotiation"},
		{"collection": "rocketchat_message", "field": "", "type": "Message"},
		{"collection": "rocketchat_subscription", "field": "", "type": "Subscription"},
		{"collection": "rocketchat_video_conference", "field": "", "type": "VideoConference"},
		{"collection": "rocketchat_team", "field": "", "type": "Team"},
		{"collection": "rocketchat_team_member", "field": "", "type": "TeamMember"},
		{"collection": "rocketchat_livechat_visitor", "field": "", "type": "LivechatVisitor"},
		{"collection": "rocketchat_livechat_department", "field": "", "type": "LivechatDepartment"},
		{"collection": "rocketchat_livechat_department_agents", "field": "", "type": "DepartmentAgent"},
		{"collection": "rocketchat_livechat_inquiry", "field": "", "type": "LivechatInquiry"},
		{"collection": "rocketchat_apps", "field": "", "type": "App"},
		{"collection": "rocketchat_apps_logs", "field": "", "type": "AppLog"},
		{"collection": "rocketchat_apps_persistence", "field": "", "type": "AppPersistence"},
		{"collection": "rocketchat_apps_settings", "field": "", "type": "AppSetting"},
		{"collection": "rocketchat_uploads", "field": "", "type": "Upload"},
		{"collection": "rocketchat_read_receipts", "field": "", "type": "ReadReceipt"},

		# Fields that hold a user's id, wherever they appear across collections.
		{"collection": "users", "field": "_id", "type": "UserId"},
		{"collection": "rocketchat_room", "field": "u._id", "type": "UserId"},
		{"collection": "rocketchat_room", "field": "uids", "type": "UserId"},  # array
		{"collection": "rocketchat_room", "field": "servedBy._id", "type": "UserId"},
		{"collection": "rocketchat_message", "field": "u._id", "type": "UserId"},
		{"collection": "rocketchat_message", "field": "editedBy._id", "type": "UserId"},
		{"collection": "rocketchat_message", "field": "pinnedBy._id", "type": "UserId"},
		{"collection": "rocketchat_message", "field": "mentions._id", "type": "UserId"},  # array
		{"collection": "rocketchat_message", "field": "starred._id", "type": "UserId"},  # array
		{"collection": "rocketchat_message", "field": "replies", "type": "UserId"},  # array of ids
		{"collection": "rocketchat_subscription", "field": "u._id", "type": "UserId"},
		{"collection": "rocketchat_video_conference", "field": "createdBy._id", "type": "UserId"},
		{"collection": "rocketchat_uploads", "field": "userId", "type": "UserId"},
		{"collection": "rocketchat_read_receipts", "field": "userId", "type": "UserId"},
		{"collection": "rocketchat_team", "field": "createdBy._id", "type": "UserId"},
		{"collection": "rocketchat_team_member", "field": "userId", "type": "UserId"},
		{"collection": "rocketchat_livechat_department_agents", "field": "agentId", "type": "UserId"},

		# Fields that hold a user's username, wherever they appear.
		{"collection": "users", "field": "username", "type": "Username"},
		{"collection": "rocketchat_room", "field": "u.username", "type": "Username"},
		{"collection": "rocketchat_message", "field": "u.username", "type": "Username"},
		{"collection": "rocketchat_message", "field": "mentions.username", "type": "Username"},  # array
		{"collection": "rocketchat_subscription", "field": "u.username", "type": "Username"},

		# Fields that hold a room's id, wherever they appear across collections.
		{"collection": "rocketchat_room", "field": "_id", "type": "RoomId"},
		{"collection": "rocketchat_room", "field": "prid", "type": "RoomId"},  # parent room (discussion)
		{"collection": "rocketchat_subscription", "field": "rid", "type": "RoomId"},
		{"collection": "rocketchat_video_conference", "field": "rid", "type": "RoomId"},
		{"collection": "rocketchat_message", "field": "rid", "type": "RoomId"},
		{"collection": "rocketchat_message", "field": "drid", "type": "RoomId"},  # discussion room
		{"collection": "rocketchat_uploads", "field": "rid", "type": "RoomId"},
		{"collection": "rocketchat_read_receipts", "field": "roomId", "type": "RoomId"},
		{"collection": "rocketchat_livechat_inquiry", "field": "rid", "type": "RoomId"},
		{"collection": "rocketchat_team", "field": "roomId", "type": "RoomId"},
		{"collection": "rocketchat_team_member", "field": "roomId", "type": "RoomId"},

		# Fields that hold a message's id.
		{"collection": "rocketchat_message", "field": "_id", "type": "MessageId"},
		{"collection": "rocketchat_message", "field": "tmid", "type": "MessageId"},  # thread parent
		{"collection": "rocketchat_read_receipts", "field": "messageId", "type": "MessageId"},

		# Fields that hold a team's id.
		{"collection": "rocketchat_team", "field": "_id", "type": "TeamId"},
		{"collection": "rocketchat_room", "field": "teamId", "type": "TeamId"},
		{"collection": "rocketchat_subscription", "field": "teamId", "type": "TeamId"},
		{"collection": "rocketchat_team_member", "field": "teamId", "type": "TeamId"},

		# Fields that hold a livechat department's id.
		{"collection": "rocketchat_livechat_department", "field": "_id", "type": "DepartmentId"},
		{"collection": "rocketchat_room", "field": "departmentId", "type": "DepartmentId"},
		{"collection": "rocketchat_livechat_department_agents", "field": "departmentId", "type": "DepartmentId"},
		{"collection": "rocketchat_livechat_inquiry", "field": "department", "type": "DepartmentId"},

		# Fields that hold a livechat visitor's id.
		{"collection": "rocketchat_livechat_visitor", "field": "_id", "type": "VisitorId"},
		{"collection": "rocketchat_room", "field": "v._id", "type": "VisitorId"},
		{"collection": "rocketchat_livechat_inquiry", "field": "v._id", "type": "VisitorId"},

		# Fields that hold an app's id.
		{"collection": "rocketchat_apps", "field": "_id", "type": "AppId"},
		{"collection": "rocketchat_apps_logs", "field": "appId", "type": "AppId"},
		{"collection": "rocketchat_apps_persistence", "field": "appId", "type": "AppId"},
		{"collection": "rocketchat_apps_settings", "field": "appId", "type": "AppId"},

		# Fields that hold an upload/file id.
		{"collection": "rocketchat_uploads", "field": "_id", "type": "FileId"},
		{"collection": "rocketchat_message", "field": "file._id", "type": "FileId"},
		{"collection": "rocketchat_message", "field": "files._id", "type": "FileId"},  # array

		# Media call ids.
		{"collection": "rocketchat_media_calls", "field": "_id", "type": "MediaCallId"},
		{"collection": "rocketchat_media_call_negotiations", "field": "callId", "type": "MediaCallId"},
		{"collection": "rocketchat_media_call_negotiations", "field": "_id", "type": "MediaCallNegotiationId"},
	]
	# No explicit type_actions: actions_for_type() auto-generates a "List <X>"
	# action for every collection/field where a type is used, so e.g. a UserId
	# value can list users, messages, subscriptions, rooms and video conferences
	# by the corresponding user-id field, all derived from the rules above.


## Sort the tree by each collection's grouped path, so it appears ordered by its
## (mutated) display layout. At every level a folder's own same-named collection
## comes first, then sub-folders, then loose collections — each band sorted by
## label. Precomputes a key per name so the sort doesn't re-walk the structure
## on every comparison.
func order_names(structure: Array, names: Array) -> Array:
	var keyed: Array = []
	for name in names:
		keyed.append({"name": name, "key": _sort_key(path_for(structure, name))})
	keyed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["key"] < b["key"])
	var ordered: Array = []
	for entry in keyed:
		ordered.append(entry["name"])
	return ordered


## Build a comparable key for a tree path. Each path segment becomes a
## [rank, label] pair so lexicographic Array comparison orders, at every level:
## the parent's self-collection (rank 0), then sub-folders (rank 1), then loose
## collections (rank 2) — alphabetically within each band.
func _sort_key(path: Array) -> Array:
	var key: Array = []
	var last := path.size() - 1
	for i in path.size():
		var rank := 1  # A folder: this segment has deeper segments below it.
		if i == last:
			# A leaf: the folder's own same-named collection sorts first, any other
			# collection sorts last.
			rank = 0 if i > 0 and path[i] == path[i - 1] else 2
		key.append([rank, path[i]])
	return key


func mutate_collection_name(collection_name: String) -> String:
	var name := collection_name
	var has_prefix := false

	# 1. Drop the common "rocketchat_" prefix.
	if name.begins_with("rocketchat_"):
		has_prefix = true
		name = name.substr("rocketchat_".length())
	elif name.begins_with("omnichannel_"):
		has_prefix = true
	elif name.begins_with("custom_emoji"):
		has_prefix = true

	# 2-4. Re-home feature prefixes under a parent feature folder.
	if name.begins_with("livechat_"):
		name = "omnichannel_" + name
	elif name.begins_with("matrix_"):
		name = "federation_" + name
	elif name.begins_with("freeswitch_"):
		name = "media_" + name
	elif name.begins_with("read_receipt"):
		name = "message_" + name

	# 5-7. Group well-known standalone collections under a feature folder.
	if name in MEDIA_COLLECTIONS:
		name = "media_" + name
	elif name in OMNICHANNEL_COLLECTIONS:
		name = "omnichannel_" + name

	if has_prefix:
		return "rocketchat_" + name

	return name


## Label a collection by its name relative to its parent's parent: take the
## (grouping-)mutated name and strip the prefix contributed by every folder above
## the parent. So "rocketchat_cron_history" nested under rocketchat > cron shows
## as "cron_history", while a collection only one folder deep keeps its full name.
func mutate_collection_label(_label: String, collection_name: String, ancestors: Array) -> String:
	var name := collection_name
	# Grandparent folders = every ancestor except the immediate parent (the last).
	var grandparents: Array = ancestors.slice(0, ancestors.size() - 1) if ancestors.size() > 1 else []
	var pos := 0
	for folder in grandparents:
		var label: String = folder
		if name.substr(pos, label.length()) != label:
			break  # Defensive: name/structure mismatch — stop stripping.
		pos += label.length()
		if pos < name.length() and (name[pos] == "_" or name[pos] == "."):
			pos += 1
	var auto_name = name.substr(pos)
	for prefix in SKIPPED_LABEL_PREFIXES:
		if auto_name.begins_with(prefix):
			auto_name = auto_name.substr(prefix.length())
	return auto_name
