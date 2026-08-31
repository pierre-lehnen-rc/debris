extends "res://dev/check_base.gd"

## Check for the Server Models view's bridge panel — the second footer, below the
## workspace one, reporting whether the injected models endpoint is answering.
##
## The distinction it exists to make: the workspace being up and the bridge being
## injected into it are different facts, and the console needs both. So the states
## are checked separately, and the panel's own reading is asked live rather than
## remembered — Rocket.Chat drops the handler when it restarts.
##
## Runs against the fixture mock, whose /api/rocketchat/status answers as an
## injected bridge unless the repository path says otherwise.

# bridge_status_bar.gd reaches for the Backend autoload, so it can't be
# preload()ed here — a `-s` main-loop script compiles before autoloads register.
var _bar: GDScript = null


func _run() -> void:
	_bar = load("res://source/ui/widgets/bridge_status_bar.gd")
	_describes_each_state()
	_details_each_state()
	await _status_stays_out_of_the_log()
	await _panel_renders_its_scene()
	await _panel_reports_an_uninjected_bridge()
	await _inject_asks_the_host()
	await _only_a_requested_injection_pops()
	await _reloading_models_is_logged()
	await _no_injection_into_an_unreachable_workspace()
	await _injection_when_the_workspace_is_up()


# Rendering -------------------------------------------------------------------
func _describes_each_state() -> void:
	expect_eq(
		_bar.describe(_state({"configured": true, "available": true, "reachable": true, "injected": true, "models": 4})),
		"Bridge injected · 4 models",
		"an answering bridge reports what it found",
	)
	expect_eq(
		_bar.describe(_state({"configured": true, "available": true, "reachable": true, "injected": true, "models": 1})),
		"Bridge injected · 1 model",
		"the model count is pluralised",
	)
	expect_eq(
		_bar.describe(_state({"configured": true, "available": true, "reachable": true})),
		"Bridge not injected",
		"a server that's up without the endpoint is distinguished from one that's down",
	)
	expect_eq(
		_bar.describe(_state({"configured": true, "available": true})),
		"Can't reach the workspace",
		"an unreachable server doesn't get blamed for a missing bridge",
	)
	# The bridge is asked about *through* the Debris server. When that one is down
	# nothing was learned about the workspace, and saying otherwise sends the user
	# after the wrong server — which is exactly what this panel used to do.
	expect_eq(
		_bar.describe(_state({"configured": true})),
		"Debris server not running",
		"a Debris server that didn't answer isn't reported as an unreachable workspace",
	)
	expect_eq(
		_bar.describe(_state({})),
		"No repository configured",
		"without a checkout there is nothing to inject from, and it says so",
	)


func _details_each_state() -> void:
	expect(
		_bar.detail(_state({})).contains("repository path"),
		"the unconfigured tooltip says what's missing",
	)
	var unasked: String = _bar.detail(_state({"configured": true, "error": "Cannot reach server"}))
	expect(unasked.contains("Debris server"), "the tooltip names the server that didn't answer")
	expect(unasked.contains("Cannot reach server"), "and carries its reason")
	var missing: String = _bar.detail(_state({"configured": true, "available": true, "reachable": true}))
	expect(missing.contains("Inject"), "a missing bridge points at the button that fixes it")
	var live: String = _bar.detail(
		_state({"configured": true, "available": true, "reachable": true, "injected": true, "models": 4})
	)
	expect(live.contains("answering"), "an injected bridge says the endpoint answers")


## A panel state, with `overrides` applied — so each case states only its subject.
func _state(overrides: Dictionary) -> Dictionary:
	var state := {
		"configured": false,
		"available": false,
		"reachable": false,
		"injected": false,
		"models": 0,
		"url": "http://localhost:3000",
		"error": "",
	}
	state.merge(overrides, true)
	return state


