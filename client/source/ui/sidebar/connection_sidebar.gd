class_name ConnectionSidebar
extends PanelContainer

## Left-hand panel: a tree of connections > databases > collections. Databases
## and collections are loaded lazily from the backend when a connection is
## connected / a database is expanded. Double-clicking a collection opens a
## query tab; right-clicking any node shows a context menu of actions.

signal collection_activated(connection: Dictionary, database: String, collection: String)
signal shell_requested(connection: Dictionary, database: String)
signal insert_document_requested(connection: Dictionary, database: String, collection: String)
signal add_connection_requested()
signal edit_connection_requested(index: int, config: Dictionary)
signal status_changed(text: String)

const META_TYPE := "type"  # "connection" | "database" | "collection" | "collection_group"

# Collections sharing a leading word are grouped into a folder tree by
# CollectionGrouper; the grouping rules live there. This sidebar only renders
# the resulting paths into the Tree.

# Create grouping folders collapsed by default. (Will become a user pref later.)
const COLLAPSE_GROUPS := true

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

@onready var _header: PanelContainer = %Header
@onready var _title: Label = %Title
@onready var _add_btn: Button = %AddBtn
@onready var _tree: Tree = %Tree
@onready var _context_menu: PopupMenu = %ContextMenu

var _menu_target: Dictionary = {}
# Runtime list of connection configs (added/edited via the connection dialog).
var _connections: Array = []
# Set of "ci/database" keys with an in-flight collection load, to de-dupe.
var _loading_dbs: Dictionary = {}


func _ready() -> void:
	# Seed a single localhost connection so there's something to connect to out
	# of the box; databases/collections are then loaded from the backend.
	_connections = [{
		"name": "Local",
		"host": "127.0.0.1:27017",
		"connected": false,
		"databases": [],
	}]

	_apply_style()
	_populate()


## Wired in connection_sidebar.tscn from the header "+" button.
func _on_add_pressed() -> void:
	add_connection_requested.emit()


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
			# A database is "loaded" once its collections are known. Seed/mock
			# data arrives with collections already filled in; real connections
			# start empty and load lazily when the node is expanded.
			var loaded: bool = db.get("loaded", not (db.get("collections", []) as Array).is_empty())
			db_item.set_metadata(0, _db_meta(ci, conn["name"], db["name"], loaded))
			db_item.set_collapsed(true)

			if loaded:
				var colls: Array = db.get("collections", [])
				if colls.is_empty():
					_add_placeholder(db_item, "(no collections)")
				else:
					_add_collection_tree(db_item, ci, conn["name"], db["name"], colls)
			else:
				# A placeholder child gives the node a fold arrow; expanding it
				# triggers a lazy collection load from the backend.
				_add_placeholder(db_item, "Loading…")


func _on_item_activated() -> void:
	var item := _tree.get_selected()
	if item == null:
		return
	var meta: Dictionary = item.get_metadata(0)
	if meta.is_empty():
		return
	match meta[META_TYPE]:
		"collection":
			collection_activated.emit(
				_connections[meta["conn_index"]], meta["database"], meta["collection"]
			)
		"database":
			item.set_collapsed(not item.is_collapsed())
			if not item.is_collapsed() and not meta.get("loaded", false):
				_load_collections(item, meta)
		"collection_group":
			item.set_collapsed(not item.is_collapsed())
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
	if _menu_target[META_TYPE] == "placeholder" or _menu_target[META_TYPE] == "collection_group":
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
		Action.OPEN_SHELL:
			shell_requested.emit(_connections[ci], _menu_target["database"])
		Action.CREATE_COLLECTION:
			_add_collection(ci, _menu_target["database"], "new_collection")
		Action.DROP_DATABASE:
			_drop_database(ci, _menu_target["database"])
		Action.VIEW_DOCUMENTS:
			collection_activated.emit(
				_connections[ci], _menu_target["database"], _menu_target["collection"]
			)
		Action.INSERT_DOCUMENT:
			insert_document_requested.emit(
				_connections[ci], _menu_target["database"], _menu_target["collection"]
			)
		Action.DROP_COLLECTION:
			_drop_collection(ci, _menu_target["database"], _menu_target["collection"])
		Action.REFRESH:
			_populate()


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
			databases.append({"name": entry.get("name", "(unknown)"), "collections": []})

	conn["databases"] = databases
	conn["connected"] = true
	_populate()
	status_changed.emit("Connected to %s — %d databases" % [
		conn.get("name", ""), databases.size(),
	])


## Lazily load a database's collections the first time its node is expanded
## via the fold arrow.
func _on_item_collapsed(item: TreeItem) -> void:
	if item == null or item.is_collapsed():
		return
	var meta: Dictionary = item.get_metadata(0)
	if meta.is_empty() or meta.get(META_TYPE) != "database" or meta.get("loaded", false):
		return
	_load_collections(item, meta)


