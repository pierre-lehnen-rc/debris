class_name CollectionSidebar
extends PanelContainer

## Per-database sidebar: shows the grouped collection tree for a single,
## pre-selected database. Collection names are loaded from the backend and the
## folder tree is built by the selected DatabaseSchema (Generic/Rocket.Chat).
## Double-clicking a collection opens a query tab; right-clicking one shows
## collection actions.

signal collection_activated(connection: Dictionary, database: String, collection: String)
signal insert_document_requested(connection: Dictionary, database: String, collection: String)
signal list_indexes_requested(connection: Dictionary, database: String, collection: String)
signal status_changed(text: String)
signal schema_changed(schema: DatabaseSchema)

const META_TYPE := "type"  # "collection" | "collection_group" | "placeholder"
const ICON_GROUP := preload("res://source/ui/icons/group.svg")
const ICON_COLLECTION := preload("res://source/ui/icons/collection.svg")
const ICON_SIZE := 16

# Create grouping folders collapsed by default. (Will become a user pref later.)
const COLLAPSE_GROUPS := true

enum Action { VIEW_DOCUMENTS, LIST_INDEXES, INSERT_DOCUMENT, COPY_NAME }

const SCHEMA_GENERIC := 0
const SCHEMA_ROCKETCHAT := 1
const SCHEMA_FLAT := 2
# A database with at least this many "rocketchat_"-prefixed collections is
# auto-detected as a Rocket.Chat database.
const ROCKETCHAT_DETECT_THRESHOLD := 2

@onready var _header: PanelContainer = %Header
@onready var _title: Label = %Title
@onready var _schema_option: OptionButton = %SchemaOption
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
# Set once the user picks a schema by hand, so auto-detection on (re)load stops
# overriding their choice.
var _schema_user_selected := false


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


## Schema selector in the header. A manual pick wins over auto-detection from
## then on, and re-renders the current list (no reload — only the layout changes).
func _on_schema_selected(index: int) -> void:
	_schema_user_selected = true
	_schema = _make_schema(index)
	schema_changed.emit(_schema)
	_render()


func _make_schema(index: int) -> DatabaseSchema:
	match index:
		SCHEMA_ROCKETCHAT:
			return RocketChatSchema.new()
		SCHEMA_FLAT:
			return FlatSchema.new()
		_:
			return GenericSchema.new()


## Pick a schema from the loaded collection names unless the user already chose
## one. A Rocket.Chat database is recognised by several "rocketchat_" collections.
func _auto_detect_schema() -> void:
	if _schema_user_selected:
		return
	var rocketchat_count := 0
	for name in _names:
		if (name as String).begins_with("rocketchat_"):
			rocketchat_count += 1
	var index := SCHEMA_ROCKETCHAT if rocketchat_count >= ROCKETCHAT_DETECT_THRESHOLD else SCHEMA_GENERIC
	_schema = _make_schema(index)
	schema_changed.emit(_schema)
	if _schema_option.selected != index:
		_schema_option.select(index)  # Programmatic; doesn't emit item_selected.


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
	_auto_detect_schema()
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
	var ordered := _schema.order_names(structure, _names)
	for coll in ordered:
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
	_context_menu.add_item("List Indexes", Action.LIST_INDEXES)
	_context_menu.add_item("Insert Document…", Action.INSERT_DOCUMENT)
	_context_menu.add_separator()
	_context_menu.add_item("Copy collection name", Action.COPY_NAME)
	_context_menu.reset_size()
	# Native pop-ups position in absolute screen coordinates.
	_context_menu.position = DisplayServer.mouse_get_position()
	_context_menu.popup()


func _on_context_action(id: int) -> void:
	var coll: String = _menu_target.get("collection", "")
	match id:
		Action.VIEW_DOCUMENTS:
			collection_activated.emit(_connection, _database, coll)
		Action.LIST_INDEXES:
			list_indexes_requested.emit(_connection, _database, coll)
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
	var highlighted := _schema.is_highlighted(full)
	var color := AppTheme.ACCENT if highlighted else AppTheme.TEXT_DIM
	leaf.set_custom_color(0, color)
	leaf.set_icon(0, ICON_COLLECTION)
	leaf.set_icon_max_width(0, ICON_SIZE)
	leaf.set_icon_modulate(0, color)
	leaf.set_tooltip_text(0, full)  # The real collection name (labels may be rewritten).
	leaf.set_metadata(0, {META_TYPE: "collection", "collection": full})
	# Reveal highlighted collections by expanding the folders that contain them.
	if highlighted:
		_expand_ancestors(leaf)


## Expand every folder above `item` so a highlighted collection is visible
## without unfolding the tree by hand.
func _expand_ancestors(item: TreeItem) -> void:
	var ancestor := item.get_parent()
	var root := _tree.get_root()
	while ancestor != null and ancestor != root:
		ancestor.set_collapsed(false)
		ancestor = ancestor.get_parent()


func _add_placeholder(parent: TreeItem, text: String) -> void:
	var ph := _tree.create_item(parent)
	ph.set_text(0, text)
	ph.set_selectable(0, false)
	ph.set_custom_color(0, AppTheme.TEXT_DIM)
	ph.set_metadata(0, {META_TYPE: "placeholder"})
