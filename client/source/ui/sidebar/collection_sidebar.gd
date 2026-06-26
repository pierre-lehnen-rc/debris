class_name CollectionSidebar
extends PanelContainer

## Per-workspace sidebar: shows the grouped collection tree for a single,
## pre-selected database. Collection names are loaded from the backend and the
## folder tree is built by the selected DatabaseSchema (Generic/Rocket.Chat).
## Double-clicking a collection opens a query tab; right-clicking one shows
## collection actions.

signal collection_activated(connection: Dictionary, database: String, collection: String)
signal insert_document_requested(connection: Dictionary, database: String, collection: String)
signal status_changed(text: String)

const META_TYPE := "type"  # "collection" | "collection_group" | "placeholder"
const ICON_GROUP := preload("res://source/ui/icons/group.svg")
const ICON_COLLECTION := preload("res://source/ui/icons/collection.svg")
const ICON_SIZE := 16

# Create grouping folders collapsed by default. (Will become a user pref later.)
const COLLAPSE_GROUPS := true

enum Action { VIEW_DOCUMENTS, INSERT_DOCUMENT, COPY_NAME }

@onready var _header: PanelContainer = %Header
@onready var _title: Label = %Title
@onready var _tree: Tree = %Tree
@onready var _context_menu: PopupMenu = %ContextMenu

var _connection: Dictionary = {}
var _database := ""
var _names: Array = []
var _menu_target: Dictionary = {}
var _loading := false
# Schema driving the grouping; swapped by the header's schema selector. Index
# order matches the SchemaOption items (0 = Generic, 1 = Rocket.Chat).
var _schema: DatabaseSchema = GenericSchema.new()


func _ready() -> void:
	_apply_style()
	if not _database.is_empty():
		_title.text = _database.to_upper()
		_load()


## Point this sidebar at a database. Loads its collections from the backend.
func configure(connection: Dictionary, database: String) -> void:
	_connection = connection
	_database = database
	if is_node_ready():
		_title.text = _database.to_upper()
		_load()


func _apply_style() -> void:
	var sb := AppTheme._flat(AppTheme.BG_DARKEST, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	_header.add_theme_stylebox_override("panel", sb)

	_title.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_title.add_theme_font_size_override("font_size", 11)


# Wired in collection_sidebar.tscn from the header buttons -------------------
func _on_refresh_pressed() -> void:
	_load()


## Schema selector in the header. Swaps the grouping schema and re-renders the
## current collection list (no reload needed — only the layout changes).
func _on_schema_selected(index: int) -> void:
	_schema = RocketChatSchema.new() if index == 1 else GenericSchema.new()
	_render()


# Loading / rendering ---------------------------------------------------------
func _load() -> void:
	if _loading or _connection.is_empty() or _database.is_empty():
		return
	_loading = true
	status_changed.emit("Loading collections for %s…" % _database)
	var result: Dictionary = await Backend.list_collections(Backend.to_spec(_connection), _database)
	_loading = false

	if not result.get("ok", false):
		status_changed.emit("Failed to load collections for %s: %s" % [
			_database, result.get("error", "unknown error"),
		])
		_render_message("(failed to load)")
		return

	_names = []
	var data: Variant = result.get("data")
	if data is Array:
		for entry in data:
			if entry is Dictionary:
				_names.append(entry.get("name", "(unknown)"))
	_names.sort()
	_render()
	status_changed.emit("Loaded %d collections in %s" % [_names.size(), _database])


## Render the grouped collection tree. The grouper decides the structure; we
## walk each name's path and create folders lazily, preserving input order.
func _render() -> void:
	_tree.clear()
	var root := _tree.create_item()
	if _names.is_empty():
		_add_placeholder(root, "(no collections)")
		return
	var structure := _schema.build_structure(_names)
	for coll in _names:
		var path := _schema.path_for(structure, coll)
		var parent := root
		for i in path.size() - 1:
			parent = _get_or_create_group(parent, path[i])
		_add_collection_leaf(parent, path[path.size() - 1], coll)


func _render_message(text: String) -> void:
	_tree.clear()
	var root := _tree.create_item()
	_add_placeholder(root, text)


func _on_item_activated() -> void:
	var item := _tree.get_selected()
	if item == null:
		return
	var meta: Dictionary = item.get_metadata(0)
	if meta.is_empty():
		return
	if meta[META_TYPE] == "collection":
		collection_activated.emit(_connection, _database, meta["collection"])
	else:
		item.set_collapsed(not item.is_collapsed())


# Context menu ----------------------------------------------------------------
func _on_item_mouse_selected(_pos: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return
	var item := _tree.get_selected()
	if item == null:
		return
	_menu_target = item.get_metadata(0)
	if _menu_target.is_empty() or _menu_target[META_TYPE] != "collection":
		return
	_context_menu.clear()
	_context_menu.add_item("View Documents", Action.VIEW_DOCUMENTS)
	_context_menu.add_item("Insert Document…", Action.INSERT_DOCUMENT)
	_context_menu.add_separator()
	_context_menu.add_item("Copy collection name", Action.COPY_NAME)
	_context_menu.reset_size()
	# Embedded sub-windows position popups in the parent viewport's space.
	_context_menu.position = Vector2i(_tree.get_global_mouse_position())
	_context_menu.popup()


func _on_context_action(id: int) -> void:
	var coll: String = _menu_target.get("collection", "")
	match id:
		Action.VIEW_DOCUMENTS:
			collection_activated.emit(_connection, _database, coll)
		Action.INSERT_DOCUMENT:
			insert_document_requested.emit(_connection, _database, coll)
		Action.COPY_NAME:
			DisplayServer.clipboard_set(coll)
			status_changed.emit("Copied '%s' to clipboard" % coll)


# Tree-building helpers -------------------------------------------------------
## Return the child folder of `parent` with the given label, creating it if it
## doesn't exist yet (so repeated paths share the same TreeItem folders).
func _get_or_create_group(parent: TreeItem, label: String) -> TreeItem:
	for child in parent.get_children():
		var meta: Dictionary = child.get_metadata(0)
		if meta.get(META_TYPE) == "collection_group" and child.get_text(0) == label:
			return child
	var group := _tree.create_item(parent)
	group.set_text(0, label)
	group.set_custom_color(0, AppTheme.TEXT)
	group.set_icon(0, ICON_GROUP)
	group.set_icon_max_width(0, ICON_SIZE)
	group.set_icon_modulate(0, AppTheme.TEXT_DIM)
	group.set_collapsed(COLLAPSE_GROUPS)
	group.set_metadata(0, {META_TYPE: "collection_group"})
	return group


func _add_collection_leaf(parent: TreeItem, label: String, full: String) -> void:
	var leaf := _tree.create_item(parent)
	leaf.set_text(0, label)
	leaf.set_custom_color(0, AppTheme.TEXT_DIM)
	leaf.set_icon(0, ICON_COLLECTION)
	leaf.set_icon_max_width(0, ICON_SIZE)
	leaf.set_icon_modulate(0, AppTheme.TEXT_DIM)
	leaf.set_metadata(0, {META_TYPE: "collection", "collection": full})


func _add_placeholder(parent: TreeItem, text: String) -> void:
	var ph := _tree.create_item(parent)
	ph.set_text(0, text)
	ph.set_selectable(0, false)
	ph.set_custom_color(0, AppTheme.TEXT_DIM)
	ph.set_metadata(0, {META_TYPE: "placeholder"})