# Behaviour -------------------------------------------------------------------
## Watching the bridge must not fill the Activity Log or pop dialogs: the panel
## checks on its own, and a bridge that isn't injected yet is a normal state.
func _status_stays_out_of_the_log() -> void:
	activity_log.clear()
	await backend.rocketchat_status({"repoPath": "/tmp/rc", "url": "http://localhost:3000"})
	expect_eq(activity_log.entries().size(), 0, "a bridge status check records nothing")


## Opening a project attempts an injection nobody asked for, and a Rocket.Chat
## that isn't running is the ordinary state of a project you haven't started yet.
## That failure is recorded but must not interrupt; the one the user asks for, from
## the footer's Inject button, must. Checked at the log entry, since that is what
## main.gd decides the dialog from.
func _only_a_requested_injection_pops() -> void:
	var target := {"repoPath": "/tmp/rc", "url": "http://localhost:3000"}

	activity_log.clear()
	await backend.rocketchat_install(target, true)
	var quiet: Array = activity_log.entries()
	expect_eq(quiet.size(), 1, "an injection on project open is still recorded")
	if not quiet.is_empty():
		expect_eq(quiet[0]["quiet"], true, "and marked so it never pops a dialog")

	activity_log.clear()
	await backend.rocketchat_install(target)
	var asked: Array = activity_log.entries()
	expect_eq(asked.size(), 1, "an injection the user asked for is recorded too")
	if not asked.is_empty():
		expect_eq(asked[0]["quiet"], false, "and stays loud, so its failure is seen")


## Re-reading the list is something the user pressed a button for, so unlike the
## panel's own status check it belongs in the log — and its failure in a dialog.
func _reloading_models_is_logged() -> void:
	activity_log.clear()
	var result: Dictionary = await backend.rocketchat_models(
		{"repoPath": "/tmp/not-injected", "url": "http://localhost:3000"}
	)
	expect_eq(result.get("ok"), false, "reloading an un-injected bridge fails")
	var entries: Array = activity_log.entries()
	expect_eq(entries.size(), 1, "the reload is recorded")
	if not entries.is_empty():
		expect_eq(entries[0]["quiet"], false, "loudly — the user pressed ⟳")


## Opening a project must not spend a `meteor shell` run on a workspace that
## isn't answering: there is nothing to inject into, the shell takes seconds, and
## it's a slow way to learn what one cheap probe already says.
func _no_injection_into_an_unreachable_workspace() -> void:
	activity_log.clear()
	var tab := _project("https://offline.example")
	await create_timer(0.5).timeout
	expect_eq(
		_injections_logged(), 0,
		"a project whose workspace is down is opened without attempting an injection",
	)
	tab.queue_free()


## The other half: when the workspace is answering, opening a project still
## injects — the guard must not have turned the feature off.
func _injection_when_the_workspace_is_up() -> void:
	activity_log.clear()
	var tab := _project("https://chat.example")
	await create_timer(0.5).timeout
	expect_eq(_injections_logged(), 1, "a reachable workspace is still injected into on open")
	tab.queue_free()


## How many bridge injections the Activity Log recorded.
func _injections_logged() -> int:
	var count := 0
	for entry in activity_log.entries():
		if String((entry as Dictionary).get("action", "")) == "inject bridge":
			count += 1
	return count


## A project tab with a workspace at `url` and a repository path set, in the tree
## and configured — what opening such a project does.
func _project(url: String) -> Control:
	var doc := WorkspaceDoc.new()
	doc.set_rocketchat(url, [], "/tmp/rocket.chat")
	var tab: Control = load("res://source/ui/project/project_tab.gd").new()
	root.add_child(tab)
	tab.configure(doc)
	return tab


