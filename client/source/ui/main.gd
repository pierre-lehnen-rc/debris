class_name Main
extends Control

## Application shell: menu bar, toolbar, a bottom-tabbed stack of open tabs, and
## a status bar. Tabs come in two kinds: a database tab (bound to one Mongo
## database, with its own collection sidebar + query workspace) chosen from the
## connection picker, and a Rocket.Chat workspace tab chosen from the workspace
## picker. Both pickers open from the toolbar; the database picker also opens
## automatically when no tabs are open. Layout lives in main.tscn (theme too).

const PROJECT_TAB_SCENE := preload("res://source/ui/project/project_tab.tscn")
const ACTIVITY_LOG_TAB_SCENE := preload("res://source/ui/log/activity_log_tab.tscn")

@onready var _background: ColorRect = %Background
@onready var _file_menu: PopupMenu = %File
@onready var _view_menu: PopupMenu = %View
@onready var _help_menu: PopupMenu = %Help
@onready var _edit_menu: PopupMenu = %Edit
@onready var _toolbar: PanelContainer = %Toolbar
@onready var _status_bar: PanelContainer = %StatusBar
@onready var _status_label: Label = %StatusLabel
@onready var _tabs: TabContainer = %MainTabs
@onready var _connection_dialog: ConnectionDialog = $ConnectionDialog
@onready var _picker: ConnectionPicker = $ConnectionPicker
@onready var _workspace_dialog: WorkspaceDialog = $WorkspaceDialog
@onready var _workspace_picker: WorkspacePicker = $WorkspacePicker
@onready var _error_dialog: ErrorDialog = $ErrorDialog

var _tab_counter := 0

# UI scale (View ▸ UI Scale). The chosen content-scale factor, or 0.0 for "Auto",
# which follows the display's reported DPI scale and updates live on dpi_changed.
# Persisted across launches via Store.
const UI_SCALE_OPTIONS := [
	{"id": 0, "label": "Auto (Match Display)", "factor": 0.0},
	{"id": 1, "label": "100%", "factor": 1.0},
	{"id": 2, "label": "125%", "factor": 1.25},
	{"id": 3, "label": "150%", "factor": 1.5},
	{"id": 4, "label": "200%", "factor": 2.0},
]
var _ui_scale_override := 0.0
var _scale_menu: PopupMenu


func _ready() -> void:
	_ui_scale_override = float(Store.get_preference("ui_scale", 0.0))
	_apply_ui_scale(true)
	# React to DPI changes (OS scaling change, or the window moving to a screen of a
	# different density) so an "Auto" scale stays correct without a restart.
	get_window().dpi_changed.connect(_on_dpi_changed)
	_apply_style()
	_populate_menus()

	var bar := _tabs.get_tab_bar()
	bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ALWAYS
	bar.tab_close_pressed.connect(_on_tab_close_pressed)

	# Surface failures immediately: any failed action pops up a small error dialog
	# offering to open the activity log, rather than opening the log unprompted.
	ActivityLog.entry_added.connect(_on_activity_log_entry)

	# Show the bundled-server startup progress in the status bar.
	ServerManager.status_changed.connect(_on_status_changed)


## The content-scale factor to apply: the user's explicit override when set,
## otherwise the display's reported DPI scale (floored at 1.0). On a 2x screen
## (e.g. a macOS Retina display) the OS reports the full pixel resolution, so an
## unscaled UI is drawn at half its intended physical size — tiny and hard to
## read; matching this factor renders the UI at the right physical size, crisply.
func _effective_scale() -> float:
	if _ui_scale_override > 0.0:
		return _ui_scale_override
	return maxf(1.0, DisplayServer.screen_get_scale(get_window().current_screen))


## Apply the effective UI scale to the whole window. When `resize_window` is true
## (startup only) and the scale magnifies the UI, the window is grown so the
## logical working area is preserved, clamped to the usable screen and re-centred.
## Live re-applies (DPI change, menu selection) keep the current window size and
## just re-scale the content, so they never fight the user's own window sizing.
func _apply_ui_scale(resize_window: bool) -> void:
	var window := get_window()
	var scale := _effective_scale()
	window.content_scale_factor = scale
	if not resize_window or scale <= 1.0:
		return
	var base_w: int = ProjectSettings.get_setting("display/window/size/viewport_width", 1280)
	var base_h: int = ProjectSettings.get_setting("display/window/size/viewport_height", 800)
	var usable := DisplayServer.screen_get_usable_rect(window.current_screen)
	var target := Vector2i(
		mini(int(base_w * scale), usable.size.x),
		mini(int(base_h * scale), usable.size.y),
	)
	window.size = target
	window.position = usable.position + (usable.size - target) / 2


