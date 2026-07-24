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
	_build_project_dialogs()
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


# When set, the next picker selection attaches its source to this existing project
# instead of opening a new one. Cleared once used, or when a picker opens for a new
# project (so a cancelled attach doesn't leak into the next open).
var _attach_target: ProjectTab = null

# Project file lifecycle (.debris-project). One shared FileDialog serves both Save
# and Open; `_file_dialog_mode` says which, and `_file_dialog_project` is the
# project a pending save writes to.
var _file_dialog: FileDialog
var _recent_menu: PopupMenu
var _file_dialog_mode := ""  # "save" | "open"
var _file_dialog_project: ProjectTab = null


## Build the shared save/open FileDialog and the Open Recent submenu.
func _build_project_dialogs() -> void:
	_file_dialog = FileDialog.new()
	_file_dialog.theme = AppTheme.shared()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.add_filter("*.%s" % WorkspaceFile.EXTENSION, "Debris Project")
	_file_dialog.file_selected.connect(_on_file_dialog_selected)
	add_child(_file_dialog)

	_recent_menu = PopupMenu.new()
	_recent_menu.name = "OpenRecent"
	_recent_menu.id_pressed.connect(_on_recent_selected)


func _open_picker() -> void:
	_attach_target = null
	_picker.open()


func _open_workspace_picker() -> void:
	_attach_target = null
	_workspace_picker.open()


## The project tab currently in focus, or null if the active tab isn't a project.
func _current_project() -> ProjectTab:
	var control := _tabs.get_current_tab_control()
	return control as ProjectTab


# New / attach ----------------------------------------------------------------
## Open a fresh empty project (no sources yet); the user attaches a DB and/or API.
func _new_project() -> void:
	var doc := WorkspaceDoc.new()
	doc.name = "Untitled"
	_open_project_tab(doc)
	_status_label.text = "New project"


## Attach a database to the current project: open the connection picker aimed at
## the active project so its selection binds there instead of opening a new tab.
func _attach_database() -> void:
	var proj := _current_project()
	if proj == null or proj.has_mongo():
		return
	_attach_target = proj
	_picker.open()


## Attach an API to the current project via the workspace picker.
func _attach_api() -> void:
	var proj := _current_project()
	if proj == null or proj.has_rocketchat():
		return
	_attach_target = proj
	_workspace_picker.open()


# Project tabs ----------------------------------------------------------------
## A database was picked. When an attach is pending, bind it to that project;
## otherwise open a new project bound to just this DB.
func _on_database_selected(connection: Dictionary, database: String) -> void:
	var conn_name := String(connection.get("name", ""))
	if _attach_target != null and is_instance_valid(_attach_target):
		var target := _attach_target
		_attach_target = null
		target.attach_mongo(connection, database)
		_update_project_tab_title(target)
		_status_label.text = "Attached %s on %s" % [database, conn_name]
		return
	var doc := WorkspaceDoc.new()
	doc.name = "%s · %s" % [conn_name, database] if not conn_name.is_empty() else database
	doc.set_mongo(connection, database)
	_open_project_tab(doc)
	_status_label.text = "Opened %s on %s" % [database, conn_name]


## A workspace was picked. When an attach is pending, bind it to that project;
## otherwise open a new project bound to just this API.
func _on_workspace_selected(workspace: Dictionary) -> void:
	if _attach_target != null and is_instance_valid(_attach_target):
		var target := _attach_target
		_attach_target = null
		target.attach_rocketchat(workspace)
		_update_project_tab_title(target)
		_status_label.text = "Attached workspace %s" % workspace.get("name", "")
		return
	var doc := WorkspaceDoc.new()
	doc.name = String(workspace.get("name", ""))
	doc.set_rocketchat(String(workspace.get("url", "")), workspace.get("users", []))
	_open_project_tab(doc)
	_status_label.text = "Opened workspace %s" % doc.name


func _open_project_tab(doc: WorkspaceDoc) -> ProjectTab:
	var tab: ProjectTab = PROJECT_TAB_SCENE.instantiate()
	tab.configure(doc)
	tab.status_changed.connect(_on_status_changed)
	tab.name = "proj_%d" % _tab_counter
	_tab_counter += 1
	_tabs.add_child(tab)
	_tabs.current_tab = _tabs.get_tab_count() - 1
	_update_project_tab_title(tab)
	return tab