## Fetch a database's collections from the backend and graft them onto the
## existing tree node in place (so the expanded state is preserved).
func _load_collections(db_item: TreeItem, meta: Dictionary) -> void:
	var ci: int = meta.get("conn_index", -1)
	var db_name: String = meta.get("database", "")
	if ci < 0 or db_name.is_empty():
		return

	var key := "%d/%s" % [ci, db_name]
	if _loading_dbs.has(key):
		return
	_loading_dbs[key] = true

	var conn_name: String = meta.get("connection", "")
	status_changed.emit("Loading collections for %s…" % db_name)
	var result: Dictionary = await Backend.list_collections(Backend.to_spec(_connections[ci]), db_name)
	_loading_dbs.erase(key)

	if not result.get("ok", false):
		status_changed.emit("Failed to load collections for %s: %s" % [
			db_name, result.get("error", "unknown error"),
		])
		return

	var names: Array = []
	var data: Variant = result.get("data")
	if data is Array:
		for entry in data:
			if entry is Dictionary:
				names.append(entry.get("name", "(unknown)"))
	names.sort()

	# Persist into the data model so later rebuilds (refresh, edits) keep them.
	for db in _connections[ci]["databases"]:
		if db["name"] == db_name:
			db["collections"] = names
			db["loaded"] = true
			break

	# The node may have been rebuilt while the request was in flight; bail if so.
	if not is_instance_valid(db_item):
		return
	for child in db_item.get_children():
		child.free()
	if names.is_empty():
		_add_placeholder(db_item, "(no collections)")
	else:
		_add_collection_tree(db_item, ci, conn_name, db_name, names)
	db_item.set_metadata(0, _db_meta(ci, conn_name, db_name, true))
	status_changed.emit("Loaded %d collections in %s" % [names.size(), db_name])


# Tree-building helpers -------------------------------------------------------
func _db_meta(ci: int, connection: String, db_name: String, loaded: bool) -> Dictionary:
	return {
		META_TYPE: "database",
		"conn_index": ci,
		"connection": connection,
		"database": db_name,
		"loaded": loaded,
	}


## Group a flat list of collection names into a folder tree (by shared leading
## words, via CollectionGrouper) and add it under the database node. The grouper
## decides the structure; here we just walk each name's path and create folders
## lazily, which preserves the input order wherever the structure allows.
func _add_collection_tree(
	db_item: TreeItem, ci: int, connection: String, db_name: String, names: Array
) -> void:
	var structure := CollectionGrouper.build_structure(names)
	for coll in names:
		var path := CollectionGrouper.path_for(structure, coll)
		var parent := db_item
		for i in path.size() - 1:
			parent = _get_or_create_group(parent, ci, connection, db_name, path[i])
		_add_collection_leaf(parent, ci, connection, db_name, path[path.size() - 1], coll)


## Return the child folder of `parent` with the given label, creating it if it
## doesn't exist yet (so repeated paths share the same TreeItem folders).
func _get_or_create_group(
	parent: TreeItem, ci: int, connection: String, db_name: String, label: String
) -> TreeItem:
	for child in parent.get_children():
		var meta: Dictionary = child.get_metadata(0)
		if meta.get(META_TYPE) == "collection_group" and child.get_text(0) == label:
			return child
	return _create_group(parent, ci, connection, db_name, label)


func _create_group(
	parent: TreeItem, ci: int, connection: String, db_name: String, label: String
) -> TreeItem:
	var group := _tree.create_item(parent)
	group.set_text(0, label)
	group.set_custom_color(0, AppTheme.TEXT)
	group.set_collapsed(COLLAPSE_GROUPS)
	group.set_metadata(0, {
		META_TYPE: "collection_group",
		"conn_index": ci,
		"connection": connection,
		"database": db_name,
	})
	return group


func _add_collection_leaf(
	parent: TreeItem, ci: int, connection: String, db_name: String,
	label: String, full: String
) -> void:
	var leaf := _tree.create_item(parent)
	leaf.set_text(0, label)
	leaf.set_custom_color(0, AppTheme.TEXT_DIM)
	leaf.set_metadata(0, _collection_meta(ci, connection, db_name, full))


func _collection_meta(ci: int, connection: String, db_name: String, coll: String) -> Dictionary:
	return {
		META_TYPE: "collection",
		"conn_index": ci,
		"connection": connection,
		"database": db_name,
		"collection": coll,
	}


func _add_placeholder(db_item: TreeItem, text: String) -> void:
	var ph := _tree.create_item(db_item)
	ph.set_text(0, text)
	ph.set_selectable(0, false)
	ph.set_custom_color(0, AppTheme.TEXT_DIM)
	ph.set_metadata(0, {META_TYPE: "placeholder"})


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
