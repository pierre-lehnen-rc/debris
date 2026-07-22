class_name ConnectionBrowser
extends PanelContainer

## Browser of connections and their databases, shown inside the connection
## picker popup. Owns the runtime connection list (add/edit/remove, connect/
## disconnect, lazy database load) and lets the user pick a database to open as
## a database tab. Collections are NOT shown here — those live in each
## database tab's own CollectionSidebar.

signal database_activated(connection: Dictionary, database: String)
signal add_connection_requested()
signal edit_connection_requested(index: int, config: Dictionary)
signal status_changed(text: String)
signal selection_changed(has_database: bool)

const META_TYPE := "type"  # "connection" | "database"
const ICON_DATABASE := preload("res://source/ui/icons/database.svg")
const ICON_SIZE := 16

# Context-menu action ids (connections only; databases have no context menu).
enum Action {
	CONNECT_TOGGLE,
	EDIT_CONNECTION,
	REMOVE_CONNECTION,
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
	_load_connections()
	_apply_style()
	_populate()


## Load the saved connections, rehydrating the transient runtime fields. On the
## very first run (nothing ever saved) seed a single localhost connection so
## there's something to connect to out of the box, and persist it.
func _load_connections() -> void:
	if not Store.has("connections"):
		_connections = [{
			"name": "Local",
			"host": "127.0.0.1:27017",
			"connected": false,
			"default_database": "",
			"databases": [],
		}]
		_persist()
		return
	_connections = []
	for saved in Store.connections():
		var default_db: String = saved.get("default_database", "")
		_connections.append({
			"name": saved.get("name", ""),
			"host": saved.get("host", ""),
			"connected": false,
			"default_database": default_db,
			# Pre-load the default database so it can be opened without first
			# listing every database on the server.
			"databases": _seed_databases(default_db),
		})


## The initial visible database list for a not-yet-connected connection: just its
## configured default database (if any), so it shows in the tree straight away.
static func _seed_databases(default_db: String) -> Array:
	return [{"name": default_db}] if not default_db.is_empty() else []


## Write the persistable part of each connection (name, host, default database)
## back to disk; the live database list and connected flag are runtime-only.
func _persist() -> void:
	var out: Array = []
	for conn in _connections:
		out.append({
			"name": conn.get("name", ""),
			"host": conn.get("host", ""),
			"default_database": conn.get("default_database", ""),
		})
	Store.save_connections(out)


## Wired in connection_browser.tscn from the header "+" button.
func _on_add_pressed() -> void:
	add_connection_requested.emit()


# Public mutations (called by Main after the connection dialog) ----------------
func add_connection(config: Dictionary) -> void:
	var default_db: String = config.get("default_database", "")
	_connections.append({
		"name": config.get("name", "New Connection"),
		"host": config.get("host", ""),
		"connected": false,
		"default_database": default_db,
		"databases": _seed_databases(default_db),
	})
	_persist()
	_populate()


func update_connection(index: int, config: Dictionary) -> void:
	if index < 0 or index >= _connections.size():
		return
	var conn: Dictionary = _connections[index]
	conn["name"] = config.get("name", conn["name"])
	conn["host"] = config.get("host", conn["host"])
	conn["default_database"] = config.get("default_database", conn.get("default_database", ""))
	# Refresh the pre-loaded default in the tree, unless we're already showing the
	# live list from an active connection (which we don't want to clobber).
	if not conn.get("connected", false):
		conn["databases"] = _seed_databases(conn["default_database"])
	_persist()
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
		# Expand whenever there are databases to show (a pre-loaded default or a
		# live listing); a bare, unconnected connection stays folded.
		conn_item.set_collapsed(conn["databases"].is_empty())

		var default_db: String = conn.get("default_database", "")
		for db in conn["databases"]:
			var is_default: bool = not default_db.is_empty() and db["name"] == default_db
			var db_color := AppTheme.ACCENT if is_default else AppTheme.TEXT
			var db_item := _tree.create_item(conn_item)
			db_item.set_text(0, "%s ★" % db["name"] if is_default else db["name"])
			db_item.set_custom_color(0, db_color)
			if is_default:
				db_item.set_tooltip_text(0, "Default database")
			db_item.set_icon(0, ICON_DATABASE)
			db_item.set_icon_max_width(0, ICON_SIZE)
			db_item.set_icon_modulate(0, db_color)
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


# Selection tracking (drives the picker's "Open" footer button) ---------------
func _on_item_selected() -> void:
	selection_changed.emit(not selected_database().is_empty())


func _on_nothing_selected() -> void:
	selection_changed.emit(false)


## The database currently selected in the tree, as {connection, database}, or an
## empty dictionary when the selection isn't a database.
func selected_database() -> Dictionary:
	var item := _tree.get_selected()
	if item == null:
		return {}
	var meta: Dictionary = item.get_metadata(0)
	if meta.is_empty() or meta.get(META_TYPE) != "database":
		return {}
	return {"connection": _connections[meta["conn_index"]], "database": meta["database"]}


# Context menu ----------------------------------------------------------------
func _on_item_mouse_selected(_pos: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return
	var item := _tree.get_selected()
	if item == null:
		return
	_menu_target = item.get_metadata(0)
	# Databases have no context menu — only connections do.
	if _menu_target.is_empty() or _menu_target[META_TYPE] != "connection":
		return
	_build_context_menu()
	_context_menu.reset_size()
	# Native pop-ups position in absolute screen coordinates.
	_context_menu.position = DisplayServer.mouse_get_position()
	_context_menu.popup()


func _build_context_menu() -> void:
	_context_menu.clear()
	var connected: bool = _connections[_menu_target["conn_index"]].get("connected", false)
	_context_menu.add_item("Disconnect" if connected else "Connect", Action.CONNECT_TOGGLE)
	_context_menu.add_item("Edit Connection…", Action.EDIT_CONNECTION)
	_context_menu.add_separator()
	_context_menu.add_item("Refresh", Action.REFRESH)
	_context_menu.add_separator()
	_context_menu.add_item("Remove Connection", Action.REMOVE_CONNECTION)


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
			_persist()
			_populate()
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
