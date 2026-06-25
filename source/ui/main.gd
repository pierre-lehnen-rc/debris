class_name Main
extends Control

## Application shell: menu bar, toolbar, sidebar | workspace split, status bar.
## Layout lives in main.tscn (which also carries the shared theme); this script
## seeds the menu items, applies palette styling and wires the sidebar's
## collection activation to the workspace so double-clicking opens a query tab.

@onready var _background: ColorRect = %Background
@onready var _file_menu: PopupMenu = %File
@onready var _view_menu: PopupMenu = %View
@onready var _help_menu: PopupMenu = %Help
@onready var _edit_menu: PopupMenu = %Edit
@onready var _toolbar: PanelContainer = %Toolbar
@onready var _connect_btn: Button = %ConnectBtn
@onready var _refresh_btn: Button = %RefreshBtn
@onready var _status_bar: PanelContainer = %StatusBar
@onready var _status_label: Label = %StatusLabel
@onready var _sidebar: ConnectionSidebar = %Sidebar
@onready var _workspace: Workspace = %Workspace

var _connection_dialog: ConnectionDialog


func _ready() -> void:
	_apply_style()
	_populate_menus()

	_connect_btn.pressed.connect(_open_connection_dialog)

	_connection_dialog = ConnectionDialog.new()
	add_child(_connection_dialog)
	_connection_dialog.saved.connect(_on_connection_saved)
	_connection_dialog.updated.connect(_on_connection_updated)

	_sidebar.collection_activated.connect(_on_collection_activated)
	_sidebar.add_connection_requested.connect(_open_connection_dialog)
	_sidebar.edit_connection_requested.connect(_on_edit_connection_requested)
	_sidebar.shell_requested.connect(_on_shell_requested)
	_sidebar.insert_document_requested.connect(_on_insert_document_requested)


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
	_file_menu.add_item("Open Shell", 1)
	_file_menu.add_separator()
	_file_menu.add_item("Quit", 2)
	_file_menu.id_pressed.connect(_on_file_menu)

	_edit_menu.add_item("Copy", 0)
	_edit_menu.add_item("Paste", 1)

	_view_menu.add_item("Tree", 0)
	_view_menu.add_item("Table", 1)
	_view_menu.add_item("Text", 2)

	_help_menu.add_item("About Quetzalcoatl", 0)


func _open_connection_dialog() -> void:
	_connection_dialog.open_new()


func _on_edit_connection_requested(index: int, config: Dictionary) -> void:
	_connection_dialog.open_edit(index, config)


func _on_shell_requested(conn: String, database: String) -> void:
	_workspace.open_collection(conn, database, "")
	_status_label.text = "Opened shell on %s.%s" % [conn, database]


func _on_insert_document_requested(conn: String, database: String, collection: String) -> void:
	var tab := _workspace.open_collection(conn, database, collection)
	tab.results().request_insert()
	_status_label.text = "Insert document into %s.%s" % [database, collection]


func _on_collection_activated(conn: String, database: String, collection: String) -> void:
	_workspace.open_collection(conn, database, collection)
	_status_label.text = "Opened %s.%s on %s" % [database, collection, conn]


func _on_file_menu(id: int) -> void:
	match id:
		0:  # New Connection…
			_open_connection_dialog()
		2:  # Quit
			get_tree().quit()


func _on_connection_saved(config: Dictionary) -> void:
	_sidebar.add_connection(config)
	_status_label.text = "Added connection '%s'" % config.get("name", "")


func _on_connection_updated(index: int, config: Dictionary) -> void:
	_sidebar.update_connection(index, config)
	_status_label.text = "Updated connection '%s'" % config.get("name", "")
