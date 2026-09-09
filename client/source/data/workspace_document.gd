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
## { "url": String, "users": Array, "repo_path": String }, or {} when no API is
## attached. `repo_path` is the local path to the server's Rocket.Chat repository
## (the checkout root), used by the Server Models bridge; "" when not configured.
var rocketchat: Dictionary = {}
## Favorite queries flagged for permanent keeping, per collection:
## { collection: Array[query-entry] }, newest first. Unlike the sidecar's recents
## these travel with the project file and are never evicted. Each entry is a
## QueryHistory saved-query dict.
var favorite_queries: Dictionary = {}
## Saved Server-Logs filter sets, in the project file, keyed by kind ("names" |
## "columns"). Each value is an Array of { name, selection: { key -> bool }, default }.
var log_filter_sets: Dictionary = {}

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


## The workspace dict WorkspaceSession/RocketChat expect, plus the Server Models
## repository path: { name, url, users, repo_path }. The project name doubles as
## the workspace display name.
func rocketchat_config() -> Dictionary:
	return {
		"name": name,
		"url": rocketchat.get("url", ""),
		"users": rocketchat.get("users", []),
		"repo_path": rocketchat.get("repo_path", ""),
	}


## The local Rocket.Chat repository path for the Server Models bridge, or "" when
## unset. The server derives the `apps/meteor` directory from it.
func rocketchat_repo_path() -> String:
	return rocketchat.get("repo_path", "")


# Mutations (mark the document dirty) -----------------------------------------
func set_mongo(connection: Dictionary, database: String) -> void:
	mongo = {"connection": connection, "database": database}
	dirty = true


func clear_mongo() -> void:
	mongo = {}
	dirty = true


func set_rocketchat(url: String, users: Array, repo_path := "") -> void:
	rocketchat = {"url": url, "users": _clean_users(users), "repo_path": repo_path}
	dirty = true


func clear_rocketchat() -> void:
	rocketchat = {}
	dirty = true


## Persist an updated user list (from the Users panel's live session) without
## touching the URL. Runtime-only fields (login-acquired tokens) are stripped, so
## login/logout produce no change. Returns true when the persisted list actually
## changed (so the caller can flag the project dirty / update its title).
func sync_rocketchat_users(raw_users: Array) -> bool:
	if not has_rocketchat():
		return false
	var cleaned := _clean_users(raw_users)
	if cleaned == rocketchat.get("users", []):
		return false
	rocketchat["users"] = cleaned
	dirty = true
	return true


func set_name(new_name: String) -> void:
	name = new_name
	dirty = true


# Favorite queries (mark the document dirty on change) ------------------------
## The favorite queries saved for `collection`, newest first, or [] when none.
func favorite_queries_for(collection: String) -> Array:
	var list: Variant = favorite_queries.get(collection, [])
	return list if list is Array else []


## Flag `entry` as a favorite of `collection`. No-op (returns false) when an
## identical query is already saved; otherwise prepends it and marks the doc dirty.
func add_favorite_query(collection: String, entry: Dictionary) -> bool:
	if collection.is_empty():
		return false
	var list := favorite_queries_for(collection)
	for e in list:
		if e is Dictionary and QueryHistory.same_query(e, entry):
			return false
	list.push_front(entry)
	favorite_queries[collection] = list
	dirty = true
	return true


## Remove the favorite of `collection` matching `entry`. Returns true when one was
## removed (and marks the doc dirty).
func remove_favorite_query(collection: String, entry: Dictionary) -> bool:
	var list := favorite_queries_for(collection)
	for i in list.size():
		if list[i] is Dictionary and QueryHistory.same_query(list[i], entry):
			list.remove_at(i)
			if list.is_empty():
				favorite_queries.erase(collection)
			else:
				favorite_queries[collection] = list
			dirty = true
			return true
	return false


# Serialization ---------------------------------------------------------------
## The persisted form: only non-empty blocks are written, and users are reduced to
## their config shape (session-only fields like acquired tokens are dropped).
# Server-log filter sets -----------------------------------------------------
# Saved sets for the Server Logs filters, keyed by `kind` ("names" | "columns").
# Each set is { name, selection: { key -> bool }, default: bool }; the one flagged
# default seeds new tabs. See SavedSets (the shared store) and CheckFilter.
func _filter_sets_of(kind: String) -> Array:
	if not log_filter_sets.has(kind):
		log_filter_sets[kind] = []
	return log_filter_sets[kind]


## A copy of the saved sets for `kind`.
func filter_set_list(kind: String) -> Array:
	return (log_filter_sets.get(kind, []) as Array).duplicate(true)


## Add or replace (by name) a set of `kind` with the given selection, keeping its flag.
func save_filter_set(kind: String, set_name: String, selection: Dictionary) -> void:
	var sets := _filter_sets_of(kind)
	for s in sets:
		if s is Dictionary and str(s.get("name", "")) == set_name:
			s["selection"] = selection.duplicate()
			return
	sets.append({"name": set_name, "selection": selection.duplicate(), "default": false})


func remove_filter_set(kind: String, set_name: String) -> void:
	var sets := _filter_sets_of(kind)
	for i in sets.size():
		if sets[i] is Dictionary and str(sets[i].get("name", "")) == set_name:
			sets.remove_at(i)
			return


## Flag one set of `kind` as the default for new tabs (at most one); clears the rest.
func set_default_filter_set(kind: String, set_name: String, is_default: bool) -> void:
	for s in _filter_sets_of(kind):
		if not (s is Dictionary):
			continue
		if str(s.get("name", "")) == set_name:
			s["default"] = is_default
		elif is_default:
			s["default"] = false


## The default set's selection for `kind`, or {} when none is flagged.
func default_filter_selection(kind: String) -> Dictionary:
	for s in _filter_sets_of(kind):
		if s is Dictionary and bool(s.get("default", false)):
			var sel: Variant = s.get("selection", {})
			return (sel as Dictionary).duplicate() if sel is Dictionary else {}
	return {}


func to_dict() -> Dictionary:
	var data: Dictionary = {"name": name}
	if has_mongo():
		data["mongo"] = {
			"connection": mongo.get("connection", {}),
			"database": mongo.get("database", ""),
		}
	if has_rocketchat():
		var rc := {
			"url": rocketchat.get("url", ""),
			"users": _clean_users(rocketchat.get("users", [])),
		}
		var repo_path := String(rocketchat.get("repo_path", ""))
		if not repo_path.is_empty():
			rc["repo_path"] = repo_path
		data["rocketchat"] = rc
	if not favorite_queries.is_empty():
		data["favorites"] = favorite_queries
	if not log_filter_sets.is_empty():
		data["log_filter_sets"] = log_filter_sets
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
			"repo_path": String(rd.get("repo_path", "")),
		}
	var fav: Variant = data.get("favorites", {})
	doc.favorite_queries = fav if fav is Dictionary else {}
	var sets: Variant = data.get("log_filter_sets", {})
	doc.log_filter_sets = sets if sets is Dictionary else {}
	# Migrate the earlier flat name-sets field.
	var legacy: Variant = data.get("log_name_sets", [])
	if legacy is Array and not (legacy as Array).is_empty() and not doc.log_filter_sets.has("names"):
		doc.log_filter_sets["names"] = legacy
	return doc


## Reduce a users array to the persisted config shape, dropping any runtime-only
## fields (session_user_id/session_token) so login-acquired tokens never land in a
## file. `auth` is inferred from a present token when not stated, so older/looser
## user entries keep working.
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
