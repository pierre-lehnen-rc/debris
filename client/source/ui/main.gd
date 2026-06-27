class_name Main
extends Control

## Application shell: menu bar, toolbar, a bottom-tabbed stack of open tabs, and
## a status bar. Tabs come in two kinds: a database tab (bound to one Mongo
## database, with its own collection sidebar + query workspace) chosen from the
## connection picker, and a Rocket.Chat workspace tab chosen from the workspace
## picker. Both pickers open from the toolbar; the database picker also opens
## automatically when no tabs are open. Layout lives in main.tscn (theme too).

const DATABASE_TAB_SCENE := preload("res://source/ui/database/database_tab.tscn")
const WORKSPACE_TAB_SCENE := preload("res://source/ui/workspace/workspace_tab.tscn")

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

var _tab_counter := 0


func _ready() -> void:
	_apply_style()
	_populate_menus()

	var bar := _tabs.get_tab_bar()
	bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ALWAYS
	bar.tab_close_pressed.connect(_on_tab_close_pressed)

	# Nothing is open yet — prompt the user to pick a database to start.
	_open_picker.call_deferred()


## Relays a child's status message to the status bar. Wired in main.tscn.
func _on_status_changed(text: String) -> void:
	_status_label.text = text


func _open_picker() -> void:
	_picker.open()


func _open_workspace_picker() -> void:
	_workspace_picker.open()


# Database tabs ---------------------------------------------------------------
func _on_database_selected(connection: Dictionary, database: String) -> void:
	_open_database_tab(connection, database)


func _open_database_tab(connection: Dictionary, database: String) -> DatabaseTab:
	var tab: DatabaseTab = DATABASE_TAB_SCENE.instantiate()
	tab.configure(connection, database)
	tab.status_changed.connect(_on_status_changed)
	tab.name = "db_%d" % _tab_counter
	_tab_counter += 1
	_tabs.add_child(tab)
	var index := _tabs.get_tab_count() - 1
	_tabs.set_tab_title(index, tab.tab_title())
	_tabs.set_tab_tooltip(index, "%s · %s" % [connection.get("name", ""), database])
	_tabs.current_tab = index
	_status_label.text = "Opened %s on %s" % [database, connection.get("name", "")]
	return tab


# Workspace tabs --------------------------------------------------------------
func _on_workspace_selected(workspace: Dictionary) -> void:
	_open_workspace_tab(workspace)


func _open_workspace_tab(workspace: Dictionary) -> WorkspaceTab:
	var tab: WorkspaceTab = WORKSPACE_TAB_SCENE.instantiate()
	tab.configure(workspace)
	tab.status_changed.connect(_on_status_changed)
	tab.name = "ws_%d" % _tab_counter
	_tab_counter += 1
	_tabs.add_child(tab)
	var index := _tabs.get_tab_count() - 1
	_tabs.set_tab_title(index, tab.tab_title())
	_tabs.set_tab_tooltip(index, workspace.get("url", ""))
	_tabs.current_tab = index
	_status_label.text = "Opened workspace %s" % workspace.get("name", "")
	return tab


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
	_file_menu.add_item("Quit", 3)

	_edit_menu.add_item("Copy", 0)
	_edit_menu.add_item("Paste", 1)

	_view_menu.add_item("Tree", 0)
	_view_menu.add_item("Table", 1)
	_view_menu.add_item("Text", 2)

	_help_menu.add_item("About Quetzalcoatl", 0)
