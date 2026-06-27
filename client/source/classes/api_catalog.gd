class_name ApiCatalog
extends RefCounted

## A catalog of known Rocket.Chat REST endpoints. `builtin()` returns the curated
## set the app ships with; later, endpoints parsed from an OpenAPI document can be
## merged in via `from_dicts()` (both produce the same ApiEndpoint shape). The
## endpoint explorer groups these by `tag` in its sidebar.

## Build ApiEndpoints from an array of plain Dictionaries (catalog or OpenAPI).
static func from_dicts(entries: Array) -> Array:
	var out: Array = []
	for entry in entries:
		if entry is Dictionary:
			out.append(ApiEndpoint.from_dict(entry))
	return out


## The endpoints the app ships with. Kept deliberately small and representative;
## the param shapes mirror the real Rocket.Chat REST API so swapping the mock for
## live HTTP later is a drop-in.
static func builtin() -> Array:
	return from_dicts([
		{
			"id": "channels.list",
			"tag": "Channels",
			"summary": "List all public channels",
			"method": "GET",
			"path": "/api/v1/channels.list",
			"result_key": "channels",
			"paginated": true,
			"params": [
				{"name": "offset", "in": "query", "type": "int", "default": 0},
				{"name": "count", "in": "query", "type": "int", "default": 50},
				{"name": "sort", "in": "query", "type": "string",
					"description": "JSON sort spec, e.g. {\"name\":1}"},
			],
		},
		{
			"id": "channels.info",
			"tag": "Channels",
			"summary": "Get a single channel by id or name",
			"method": "GET",
			"path": "/api/v1/channels.info",
			"result_key": "channel",
			"single": true,
			"params": [
				{"name": "roomId", "in": "query", "type": "string",
					"description": "The channel's _id"},
				{"name": "roomName", "in": "query", "type": "string",
					"description": "The channel's name"},
			],
		},
		{
			"id": "channels.members",
			"tag": "Channels",
			"summary": "List the members of a channel",
			"method": "GET",
			"path": "/api/v1/channels.members",
			"result_key": "members",
			"paginated": true,
			"item_noun": "member",
			"params": [
				{"name": "roomId", "in": "query", "type": "string", "required": true},
				{"name": "offset", "in": "query", "type": "int", "default": 0},
				{"name": "count", "in": "query", "type": "int", "default": 50},
			],
		},
		{
			"id": "users.list",
			"tag": "Users",
			"summary": "List all users",
			"method": "GET",
			"path": "/api/v1/users.list",
			"result_key": "users",
			"paginated": true,
			"params": [
				{"name": "offset", "in": "query", "type": "int", "default": 0},
				{"name": "count", "in": "query", "type": "int", "default": 50},
				{"name": "query", "in": "query", "type": "string",
					"description": "JSON Mongo query filter"},
			],
		},
		{
			"id": "users.info",
			"tag": "Users",
			"summary": "Get a single user by id or username",
			"method": "GET",
			"path": "/api/v1/users.info",
			"result_key": "user",
			"single": true,
			"params": [
				{"name": "userId", "in": "query", "type": "string"},
				{"name": "username", "in": "query", "type": "string"},
			],
		},
		{
			"id": "chat.getMessage",
			"tag": "Chat",
			"summary": "Get a single message by id",
			"method": "GET",
			"path": "/api/v1/chat.getMessage",
			"result_key": "message",
			"single": true,
			"params": [
				{"name": "msgId", "in": "query", "type": "string", "required": true},
			],
		},
		{
			"id": "im.list",
			"tag": "Direct Messages",
			"summary": "List the caller's direct message rooms",
			"method": "GET",
			"path": "/api/v1/im.list",
			"result_key": "ims",
			"paginated": true,
			"item_noun": "DM",
			"params": [
				{"name": "offset", "in": "query", "type": "int", "default": 0},
				{"name": "count", "in": "query", "type": "int", "default": 50},
			],
		},
	])