## The display DPI changed (OS scaling change, or the window was dragged to a
## screen of a different density). Re-apply so an "Auto" scale tracks it live; a
## fixed override is unaffected but re-applying is harmless.
func _on_dpi_changed() -> void:
	_apply_ui_scale(false)


## Handle a UI Scale menu selection: record the chosen factor (0.0 = Auto),
## persist it, apply it, and refresh the menu's radio checks.
func _on_scale_menu(id: int) -> void:
	for opt in UI_SCALE_OPTIONS:
		if int(opt["id"]) == id:
			_ui_scale_override = float(opt["factor"])
			break
	Store.set_preference("ui_scale", _ui_scale_override)
	_apply_ui_scale(false)
	_refresh_scale_menu()


## Tick the UI Scale radio item matching the current override (0.0 = Auto).
func _refresh_scale_menu() -> void:
	if _scale_menu == null:
		return
	for opt in UI_SCALE_OPTIONS:
		var idx := _scale_menu.get_item_index(int(opt["id"]))
		_scale_menu.set_item_checked(idx, is_equal_approx(float(opt["factor"]), _ui_scale_override))


## Relays a child's status message to the status bar. Wired in main.tscn.
func _on_status_changed(text: String) -> void:
	_status_label.text = text


func _open_picker() -> void:
	_picker.open()


func _open_workspace_picker() -> void:
	_workspace_picker.open()


# Project tabs ----------------------------------------------------------------
## Opening a database from the picker builds a project bound to just that DB.
## (Stage 1: the pickers still supply the sources; attaching both a DB and an API
## to one project comes with the document lifecycle in a later stage.)
func _on_database_selected(connection: Dictionary, database: String) -> void:
	var doc := WorkspaceDoc.new()
	var conn_name := String(connection.get("name", ""))
	doc.name = "%s · %s" % [conn_name, database] if not conn_name.is_empty() else database
	doc.mongo = {"connection": connection, "database": database}
	_open_project_tab(doc)
	_status_label.text = "Opened %s on %s" % [database, conn_name]


## Opening a workspace from the picker builds a project bound to just that API.
func _on_workspace_selected(workspace: Dictionary) -> void:
	var doc := WorkspaceDoc.new()
	doc.name = String(workspace.get("name", ""))
	doc.rocketchat = {"url": workspace.get("url", ""), "users": workspace.get("users", [])}
	_open_project_tab(doc)
	_status_label.text = "Opened workspace %s" % doc.name


func _open_project_tab(doc: WorkspaceDoc) -> ProjectTab:
	var tab: ProjectTab = PROJECT_TAB_SCENE.instantiate()
	tab.configure(doc)
	tab.status_changed.connect(_on_status_changed)
	tab.name = "proj_%d" % _tab_counter
	_tab_counter += 1
	_tabs.add_child(tab)
	var index := _tabs.get_tab_count() - 1
	_tabs.set_tab_title(index, tab.tab_title())
	_tabs.current_tab = index
	return tab


# Activity log tab ------------------------------------------------------------
## A logged action failed — surface a small error popup. The user can dismiss it
## or open the activity log from there; we never open the log on our own.
func _on_activity_log_entry(entry: Dictionary) -> void:
	if not entry.get("ok", false):
		_error_dialog.show_error(entry)


## Open the activity log, or focus it if it's already open (only one is useful).
func _open_activity_log_tab() -> void:
	for i in _tabs.get_tab_count():
		if _tabs.get_tab_control(i) is ActivityLogTab:
			_tabs.current_tab = i
			return
	var tab: ActivityLogTab = ACTIVITY_LOG_TAB_SCENE.instantiate()
	tab.status_changed.connect(_on_status_changed)
	tab.name = "log_%d" % _tab_counter
	_tab_counter += 1
	_tabs.add_child(tab)
	var index := _tabs.get_tab_count() - 1
	_tabs.set_tab_title(index, tab.tab_title())
	_tabs.current_tab = index
	_status_label.text = "Opened activity log"


