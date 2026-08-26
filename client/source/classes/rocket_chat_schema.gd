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

# Maps an entity name to the DB collection whose type rules should type an
# endpoint's response rows. Rocket.Chat's REST payloads mirror the stored
# documents, so an endpoint dealing in users/rooms/messages can reuse the matching
# collection's rules (ids as UserId/RoomId/…). Looked up two ways (see
# collection_for_endpoint): by the payload envelope key (e.g. "user", "members")
# and by the operationId's namespace (e.g. "rooms", "chat"). Keys are lowercased,
# so singular/plural and case variants resolve; unlisted names stay untyped.
const RESULT_KEY_COLLECTIONS := {
	"user": "users", "users": "users", "member": "users", "members": "users",
	"channel": "rocketchat_room", "channels": "rocketchat_room",
	"group": "rocketchat_room", "groups": "rocketchat_room",
	"room": "rocketchat_room", "rooms": "rocketchat_room",
	"im": "rocketchat_room", "ims": "rocketchat_room",
	"dm": "rocketchat_room", "dms": "rocketchat_room",
	"message": "rocketchat_message", "messages": "rocketchat_message",
	"chat": "rocketchat_message",  # the chat.* namespace deals in messages
	"subscription": "rocketchat_subscription", "subscriptions": "rocketchat_subscription",
	"role": "rocketchat_roles", "roles": "rocketchat_roles",
	"team": "rocketchat_team", "teams": "rocketchat_team",
	"upload": "rocketchat_uploads", "uploads": "rocketchat_uploads",
	"file": "rocketchat_uploads", "files": "rocketchat_uploads",
	"visitor": "rocketchat_livechat_visitor", "visitors": "rocketchat_livechat_visitor",
	"department": "rocketchat_livechat_department", "departments": "rocketchat_livechat_department",
	"inquiry": "rocketchat_livechat_inquiry", "inquiries": "rocketchat_livechat_inquiry",
	"app": "rocketchat_apps", "apps": "rocketchat_apps",
}

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
		{"collection": "rocketchat_roles", "field": "", "type": "Role"},

		# A user's SIP extension.
		{"collection": "users", "field": "freeSwitchExtension", "type": "SipExtension"},

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
		{"collection": "rocketchat_media_calls", "field": "uids", "type": "UserId"},  # array
		{"collection": "rocketchat_media_call_negotiations", "field": "callId", "type": "MediaCallId"},
		{"collection": "rocketchat_media_call_negotiations", "field": "_id", "type": "MediaCallNegotiationId"},

		# Media call actor references: each is a {type, id} object whose id is a
		# UserId or a SIP extension depending on the sibling type. They're all the
		# same MediaCallActor object type (see type_defs below); _compile_type_defs()
		# expands each into the conditional `.id` sub-rules, so the condition is
		# written once and reused across every actor field.
		{"collection": "rocketchat_media_calls", "field": "createdBy", "type": "MediaCallActor"},
		{"collection": "rocketchat_media_calls", "field": "endedBy", "type": "MediaCallActor"},
		{"collection": "rocketchat_media_calls", "field": "transferredBy", "type": "MediaCallActor"},
		{"collection": "rocketchat_media_calls", "field": "divertedBy", "type": "MediaCallActor"},
		{"collection": "rocketchat_media_calls", "field": "caller", "type": "MediaCallActor"},
		{"collection": "rocketchat_media_calls", "field": "callee", "type": "MediaCallActor"},

		# Fields that hold a role's id.
		{"collection": "rocketchat_roles", "field": "_id", "type": "RoleId"},
		{"collection": "users", "field": "roles", "type": "RoleId"},  # array
		{"collection": "rocketchat_subscription", "field": "roles", "type": "RoleId"},  # array
	]
	# Object types: composite {type, id} shapes defined once and reused wherever a
	# type_rules entry binds them to a field (see the media-call actor fields above).
	type_defs = {
		# A media-call participant reference. `id` is a UserId when the actor is a
		# user, or a SIP extension number when it's a SIP endpoint — the `when`
		# paths are relative to the actor object, so the same rule works for every
		# actor field it's bound to.
		"MediaCallActor": {
			"id": [
				{"type": "UserId", "when": {"type": "user"}},
				{"type": "SipExtension", "when": {"type": "sip"}},
			],
			# Always a SIP extension, regardless of the actor's type (no `when`).
			"sipExtension": [
				{"type": "SipExtension"},
			],
		},
	}
	# Expand object-typed field bindings (MediaCallActor -> per-field `.id` rules).
	_compile_type_defs()
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


## The collection whose rules type an endpoint's rows (see RESULT_KEY_COLLECTIONS).
## The payload key names the entity directly for many endpoints (e.g. "user",
## "members"), so it's tried first — that also lets a sub-entity list type
## correctly (channels.members -> users). When the key is generic ("update",
## "remove") or the object is returned bare, it falls back to the operationId's
## namespace, so rooms.get / rooms.adminRooms.getRoom / subscriptions.get still
## type as their entity. Case-insensitive; "" when neither resolves.
func collection_for_endpoint(result_key: String, endpoint_id: String) -> String:
	var by_key := str(RESULT_KEY_COLLECTIONS.get(result_key.to_lower(), ""))
	if not by_key.is_empty():
		return by_key
	return str(RESULT_KEY_COLLECTIONS.get(_endpoint_namespace(endpoint_id), ""))


## The entity namespace of an operationId: the leading dotted token of its last
## path segment, lowercased. "rooms.adminRooms.getRoom" -> "rooms",
## "livechat/rooms.delete" -> "rooms", "users.list" -> "users".
func _endpoint_namespace(endpoint_id: String) -> String:
	var last := endpoint_id.get_slice("/", endpoint_id.get_slice_count("/") - 1)
	return last.get_slice(".", 0).to_lower()


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
