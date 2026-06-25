class_name ConnectionSidebar
extends PanelContainer

## Left-hand panel: a tree of connections > databases > collections, fed from
## a runtime list seeded from MockData. Double-clicking a collection opens a
## query tab; right-clicking any node shows a context menu of actions.

signal collection_activated(connection: String, database: String, collection: String)
signal shell_requested(connection: String, database: String)
signal insert_document_requested(connection: String, database: String, collection: String)
signal add_connection_requested()
signal edit_connection_requested(index: int, config: Dictionary)

const META_TYPE := "type"  # "connection" | "database" | "collection"

# Context-menu action ids (shared across node types; only relevant ones shown).
enum Action {
	CONNECT_TOGGLE,
	EDIT_CONNECTION,
	REMOVE_CONNECTION,
	OPEN_SHELL,
	CREATE_COLLECTION,
	DROP_DATABASE,
	VIEW_DOCUMENTS,
	INSERT_DOCUMENT,
	DROP_COLLECTION,
	REFRESH,
}

var _tree: Tree
var _context_menu: PopupMenu
var _menu_target: Dictionary = {}
# Runtime, mutable copy seeded from MockData so connections can be edited.
var _connections: Array = []


func _ready() -> void:
	_connections = MockData.CONNECTIONS.duplicate(true)

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 0)
	add_child(root_box)

	root_box.add_child(_build_header())

	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.allow_rmb_select = true
	_tree.item_activated.connect(_on_item_activated)
	_tree.item_mouse_selected.connect(_on_item_mouse_selected)
	root_box.add_child(_tree)

	_context_menu = PopupMenu.new()
	_context_menu.theme = AppTheme.shared()
	_context_menu.id_pressed.connect(_on_context_action)
	add_child(_context_menu)

	_populate()


# Public mutations (called by Main) -------------------------------------------
func add_connection(config: Dictionary) -> void:
	_connections.append({
		"name": config.get("name", "New Connection"),
		"host": config.get("host", ""),
		"connected": false,
		"databases": config.get("databases", []),
	})
	_populate()


func update_connection(index: int, config: Dictionary) -> void:
	if index < 0 or index >= _connections.size():
		return
	_connections[index]["name"] = config.get("name", _connections[index]["name"])
	_connections[index]["host"] = config.get("host", _connections[index]["host"])
	_populate()


func _build_header() -> Control:
	var header := PanelContainer.new()
	var sb := AppTheme._flat(AppTheme.BG_DARKEST, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	header.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	header.add_child(row)

	var title := Label.new()
	title.text = "CONNECTIONS"
	title.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	title.add_theme_font_size_override("font_size", 11)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)

	var add_btn := Button.new()
	add_btn.text = "+"
	add_btn.tooltip_text = "New connection"
	add_btn.focus_mode = Control.FOCUS_NONE
	add_btn.pressed.connect(func() -> void: add_connection_requested.emit())
	row.add_child(add_btn)

	return header


func _populate() -> void:
	_tree.clear()
	var root := _tree.create_item()

	for ci in _connections.size():
		var conn: Dictionary = _connections[ci]
		var conn_item := _tree.create_item(root)
		var dot := "●" if conn.get("connected", false) else "○"
		conn_item.set_text(0, "%s  %s" % [dot, conn["name"]])
		conn_item.set_tooltip_text(0, conn["host"])
		conn_item.set_custom_color(0, AppTheme.TEXT_BRIGHT)
		conn_item.set_metadata(0, {
			META_TYPE: "connection",
			"conn_index": ci,
			"connection": conn["name"],
		})
		conn_item.set_collapsed(not conn.get("connected", false))

		for db in conn["databases"]:
			var db_item := _tree.create_item(conn_item)
			db_item.set_text(0, db["name"])
			db_item.set_custom_color(0, AppTheme.TEXT)
			db_item.set_metadata(0, {
				META_TYPE: "database",
				"conn_index": ci,
				"connection": conn["name"],
				"database": db["name"],
			})
			db_item.set_collapsed(true)

			for coll in db["collections"]:
				var coll_item := _tree.create_item(db_item)
				coll_item.set_text(0, coll)
				coll_item.set_custom_color(0, AppTheme.TEXT_DIM)
				coll_item.set_metadata(0, {
					META_TYPE: "collection",
					"conn_index": ci,
					"connection": conn["name"],
					"database": db["name"],
					"collection": coll,
				})


