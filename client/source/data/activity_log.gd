extends Node

## In-memory record of every action the app runs against a backend, so the user
## can review what happened and what came back. Registered as the `ActivityLog`
## autoload. Both data clients (Backend for MongoDB, RocketChat for the REST API)
## call record() at their request chokepoints; the Activity Log tab renders the
## entries and listens to entry_added for live updates.
##
## Each entry is a Dictionary shaped as:
##   {
##     time: String,     # local "HH:MM:SS" when the action completed
##     source: String,   # "mongo" | "rocketchat"
##     action: String,   # operation name, e.g. "find" or "GET /api/…"
##     target: String,   # what it acted on, e.g. "mydb.users" or a URL path
##     params: Dictionary, # inputs sent (filter, options, pagination, query, body)
##     ok: bool,         # whether the call succeeded
##     result: String,   # human summary of the payload ("28 results", …)
##     error: String,    # error message when ok is false, else ""
##     ms: int,          # wall-clock duration in milliseconds
##   }

## Emitted whenever a new entry is recorded, so open log tabs can append live.
signal entry_added(entry: Dictionary)

## Keep the log bounded; oldest entries are dropped once this is exceeded.
const MAX_ENTRIES := 1000

var _entries: Array = []


## Append an action to the log. Callers supply everything except the timestamp,
## which is stamped here so all entries share one clock. Missing keys are filled
## with sensible defaults so partial dictionaries are safe.
func record(entry: Dictionary) -> void:
	var stamped := {
		"time": Time.get_time_string_from_system(),
		"source": entry.get("source", ""),
		"action": entry.get("action", ""),
		"target": entry.get("target", ""),
		"params": entry.get("params", {}),
		"ok": entry.get("ok", false),
		"result": entry.get("result", ""),
		"error": entry.get("error", ""),
		"ms": entry.get("ms", 0),
	}
	_entries.append(stamped)
	if _entries.size() > MAX_ENTRIES:
		_entries = _entries.slice(_entries.size() - MAX_ENTRIES)
	entry_added.emit(stamped)


## All recorded entries, oldest first. Returns a copy so callers can reorder or
## trim without disturbing the log.
func entries() -> Array:
	return _entries.duplicate()


## Drop every recorded entry.
func clear() -> void:
	_entries.clear()
