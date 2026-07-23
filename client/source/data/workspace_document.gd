class_name WorkspaceDoc
extends RefCounted

## An in-memory "Debris project": a named workspace that optionally binds one
## Mongo database and one Rocket.Chat API. Both are optional and there is at most
## one of each. Persisted to a `.debris-project` JSON file by WorkspaceFile, or
## kept memory-only ("Untitled"). Only configuration is stored — runtime state
## (live connections, and login-acquired tokens held in WorkspaceSession) is never
## serialized. The project file IS the link between the DB and the API: both being
## members of the same document is what lets the two browsers interact.

# Persisted -------------------------------------------------------------------
var name: String = ""
## { "connection": Dictionary, "database": String }, or {} when no DB is attached.
var mongo: Dictionary = {}
## { "url": String, "users": Array }, or {} when no API is attached.
var rocketchat: Dictionary = {}

# Runtime-only, never serialized ----------------------------------------------
## Absolute path this project was loaded from / last saved to; "" for Untitled.
var file_path: String = ""
## Unsaved-changes flag; drives the save-on-close prompt and title bar marker.
var dirty: bool = false


func has_mongo() -> bool:
	return not mongo.is_empty()


func has_rocketchat() -> bool:
	return not rocketchat.is_empty()


## The connection config this project binds, or {} when no DB is attached.
func mongo_connection() -> Dictionary:
	return mongo.get("connection", {})


## The database name this project binds, or "" when no DB is attached.
func mongo_database() -> String:
	return mongo.get("database", "")


## The workspace dict WorkspaceSession/RocketChat expect: { name, url, users }.
## The project name doubles as the workspace display name.
func rocketchat_config() -> Dictionary:
	return {
		"name": name,
		"url": rocketchat.get("url", ""),
		"users": rocketchat.get("users", []),
	}


# Mutations (mark the document dirty) -----------------------------------------
func set_mongo(connection: Dictionary, database: String) -> void:
	mongo = {"connection": connection, "database": database}
	dirty = true


func clear_mongo() -> void:
	mongo = {}
	dirty = true


func set_rocketchat(url: String, users: Array) -> void:
	rocketchat = {"url": url, "users": _clean_users(users)}
	dirty = true


func clear_rocketchat() -> void:
	rocketchat = {}
	dirty = true


func set_name(new_name: String) -> void:
	name = new_name
	dirty = true


# Serialization ---------------------------------------------------------------
## The persisted form: only non-empty blocks are written, and users are reduced to
## their config shape (session-only fields like acquired tokens are dropped).
func to_dict() -> Dictionary:
	var data: Dictionary = {"name": name}
	if has_mongo():
		data["mongo"] = {
			"connection": mongo.get("connection", {}),
			"database": mongo.get("database", ""),
		}
	if has_rocketchat():
		data["rocketchat"] = {
			"url": rocketchat.get("url", ""),
			"users": _clean_users(rocketchat.get("users", [])),
		}
	return data


static func from_dict(data: Dictionary) -> WorkspaceDoc:
	var doc := WorkspaceDoc.new()
	doc.name = String(data.get("name", ""))
	var m: Variant = data.get("mongo")
	if m is Dictionary and not (m as Dictionary).is_empty():
		var md := m as Dictionary
		var conn: Variant = md.get("connection", {})
		doc.mongo = {
			"connection": conn if conn is Dictionary else {},
			"database": String(md.get("database", "")),
		}
	var r: Variant = data.get("rocketchat")
	if r is Dictionary and not (r as Dictionary).is_empty():
		var rd := r as Dictionary
		doc.rocketchat = {
			"url": String(rd.get("url", "")),
			"users": _clean_users(rd.get("users", [])),
		}
	return doc


## Reduce a users array to the persisted config shape, dropping any runtime-only
## fields (session_user_id/session_token) so login-acquired tokens never land in a
## file. Mirrors WorkspacePicker._user_entry so legacy configs keep working:
## `auth` is inferred from a present token when not stated.
static func _clean_users(raw: Variant) -> Array:
	var out: Array = []
	if not (raw is Array):
		return out
	for entry in (raw as Array):
		if not (entry is Dictionary):
			continue
		var e := entry as Dictionary
		var token := String(e.get("token", ""))
		var auth := String(e.get("auth", "token" if not token.is_empty() else "password"))
		if auth != "password":
			auth = "token"
		out.append({
			"auth": auth,
			"user_id": String(e.get("user_id", "")),
			"username": String(e.get("username", "")),
			"token": token,
			"password": String(e.get("password", "")),
		})
	return out
