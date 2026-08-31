extends "res://dev/check_base.gd"

## Check for the Endpoints footer's workspace panel, and for the quiet-logging
## rule it goes with.
##
## The panel is read-only by design: a workspace is somebody else's server, so
## there is nothing to start or stop — only to report on. The rule is the other
## half of the same idea: refreshing the endpoint catalog is a side effect of
## opening a project, not something the user asked for, so a workspace that's down
## must be logged without interrupting them.
##
## The same panel sits under all three of a project's workspace views — Endpoints,
## Users and Server Models — since all three act on that one server.
##
## Runs against the fixture mock, which answers /api/info like a real workspace.

# Both scripts reference autoloads, so neither can be preload()ed here — a `-s`
# main-loop script compiles before autoloads register. Loaded at runtime in _run().
var _bar: GDScript = null


func _run() -> void:
	_bar = load("res://source/ui/widgets/workspace_status_bar.gd")
	_describes_each_state()
	_details_each_state()
	await _probes_the_workspace()
	await _probe_stays_out_of_the_log()
	await _catalog_refresh_is_logged_quietly()
	await _panel_renders_its_scene()
	await _panel_is_on_every_workspace_view()
	await _refreshing_one_panel_updates_them_all()
	await _a_probe_joins_one_already_running()


# Rendering -------------------------------------------------------------------
func _describes_each_state() -> void:
	expect_eq(
		_bar.describe(_state({"running": true, "version": "7.4.0"})),
		"Workspace online · 7.4.0",
		"a workspace that answered reports its version",
	)
	expect_eq(
		_bar.describe(_state({"running": true})),
		"Workspace online",
		"a workspace that withheld its version still reads as online",
	)
	expect_eq(
		_bar.describe(_state({"error": "Cannot reach https://chat.example"})),
		"Workspace offline",
		"a workspace that didn't answer reads as offline",
	)
	expect_eq(
		_bar.describe(_state({"url": ""})),
		"No workspace URL",
		"a project whose workspace has no URL says so, rather than blaming it",
	)


func _details_each_state() -> void:
	var online: String = _bar.detail(_state({"running": true, "version": "7.4.0"}))
	expect(online.contains("https://chat.example"), "the tooltip names the workspace")
	expect(online.contains("Rocket.Chat 7.4.0"), "the tooltip carries the version")

	var offline: String = _bar.detail(_state({"error": "Cannot reach https://chat.example"}))
	expect(offline.contains("No workspace answering"), "an offline tooltip says nothing answered")
	expect(offline.contains("Cannot reach"), "an offline tooltip carries the reason")

	expect(
		_bar.detail(_state({"url": ""})).contains("no URL"),
		"an unconfigured tooltip explains there is nothing to check",
	)


## A probe result in RocketChat.probe's shape, with `overrides` applied — so each
## case above states only the fields it is about.
func _state(overrides: Dictionary) -> Dictionary:
	var state := {"running": false, "version": "", "url": "https://chat.example", "error": ""}
	state.merge(overrides, true)
	return state


# Probing ---------------------------------------------------------------------
## probe() answers in a fixed shape whether or not the workspace is there, so the
## panel can read every key unconditionally.
func _probes_the_workspace() -> void:
	var state: Dictionary = await rocketchat.probe({"url": "https://chat.example"})
	for key in ["running", "version", "url", "error"]:
		expect(state.has(key), "probe reports '%s'" % key)
	expect_eq(state["running"], true, "the mock workspace answers")
	expect_eq(state["version"], "7.4.0", "the version comes off /api/info")

	var unset: Dictionary = await rocketchat.probe({})
	expect_eq(unset["running"], false, "a workspace with no URL isn't running")
	expect(not String(unset["error"]).is_empty(), "and says why it couldn't be checked")


## Watching a workspace must not fill the Activity Log: the panel checks on its
## own schedule, and those checks would bury the requests the user actually made.
func _probe_stays_out_of_the_log() -> void:
	activity_log.clear()
	await rocketchat.probe({"url": "https://chat.example"})
	expect_eq(activity_log.entries().size(), 0, "a status probe records nothing")


## The endpoint catalog refresh rides along with opening a project. It stays in
## the log — the user can still find out what happened — but is marked quiet, and
## main.gd pops a dialog only for failures that aren't.
func _catalog_refresh_is_logged_quietly() -> void:
	activity_log.clear()
	await rocketchat.fetch_openapi({"url": "https://chat.example"}, true)
	var entries: Array = activity_log.entries()
	expect_eq(entries.size(), 1, "the catalog refresh is still recorded")
	if entries.is_empty():
		return
	expect_eq(entries[0]["quiet"], true, "and is marked as a background side effect")

	# A call the user asked for is not quiet, so its failures still interrupt.
	activity_log.clear()
	await rocketchat.fetch_openapi({"url": "https://chat.example"})
	expect_eq(activity_log.entries()[0]["quiet"], false, "a call the user made is not quiet")