func _on_tab_close_pressed(tab_index: int) -> void:
	var control := _tabs.get_tab_control(tab_index)
	if control == null:
		return
	_tabs.remove_child(control)
	control.queue_free()
	# Back to an empty shell — reopen the picker so the user can choose again.
	if _tabs.get_tab_count() == 0:
		_open_picker.call_deferred()


# Connection picker / dialog --------------------------------------------------
func _on_add_connection_requested() -> void:
	_connection_dialog.open_new()


func _on_edit_connection_requested(index: int, config: Dictionary) -> void:
	_connection_dialog.open_edit(index, config)


func _on_connection_saved(config: Dictionary) -> void:
	_picker.add_connection(config)
	_status_label.text = "Added connection '%s'" % config.get("name", "")


func _on_connection_updated(index: int, config: Dictionary) -> void:
	_picker.update_connection(index, config)
	_status_label.text = "Updated connection '%s'" % config.get("name", "")


# Workspace picker / dialog ---------------------------------------------------
func _on_add_workspace_requested() -> void:
	_workspace_dialog.open_new()


func _on_edit_workspace_requested(index: int, config: Dictionary) -> void:
	_workspace_dialog.open_edit(index, config)


func _on_workspace_saved(config: Dictionary) -> void:
	_workspace_picker.add_workspace(config)
	_status_label.text = "Added workspace '%s'" % config.get("name", "")


func _on_workspace_updated(index: int, config: Dictionary) -> void:
	_workspace_picker.update_workspace(index, config)
	_status_label.text = "Updated workspace '%s'" % config.get("name", "")


# Menus / styling -------------------------------------------------------------
func _on_file_menu(id: int) -> void:
	match id:
		0:  # New Connection…
			_connection_dialog.open_new()
		1:  # Open Database…
			_open_picker()
		2:  # Open Workspace…
			_open_workspace_picker()
		4:  # Activity Log
			_open_activity_log_tab()
		3:  # Quit
			get_tree().quit()


func _apply_style() -> void:
	_background.color = AppTheme.BG_DARKEST

	var tool_sb := AppTheme._flat(AppTheme.BG_DARK, 0)
	tool_sb.border_width_bottom = 1
	tool_sb.border_color = AppTheme.BORDER
	tool_sb.content_margin_left = 8
	tool_sb.content_margin_right = 8
	tool_sb.content_margin_top = 5
	tool_sb.content_margin_bottom = 5
	_toolbar.add_theme_stylebox_override("panel", tool_sb)

	var status_sb := AppTheme._flat(AppTheme.BG_DARKEST, 0)
	status_sb.border_width_top = 1
	status_sb.border_color = AppTheme.BORDER
	status_sb.content_margin_left = 8
	status_sb.content_margin_right = 8
	status_sb.content_margin_top = 3
	status_sb.content_margin_bottom = 3
	_status_bar.add_theme_stylebox_override("panel", status_sb)

	_status_label.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_status_label.add_theme_font_size_override("font_size", 12)


func _populate_menus() -> void:
	_file_menu.add_item("New Connection…", 0)
	_file_menu.add_item("Open Database…", 1)
	_file_menu.add_item("Open Workspace…", 2)
	_file_menu.add_separator()
	_file_menu.add_item("Activity Log", 4)
	_file_menu.add_separator()
	_file_menu.add_item("Quit", 3)

	_edit_menu.add_item("Copy", 0)
	_edit_menu.add_item("Paste", 1)

	_view_menu.add_item("Tree", 0)
	_view_menu.add_item("Table", 1)
	_view_menu.add_item("Text", 2)
	_view_menu.add_separator()
	_scale_menu = PopupMenu.new()
	_scale_menu.name = "UIScale"
	for opt in UI_SCALE_OPTIONS:
		_scale_menu.add_radio_check_item(str(opt["label"]), int(opt["id"]))
	_scale_menu.id_pressed.connect(_on_scale_menu)
	_view_menu.add_submenu_node_item("UI Scale", _scale_menu)
	_refresh_scale_menu()

	_help_menu.add_item("About Debris", 0)
