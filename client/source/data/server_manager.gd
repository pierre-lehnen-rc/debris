extends Node

## Owns startup of the bundled Debris server. On launch it checks whether a
## server is already answering at Backend's base URL (one the developer started by
## hand, or one this app opened earlier); if so it reuses it. Otherwise it locates
## a `node` binary, extracts the bundled server (res://server/…) to a writable
## location, and launches it in its OWN terminal window so the user can watch the
## logs and stop it whenever they like.
##
## The server is intentionally NOT killed when the app exits — it keeps running in
## its terminal and will simply be reused the next time the app starts (so runs
## never stack up duplicate servers). To stop it, the user closes the terminal
## window (or presses Ctrl+C).
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
## Directory (inside user://) where we write the launcher script.
const LAUNCHER_USER_DIR := "user://server"
## How long to wait for a freshly-launched server to answer /health.
const STARTUP_POLL_ATTEMPTS := 40
const STARTUP_POLL_INTERVAL := 0.25

var _host := "127.0.0.1"
var _port := 4000

# Startup readiness, consumed by await_ready(). `_startup_resolved` flips true the
# moment startup concludes (server answering, or given up on); `_server_available`
# is the outcome. Callers that ask before it resolves await `ready_resolved`.
var _startup_resolved := false
var _server_available := false


func _ready() -> void:
	# Under the headless test/validation runner (dev/ scripts set DEBRIS_HEADLESS),
	# never touch the network or spawn the bundled server — tests run against mocks.
	# Resolve readiness immediately so anything that does await_ready() (nothing does
	# under mocks, but be safe) returns at once instead of hanging.
	if not OS.get_environment("DEBRIS_HEADLESS").is_empty():
		_finish_startup(false)
		return
	_parse_base_url(Backend.base_url)
	_start()


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
	if await _healthy():
		_set_status("Using server already running at %s" % Backend.base_url)
		_finish_startup(true)
		return

	var node := _find_node()
	if node.is_empty():
		_set_status("Node.js not found — start the server manually (set DEBRIS_NODE to override)")
		push_warning("ServerManager: no usable `node` binary found; server not started")
		_finish_startup(false)
		return

	var script := _extract_bundle()
	if script.is_empty():
		_set_status("Bundled server is missing (run `yarn bundle`)")
		push_warning("ServerManager: could not read " + BUNDLE_RES_PATH)
		_finish_startup(false)
		return

	var windowed := _launch_in_terminal(node, script)
	if not windowed:
		# No terminal emulator available (e.g. a headless box) — fall back to a
		# plain background process so the app still works. Reuse detection keeps
		# this from stacking up across runs. The server reads its port/host from
		# the environment, which the child inherits from us. (The terminal path
		# instead bakes these into the launcher script.)
		OS.set_environment("PORT", str(_port))
		OS.set_environment("HOST", _host)
		if OS.get_environment("LOG_LEVEL").is_empty():
			OS.set_environment("LOG_LEVEL", "warn")
		var pid := OS.create_process(node, [script])
		if pid <= 0:
			_set_status("Failed to launch the bundled server")
			push_warning("ServerManager: OS.create_process failed for " + node)
			_finish_startup(false)
			return
		_set_status("Started bundled server in the background (pid %d)" % pid)
	else:
		_set_status("Opening a terminal window for the bundled server…")

	for _i in STARTUP_POLL_ATTEMPTS:
		await get_tree().create_timer(STARTUP_POLL_INTERVAL).timeout
		if await _healthy():
			if windowed:
				_set_status("Bundled server ready at %s (running in its own terminal)" % Backend.base_url)
			else:
				_set_status("Bundled server ready at %s" % Backend.base_url)
			_finish_startup(true)
			return
	_set_status("Bundled server launched but not yet responding")
	_finish_startup(false)


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


