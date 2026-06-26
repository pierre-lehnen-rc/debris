class_name ConnectionBrowser
extends PanelContainer

## Browser of connections and their databases, shown inside the connection
## picker popup. Owns the runtime connection list (add/edit/remove, connect/
## disconnect, lazy database load) and lets the user pick a database to open as
## a workspace tab. Collections are NOT shown here — those live in each
## workspace tab's own CollectionSidebar.

signal database_activated(connection: Dictionary, database: String)
signal shell_requested(connection: Dictionary, database: String)
signal add_connection_requested()
signal edit_connection_requested(index: int, config: Dictionary)
signal status_changed(text: String)

const META_TYPE := "type"  # "connection" | "database"
const ICON_DATABASE := preload("res://source/ui/icons/database.svg")
const ICON_SIZE := 16

# Context-menu action ids (shared across node types; only relevant ones shown).
enum Action {
	CONNECT_TOGGLE,
	EDIT_CONNECTION,
	REMOVE_CONNECTION,
	OPEN_TAB,
	OPEN_SHELL,
	DROP_DATABASE,
	REFRESH,
}

@onready var _header: PanelContainer = %Header
@onready var _title: Label = %Title
@onready var _tree: Tree = %Tree
@onready var _context_menu: PopupMenu = %ContextMenu

var _menu_target: Dictionary = {}
# Runtime list of connection configs (added/edited via the connection dialog).
var _connections: Array = []


func _ready() -> void:
	# Seed a single localhost connection so there's something to connect to out
	# of the box; databases are then loaded from the backend.
	_connections = [{
		"name": "Local",
		"host": "127.0.0.1:27017",
		"connected": false,
		"databases": [],
	}]
	_apply_style()
	_populate()


## Wired in connection_browser.tscn from the header "+" button.
func _on_add_pressed() -> void:
	add_connection_requested.emit()


# Public mutations (called by Main after the connection dialog) ----------------
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


func _apply_style() -> void:
	var sb := AppTheme._flat(AppTheme.BG_DARKEST, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	_header.add_theme_stylebox_override("panel", sb)

	_title.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_title.add_theme_font_size_override("font_size", 11)


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
			db_item.set_icon(0, ICON_DATABASE)
			db_item.set_icon_max_width(0, ICON_SIZE)
			db_item.set_icon_modulate(0, AppTheme.TEXT)
			db_item.set_metadata(0, {
				META_TYPE: "database",
				"conn_index": ci,
				"connection": conn["name"],
				"database": db["name"],
			})


func _on_item_activated() -> void:
	var item := _tree.get_selected()
	if item == null:
		return
	var meta: Dictionary = item.get_metadata(0)
	if meta.is_empty():
		return
	match meta[META_TYPE]:
		"database":
			database_activated.emit(_connections[meta["conn_index"]], meta["database"])
		"connection":
			var ci: int = meta["conn_index"]
			if _connections[ci].get("connected", false):
				item.set_collapsed(not item.is_collapsed())
			else:
				_connect(ci)


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
			_context_menu.add_item("Open in New Tab", Action.OPEN_TAB)
			_context_menu.add_item("Open Shell", Action.OPEN_SHELL)
			_context_menu.add_separator()
			_context_menu.add_item("Drop Database", Action.DROP_DATABASE)


func _on_context_action(id: int) -> void:
	var ci: int = _menu_target.get("conn_index", -1)
	match id:
		Action.CONNECT_TOGGLE:
			if _connections[ci].get("connected", false):
				_connections[ci]["connected"] = false
				_populate()
			else:
				_connect(ci)
		Action.EDIT_CONNECTION:
			edit_connection_requested.emit(ci, _connections[ci].duplicate(true))
		Action.REMOVE_CONNECTION:
			_connections.remove_at(ci)
			_populate()
		Action.OPEN_TAB:
			database_activated.emit(_connections[ci], _menu_target["database"])
		Action.OPEN_SHELL:
			shell_requested.emit(_connections[ci], _menu_target["database"])
		Action.DROP_DATABASE:
			_drop_database(ci, _menu_target["database"])
		Action.REFRESH:
			if _connections[ci].get("connected", false):
				_connect(ci)


## Connect to a connection's server via the backend and replace its database
## list with the real databases reported by MongoDB.
func _connect(ci: int) -> void:
	var conn: Dictionary = _connections[ci]
	status_changed.emit("Connecting to %s…" % conn.get("name", ""))

	var result: Dictionary = await Backend.list_databases(Backend.to_spec(conn))
	if not result.get("ok", false):
		status_changed.emit("Connection to %s failed: %s" % [
			conn.get("name", ""), result.get("error", "unknown error"),
		])
		return

	var databases: Array = []
	var data: Variant = result.get("data")
	if data is Dictionary and data.get("databases") is Array:
		for entry in data["databases"]:
			databases.append({"name": entry.get("name", "(unknown)")})

	conn["databases"] = databases
	conn["connected"] = true
	_populate()
	status_changed.emit("Connected to %s — %d databases" % [
		conn.get("name", ""), databases.size(),
	])


func _drop_database(ci: int, db_name: String) -> void:
	var dbs: Array = _connections[ci]["databases"]
	for i in dbs.size():
		if dbs[i]["name"] == db_name:
			dbs.remove_at(i)
			break
	_populate()
