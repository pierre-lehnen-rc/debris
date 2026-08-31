extends Node

## Owns this app's relationship with the Debris server. On launch it checks
## whether a server is already answering at Backend's base URL (one the developer
## started by hand, or one left running from an earlier session) and attaches to
## it. It never starts one by itself: launching the bundled server is a deliberate
## action the user takes from the Collections footer panel, so opening the app
## doesn't spawn a background process behind their back.
##
## Starting one, when asked, means locating a `node` binary, extracting the
## bundled server (res://server/…) to a writable location, and launching it as a
## quiet background process (no console window).
##
## While attached, the app heartbeats the server every 30 seconds and sends a
## disconnect when it closes, so the server knows who is connected. A server this
## app launched (a "managed" server) stops itself once the last connected app
## goes away — so runs never leave an orphaned server behind, and there's no
## window for the user to watch or close. A server the developer started by hand
## keeps running regardless; the app just reuses it.
##
## The footer panel drives all of it: fetch_state() reports what the server is
## doing without registering this app as a client, and connect_to_server() /
## disconnect_from_server() / stop_server() attach, detach and shut it down.
## Disconnecting is the same signal closing the app sends, so a managed server
## left with no apps stops itself either way; stop_server() is for one that
## doesn't (a server started by hand).

signal status_changed(text: String)
## Emitted once startup concludes, carrying whether the server is answering. Used
## by await_ready() to unblock callers that started waiting before it resolved.
signal ready_resolved(available: bool)
## Emitted when a connect attempt concludes, carrying whether a server is up.
## Lets callers that asked while one was already in flight wait for its result
## instead of starting a second attempt.
signal connect_resolved(available: bool)
## Emitted when this app's connection to the server, or the server's
## availability, actually changes — attaching, detaching, or the server going
## away. The footer panel listens so it repaints when something other than the
## panel moved the server: opening a project starts one on demand, and the panel
## would otherwise keep showing whatever it read before that happened.
signal state_changed()

## Path (inside res://) of the bundled server produced by `yarn bundle`.
const BUNDLE_RES_PATH := "res://server/debris-server.cjs"
## Where the bundle is copied so `node` can run it (res:// may live inside a
## packed archive in exported builds and isn't a real filesystem path).
const BUNDLE_USER_PATH := "user://server/debris-server.cjs"
## How long to wait for a freshly-launched server to answer /health.
const STARTUP_POLL_ATTEMPTS := 40
const STARTUP_POLL_INTERVAL := 0.25
## How often we tell the server we're still here. The server presumes an app gone
## after ~60s of silence, so 30s tolerates one dropped beat.
const HEARTBEAT_INTERVAL := 30.0
## Timeout for the small control-plane calls (health, state, heartbeat, stop).
## Short so they never stall shutdown or the footer panel if the server is gone.
const CONTROL_TIMEOUT := 2.0
## How long to let a stopped server close before reporting the state that's left.
const STOP_SETTLE_SECONDS := 0.4
## Stands in for a server reply under the headless runner, where no call is made.
const OFFLINE_ERROR := "Server calls are disabled under the headless runner"

var _host := "127.0.0.1"
var _port := 4020

# Startup readiness, consumed by await_ready(). `_startup_resolved` flips true the
# moment startup concludes (server answering, or given up on); `_server_available`
# is the outcome. Callers that ask before it resolves await `ready_resolved`.
var _startup_resolved := false
var _server_available := false

# Identifies this app instance to the server for connection tracking. Generated
# once per run; distinct instances on one machine get distinct ids.
var _client_id := ""
var _heartbeat_timer: Timer = null

# True while a connect attempt is in flight, so concurrent askers queue behind it
# rather than each launching a server of their own.
var _connecting := false


func _ready() -> void:
	# Under the headless test/validation runner (dev/ scripts set DEBRIS_HEADLESS),
	# never touch the network or spawn the bundled server — tests run against mocks.
	# Resolve readiness immediately so anything that does await_ready() (nothing does
	# under mocks, but be safe) returns at once instead of hanging.
	if not OS.get_environment("DEBRIS_HEADLESS").is_empty():
		_finish_startup(false)
		return
	# Route the window's close button through us so we can send a disconnect
	# before the process dies. Programmatic quits go through quit() instead.
	get_tree().set_auto_accept_quit(false)
	_parse_base_url(Backend.base_url)
	_start()


