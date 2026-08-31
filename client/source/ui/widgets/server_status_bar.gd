class_name ServerStatusBar
extends PanelContainer

## One-line footer reporting what the Debris server is doing, with the actions
## that change it: the status on the left, and on the right Connect or Disconnect
## (only the applicable one is shown), Stop, and a refresh that re-reads the
## state. Sits at the bottom of the Collections sidebar.
##
## Reading the state registers nothing with the server (see
## ServerManager.fetch_state), so the panel keeps reporting on a server this app
## has deliberately detached from. Every action repaints the line from the state
## the server reports afterwards, never from what the action was expected to do —
## so a stop that didn't take, or a connection dropped elsewhere, shows honestly.

const FONT_SIZE := 11

@onready var _status: Label = %Status
@onready var _connect_btn: Button = %ConnectBtn
@onready var _disconnect_btn: Button = %DisconnectBtn
@onready var _stop_btn: Button = %StopBtn
@onready var _refresh_btn: Button = %RefreshBtn

## Set while a call is in flight: every button stays disabled until it lands, so
## a second click can't race the first.
var _busy := false
## Set when the server changed under us while one of our own calls was in flight.
## The answer we're waiting on predates the change, so we re-read once it lands
## rather than painting what was true a moment ago.
var _stale := false


func _ready() -> void:
	_apply_style()
	# The panel isn't the only thing that moves the server: opening a project with
	# a database starts one on demand. Repaint whenever it changes hands.
	ServerManager.state_changed.connect(_on_server_state_changed)
	refresh()


## The server was attached, detached or stopped by something other than a button
## here — most often a project loading its collections.
func _on_server_state_changed() -> void:
	if _busy:
		_stale = true
		return
	refresh()


## Re-read the server's state and repaint the line — also the ⟳ button's action.
func refresh() -> void:
	if _busy:
		return
	_begin("Checking the server…")
	_apply_state(await ServerManager.fetch_state())


# Wired in server_status_bar.tscn ---------------------------------------------
func _on_connect_pressed() -> void:
	if _busy:
		return
	_begin("Connecting…")
	_apply_state(await ServerManager.connect_to_server())


func _on_disconnect_pressed() -> void:
	if _busy:
		return
	_begin("Disconnecting…")
	_apply_state(await ServerManager.disconnect_from_server())


func _on_stop_pressed() -> void:
	if _busy:
		return
	_begin("Stopping the server…")
	_apply_state(await ServerManager.stop_server())


func _on_refresh_pressed() -> void:
	refresh()


# State rendering -------------------------------------------------------------
## Show a call in progress: the pending action as the line, every button locked.
func _begin(text: String) -> void:
	_busy = true
	_status.text = text
	_status.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_status.tooltip_text = ""
	for btn in [_connect_btn, _disconnect_btn, _stop_btn, _refresh_btn]:
		(btn as Button).disabled = true


## Paint a ServerManager state dictionary: the summary line, its tooltip, and
## which actions the state allows. Connect and Disconnect swap places rather than
## both sitting there half-disabled — only one of them ever applies.
func _apply_state(state: Dictionary) -> void:
	_busy = false
	var running := bool(state.get("running", false))
	var connected := bool(state.get("connected", false))

	_status.text = describe(state)
	_status.tooltip_text = detail(state)
	_status.add_theme_color_override("font_color", _color_for(state))

	_connect_btn.visible = not connected
	_disconnect_btn.visible = connected
	_connect_btn.disabled = false
	_disconnect_btn.disabled = false
	# Nothing to stop when nothing is answering.
	_stop_btn.disabled = not running
	_refresh_btn.disabled = false

	# The server moved while this answer was in flight, so what we just painted is
	# already behind — the line is never left blank, but go read the truth now.
	if _stale:
		_stale = false
		refresh()


## The one-line summary for a ServerManager state dictionary. Kept short enough
## for a narrow sidebar; the full picture lives in detail(), as the tooltip.
static func describe(state: Dictionary) -> String:
	if not bool(state.get("running", false)):
		return "Server not running"
	var apps := int(state.get("apps", 0))
	var attached := "%d app%s" % [apps, "" if apps == 1 else "s"]
	if bool(state.get("connected", false)):
		return "Connected · %s" % attached
	return "Running, not connected · %s" % attached


## The tooltip: where the server is, what process it is, who is attached, and
## whether it stops itself when they all leave. When nothing is answering, why.
static func detail(state: Dictionary) -> String:
	var url := String(state.get("url", ""))
	if not bool(state.get("running", false)):
		var error := String(state.get("error", ""))
		if error.is_empty():
			return "No server answering at %s" % url
		return "No server answering at %s\n%s" % [url, error]

	var apps := int(state.get("apps", 0))
	var connections := int(state.get("connections", 0))
	var lines := PackedStringArray([
		url,
		"pid %d, up %s" % [int(state.get("pid", 0)), _uptime(int(state.get("uptime_ms", 0)))],
		"%d app%s attached, %d MongoDB connection%s" % [
			apps, "" if apps == 1 else "s", connections, "" if connections == 1 else "s",
		],
	])
	if bool(state.get("managed", false)):
		lines.append("Stops itself once the last app disconnects")
	else:
		lines.append("Keeps running once the last app disconnects")
	return "\n".join(lines)


## Colour for the summary: green while we're attached, plain text for a server
## running without us, dim when there's nothing there.
static func _color_for(state: Dictionary) -> Color:
	if not bool(state.get("running", false)):
		return AppTheme.TEXT_DIM
	return AppTheme.ACCENT_GREEN if bool(state.get("connected", false)) else AppTheme.TEXT


## Server uptime as a compact "3s" / "4m 12s" / "2h 07m".
static func _uptime(ms: int) -> String:
	var seconds := ms / 1000
	if seconds < 60:
		return "%ds" % seconds
	if seconds < 3600:
		return "%dm %02ds" % [seconds / 60, seconds % 60]
	return "%dh %02dm" % [seconds / 3600, (seconds % 3600) / 60]


func _apply_style() -> void:
	# Matches the sidebar header at the other end of the list: the darkest panel
	# colour, separated from the tree by a hairline.
	var sb := AppTheme._flat(AppTheme.BG_DARKEST, 0)
	sb.border_width_top = 1
	sb.border_color = AppTheme.BORDER
	sb.content_margin_left = 8
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	add_theme_stylebox_override("panel", sb)

	_status.add_theme_font_size_override("font_size", FONT_SIZE)
	for btn in [_connect_btn, _disconnect_btn, _stop_btn, _refresh_btn]:
		(btn as Button).add_theme_font_size_override("font_size", FONT_SIZE)
