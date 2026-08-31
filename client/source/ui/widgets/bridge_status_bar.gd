class_name BridgeStatusBar
extends PanelContainer

## One-line footer for the Server Models view reporting whether the bridge is
## injected into the project's Rocket.Chat server, with Inject and a refresh.
## Sits below the workspace panel: that line says whether the server is up, this
## one says whether the endpoint the console calls through is there.
##
## The state is asked live (Backend.rocketchat_status, which injects nothing and
## isn't logged) rather than remembered, because the bridge is a handler held in
## the running server's memory: it disappears when Rocket.Chat restarts, and
## another Debris server can supersede its token. A panel reporting what it
## injected an hour ago would be confidently wrong.
##
## Injecting runs `meteor shell` against the local repository, which takes a
## while and does more than this panel owns — the model list feeds the tree and
## the query tabs — so the button asks the host to do it via inject_requested,
## and the host refreshes the panel afterwards.

## The Inject button was pressed. The host runs the injection (and calls
## refresh() when it's done).
signal inject_requested()

const FONT_SIZE := 11

@onready var _status: Label = %Status
@onready var _inject_btn: Button = %InjectBtn
@onready var _refresh_btn: Button = %RefreshBtn

## { repoPath, url } for the project's Rocket.Chat server, or empty before
## configure(). Without a repository path there is nothing to inject from.
var _target: Dictionary = {}
## Set while a status check of our own is in flight, so a second click can't race
## the first.
var _busy := false
## Set between pressing Inject and the host reporting back. The buttons stay
## locked meanwhile — but unlike _busy this must not block refresh(), because the
## host calling refresh() is precisely how the injection is reported as finished.
var _injecting := false


func _ready() -> void:
	_apply_style()
	# configure() may land before this node is in the tree; pick it up here. With
	# nothing to check, say so rather than sitting on "Checking…" forever.
	if _target.is_empty():
		_apply_state(_blank_state())
		return
	refresh()


## Point the panel at a project's Rocket.Chat server — `repo_path` is the local
## checkout the injection is run from, `url` the running server it goes into.
## Safe to call before the node is ready; the check then runs once it is.
func configure(repo_path: String, url: String) -> void:
	_target = {"repoPath": repo_path, "url": url}
	if is_node_ready():
		refresh()


## Re-check the bridge and repaint the line — the ⟳ button's action, and what the
## host calls once an injection it ran has finished.
func refresh() -> void:
	if _busy or not is_node_ready():
		return
	# An explicit re-read supersedes any injection we were waiting on.
	_injecting = false
	_busy = true
	_status.text = "Checking the bridge…"
	_status.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_status.tooltip_text = ""
	_inject_btn.disabled = true
	_refresh_btn.disabled = true
	_apply_state(await _fetch_state())


# Wired in bridge_status_bar.tscn ---------------------------------------------
func _on_inject_pressed() -> void:
	if _busy or _injecting:
		return
	# Injecting takes a `meteor shell` round trip; show that something is
	# happening, and leave the buttons locked until the host refreshes us.
	_injecting = true
	_status.text = "Injecting the bridge…"
	_status.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_inject_btn.disabled = true
	_refresh_btn.disabled = true
	inject_requested.emit()


func _on_refresh_pressed() -> void:
	refresh()


# State -----------------------------------------------------------------------
## Ask the Debris server about the bridge, in this panel's own shape. Without a
## repository path there's nothing to ask about — the console needs a local
## checkout to run `meteor shell` in.
func _fetch_state() -> Dictionary:
	var state := _blank_state()
	if String(_target.get("repoPath", "")).is_empty():
		return state
	state["configured"] = true
	# The bridge is reached through the Debris server, so make sure one is running
	# before asking — a project with only a workspace attached never starts one on
	# any other path, and without it there is no answer to be had.
	await ServerManager.ensure_connected()
	var result: Dictionary = await Backend.rocketchat_status(_target)
	if not result.get("ok", false):
		# The Debris server didn't answer. That says nothing about the workspace,
		# and reporting it as one would send the user after the wrong server.
		state["error"] = result.get("error", "")
		return state
	var data: Dictionary = result["data"] if result.get("data") is Dictionary else {}
	state["available"] = true
	state["reachable"] = bool(data.get("reachable", false))
	state["injected"] = bool(data.get("injected", false))
	state["models"] = int(data.get("models", 0))
	state["url"] = String(data.get("url", _target.get("url", "")))
	state["error"] = String(data.get("error", ""))
	return state


