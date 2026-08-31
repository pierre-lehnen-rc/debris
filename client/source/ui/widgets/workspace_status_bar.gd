class_name WorkspaceStatusBar
extends PanelContainer

## One-line footer reporting whether this project's Rocket.Chat workspace is
## answering, with a refresh to re-check. Sits at the bottom of the Endpoints
## sidebar, mirroring the server panel under Collections — but read-only. A
## workspace is somebody else's server, running wherever it runs: the app can say
## whether it's up, and nothing more, so there is nothing here to start or stop.
##
## The check is RocketChat.probe (GET /api/info, no auth, unlogged), so watching a
## workspace needs no credentials and leaves the Activity Log to real requests.
##
## A project shows this same line under Endpoints, Users and Server Models — one
## workspace, three views of it — so the line is painted from the broadcast
## RocketChat makes when any probe lands, not from this panel's own call.
## Re-checking from one footer therefore updates all of them, and the three that
## ask at once when a project opens share a single request.

const FONT_SIZE := 11

@onready var _status: Label = %Status
@onready var _refresh_btn: Button = %RefreshBtn

## The workspace config being watched ({ url, … }), or empty before configure().
var _workspace: Dictionary = {}
## Set while a probe is in flight, so a second click can't race the first.
var _busy := false


func _ready() -> void:
	_apply_style()
	RocketChat.workspace_probed.connect(_on_workspace_probed)
	# configure() may land before this node is in the tree; pick it up here. With
	# no workspace to check, say so rather than sitting on "Checking…" forever.
	if _workspace.is_empty():
		_apply_state(_blank_state())
		return
	refresh()


## Point the panel at a workspace config and check it. Safe to call before the
## node is ready — the check then runs once it is.
func configure(workspace: Dictionary) -> void:
	_workspace = workspace
	if is_node_ready():
		refresh()


## Re-check the workspace and repaint the line — also the ⟳ button's action.
## Repaints every panel on this workspace, not just this one.
func refresh() -> void:
	if _busy:
		return
	_busy = true
	_status.text = "Checking the workspace…"
	_status.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_status.tooltip_text = ""
	_refresh_btn.disabled = true
	var state: Dictionary = await RocketChat.probe(_workspace)
	# The broadcast normally repainted us before this returns. Catch the case
	# where it didn't — the workspace was re-pointed mid-probe, say — so the panel
	# can never be left stuck on "Checking…" with its button disabled.
	if _busy:
		_apply_state(state)


## A probe landed. Repaint when it was about the workspace this panel shows —
## whichever of the project's three footers asked for it.
func _on_workspace_probed(url: String, state: Dictionary) -> void:
	if url == RocketChat.workspace_url(_workspace):
		_apply_state(state)


# Wired in workspace_status_bar.tscn ------------------------------------------
func _on_refresh_pressed() -> void:
	refresh()


## Paint a RocketChat.probe result.
func _apply_state(state: Dictionary) -> void:
	_busy = false
	_status.text = describe(state)
	_status.tooltip_text = detail(state)
	_status.add_theme_color_override("font_color", _color_for(state))
	_refresh_btn.disabled = false


## The one-line summary for a probe result. Kept short enough for a narrow
## sidebar; the full picture lives in detail(), as the tooltip.
static func describe(state: Dictionary) -> String:
	if String(state.get("url", "")).is_empty():
		return "No workspace URL"
	if not bool(state.get("running", false)):
		return "Workspace offline"
	var version := String(state.get("version", ""))
	if version.is_empty():
		return "Workspace online"
	return "Workspace online · %s" % version


## The tooltip: which workspace this is and what it reported, or why it didn't.
static func detail(state: Dictionary) -> String:
	var url := String(state.get("url", ""))
	if url.is_empty():
		return "This project's workspace has no URL"
	if not bool(state.get("running", false)):
		var error := String(state.get("error", ""))
		if error.is_empty():
			return "No workspace answering at %s" % url
		return "No workspace answering at %s\n%s" % [url, error]
	var version := String(state.get("version", ""))
	if version.is_empty():
		return "%s\nAnswering; it didn't report a version" % url
	return "%s\nRocket.Chat %s" % [url, version]


## A probe result for "nothing to check", in the shape RocketChat.probe returns —
## so the panel paints an unconfigured project through the same path as any other.
static func _blank_state() -> Dictionary:
	return {"running": false, "version": "", "url": "", "error": ""}


## Colour for the summary: green for a workspace that answered, dim otherwise.
static func _color_for(state: Dictionary) -> Color:
	return AppTheme.ACCENT_GREEN if bool(state.get("running", false)) else AppTheme.TEXT_DIM


func _apply_style() -> void:
	# Matches the server panel under Collections, and the sidebar header above.
	var sb := AppTheme._flat(AppTheme.BG_DARKEST, 0)
	sb.border_width_top = 1
	sb.border_color = AppTheme.BORDER
	sb.content_margin_left = 8
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	add_theme_stylebox_override("panel", sb)

	_status.add_theme_font_size_override("font_size", FONT_SIZE)
	_refresh_btn.add_theme_font_size_override("font_size", FONT_SIZE)