# Scene wiring ----------------------------------------------------------------
## Boot the panel inside the Server Models sidebar that hosts it, so the unique
## node names, the scene's button signals, and set_workspace()'s configure are all
## exercised — alongside the workspace panel it shares the footer area with.
func _panel_renders_its_scene() -> void:
	var sidebar: Control = _sidebar("/tmp/rocket.chat")
	var panel: Control = sidebar.get_node_or_null("VBox/BridgeFooter")
	expect(panel != null, "the Server Models sidebar carries the bridge panel")
	expect(
		sidebar.get_node_or_null("VBox/Footer") != null,
		"and still carries the workspace panel above it — they report different things",
	)
	if panel == null:
		sidebar.queue_free()
		return
	await create_timer(0.3).timeout

	expect_eq(
		panel.get_node("Row/Status").text, "Bridge injected · 4 models",
		"the panel reads the bridge when the sidebar is pointed at a workspace",
	)
	expect(not panel.get_node("Row/InjectBtn").disabled, "Inject is offered with a repository set")

	# ⟳ goes through the scene's signal wiring and re-reads.
	panel.get_node("Row/Status").text = "(stale)"
	panel.get_node("Row/RefreshBtn").emit_signal("pressed")
	await create_timer(0.3).timeout
	expect_eq(
		panel.get_node("Row/Status").text, "Bridge injected · 4 models",
		"the refresh button re-checks the bridge",
	)
	sidebar.queue_free()


## A server that's up with nothing injected is the state a fresh project is in —
## it must read as such, with Inject offered rather than the panel claiming a
## bridge that isn't there.
func _panel_reports_an_uninjected_bridge() -> void:
	var sidebar: Control = _sidebar("/tmp/not-injected")
	await create_timer(0.3).timeout
	var panel: Control = sidebar.get_node("VBox/BridgeFooter")
	expect_eq(
		panel.get_node("Row/Status").text, "Bridge not injected",
		"an un-injected bridge is reported honestly",
	)
	expect(not panel.get_node("Row/InjectBtn").disabled, "and Inject is there to fix it")
	sidebar.queue_free()


## Injecting runs `meteor shell` and refreshes the model tree and the query tabs,
## so the panel asks the host rather than doing it — the button has to reach the
## host, not dead-end in the widget.
##
## And it must ask on its own signal: the header's ⟳ only re-reads the list from
## the endpoint already there, so routing Inject through it would put a several
## second `meteor shell` run behind a button that means "reload".
func _inject_asks_the_host() -> void:
	var sidebar: Control = _sidebar("/tmp/rocket.chat")
	await create_timer(0.3).timeout
	var asked := [0]
	var reloaded := [0]
	sidebar.inject_requested.connect(func() -> void: asked[0] += 1)
	sidebar.refresh_requested.connect(func() -> void: reloaded[0] += 1)

	sidebar.get_node("VBox/BridgeFooter/Row/InjectBtn").emit_signal("pressed")
	await create_timer(0.1).timeout
	expect_eq(asked[0], 1, "Inject asks the host to run the injection")
	expect_eq(reloaded[0], 0, "and doesn't go out as a reload")

	# The header's ⟳ is the other way round: a reload, never an injection.
	sidebar.get_node("VBox/Header/HeaderBox/Row/RefreshBtn").emit_signal("pressed")
	await create_timer(0.1).timeout
	expect_eq(reloaded[0], 1, "the header button asks for a reload")
	expect_eq(asked[0], 1, "and never injects")

	var panel: Control = sidebar.get_node("VBox/BridgeFooter")
	expect(panel.get_node("Row/Status").text.contains("Injecting"), "and says so while it runs")
	expect(panel.get_node("Row/InjectBtn").disabled, "with the button locked until it lands")

	# The host reports back once the injection is done; the panel re-reads.
	sidebar.refresh_bridge_status()
	await create_timer(0.3).timeout
	expect_eq(
		panel.get_node("Row/Status").text, "Bridge injected · 4 models",
		"refresh_bridge_status repaints from what the server says afterwards",
	)
	sidebar.queue_free()


## A Server Models sidebar in the tree, pointed at a workspace with `repo_path`.
func _sidebar(repo_path: String) -> Control:
	var sidebar: Control = load("res://source/ui/workspace/rc_models_sidebar.tscn").instantiate()
	root.add_child(sidebar)
	sidebar.set_workspace({
		"url": "http://localhost:3000", "users": [], "repo_path": repo_path,
	})
	return sidebar