## Paint a state and set which actions it allows.
func _apply_state(state: Dictionary) -> void:
	_busy = false
	_injecting = false
	_status.text = describe(state)
	_status.tooltip_text = detail(state)
	_status.add_theme_color_override("font_color", _color_for(state))
	# Injecting needs a repository to run the shell in; re-checking is always fine.
	_inject_btn.disabled = not bool(state.get("configured", false))
	_refresh_btn.disabled = false


## The one-line summary. Kept short enough for a narrow sidebar; the full picture
## lives in detail(), as the tooltip.
static func describe(state: Dictionary) -> String:
	if not bool(state.get("configured", false)):
		return "No repository configured"
	if not bool(state.get("available", false)):
		return "Debris server not running"
	if not bool(state.get("reachable", false)):
		return "Can't reach the workspace"
	if not bool(state.get("injected", false)):
		return "Bridge not injected"
	var models := int(state.get("models", 0))
	return "Bridge injected · %d model%s" % [models, "" if models == 1 else "s"]


## The tooltip: what the bridge is, and what to do about it when it isn't there.
static func detail(state: Dictionary) -> String:
	if not bool(state.get("configured", false)):
		return "Set a Rocket.Chat repository path on this project to use the models console"
	var url := String(state.get("url", ""))
	var error := String(state.get("error", ""))
	if not bool(state.get("available", false)):
		# Nothing was learned about the workspace — the question never got asked.
		var unasked := "The bridge is reached through the Debris server, which isn't answering"
		return unasked if error.is_empty() else "%s\n%s" % [unasked, error]
	if not bool(state.get("reachable", false)):
		var lines := "No Rocket.Chat answering at %s" % url
		return lines if error.is_empty() else "%s\n%s" % [lines, error]
	if not bool(state.get("injected", false)):
		var missing := (
			"%s is up, but the models endpoint isn't injected.\n"
			+ "Press Inject to run it into the running server."
		) % url
		return missing if error.is_empty() else "%s\n%s" % [missing, error]
	return "%s\nThe models endpoint is answering" % url


## A state for "nothing to check" — the shape every _fetch_state result has, so
## the painters can read the keys unconditionally. `configured` is a repository to
## inject from, `available` the Debris server that carries the question,
## `reachable` the Rocket.Chat server it's asked about, `injected` the endpoint
## inside it: four different things that can be missing, told apart so the line
## never blames the wrong one.
static func _blank_state() -> Dictionary:
	return {
		"configured": false,
		"available": false,
		"reachable": false,
		"injected": false,
		"models": 0,
		"url": "",
		"error": "",
	}


## Colour for the summary: green once the endpoint answers, dim otherwise — a
## missing bridge is the resting state of a project you haven't injected into
## yet, not a fault to shout about.
static func _color_for(state: Dictionary) -> Color:
	return AppTheme.ACCENT_GREEN if bool(state.get("injected", false)) else AppTheme.TEXT_DIM


func _apply_style() -> void:
	# Matches the workspace panel directly above it.
	var sb := AppTheme._flat(AppTheme.BG_DARKEST, 0)
	sb.border_width_top = 1
	sb.border_color = AppTheme.BORDER
	sb.content_margin_left = 8
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	add_theme_stylebox_override("panel", sb)

	_status.add_theme_font_size_override("font_size", FONT_SIZE)
	_inject_btn.add_theme_font_size_override("font_size", FONT_SIZE)
	_refresh_btn.add_theme_font_size_override("font_size", FONT_SIZE)
