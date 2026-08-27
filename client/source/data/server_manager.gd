extends Node

## Owns startup of the bundled Debris server. On launch it checks whether a
## server is already answering at Backend's base URL (one the developer started by
## hand, or one this app opened earlier); if so it reuses it. Otherwise it locates
## a `node` binary, extracts the bundled server (res://server/…) to a writable
## location, and launches it as a quiet background process (no console window).
##
## While the app runs it heartbeats the server every 30 seconds and sends a
## disconnect when it closes, so the server knows who is connected. A server this
## app launched (a "managed" server) stops itself once the last connected app
## goes away — so runs never leave an orphaned server behind, and there's no
## window for the user to watch or close. A server the developer started by hand
## keeps running regardless; the app just reuses it.
##
## If Node.js can't be found the app still runs — the user just has to start a
## server themselves; a status message explains what happened.

signal status_changed(text: String)
## Emitted once startup concludes, carrying whether the server is answering. Used
## by await_ready() to unblock callers that started waiting before it resolved.
signal ready_resolved(available: bool)

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


func _start() -> void:
	var started := Time.get_ticks_msec()
	if await _healthy():
		_set_status("Using server already running at %s" % Backend.base_url)
		_record_server_event("detected", true, "Reused server already running", Time.get_ticks_msec() - started)
		_finish_startup(true)
		return

	var node := _find_node()
	if node.is_empty():
		_set_status("Node.js not found — start the server manually (set DEBRIS_NODE to override)")
		push_warning("ServerManager: no usable `node` binary found; server not started")
		_record_server_event("start", false, "Node.js not found — start the server manually", Time.get_ticks_msec() - started)
		_finish_startup(false)
		return

	var script := _extract_bundle()
	if script.is_empty():
		_set_status("Bundled server is missing (run `yarn bundle`)")
		push_warning("ServerManager: could not read " + BUNDLE_RES_PATH)
		_record_server_event("start", false, "Bundled server is missing (run `yarn bundle`)", Time.get_ticks_msec() - started)
		_finish_startup(false)
		return

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
		_finish_startup(false)
		return
	_set_status("Started bundled server in the background (pid %d)" % pid)

	for _i in STARTUP_POLL_ATTEMPTS:
		await get_tree().create_timer(STARTUP_POLL_INTERVAL).timeout
		if await _healthy():
			_set_status("Bundled server ready at %s" % Backend.base_url)
			_record_server_event("started", true, "Launched bundled server (pid %d)" % pid, Time.get_ticks_msec() - started)
			_finish_startup(true)
			return
	_set_status("Bundled server launched but not yet responding")
	_record_server_event("started", false, "Launched bundled server (pid %d) but it never answered" % pid, Time.get_ticks_msec() - started)
	_finish_startup(false)


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


## GET /health once; true when the server answers 200.
func _healthy() -> bool:
	var http := HTTPRequest.new()
	http.timeout = 2.0
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


## POST /clients/heartbeat, fire-and-forget (a missed beat is tolerated server-side).
func _send_heartbeat() -> void:
	_post_client("/clients/heartbeat")


## Tell the server we're disconnecting and wait briefly for it to land, so a
## managed server can stop promptly instead of waiting out its timeout. No-op if
## we never started heartbeating (server was never available).
func _notify_disconnect() -> void:
	if _client_id.is_empty():
		return
	await _post_client("/clients/disconnect")


## POST a control-plane call carrying our client id. Awaitable; short timeout so
## it never stalls shutdown if the server is already gone.
func _post_client(path: String) -> void:
	var http := HTTPRequest.new()
	http.timeout = 2.0
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body := JSON.stringify({"clientId": _client_id})
	var err := http.request(Backend.base_url + path, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		return
	await http.request_completed
	http.queue_free()


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