func _on_item_activated() -> void:
	var item := _tree.get_selected()
	if item == null:
		return
	var meta: Dictionary = item.get_metadata(0)
	if meta.is_empty():
		return
	match meta[META_TYPE]:
		"collection":
			collection_activated.emit(meta["connection"], meta["database"], meta["collection"])
		_:
			item.set_collapsed(not item.is_collapsed())


# Context menu ----------------------------------------------------------------
func _on_item_mouse_selected(_pos: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return
	var item := _tree.get_selected()
	if item == null:
		return
	_menu_target = item.get_metadata(0)
	if _menu_target.is_empty():
		return
	_build_context_menu(_menu_target[META_TYPE])
	_context_menu.reset_size()
	# Embedded sub-windows position popups in the parent viewport's space.
	_context_menu.position = Vector2i(_tree.get_global_mouse_position())
	_context_menu.popup()


func _build_context_menu(node_type: String) -> void:
	_context_menu.clear()
	match node_type:
		"connection":
			var connected: bool = _connections[_menu_target["conn_index"]].get("connected", false)
			_context_menu.add_item("Disconnect" if connected else "Connect", Action.CONNECT_TOGGLE)
			_context_menu.add_item("Edit Connection…", Action.EDIT_CONNECTION)
			_context_menu.add_separator()
			_context_menu.add_item("Refresh", Action.REFRESH)
			_context_menu.add_separator()
			_context_menu.add_item("Remove Connection", Action.REMOVE_CONNECTION)
		"database":
			_context_menu.add_item("Open Shell", Action.OPEN_SHELL)
			_context_menu.add_item("Create Collection…", Action.CREATE_COLLECTION)
			_context_menu.add_separator()
			_context_menu.add_item("Refresh", Action.REFRESH)
			_context_menu.add_separator()
			_context_menu.add_item("Drop Database", Action.DROP_DATABASE)
		"collection":
			_context_menu.add_item("View Documents", Action.VIEW_DOCUMENTS)
			_context_menu.add_item("Insert Document…", Action.INSERT_DOCUMENT)
			_context_menu.add_separator()
			_context_menu.add_item("Drop Collection", Action.DROP_COLLECTION)


func _on_context_action(id: int) -> void:
	var ci: int = _menu_target.get("conn_index", -1)
	match id:
		Action.CONNECT_TOGGLE:
			_connections[ci]["connected"] = not _connections[ci].get("connected", false)
			_populate()
		Action.EDIT_CONNECTION:
			edit_connection_requested.emit(ci, _connections[ci].duplicate(true))
		Action.REMOVE_CONNECTION:
			_connections.remove_at(ci)
			_populate()
		Action.OPEN_SHELL:
			shell_requested.emit(_menu_target["connection"], _menu_target["database"])
		Action.CREATE_COLLECTION:
			_add_collection(ci, _menu_target["database"], "new_collection")
		Action.DROP_DATABASE:
			_drop_database(ci, _menu_target["database"])
		Action.VIEW_DOCUMENTS:
			collection_activated.emit(
				_menu_target["connection"], _menu_target["database"], _menu_target["collection"]
			)
		Action.INSERT_DOCUMENT:
			insert_document_requested.emit(
				_menu_target["connection"], _menu_target["database"], _menu_target["collection"]
			)
		Action.DROP_COLLECTION:
			_drop_collection(ci, _menu_target["database"], _menu_target["collection"])
		Action.REFRESH:
			_populate()


func _add_collection(ci: int, db_name: String, coll_name: String) -> void:
	for db in _connections[ci]["databases"]:
		if db["name"] == db_name:
			db["collections"].append(coll_name)
			break
	_populate()


func _drop_database(ci: int, db_name: String) -> void:
	var dbs: Array = _connections[ci]["databases"]
	for i in dbs.size():
		if dbs[i]["name"] == db_name:
			dbs.remove_at(i)
			break
	_populate()


func _drop_collection(ci: int, db_name: String, coll_name: String) -> void:
	for db in _connections[ci]["databases"]:
		if db["name"] == db_name:
			db["collections"].erase(coll_name)
			break
	_populate()
