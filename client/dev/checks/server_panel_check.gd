extends "res://dev/check_base.gd"

## Check for the Collections footer's server panel — ServerManager's state/connect/
## disconnect/stop API and the ServerStatusBar rendering built on top of it.
##
## Three parts, all network-free. The rendering part drives ServerStatusBar's
## static describe()/detail() over hand-built state dictionaries, covering the
## states a real server produces. The ServerManager part runs against the real
## autoload under DEBRIS_HEADLESS, where every call that would open a socket is
## refused — so it pins the contract that matters when there is no server: the
## state dictionary always has its full shape, and the actions stay quiet. The
## scene part instantiates the panel inside its host sidebar, so the node names
## and signal wiring the script depends on are checked too.

# server_manager.gd and server_status_bar.gd both reference autoloads, so neither
# can be preload()ed here — a `-s` main-loop script compiles before autoloads
# register. Loaded at runtime in _run(), by which point they exist.
var _bar: GDScript = null
var _server_manager: Object = null


func _run() -> void:
	_bar = load("res://source/ui/widgets/server_status_bar.gd")
	_server_manager = root.get_node_or_null("ServerManager")
	_describes_each_state()
	_details_each_state()
	await _state_is_offline_and_fully_shaped()
	await _actions_are_quiet_without_a_server()
	await _concurrent_connects_all_resolve()
	_announces_real_transitions()
	await _panel_renders_its_scene()
	await _panel_repaints_when_the_server_moves()
	await _panel_is_on_the_empty_collections_view()


## Opening a project with a database and configuring a connection both call
## ensure_connected(), and several tabs restoring at once call it together. Only
## one attempt may run — the rest wait on it — and every caller must get an
## answer: a latecomer left waiting on a signal that already fired would hang the
## load it sits in front of.
func _concurrent_connects_all_resolve() -> void:
	var done: Array[bool] = [false, false, false]
	for i in 3:
		_connect_into(done, i)
	await create_timer(0.2).timeout
	expect_eq(done, [true, true, true] as Array[bool], "every concurrent connect gets an answer")
	expect_eq(
		await _server_manager.ensure_connected(), false,
		"ensure_connected reports no server under the headless runner",
	)


## Fire-and-forget one connect attempt, recording that it came back.
func _connect_into(done: Array[bool], index: int) -> void:
	await _server_manager.connect_to_server()
	done[index] = true


## The panel repaints off ServerManager.state_changed, so that signal has to fire
## on the real transitions and stay quiet otherwise — a spurious emit would send
## the panel on a pointless round trip, a missing one would leave it stale. Driven
## on a bare instance (never in the tree, so no network and no timers).
func _announces_real_transitions() -> void:
	var sm: Object = load("res://source/data/server_manager.gd").new()
	var beats := [0]
	sm.state_changed.connect(func() -> void: beats[0] += 1)

	sm._set_available(true)
	expect_eq(beats[0], 1, "the server becoming available is announced")
	sm._set_available(true)
	expect_eq(beats[0], 1, "setting the same availability again says nothing")
	sm._set_available(false)
	expect_eq(beats[0], 2, "the server going away is announced")

	# Detaching when we were never attached changes nothing to announce.
	sm._stop_heartbeat()
	expect_eq(beats[0], 2, "detaching while already detached says nothing")
	sm.free()


# Scene wiring ----------------------------------------------------------------
## Boot the real panel scene — including the Collections sidebar that hosts it —
## so the parts a static check can't see are exercised: the unique node names the
## script reaches for, the button signals wired in the scene file, and the first
## refresh() that _ready() kicks off. Headless there is no server, so the panel
## should settle on the stopped state with only Connect and ⟳ live.
func _panel_renders_its_scene() -> void:
	var sidebar: Control = load("res://source/ui/sidebar/collection_sidebar.tscn").instantiate()
	root.add_child(sidebar)
	var panel: Control = sidebar.get_node_or_null("Box/Footer")
	expect(panel != null, "the Collections sidebar carries the server panel as its footer")
	if panel == null:
		sidebar.queue_free()
		return
	# _ready()'s refresh() is a coroutine; let it land before reading the line.
	await create_timer(0.1).timeout

	expect_eq(panel.get_node("Row/Status").text, "Server not running", "the panel reports no server")
	expect(panel.get_node("Row/ConnectBtn").visible, "Connect is offered when we're detached")
	expect(not panel.get_node("Row/DisconnectBtn").visible, "Disconnect is hidden when we're detached")
	expect(panel.get_node("Row/StopBtn").disabled, "there is nothing to stop")
	expect(not panel.get_node("Row/RefreshBtn").disabled, "the state can always be re-read")

	# Pressing Connect goes through the scene's signal wiring; with no server to
	# reach it must come back to the same state rather than hang or half-enable.
	panel.get_node("Row/ConnectBtn").emit_signal("pressed")
	await create_timer(0.1).timeout
	expect_eq(panel.get_node("Row/Status").text, "Server not running", "a failed connect leaves the line honest")
	expect(panel.get_node("Row/ConnectBtn").visible, "Connect is still the offered action")

	sidebar.queue_free()


## The panel is not the only thing that moves the server: opening a project with a
## database starts one on demand, well after the panel first painted. It has to
## re-read on ServerManager.state_changed rather than sit on its launch reading.
func _panel_repaints_when_the_server_moves() -> void:
	var sidebar: Control = load("res://source/ui/sidebar/collection_sidebar.tscn").instantiate()
	root.add_child(sidebar)
	await create_timer(0.1).timeout
	var line: Label = sidebar.get_node("Box/Footer/Row/Status")

	# Stand in for a stale line, then announce a change as a project load would.
	line.text = "(stale)"
	_server_manager.state_changed.emit()
	await create_timer(0.1).timeout
	expect_eq(line.text, "Server not running", "the panel re-reads when the server changes hands")

	sidebar.queue_free()