## Handle the OS "close window" request: tell the server we're leaving, then quit.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit()


## Notify the server we're disconnecting, then quit the app. Every quit path
## (window close, Cmd/Ctrl+Q, File ▸ Quit) should call this so a managed server
## learns promptly that this app is gone instead of waiting out its timeout.
func quit() -> void:
	await _notify_disconnect()
	get_tree().quit()


## Await the bundled server's startup. Returns immediately once startup has
## concluded — true when the server is answering, false when it couldn't be
## started (the caller's request then fails with a clear error, as before) —
## otherwise blocks until the in-progress startup resolves. Lets the first
## requests after a cold launch wait for the server instead of racing it.
func await_ready() -> bool:
	if _startup_resolved:
		return _server_available
	return await ready_resolved


## Record the startup outcome and wake any waiters. Idempotent: only the first
## call takes effect, so late failure paths can't override an earlier success.
func _finish_startup(available: bool) -> void:
	if _startup_resolved:
		return
	_server_available = available
	_startup_resolved = true
	ready_resolved.emit(available)
	if available:
		_start_heartbeat()


## Update the availability flag once startup has already resolved. The footer
## panel's connect and stop actions change whether a server is answering, and
## await_ready() has to keep telling later Backend requests the truth. The
## startup gate itself stays resolved — waiters that already resumed are never
## re-armed. Only a real change is announced, so repeat calls stay silent.
func _set_available(available: bool) -> void:
	if _server_available == available:
		return
	_server_available = available
	state_changed.emit()


## Latest status line, also emitted via status_changed for the UI.
func _set_status(text: String) -> void:
	status_changed.emit(text)


func _parse_base_url(url: String) -> void:
	var stripped := url.replace("https://", "").replace("http://", "")
	var slash := stripped.find("/")
	if slash != -1:
		stripped = stripped.substr(0, slash)
	var parts := stripped.split(":")
	if parts.size() >= 1 and not parts[0].is_empty():
		_host = parts[0]
	if parts.size() >= 2:
		_port = int(parts[1])


## Launch-time attach: take up a server that's already answering, and stop there.
## Nothing is spawned — a cold start leaves the app running with no server, which
## the status line says and the footer panel's Connect button fixes. Finding none
## isn't a failed action, so it goes to the status line rather than the Activity
## Log, whose failures pop an error dialog.
func _start() -> void:
	var started := Time.get_ticks_msec()
	if await _healthy():
		_set_status("Using server already running at %s" % Backend.base_url)
		_record_server_event("detected", true, "Reused server already running", Time.get_ticks_msec() - started)
		_finish_startup(true)
		return
	_set_status("No server running — use Connect in the Collections footer to start one")
	_finish_startup(false)


## Make sure a server is answering at Backend's base URL: reuse one that already
## is, otherwise launch the bundled server and poll until it answers. Returns
## whether a server is up, recording the outcome in the Activity Log either way.
## Reached only through connect_to_server() — this is the one path that starts a
## server, and only the user asks for it.
func _ensure_running() -> bool:
	# Guarded here as well as in _healthy(): past the probe, this path runs
	# `node --version` and spawns a process.
	if _offline():
		return false
	var started := Time.get_ticks_msec()
	if await _healthy():
		_set_status("Using server already running at %s" % Backend.base_url)
		_record_server_event("detected", true, "Reused server already running", Time.get_ticks_msec() - started)
		return true

	var node := _find_node()
	if node.is_empty():
		_set_status("Node.js not found — start the server manually (set DEBRIS_NODE to override)")
		push_warning("ServerManager: no usable `node` binary found; server not started")
		_record_server_event("start", false, "Node.js not found — start the server manually", Time.get_ticks_msec() - started)
		return false

	var script := _extract_bundle()
	if script.is_empty():
		_set_status("Bundled server is missing (run `yarn bundle`)")
		push_warning("ServerManager: could not read " + BUNDLE_RES_PATH)
		_record_server_event("start", false, "Bundled server is missing (run `yarn bundle`)", Time.get_ticks_msec() - started)
		return false

	# Launch the server as a detached background process — no console window. It
	# runs quietly and stops itself once the last app disconnects (see the class
	# doc), so there's nothing for the user to watch or close. The child reads its
	# port/host and the managed flag from the environment it inherits from us.
	# Reuse detection keeps this from stacking up across runs.
	OS.set_environment("PORT", str(_port))
	OS.set_environment("HOST", _host)
	# Mark this as a managed server so it stops itself when the last app leaves.
	OS.set_environment("DEBRIS_MANAGED", "1")
	if OS.get_environment("LOG_LEVEL").is_empty():
		OS.set_environment("LOG_LEVEL", "warn")
	# open_console defaults to false, so no terminal window appears on Windows.
	var pid := OS.create_process(node, [script])
	if pid <= 0:
		_set_status("Failed to launch the bundled server")
		push_warning("ServerManager: OS.create_process failed for " + node)
		_record_server_event("start", false, "Failed to launch the bundled server", Time.get_ticks_msec() - started)
		return false
	_set_status("Started bundled server in the background (pid %d)" % pid)

	for _i in STARTUP_POLL_ATTEMPTS:
		await get_tree().create_timer(STARTUP_POLL_INTERVAL).timeout
		if await _healthy():
			_set_status("Bundled server ready at %s" % Backend.base_url)
			_record_server_event("started", true, "Launched bundled server (pid %d)" % pid, Time.get_ticks_msec() - started)
			return true
	_set_status("Bundled server launched but not yet responding")
	_record_server_event("started", false, "Launched bundled server (pid %d) but it never answered" % pid, Time.get_ticks_msec() - started)
	return false


