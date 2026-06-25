class_name Main
extends Control

## Application shell: menu bar, toolbar, sidebar | workspace split, status bar.
## Builds the dark theme and wires the sidebar's collection activation to the
## workspace so double-clicking a collection opens a query tab.

var _sidebar: ConnectionSidebar
var _workspace: Workspace
var _status_label: Label
var _connection_dialog: ConnectionDialog


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = AppTheme.shared()

	var bg := ColorRect.new()
	bg.color = AppTheme.BG_DARKEST
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	root.add_child(_build_menu_bar())
	root.add_child(_build_toolbar())

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 260
	root.add_child(split)

	_sidebar = ConnectionSidebar.new()
	_sidebar.custom_minimum_size = Vector2(200, 0)
	split.add_child(_sidebar)

	_workspace = Workspace.new()
	_workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(_workspace)

	root.add_child(_build_status_bar())

	_connection_dialog = ConnectionDialog.new()
	add_child(_connection_dialog)
	_connection_dialog.saved.connect(_on_connection_saved)
	_connection_dialog.updated.connect(_on_connection_updated)

	_sidebar.collection_activated.connect(_on_collection_activated)
	_sidebar.add_connection_requested.connect(_open_connection_dialog)
	_sidebar.edit_connection_requested.connect(_on_edit_connection_requested)
	_sidebar.shell_requested.connect(_on_shell_requested)
	_sidebar.insert_document_requested.connect(_on_insert_document_requested)


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


func _build_menu_bar() -> Control:
	var bar := MenuBar.new()
	bar.flat = true

	var file := PopupMenu.new()
	file.name = "File"
	file.add_item("New Connection…", 0)
	file.add_item("Open Shell", 1)
	file.add_separator()
	file.add_item("Quit", 2)
	file.id_pressed.connect(_on_file_menu)
	bar.add_child(file)

	var edit := PopupMenu.new()
	edit.name = "Edit"
	edit.add_item("Copy", 0)
	edit.add_item("Paste", 1)
	bar.add_child(edit)

	var view := PopupMenu.new()
	view.name = "View"
	view.add_item("Tree", 0)
	view.add_item("Table", 1)
	view.add_item("Text", 2)
	bar.add_child(view)

	var help := PopupMenu.new()
	help.name = "Help"
	help.add_item("About Quetzalcoatl", 0)
	bar.add_child(help)

	return bar


func _build_toolbar() -> Control:
	var panel := PanelContainer.new()
	var sb := AppTheme._flat(AppTheme.BG_DARK, 0)
	sb.border_width_bottom = 1
	sb.border_color = AppTheme.BORDER
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)

	var connect_btn := Button.new()
	connect_btn.text = "Connect"
	connect_btn.focus_mode = Control.FOCUS_NONE
	connect_btn.pressed.connect(_open_connection_dialog)
	row.add_child(connect_btn)

	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.focus_mode = Control.FOCUS_NONE
	row.add_child(refresh_btn)

	return panel


func _build_status_bar() -> Control:
	var panel := PanelContainer.new()
	var sb := AppTheme._flat(AppTheme.BG_DARKEST, 0)
	sb.border_width_top = 1
	sb.border_color = AppTheme.BORDER
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", sb)

	_status_label = Label.new()
	_status_label.text = "Ready"
	_status_label.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_status_label.add_theme_font_size_override("font_size", 12)
	panel.add_child(_status_label)

	return panel


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