# Scene wiring ----------------------------------------------------------------
## Boot the real panel inside the Endpoints sidebar that hosts it, so the unique
## node names, the refresh signal wired in the scene file, and configure()'s probe
## are all exercised.
func _panel_renders_its_scene() -> void:
	var sidebar: Control = load("res://source/ui/workspace/endpoint_sidebar.tscn").instantiate()
	root.add_child(sidebar)
	var panel: Control = sidebar.get_node_or_null("Box/Footer")
	expect(panel != null, "the Endpoints sidebar carries the workspace panel as its footer")
	if panel == null:
		sidebar.queue_free()
		return

	sidebar.configure({"url": "https://chat.example", "users": []})
	await create_timer(0.2).timeout
	var line: Label = panel.get_node("Row/Status")
	expect_eq(line.text, "Workspace online · 7.4.0", "configuring the sidebar checks the workspace")

	# Pressing ⟳ goes through the scene's signal wiring and re-reads.
	line.text = "(stale)"
	panel.get_node("Row/RefreshBtn").emit_signal("pressed")
	await create_timer(0.2).timeout
	expect_eq(line.text, "Workspace online · 7.4.0", "the refresh button re-checks the workspace")

	sidebar.queue_free()


## All three workspace views act on the same Rocket.Chat server, so all three
## carry the panel — and each must actually configure it, not merely contain one:
## a footer nobody points at a workspace sits on "No workspace URL" forever.
func _panel_is_on_every_workspace_view() -> void:
	var workspace := {"url": "https://chat.example", "users": []}
	# Built from the script at runtime, not from the WorkspaceSession global:
	# naming the class would compile it — and its RocketChat reference — before the
	# autoloads exist (see the note at the top of this file).
	var session: Object = load("res://source/data/workspace_session.gd").new(workspace)

	var users: Control = load("res://source/ui/workspace/users_panel.tscn").instantiate()
	root.add_child(users)
	users.configure(session)
	await _expect_online(users, "Col/Footer", "Users")
	users.queue_free()

	var models: Control = load("res://source/ui/workspace/rc_models_sidebar.tscn").instantiate()
	root.add_child(models)
	models.set_workspace(workspace)
	await _expect_online(models, "VBox/Footer", "Server Models")
	models.queue_free()


## Assert the panel at `path` under `view` checked the workspace and found it up.
func _expect_online(view: Control, path: String, label: String) -> void:
	var panel: Control = view.get_node_or_null(path)
	expect(panel != null, "the %s view carries the workspace panel" % label)
	if panel == null:
		return
	await create_timer(0.2).timeout
	expect_eq(
		panel.get_node("Row/Status").text, "Workspace online · 7.4.0",
		"the %s panel checks the workspace it was given" % label,
	)


## The three views show one workspace, so re-checking from any of them has to move
## the others — a user who refreshes under Users and then switches to Endpoints
## must not find a stale line there.
func _refreshing_one_panel_updates_them_all() -> void:
	var workspace := {"url": "https://chat.example", "users": []}
	var panels := await _three_panels(workspace)

	# Stale every line, then refresh exactly one of them.
	for panel in panels:
		(panel as Control).get_node("Row/Status").text = "(stale)"
	(panels[0] as Control).get_node("Row/RefreshBtn").emit_signal("pressed")
	await create_timer(0.2).timeout

	for i in panels.size():
		expect_eq(
			(panels[i] as Control).get_node("Row/Status").text, "Workspace online · 7.4.0",
			"panel %d repaints when another one is refreshed" % i,
		)

	# A panel on a different workspace is none of their business.
	var other: Control = load("res://source/ui/widgets/workspace_status_bar.tscn").instantiate()
	root.add_child(other)
	other.configure({"url": "https://other.example"})
	await create_timer(0.2).timeout
	other.get_node("Row/Status").text = "(untouched)"
	(panels[0] as Control).get_node("Row/RefreshBtn").emit_signal("pressed")
	await create_timer(0.2).timeout
	expect_eq(
		other.get_node("Row/Status").text, "(untouched)",
		"a panel on a different workspace is left alone",
	)

	other.queue_free()
	for panel in panels:
		(panel as Node).queue_free()


## Opening a project configures all three of its workspace views in the same
## frame and each asks, so a second ask must join the one already running rather
## than repeat it. The fixture mock answers without ever suspending, so two probes
## can't actually overlap here — the in-flight registry is driven directly
## instead, which is the part that would break. (End to end this needs a real
## round trip; it's verified live against a dead URL.)
func _a_probe_joins_one_already_running() -> void:
	var url := "https://busy.example"
	rocketchat._probes[url] = true  # stand in for a probe in flight
	var joined: Array = [null]
	_probe_into(joined, 0, {"url": url})
	await create_timer(0.1).timeout
	expect_eq(joined[0], null, "a second ask waits instead of asking again")

	# Another workspace's result must not be mistaken for the one being waited on.
	rocketchat.workspace_probed.emit("https://other.example", {"running": true})
	await create_timer(0.1).timeout
	expect_eq(joined[0], null, "and isn't unblocked by a different workspace")

	rocketchat._probes.erase(url)
	rocketchat.workspace_probed.emit(url, {"running": true, "url": url})
	await create_timer(0.1).timeout
	expect(joined[0] != null, "it takes the answer when that probe lands")
	if joined[0] != null:
		expect_eq((joined[0] as Dictionary).get("running"), true, "with the state that probe found")


## Fire-and-forget one probe, keeping its result in `results[index]`.
func _probe_into(results: Array, index: int, workspace: Dictionary) -> void:
	results[index] = await rocketchat.probe(workspace)


## Three panels on the same workspace, configured and settled — what a project
## with an API attached puts on screen.
func _three_panels(workspace: Dictionary) -> Array:
	var scene: PackedScene = load("res://source/ui/widgets/workspace_status_bar.tscn")
	var panels: Array = []
	for i in 3:
		var panel: Control = scene.instantiate()
		root.add_child(panel)
		panel.configure(workspace)
		panels.append(panel)
	await create_timer(0.3).timeout
	return panels
