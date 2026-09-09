class_name LogSourcePanel
extends PanelContainer

## The Server Logs sidebar view: the source controls for the shared server-log tail,
## plus a way to open more views onto it. Controls here act on the source — start and
## stop the tail — while the lines and the per-view controls (text/level filters,
## clear) live in the Server Logs tabs it opens. The two footer panels are the
## same ones the Server Models view carries: whether the workspace is up, and whether
## the bridge (which the tail reads through) is injected — the tail depends on both,
## so their state belongs here as much as there.
##
## Holds no streaming state of its own: it drives the LogStream and reflects whatever
## it reports, so the button and the tail never disagree.

## The New tab button — the host should open another Server Logs view.
signal new_tab_requested()
## The bridge footer's Inject button — forwarded so the host runs the injection (the
## same handler the Server Models view uses).
signal inject_requested()

const DESC := "Tail the running Rocket.Chat server's log output."
const WORKSPACE_BAR := "res://source/ui/widgets/workspace_status_bar.tscn"
const BRIDGE_BAR := "res://source/ui/widgets/bridge_status_bar.tscn"

# Untyped (not `: LogStream`) on purpose: LogStream reaches for autoloads, and typing
# against it would drag this panel out of the isolated compile check. Its methods and
# signal are resolved dynamically.
var _stream = null
var _streaming := false
var _configured := true

var _toggle_btn: Button = null
var _new_tab_btn: Button = null
var _status: Label = null
# Loaded at runtime (their scripts reach for autoloads), so this script stays
# isolated-compile-clean. Typed as PanelContainer, not by their class names, for the
# same reason — see rc_models_sidebar.gd.
var _workspace_footer: PanelContainer = null
var _bridge_footer: PanelContainer = null


func _ready() -> void:
	add_theme_stylebox_override("panel", AppTheme._flat(AppTheme.BG_DARKEST, 0))
	_build_ui()
	set_status({"streaming": false, "lines": 0, "message": ""})


func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	pad.add_child(controls)
	column.add_child(pad)

	var title := Label.new()
	title.text = "Server Logs"
	title.add_theme_color_override("font_color", AppTheme.TEXT_BRIGHT)
	controls.add_child(title)

	var desc := Label.new()
	desc.text = DESC
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	controls.add_child(desc)

	_toggle_btn = Button.new()
	_toggle_btn.focus_mode = Control.FOCUS_NONE
	_toggle_btn.pressed.connect(_on_toggle_pressed)
	controls.add_child(_toggle_btn)

	_new_tab_btn = Button.new()
	_new_tab_btn.text = "New log tab"
	_new_tab_btn.focus_mode = Control.FOCUS_NONE
	_new_tab_btn.pressed.connect(func() -> void: new_tab_requested.emit())
	controls.add_child(_new_tab_btn)

	# Clear discards the shared backlog — every view drops it — so it belongs here on
	# the source, not per-tab.
	var clear_btn := Button.new()
	clear_btn.text = "Clear log"
	clear_btn.focus_mode = Control.FOCUS_NONE
	clear_btn.pressed.connect(_on_clear_pressed)
	controls.add_child(clear_btn)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	controls.add_child(_status)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	# The same two status footers the Server Models view carries, in the same order.
	_workspace_footer = load(WORKSPACE_BAR).instantiate()
	column.add_child(_workspace_footer)
	_bridge_footer = load(BRIDGE_BAR).instantiate()
	_bridge_footer.inject_requested.connect(func() -> void: inject_requested.emit())
	column.add_child(_bridge_footer)


func _on_clear_pressed() -> void:
	if _stream != null:
		_stream.clear()


func _on_toggle_pressed() -> void:
	if _stream == null:
		return
	if _streaming:
		_stream.stop()
	else:
		_stream.start()


# Host wiring -----------------------------------------------------------------
## Attach to the project's shared tail: reflect its state and drive it from the
## button. `stream` is a LogStream (untyped for the isolated-compile reason above).
func bind_stream(stream) -> void:
	_stream = stream
	stream.status_changed.connect(set_status)


## Point the two footers at the project's workspace: the upper one at the server, the
## lower one at the bridge injected into it (the same wiring the Models view uses).
func configure_workspace(workspace: Dictionary) -> void:
	if _workspace_footer != null:
		_workspace_footer.configure(workspace)
	if _bridge_footer != null:
		_bridge_footer.configure(
			String(workspace.get("repo_path", "")), String(workspace.get("url", ""))
		)


## Re-check the bridge and repaint its footer, after an injection the host ran.
func refresh_bridge_status() -> void:
	if _bridge_footer != null:
		_bridge_footer.refresh()


## Re-check and repaint both footers (workspace up? bridge injected?), e.g. when the
## tail finds the server has gone down.
func refresh_status() -> void:
	if _workspace_footer != null:
		_workspace_footer.refresh()
	if _bridge_footer != null:
		_bridge_footer.refresh()


## Whether the workspace has a repository path — without one the tail can't be read,
## so Start is disabled and says why.
func set_configured(configured: bool) -> void:
	_configured = configured
	_apply_enabled()


## Render the streaming state reported by the tail: { streaming, lines, message }.
func set_status(state: Dictionary) -> void:
	_streaming = bool(state.get("streaming", false))
	_apply_enabled()
	if _status == null:
		return
	var message := str(state.get("message", ""))
	var line := ""
	if _streaming:
		line = "Streaming · %d lines" % int(state.get("lines", 0))
		if not message.is_empty():
			line = "%s\n%s" % [line, message]
	elif not _configured:
		line = "Set the Rocket.Chat Repository path in the workspace settings first"
	else:
		line = "Stopped" if message.is_empty() else message
	_status.text = line
	var problem := not message.is_empty() and _streaming
	_status.add_theme_color_override("font_color", AppTheme.ERROR if problem else AppTheme.TEXT_DIM)


func _apply_enabled() -> void:
	if _toggle_btn != null:
		_toggle_btn.text = "Stop streaming" if _streaming else "Start streaming"
		_toggle_btn.disabled = not _configured and not _streaming