# Terminal launch -------------------------------------------------------------
## Launch `node script` inside a new terminal window. Returns true if a terminal
## was opened, false if no supported terminal could be found (caller then falls
## back to a background process).
func _launch_in_terminal(node: String, script: String) -> bool:
	var launcher := _write_launcher(node, script)
	if launcher.is_empty():
		return false

	match OS.get_name():
		"Windows":
			return OS.create_process("cmd", \
				["/c", "start", "Debris Server", "cmd", "/k", launcher]) > 0
		"macOS":
			# Terminal.app runs an executable file; it needs the exec bit set.
			OS.execute("chmod", ["+x", launcher])
			return OS.create_process("open", ["-a", "Terminal", launcher]) > 0
		_:
			return _launch_linux_terminal(launcher)


## Try each known Linux/BSD terminal emulator in turn; the first one present wins.
func _launch_linux_terminal(launcher: String) -> bool:
	# Each entry is [binary, args]. Most terminals want the command split into
	# separate argv entries (-e sh <file>); a few want it as one string.
	var candidates := [
		["x-terminal-emulator", ["-e", "sh", launcher]],
		["gnome-terminal", ["--title", "Debris Server", "--", "sh", launcher]],
		["konsole", ["-e", "sh", launcher]],
		["kitty", ["sh", launcher]],
		["alacritty", ["-e", "sh", launcher]],
		["xfce4-terminal", ["--title=Debris Server", "--command", "sh %s" % launcher]],
		["tilix", ["-e", "sh %s" % launcher]],
		["terminator", ["-e", "sh %s" % launcher]],
		["xterm", ["-e", "sh", launcher]],
	]
	for entry in candidates:
		var binary: String = entry[0]
		if not _which(binary):
			continue
		if OS.create_process(binary, entry[1]) > 0:
			return true
	return false


func _which(binary: String) -> bool:
	var out: Array = []
	return OS.execute("which", [binary], out, true) == 0


## Write a small launcher script (sh or bat) that sets the server's env, runs it,
## and keeps the window open afterwards so any startup error stays visible.
## Returns the globalized path, or "" on failure.
func _write_launcher(node: String, script: String) -> String:
	DirAccess.make_dir_recursive_absolute(LAUNCHER_USER_DIR)
	var is_windows := OS.get_name() == "Windows"
	# macOS: ".command" is the canonical Terminal-executable extension, so
	# `open -a Terminal` runs it regardless of how ".sh" happens to be associated.
	var filename := "run-server.sh"
	if is_windows:
		filename = "run-server.bat"
	elif OS.get_name() == "macOS":
		filename = "run-server.command"
	var path := LAUNCHER_USER_DIR + "/" + filename
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""

	if is_windows:
		f.store_string("@echo off\r\n")
		f.store_string("title Debris Server\r\n")
		f.store_string("set PORT=%d\r\n" % _port)
		f.store_string("set HOST=%s\r\n" % _host)
		f.store_string("if \"%%LOG_LEVEL%%\"==\"\" set LOG_LEVEL=info\r\n")
		f.store_string("echo Debris bundled server - close this window to stop it.\r\n")
		f.store_string("echo.\r\n")
		f.store_string("\"%s\" \"%s\"\r\n" % [node, script])
		f.store_string("echo.\r\n")
		f.store_string("echo Server exited. Press any key to close.\r\n")
		f.store_string("pause >nul\r\n")
	else:
		f.store_string("#!/bin/sh\n")
		f.store_string("export PORT='%d'\n" % _port)
		f.store_string("export HOST='%s'\n" % _host)
		f.store_string(": \"${LOG_LEVEL:=info}\"; export LOG_LEVEL\n")
		f.store_string("echo 'Debris bundled server - close this window (or Ctrl+C) to stop it.'\n")
		f.store_string("echo\n")
		f.store_string("'%s' '%s'\n" % [node, script])
		f.store_string("status=$?\n")
		f.store_string("echo\n")
		f.store_string("echo \"Server exited (status $status). Press Enter to close.\"\n")
		f.store_string("read _\n")
	f.close()
	return ProjectSettings.globalize_path(path)