## Record a server-lifecycle event in the shared ActivityLog, so the user sees
## when and how the server came up (or why it didn't) alongside their queries.
## The message lands in `result` on success and in `error` on failure; the
## `target` is the server's base URL, matching how Backend logs its requests.
func _record_server_event(action: String, ok: bool, message: String, ms: int) -> void:
	ActivityLog.record({
		"source": "server",
		"action": action,
		"target": Backend.base_url,
		"ok": ok,
		"result": message if ok else "",
		"error": "" if ok else message,
		"ms": ms,
	})


## True under the headless test/validation runner (dev/ scripts set
## DEBRIS_HEADLESS), where nothing may touch the network or spawn a server — see
## client/dev/README.md. Checked at every boundary that would do either.
func _offline() -> bool:
	return not OS.get_environment("DEBRIS_HEADLESS").is_empty()


## GET /health once; true when the server answers 200.
func _healthy() -> bool:
	if _offline():
		return false
	var http := HTTPRequest.new()
	http.timeout = CONTROL_TIMEOUT
	add_child(http)
	var err := http.request(Backend.base_url + "/health")
	if err != OK:
		http.queue_free()
		return false
	var result: Array = await http.request_completed
	http.queue_free()
	return result[0] == HTTPRequest.RESULT_SUCCESS and int(result[1]) == 200


# Connection heartbeat --------------------------------------------------------
## Begin heartbeating the server so it knows this app is connected. Sends one
## beat immediately, then every HEARTBEAT_INTERVAL. Idempotent. No-op under the
## headless runner (no network) and when not inside the tree.
func _start_heartbeat() -> void:
	if _heartbeat_timer != null:
		return
	if not OS.get_environment("DEBRIS_HEADLESS").is_empty() or not is_inside_tree():
		return
	_client_id = "%d-%d" % [Time.get_ticks_usec(), randi()]
	_send_heartbeat()
	_heartbeat_timer = Timer.new()
	_heartbeat_timer.wait_time = HEARTBEAT_INTERVAL
	_heartbeat_timer.timeout.connect(_send_heartbeat)
	add_child(_heartbeat_timer)
	_heartbeat_timer.start()
	# Past the guard above, so this fires only when we really did attach.
	state_changed.emit()


## Stop heartbeating and forget our client id, so this app is no longer a
## connected client. Purely local teardown — telling the server is the caller's
## business (see disconnect_from_server and stop_server, which differ in what
## they say to it). Re-arms cleanly: _start_heartbeat() registers a fresh id.
func _stop_heartbeat() -> void:
	var was_attached := not _client_id.is_empty()
	if _heartbeat_timer != null:
		_heartbeat_timer.stop()
		_heartbeat_timer.queue_free()
		_heartbeat_timer = null
	_client_id = ""
	if was_attached:
		state_changed.emit()


## POST /clients/heartbeat, fire-and-forget (a missed beat is tolerated server-side).
func _send_heartbeat() -> void:
	await _post_client("/clients/heartbeat")


