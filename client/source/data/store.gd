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