# Save / open project files ---------------------------------------------------
## Save the current project to its file, or fall through to Save As when it has
## never been saved.
func _save_project() -> void:
	var proj := _current_project()
	if proj == null:
		return
	if proj.doc().file_path.is_empty():
		_save_project_as()
		return
	_write_project(proj, proj.doc().file_path)


## Prompt for a path and save the current project there.
func _save_project_as() -> void:
	var proj := _current_project()
	if proj == null:
		return
	_file_dialog_mode = "save"
	_file_dialog_project = proj
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.title = "Save Project"
	_file_dialog.ok_button_text = "Save"
	var doc := proj.doc()
	if not doc.file_path.is_empty():
		_file_dialog.current_path = doc.file_path
	else:
		_file_dialog.current_file = "%s.%s" % [_project_basename(doc), WorkspaceFile.EXTENSION]
	_file_dialog.popup_centered(Vector2i(720, 520))


## Prompt for a project file to open.
func _open_project_dialog() -> void:
	_file_dialog_mode = "open"
	_file_dialog_project = null
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.title = "Open Project"
	_file_dialog.ok_button_text = "Open"
	_file_dialog.popup_centered(Vector2i(720, 520))


func _on_file_dialog_selected(path: String) -> void:
	if _file_dialog_mode == "save":
		if not path.ends_with("." + WorkspaceFile.EXTENSION):
			path += "." + WorkspaceFile.EXTENSION
		if _file_dialog_project != null and is_instance_valid(_file_dialog_project):
			_write_project(_file_dialog_project, path)
		_file_dialog_project = null
	elif _file_dialog_mode == "open":
		_open_project_file(path)


## Write a project to `path`, deriving a name from the filename when the project is
## still Untitled, then refresh its tab title and the recent list.
func _write_project(proj: ProjectTab, path: String) -> void:
	var doc := proj.doc()
	if doc.name.is_empty() or doc.name == "Untitled":
		doc.name = path.get_file().get_basename()
	var result := WorkspaceFile.save(doc, path)
	if not result.get("ok", false):
		_status_label.text = "Save failed: %s" % result.get("error", "unknown error")
		return
	Store.add_recent_workspace(path)
	_update_project_tab_title(proj)
	_status_label.text = "Saved %s" % doc.name


## Open a project file into a new tab, focusing it if it's already open.
func _open_project_file(path: String) -> void:
	for i in _tabs.get_tab_count():
		var control := _tabs.get_tab_control(i)
		if control is ProjectTab and (control as ProjectTab).doc().file_path == path:
			_tabs.current_tab = i
			return
	var result := WorkspaceFile.load(path)
	if not result.get("ok", false):
		_status_label.text = "Open failed: %s" % result.get("error", "unknown error")
		return
	var doc: WorkspaceDoc = result["doc"]
	_open_project_tab(doc)
	Store.add_recent_workspace(path)
	_status_label.text = "Opened %s" % path.get_file()


func _on_recent_selected(index: int) -> void:
	var recent := Store.recent_workspaces()
	if index >= 0 and index < recent.size():
		_open_project_file(String(recent[index]))


# Tab title / helpers ---------------------------------------------------------
## Set a project tab's title from its name, prefixed with a dot when it has unsaved
## changes, and its tooltip to the file path.
func _update_project_tab_title(proj: ProjectTab) -> void:
	var index := _tab_index_of(proj)
	if index < 0:
		return
	var doc := proj.doc()
	var title := proj.tab_title()
	if doc.dirty:
		title = "• " + title
	_tabs.set_tab_title(index, title)
	_tabs.set_tab_tooltip(index, doc.file_path)


func _tab_index_of(control: Control) -> int:
	for i in _tabs.get_tab_count():
		if _tabs.get_tab_control(i) == control:
			return i
	return -1


