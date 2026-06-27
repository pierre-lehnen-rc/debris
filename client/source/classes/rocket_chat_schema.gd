class_name RocketChatSchema
extends DatabaseSchema

## Schema tuned for Rocket.Chat databases. It rewrites collection names before
## grouping so related collections land under meaningful feature folders
## (omnichannel, federation, media calls, admin, …). The rewrite affects only the
## grouping/display — the real collection name used to run queries is preserved.

# Collections grouped under a feature folder by an exact name match.
const MAIN_COLLECTIONS := ["users", "room", "subscription", "message", "roles", "permissions"]
const ADMIN_COLLECTIONS := ["migrations", "settings", "instances", "statistics", "server_events", "moderation_reports", "analytics", "_trash", "usersSessions", "sessions", "oembed_cache"]
const MEDIA_COLLECTIONS := ["call_history", "video_conference"]
const NOTIFICATION_COLLECTIONS := ["_raix_push_app_tokens", "notification_queue"]
const OMNICHANNEL_COLLECTIONS := ["canned_response"]

func mutate_collection_name(collection_name: String) -> String:
	var name := collection_name

	# 1. Drop the common "rocketchat_" prefix.
	if name.begins_with("rocketchat_"):
		name = name.substr("rocketchat_".length())

	# 2-4. Re-home feature prefixes under a parent feature folder.
	if name.begins_with("livechat_"):
		name = "omnichannel_" + name
	elif name.begins_with("matrix_"):
		name = "federation_" + name
	elif name.begins_with("freeswitch_"):
		name = "media_call_" + name

	# 5-7. Group well-known standalone collections under a feature folder.
	elif name in MAIN_COLLECTIONS:
		name = "main_" + name
	elif name in ADMIN_COLLECTIONS:
		name = "admin_" + name
	elif name in MEDIA_COLLECTIONS:
		name = "media_" + name
	elif name in NOTIFICATION_COLLECTIONS:
		name = "notification_" + name
	elif name in OMNICHANNEL_COLLECTIONS:
		name = "omnichannel_" + name


	return name