## A project with no database still has a server to see, start and stop, so the
## Collections view carries the panel in its "No database in this project" state
## too — and it must be live there, not a decoration. The Endpoints placeholder
## shares the same builder and must not pick one up.
func _panel_is_on_the_empty_collections_view() -> void:
	var tab: Control = load("res://source/ui/project/project_tab.gd").new()
	root.add_child(tab)
	tab.configure(WorkspaceDoc.new())  # No mongo, no API: both views are placeholders.
	await create_timer(0.2).timeout

	var collections := _find_server_bar(tab._views["collections"])
	expect(collections != null, "the empty Collections view shows the server panel")
	if collections != null:
		expect_eq(
			collections.get_node("Row/Status").text, "Server not running",
			"the panel on the empty view reads the server like any other",
		)
	# Both placeholders come off the same builder; only Collections asked for one.
	expect(
		_find_server_bar(tab._views["endpoints"]) == null,
		"the empty Endpoints view does not pick up a server panel",
	)
	tab.queue_free()


## The one server panel under `node`, or null. Walked rather than addressed by
## path: the placeholder is assembled in code, and the path isn't the point.
## Matched on the script's path rather than `is ServerStatusBar` — naming the
## class here would compile server_status_bar.gd, and its ServerManager reference,
## before the autoloads exist (the same reason nothing here is preload()ed).
func _find_server_bar(node: Node) -> Node:
	var script: Script = node.get_script()
	if script != null and script.resource_path.ends_with("server_status_bar.gd"):
		return node
	for child in node.get_children():
		var found := _find_server_bar(child)
		if found != null:
			return found
	return null


# Rendering -------------------------------------------------------------------
func _describes_each_state() -> void:
	expect_eq(_bar.describe(_state({})), "Server not running", "stopped server reads as not running")
	expect_eq(
		_bar.describe(_state({"running": true, "connected": true, "apps": 1})),
		"Connected · 1 app",
		"attached to a server we're the only app on",
	)
	expect_eq(
		_bar.describe(_state({"running": true, "connected": true, "apps": 3})),
		"Connected · 3 apps",
		"app count is pluralised",
	)
	expect_eq(
		_bar.describe(_state({"running": true, "connected": false, "apps": 0})),
		"Running, not connected · 0 apps",
		"a server running without us is distinguished from a stopped one",
	)


func _details_each_state() -> void:
	var stopped: String = _bar.detail(_state({"error": "Cannot reach server"}))
	expect(stopped.contains("http://127.0.0.1:4020"), "stopped tooltip names the URL")
	expect(stopped.contains("Cannot reach server"), "stopped tooltip carries the reason")

	var managed: String = _bar.detail(_state({
		"running": true, "connected": true, "apps": 1, "connections": 2,
		"managed": true, "pid": 4242, "uptime_ms": 125_000,
	}))
	expect(managed.contains("pid 4242"), "running tooltip names the process")
	expect(managed.contains("2m 05s"), "uptime is formatted as minutes and seconds")
	expect(managed.contains("1 app attached, 2 MongoDB connections"), "tooltip counts what's attached")
	expect(managed.contains("Stops itself"), "a managed server says it stops itself")

	var standalone: String = _bar.detail(_state({"running": true, "managed": false, "uptime_ms": 7_500}))
	expect(standalone.contains("Keeps running"), "a hand-started server says it keeps running")
	expect(standalone.contains("7s"), "a short uptime is formatted as seconds")


## A state dictionary in ServerManager's shape, with `overrides` applied — so each
## case above states only the fields it is about.
func _state(overrides: Dictionary) -> Dictionary:
	var state := {
		"running": false,
		"connected": false,
		"apps": 0,
		"connections": 0,
		"managed": false,
		"pid": 0,
		"uptime_ms": 0,
		"url": "http://127.0.0.1:4020",
		"error": "",
	}
	state.merge(overrides, true)
	return state


# ServerManager ---------------------------------------------------------------
## fetch_state() always answers with the full dictionary, so the panel can read
## every key without guarding. Headless, that answer is a stopped server.
func _state_is_offline_and_fully_shaped() -> void:
	var state: Dictionary = await _server_manager.fetch_state()
	for key in ["running", "connected", "apps", "connections", "managed", "pid", "uptime_ms", "url", "error"]:
		expect(state.has(key), "fetch_state reports '%s'" % key)
	expect_eq(state["running"], false, "no server is running under the headless runner")
	expect_eq(state["connected"], false, "the headless runner attaches to nothing")
	expect(not String(state["error"]).is_empty(), "an unreachable server explains itself")


## The three actions are safe to call with nothing answering: each resolves to the
## same stopped state instead of hanging or erroring, and none of them registers
## this app (which is what would make the panel's read-only refresh a lie).
func _actions_are_quiet_without_a_server() -> void:
	var connected: Dictionary = await _server_manager.connect_to_server()
	expect_eq(connected["running"], false, "connect gives up cleanly with no server to reach")
	expect_eq(connected["connected"], false, "a failed connect leaves us unattached")

	var disconnected: Dictionary = await _server_manager.disconnect_from_server()
	expect_eq(disconnected["connected"], false, "disconnect leaves us unattached")

	var stopped: Dictionary = await _server_manager.stop_server()
	expect_eq(stopped["running"], false, "stop reports the server as gone")