## A filename-safe base for an Untitled project's default save name.
func _project_basename(doc: WorkspaceDoc) -> String:
	var name := doc.name
	if name.is_empty() or name == "Untitled":
		return "project"
	return name.replace("·", "-").replace("/", "-").strip_edges()


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
# File menu item ids.
const FILE_NEW_CONNECTION := 0
const FILE_OPEN_DATABASE := 1
const FILE_OPEN_WORKSPACE := 2
const FILE_QUIT := 3
const FILE_ACTIVITY_LOG := 4
const FILE_NEW_PROJECT := 5
const FILE_ATTACH_DATABASE := 6
const FILE_ATTACH_API := 7
const FILE_SAVE_PROJECT := 8
const FILE_SAVE_PROJECT_AS := 9
const FILE_OPEN_PROJECT := 10


func _on_file_menu(id: int) -> void:
	match id:
		FILE_NEW_PROJECT:
			_new_project()
		FILE_OPEN_PROJECT:
			_open_project_dialog()
		FILE_SAVE_PROJECT:
			_save_project()
		FILE_SAVE_PROJECT_AS:
			_save_project_as()
		FILE_NEW_CONNECTION:
			_connection_dialog.open_new()
		FILE_OPEN_DATABASE:
			_open_picker()
		FILE_OPEN_WORKSPACE:
			_open_workspace_picker()
		FILE_ATTACH_DATABASE:
			_attach_database()
		FILE_ATTACH_API:
			_attach_api()
		FILE_ACTIVITY_LOG:
			_open_activity_log_tab()
		FILE_QUIT:
			get_tree().quit()


## Enable project-scoped items only when a project is active, and the Attach items
## only when it can take that source (enforcing the ≤1-DB / ≤1-API rule). Also
## refresh the Open Recent submenu.
func _refresh_file_menu() -> void:
	var proj := _current_project()
	_file_menu.set_item_disabled(
		_file_menu.get_item_index(FILE_ATTACH_DATABASE), proj == null or proj.has_mongo()
	)
	_file_menu.set_item_disabled(
		_file_menu.get_item_index(FILE_ATTACH_API), proj == null or proj.has_rocketchat()
	)
	_file_menu.set_item_disabled(_file_menu.get_item_index(FILE_SAVE_PROJECT), proj == null)
	_file_menu.set_item_disabled(_file_menu.get_item_index(FILE_SAVE_PROJECT_AS), proj == null)
	_refresh_recent_menu()


## Rebuild the Open Recent submenu from the stored recent-project paths.
func _refresh_recent_menu() -> void:
	_recent_menu.clear()
	var recent := Store.recent_workspaces()
	if recent.is_empty():
		_recent_menu.add_item("(no recent projects)")
		_recent_menu.set_item_disabled(0, true)
		return
	for i in recent.size():
		var path := String(recent[i])
		_recent_menu.add_item(path.get_file(), i)
		_recent_menu.set_item_tooltip(i, path)


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
	_file_menu.add_item("New Project", FILE_NEW_PROJECT)
	_file_menu.add_item("Open Project…", FILE_OPEN_PROJECT)
	_file_menu.add_submenu_node_item("Open Recent", _recent_menu)
	_file_menu.add_separator()
	_file_menu.add_item("Save Project", FILE_SAVE_PROJECT)
	_file_menu.add_item("Save Project As…", FILE_SAVE_PROJECT_AS)
	_file_menu.add_separator()
	_file_menu.add_item("Open Database…", FILE_OPEN_DATABASE)
	_file_menu.add_item("Open Workspace…", FILE_OPEN_WORKSPACE)
	_file_menu.add_item("Attach Database…", FILE_ATTACH_DATABASE)
	_file_menu.add_item("Attach API…", FILE_ATTACH_API)
	_file_menu.add_separator()
	_file_menu.add_item("New Connection…", FILE_NEW_CONNECTION)
	_file_menu.add_item("Activity Log", FILE_ACTIVITY_LOG)
	_file_menu.add_separator()
	_file_menu.add_item("Quit", FILE_QUIT)
	# Enable/disable project items and refresh Open Recent each time the menu opens.
	_file_menu.about_to_popup.connect(_refresh_file_menu)

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
