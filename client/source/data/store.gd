class_name Store
extends RefCounted

## Persists user-configured connections and workspaces to a JSON file in the
## user data directory, so they survive across launches. The connection browser
## and workspace picker load their lists from here on startup and write back on
## every add/edit/remove. Only the configuration is stored — transient runtime
## state (a connection's live database list, connected flag, …) is left out and
## rebuilt at load time. A missing key means "never configured", which lets the
## UI seed a first-run default without re-seeding after the user clears the list.

const PATH := "user://settings.json"


static func connections() -> Array:
	return _read().get("connections", [])


static func workspaces() -> Array:
	return _read().get("workspaces", [])


## True once the given top-level key has been written at least once. Callers use
## this to distinguish "first run" from "user cleared the list".
static func has(key: String) -> bool:
	return _read().has(key)


static func save_connections(list: Array) -> void:
	var data := _read()
	data["connections"] = list
	_write(data)


static func save_workspaces(list: Array) -> void:
	var data := _read()
	data["workspaces"] = list
	_write(data)


## Recently-opened project file paths, most-recent first. Backs the File ▸ Open
## Recent menu in the document-based workspace model.
static func recent_workspaces() -> Array:
	return _read().get("recent_workspaces", [])


## Record `path` as the most-recently-opened project, de-duplicating and capping
## the list so it stays short.
static func add_recent_workspace(path: String, limit: int = 10) -> void:
	if path.is_empty():
		return
	var data := _read()
	var list: Array = data.get("recent_workspaces", [])
	list.erase(path)
	list.insert(0, path)
	while list.size() > limit:
		list.remove_at(list.size() - 1)
	data["recent_workspaces"] = list
	_write(data)


## Paths of the projects that were open at last shutdown, restored on launch.
## Only saved (on-disk) projects are listed; memory-only Untitled ones are lost.
static func open_workspaces() -> Array:
	return _read().get("open_workspaces", [])


static func save_open_workspaces(paths: Array) -> void:
	var data := _read()
	data["open_workspaces"] = paths
	_write(data)


## Read a single user preference (kept in a "preferences" sub-object), returning
## `default_value` when it was never set.
static func get_preference(key: String, default_value: Variant = null) -> Variant:
	var prefs: Variant = _read().get("preferences", {})
	if prefs is Dictionary and (prefs as Dictionary).has(key):
		return (prefs as Dictionary)[key]
	return default_value


static func set_preference(key: String, value: Variant) -> void:
	var data := _read()
	var prefs: Dictionary = data.get("preferences", {})
	prefs[key] = value
	data["preferences"] = prefs
	_write(data)


static func _read() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


static func _write(data: Dictionary) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Store: could not write %s" % PATH)
		return
	f.store_string(JSON.stringify(data, "\t"))