## Tell the server we're disconnecting and wait briefly for it to land, so a
## managed server can stop promptly instead of waiting out its timeout. No-op if
## we never started heartbeating (server was never available).
func _notify_disconnect() -> void:
	if _client_id.is_empty():
		return
	await _post_client("/clients/disconnect")


## POST a control-plane call carrying our client id, plus any extra body fields.
func _post_client(path: String, extra: Dictionary = {}) -> Dictionary:
	var body := {"clientId": _client_id}
	body.merge(extra)
	return await _post_json(path, body)


## POST a control-plane call. Awaitable; short timeout so it never stalls
## shutdown if the server is already gone. Returns { ok, data, error }.
func _post_json(path: String, body: Dictionary) -> Dictionary:
	if _offline():
		return _failed_reply(OFFLINE_ERROR)
	var http := HTTPRequest.new()
	http.timeout = CONTROL_TIMEOUT
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := http.request(Backend.base_url + path, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		http.queue_free()
		return _failed_reply("Could not start request (error %d)" % err)
	var result: Array = await http.request_completed
	http.queue_free()
	return _reply_from(result)


## GET a control-plane call. Same shape and timeout as _post_json.
func _get_json(path: String) -> Dictionary:
	if _offline():
		return _failed_reply(OFFLINE_ERROR)
	var http := HTTPRequest.new()
	http.timeout = CONTROL_TIMEOUT
	add_child(http)
	var err := http.request(Backend.base_url + path)
	if err != OK:
		http.queue_free()
		return _failed_reply("Could not start request (error %d)" % err)
	var result: Array = await http.request_completed
	http.queue_free()
	return _reply_from(result)


## Turn an HTTPRequest.request_completed payload into { ok, data, error }, the
## same shape Backend hands back — a transport failure reads as an unreachable
## server, an HTTP error carries the server's message when it sent one.
func _reply_from(result: Array) -> Dictionary:
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS:
		return _failed_reply("Cannot reach server at %s" % Backend.base_url)
	var status := int(result[1])
	var parsed: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if status >= 200 and status < 300:
		return {"ok": true, "data": parsed, "error": ""}
	var message := "HTTP %d" % status
	if parsed is Dictionary and (parsed as Dictionary).get("error") is Dictionary:
		message = (parsed as Dictionary)["error"].get("message", message)
	return {"ok": false, "data": parsed, "error": message}


func _failed_reply(error: String) -> Dictionary:
	return {"ok": false, "data": null, "error": error}


# Server panel ----------------------------------------------------------------
## A read-only snapshot of the server, for the Collections footer panel. Asking
## registers nothing: it GETs /server/state, which has no side effects, so the
## panel can report on a server this app is deliberately not attached to. Our
## client id rides along only so the server can say whether we're still in its
## registry — a heartbeat lost to a restart or a timeout then shows as
## disconnected rather than as whatever we last believed.
##
## Always returns a full dictionary; when the server can't be reached `running`
## is false and `error` says why. Keys: running, connected (this app is
## registered), apps, connections (cached MongoDB clients), managed (the server
## stops itself when the last app leaves), pid, uptime_ms, url, error.
func fetch_state() -> Dictionary:
	var state := _blank_state()
	var path := "/server/state"
	if not _client_id.is_empty():
		path += "?clientId=" + _client_id.uri_encode()
	var reply := await _get_json(path)
	if not reply.get("ok", false):
		state["error"] = reply.get("error", "")
		return state
	var data: Dictionary = reply["data"] if reply.get("data") is Dictionary else {}
	state["running"] = true
	state["connected"] = bool(data.get("connected", false))
	state["apps"] = int(data.get("apps", 0))
	state["connections"] = int(data.get("connections", 0))
	state["managed"] = bool(data.get("managed", false))
	state["pid"] = int(data.get("pid", 0))
	state["uptime_ms"] = int(data.get("uptimeMs", 0))
	return state


## Attach this app to the server, launching one when nothing is answering.
## Idempotent: connecting while already attached just re-reads the state.
## Returns the resulting state.
##
## Only one attempt runs at a time. Several project tabs restoring at once — or a
## restore racing the footer's Connect button — would otherwise each launch a
## server, and every one after the first would fail to bind the port; latecomers
## wait for the attempt already running instead.
func connect_to_server() -> Dictionary:
	if _connecting:
		await connect_resolved
		return await fetch_state()
	if _client_id.is_empty():
		_connecting = true
		var available := await _ensure_running()
		# Resolves the startup gate on a cold launch; afterwards this just keeps
		# the availability flag current for requests made from here on.
		_finish_startup(available)
		_set_available(available)
		if available:
			# No-op when startup's own resolution already armed the heartbeat.
			_start_heartbeat()
			_set_status("Connected to the server at %s" % Backend.base_url)
		_connecting = false
		connect_resolved.emit(available)
	return await fetch_state()


## Make sure this app is attached to a running server, starting one if nothing is
## answering. The on-demand counterpart to the footer's Connect button, for the
## points where the app is about to need a server anyway: opening a project that
## has a database, or configuring one. Returns whether a server is available.
##
## Cheap to call on those paths — once attached it answers immediately without a
## round trip, so it can sit in front of a request that runs on every refresh.
func ensure_connected() -> bool:
	if not _client_id.is_empty():
		return true
	var state: Dictionary = await connect_to_server()
	return bool(state.get("running", false))


## Detach this app from the server: the same disconnect closing the app sends, so
## a managed server left with no apps stops itself here too. A server started by
## hand keeps running, and stop_server() below is how to end that one.
func disconnect_from_server() -> Dictionary:
	if not _client_id.is_empty():
		await _notify_disconnect()
		_stop_heartbeat()
		_set_status("Disconnected from the server at %s" % Backend.base_url)
	# A managed server is on its way out; let it go before reporting what's left.
	if is_inside_tree():
		await get_tree().create_timer(STOP_SETTLE_SECONDS).timeout
	return await fetch_state()


## Ask the server to shut down, and drop our connection to it. Works on a server
## this app launched and on one started by hand. Returns the state once the
## process has had a moment to close, so the caller sees it gone rather than
## catching it mid-shutdown.
func stop_server() -> Dictionary:
	var reply := await _post_json("/server/stop", {})
	if reply.get("ok", false):
		# The server is going away; there is nothing left to heartbeat. A stop
		# that failed leaves us attached to the server it couldn't end.
		_stop_heartbeat()
		_set_available(false)
		_set_status("Stopped the server at %s" % Backend.base_url)
	else:
		_set_status("Couldn't stop the server: %s" % reply.get("error", "unknown error"))
	if is_inside_tree():
		await get_tree().create_timer(STOP_SETTLE_SECONDS).timeout
	return await fetch_state()


## The state dictionary for a server that isn't answering — also the shape every
## fetch_state() result has, so callers can read the keys unconditionally.
func _blank_state() -> Dictionary:
	return {
		"running": false,
		"connected": false,
		"apps": 0,
		"connections": 0,
		"managed": false,
		"pid": 0,
		"uptime_ms": 0,
		"url": Backend.base_url,
		"error": "",
	}


## Find a runnable `node`: an explicit override first, then PATH, then the usual
## install locations (covers GUI launches with a minimal PATH).
func _find_node() -> String:
	var override := OS.get_environment("DEBRIS_NODE")
	if not override.is_empty() and _node_works(override):
		return override

	var candidates := ["node"]
	var home := OS.get_environment("HOME")
	if not home.is_empty():
		candidates.append(home + "/.volta/bin/node")
		candidates.append(home + "/.nvm/current/bin/node")
		candidates.append(home + "/.local/bin/node")
	candidates.append("/usr/local/bin/node")
	candidates.append("/usr/bin/node")
	candidates.append("/opt/homebrew/bin/node")  # macOS (Apple Silicon)
	candidates.append("/opt/local/bin/node")

	for candidate in candidates:
		if _node_works(candidate):
			return candidate
	return ""


func _node_works(path: String) -> bool:
	var out: Array = []
	var code := OS.execute(path, ["--version"], out, true)
	return code == 0


## Copy the bundled server out of res:// to a real, writable path and return its
## absolute (globalized) location, or "" if the bundle can't be read.
func _extract_bundle() -> String:
	var src := FileAccess.open(BUNDLE_RES_PATH, FileAccess.READ)
	if src == null:
		return ""
	var bytes := src.get_buffer(src.get_length())
	src.close()

	DirAccess.make_dir_recursive_absolute(BUNDLE_USER_PATH.get_base_dir())
	var dst := FileAccess.open(BUNDLE_USER_PATH, FileAccess.WRITE)
	if dst == null:
		return ""
	dst.store_buffer(bytes)
	dst.close()
	return ProjectSettings.globalize_path(BUNDLE_USER_PATH)
