class_name LogStream
extends Node

## The shared server-log tail for one project: a single poll loop against the log
## tap, with one cursor and one backlog buffer. The Server Logs sidebar panel drives
## it (start/stop the source), and any number of Server Logs tabs render it, each
## with its own client-side filters — so there is one stream of the server's log and
## several views onto it, never several rival pollers.
##
## Lives as a child of the project tab (like the session and history stores). Holds
## Node-ness only for its poll Timer.

## Newly captured lines (parsed LogEntry dicts), appended to the buffer this poll.
signal entries_added(entries: Array)
## The streaming state, for the panel: { streaming: bool, lines: int, message: String }.
signal status_changed(state: Dictionary)
## The backlog was cleared — views should drop what they show.
signal cleared()
## New logger `name` values appeared in the tail (never seen before), so the Names
## filter can add them and the host can cache them for next session.
signal names_discovered(new_names: Array)
## The tail's reach flipped — the server (via the bridge) started or stopped
## answering — so the host can repaint the workspace/bridge status footers.
signal reachability_changed(reachable: bool)

const POLL_INTERVAL := 1.0
## Cap on the retained backlog (across polls). The server buffer is bounded too;
## this bounds accumulation so a long session can't grow without limit.
const MAX_ENTRIES := 5000
const TRIM_CHUNK := 1000

# Reads the workspace's Server Models target ({ repo_path, url }) live, so a
# repository path set after the stream was created is picked up without recreating it.
var _target_provider: Callable = Callable()

var _since := 0
var _buffer: Array = []
var _streaming := false
var _polling := false
var _timer: Timer = null
# Distinct logger `name` values seen (a set: name -> true), seeded from the cache and
# grown as new names appear.
var _known_names: Dictionary = {}
# The last error surfaced, so repeated identical failures neither re-log nor
# re-alarm — only a change of state reaches the Activity Log.
var _last_error := ""


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = POLL_INTERVAL
	_timer.one_shot = false
	_timer.timeout.connect(_poll)
	add_child(_timer)


## Bind the Callable that returns the current target ({ repo_path, url }).
func bind_target(provider: Callable) -> void:
	_target_provider = provider


## The retained backlog (parsed LogEntry dicts), for a view opening mid-stream.
func buffer() -> Array:
	return _buffer


## Seed the known logger names from the workspace cache, so the Names filter offers
## them before a line for one is seen this session.
func seed_known_names(names: Array) -> void:
	for name in names:
		var n := str(name)
		if not n.is_empty():
			_known_names[n] = true


## The distinct logger names seen so far (cached + discovered), sorted.
func known_names() -> Array:
	var names := _known_names.keys()
	names.sort()
	return names


func is_streaming() -> bool:
	return _streaming


# Control (from the sidebar panel) --------------------------------------------
func start() -> void:
	if _streaming:
		return
	if _build_target().is_empty():
		_emit_status("Set the Rocket.Chat Repository path in the workspace settings first")
		return
	_streaming = true
	_emit_status("Connecting…")
	await ServerManager.ensure_connected()
	if not _streaming:  # a Stop during the await wins
		return
	_timer.start()
	_poll()


func stop() -> void:
	if not _streaming:
		return
	_streaming = false
	if _timer != null:
		_timer.stop()
	_emit_status("")


## Discard the backlog. Streaming (if on) keeps its cursor, so only lines from here
## on appear — a fresh window on an ongoing tail, shared by every view.
func clear() -> void:
	_buffer.clear()
	cleared.emit()
	_emit_status("" if _last_error.is_empty() else _last_error)


# Polling ---------------------------------------------------------------------
func _poll() -> void:
	if not _streaming or _polling:
		return
	var target := _build_target()
	if target.is_empty():
		stop()
		return
	_polling = true
	var result: Dictionary = await Backend.rocketchat_logs(target, _since)
	_polling = false
	if not _streaming:  # stopped while the request was in flight
		return

	var url := String(target.get("url", ""))
	if not result.get("ok", false):
		# Keep polling — the bridge may not be injected yet, or the server may be
		# down; the tail recovers on its own once it answers. The failure is noted
		# once (see _note), not every second.
		var err := String(result.get("error", "request failed"))
		_note(err, url)
		_emit_status(err)
		return

	var data: Dictionary = result.get("data", {}) if result.get("data") is Dictionary else {}
	var batch := _parse_batch(data.get("entries", []))
	_since = maxi(_since, int(data.get("seq", _since)))
	if not batch.is_empty():
		_buffer.append_array(batch)
		if _buffer.size() > MAX_ENTRIES:
			_buffer = _buffer.slice(_buffer.size() - (MAX_ENTRIES - TRIM_CHUNK))
		# Announce any new logger names before the lines render, so the Names filter
		# already knows them when the entries_added listeners re-render.
		_announce_new_names(batch)
		entries_added.emit(batch)

	# A tap that couldn't attach reports through `error` even on an ok poll.
	var tap_error := String(data.get("error", ""))
	_note(tap_error, url)
	_emit_status(tap_error)


## Note any logger names in `batch` not seen before, and announce them.
func _announce_new_names(batch: Array) -> void:
	var new_names: Array = []
	for entry in batch:
		var doc: Dictionary = entry.get("doc", {}) if entry.get("doc") is Dictionary else {}
		var name := str(doc.get("name", ""))
		if not name.is_empty() and not _known_names.has(name):
			_known_names[name] = true
			new_names.append(name)
	if not new_names.is_empty():
		names_discovered.emit(new_names)


func _parse_batch(raw_entries: Variant) -> Array:
	var out: Array = []
	if not (raw_entries is Array):
		return out
	for raw in raw_entries:
		if raw is Dictionary:
			out.append(LogEntry.parse(int(raw.get("seq", 0)), str(raw.get("line", ""))))
	return out


# Activity Log ----------------------------------------------------------------
## Record a change in the tail's health. Polling itself is watching, not an action,
## so a steady stream (or a steady failure) records nothing; but the transition into
## a problem — a 404 because the endpoint isn't there, an unreachable server — and
## the recovery out of it are worth one entry each, so a silent failure never is.
func _note(error: String, url: String) -> void:
	if error == _last_error:
		return
	var was_ok := _last_error.is_empty()
	_last_error = error
	# Quiet: a background poll failure is surfaced in the panel's status line and here
	# in the Activity Log, but must not pop an error dialog on every second it's down.
	ActivityLog.record({
		"source": "rocketchat",
		"action": "rocketchat/logs",
		"target": url,
		"ok": error.is_empty(),
		"result": "streaming" if error.is_empty() else "",
		"error": error,
		"quiet": true,
	})
	# Announce a reach flip (ok <-> failing) so the status footers repaint.
	if error.is_empty() != was_ok:
		reachability_changed.emit(error.is_empty())


# Helpers ---------------------------------------------------------------------
func _emit_status(message: String) -> void:
	status_changed.emit({"streaming": _streaming, "lines": _buffer.size(), "message": message})


func _build_target() -> Dictionary:
	var info: Dictionary = _target_provider.call() if _target_provider.is_valid() else {}
	var repo := String(info.get("repo_path", "")).strip_edges()
	if repo.is_empty():
		return {}
	var target := {"repoPath": repo}
	var url := String(info.get("url", "")).strip_edges()
	if not url.is_empty():
		target["url"] = url
	return target
