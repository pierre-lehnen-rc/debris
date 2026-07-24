class_name DocResultsView
extends Tree

## Shared behaviour for the document-bearing result views (tree and table).
## Subclasses implement display() to render a page of documents into the Tree;
## this base owns the right-click context menu, clipboard copy actions and the
## value formatting helpers. Edit/view/insert/delete are surfaced as signals so
## the owning ResultsView (which holds the document array and the dialog) stays
## the single source of truth for mutations.

signal edit_requested(doc_index: int)
signal view_requested(doc_index: int)
signal insert_requested()
signal delete_requested(doc_index: int)
## Emitted when a schema-defined custom type action is triggered, asking the owner
## to open a new query tab on `collection` filtered by `filter`.
signal open_query_requested(collection: String, filter: Dictionary, function: String)

enum DocAction {
	EXPAND_RECURSIVE,
	COLLAPSE_RECURSIVE,
	EDIT,
	VIEW,
	INSERT,
	COPY_NAME,
	COPY_PATH,
	COPY_JSON,
	DELETE,
}

## Custom type actions are added to the context menu with ids offset by this base
## so they never collide with the fixed DocAction ids.
const CUSTOM_ACTION_BASE := 1000

var _doc_menu: PopupMenu
var _menu_doc_index := -1
var _menu_item: TreeItem

## When set, top-level rows render as activity-log entries (see the tree view) and
## the context menu drops the Insert/Edit actions, since log entries aren't
## editable documents. Delete stays available.
var _log_mode := false

## When set (endpoint results in a project that also has a database attached),
## string values offer the schema's "Unknown Type" search actions even though this
## view has no collection of its own — the cross-browser handoff.
var _cross_query := false

# Schema-driven custom types/actions ------------------------------------------
## Schema resolving custom types for the collection currently displayed, and the
## collection name itself. Set via set_type_context(); null/"" disables the feature.
var _schema: DatabaseSchema = null
var _collection := ""
## Flat registry of the custom actions currently offered by the open context menu.
## Each entry is { "action": Dictionary, "source": Variant }; a menu item's id is
## CUSTOM_ACTION_BASE + its index here, so items in the main menu and any dynamic
## sub-menus share one id-space and one handler.
var _menu_action_entries: Array = []
## Sub-menu PopupMenus built for the current open (one per typed attribute), freed
## before the next open.
var _custom_submenus: Array = []

# Column resizing -------------------------------------------------------------
## Godot's Tree has no built-in interactive column resize, so we implement it by
## hand: dragging the boundary between two column headers sets a custom width on
## the left column. RESIZE_GRAB is how close (px) the cursor must be to a
## boundary to grab it; MIN_COL_WIDTH floors the result.
const RESIZE_GRAB := 6.0
const MIN_COL_WIDTH := 40
var _resizing_col := -1
var _resize_start_x := 0.0
var _resize_start_width := 0


func _ready() -> void:
	_doc_menu = PopupMenu.new()
	_doc_menu.theme = AppTheme.shared()
	_doc_menu.id_pressed.connect(_on_doc_action)
	add_child(_doc_menu)

	item_mouse_selected.connect(_on_doc_mouse_selected)
	gui_input.connect(_on_gui_input)
	item_activated.connect(_on_item_activated)

	_ready_view()


## Override hook: subclass setup that must run once after the base is wired
## (e.g. column titles). Called at the end of _ready().
func _ready_view() -> void:
	pass


## Set the schema + collection used to resolve custom types/actions. Subclasses
## may read _schema/_collection (e.g. the tree's Type column) after this is set.
func set_type_context(schema: DatabaseSchema, collection: String) -> void:
	_schema = schema
	_collection = collection


## Toggle activity-log rendering. The Activity Log tab enables it via ResultsView;
## subclasses read _log_mode when rendering rows and the base uses it to hide the
## Insert/Edit context-menu actions.
func set_log_mode(enabled: bool) -> void:
	_log_mode = enabled


## Allow the schema's cross-query search actions on this view's string values even
## when it has no collection of its own (endpoint results). Set by the workspace
## center on an endpoint results view when the project also has a DB.
func set_cross_query_enabled(enabled: bool) -> void:
	_cross_query = enabled


## The custom type name for a value at `field_path` in the current collection, or
## "" when no schema/collection/rule applies. field_path == "" is the document.
func _resolve_type(field_path: String, value: Variant) -> String:
	if _schema == null or _collection.is_empty():
		return ""
	return _schema.type_for(_collection, field_path, value)


## Override: render a page of documents. `start_index` is the absolute index of
## the first document so rows can carry their real position for edit/delete.
func display(_documents: Array, _start_index: int) -> void:
	pass


# Context menu ----------------------------------------------------------------
func _on_doc_mouse_selected(_pos: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return
	var item := get_selected()
	if item == null:
		return
	_menu_item = item
	_menu_doc_index = _doc_index_from_item(item)
	if _menu_doc_index < 0:
		return

	var is_document := item.get_parent() == get_root()
	var has_children := item.get_child_count() > 0

	_doc_menu.clear()
	if has_children:
		_doc_menu.add_item("Expand Recursively", DocAction.EXPAND_RECURSIVE)
		_doc_menu.set_item_accelerator(
			_doc_menu.get_item_index(DocAction.EXPAND_RECURSIVE), KEY_MASK_ALT | KEY_RIGHT
		)
		_doc_menu.add_item("Collapse Recursively", DocAction.COLLAPSE_RECURSIVE)
		_doc_menu.set_item_accelerator(
			_doc_menu.get_item_index(DocAction.COLLAPSE_RECURSIVE), KEY_MASK_ALT | KEY_LEFT
		)
		_doc_menu.add_separator()
	if not _log_mode:
		_doc_menu.add_item("Edit Document…", DocAction.EDIT)
	_doc_menu.add_item("View Document", DocAction.VIEW)
	if not _log_mode:
		_doc_menu.add_item("Insert Document…", DocAction.INSERT)
	_doc_menu.add_separator()
	if not is_document:
		_doc_menu.add_item("Copy Name", DocAction.COPY_NAME)
		_doc_menu.add_item("Copy Path", DocAction.COPY_PATH)
	# "Copy JSON" for containers (objects/arrays); "Copy Value" for scalars.
	_doc_menu.add_item("Copy JSON" if has_children else "Copy Value", DocAction.COPY_JSON)
	_doc_menu.add_separator()
	_doc_menu.add_item("Delete Document", DocAction.DELETE)
	_add_custom_actions(item, is_document)
	_doc_menu.reset_size()
	# Native pop-ups position in absolute screen coordinates.
	_doc_menu.position = DisplayServer.mouse_get_position()
	_doc_menu.popup()


## Append schema-defined custom actions to the context menu. For a document row,
## each of its typed attributes becomes a sub-menu (named by the field path)
## holding that type's actions, resolved against the attribute's value — e.g. a
## user document shows "_id › List User's Messages". Any whole-document type's
## actions are still added inline. For a field row, that field's type actions are
## added inline (right-clicking the attribute directly).
func _add_custom_actions(item: TreeItem, is_document: bool) -> void:
	_clear_custom_menus()
	if _schema == null:
		return
	# A results view with a collection resolves typed fields normally. Endpoint
	# results have no collection of their own, but when a database is attached
	# (_cross_query) their string values still offer the schema's "Unknown Type"
	# search actions — the cross-browser handoff.
	if _collection.is_empty() and not _cross_query:
		return
	var meta: Variant = item.get_metadata(0)
	if not (meta is Dictionary):
		return
	var value: Variant = (meta as Dictionary).get("value")
	if is_document:
		_add_document_type_menus(value)
	else:
		# Prefer the index-free path stored in metadata (so array elements resolve to
		# their parent's field path, e.g. "mentions._id"); fall back to the bracketed
		# path only if it's absent.
		var field_path: String = str((meta as Dictionary).get("path", ""))
		if field_path.is_empty():
			field_path = _meta_path(item)
		var type_name := _resolve_type(field_path, value)
		if not type_name.is_empty():
			_add_inline_actions(type_name, value)
		elif value is String:
			# An untyped string: let the user reinterpret it as any known id type
			# and search other collections by that value.
			_add_unknown_type_menu(value)


## Whole-document type actions inline, then a sub-menu per typed attribute.
func _add_document_type_menus(doc: Variant) -> void:
	if not (doc is Dictionary):
		return
	_add_inline_actions(_resolve_type("", doc), doc)
	for entry in _schema.typed_fields(_collection):
		var field_path: String = entry["field"]
		var field_value: Variant = DatabaseSchema.value_at_path(doc, field_path)
		if field_value == null:
			continue
		# A path that dug through arrays but found nothing yields an empty list — no
		# values to search by, so skip the attribute entirely.
		if field_value is Array and (field_value as Array).is_empty():
			continue
		var actions := _schema.actions_for_type(entry["type"])
		if not actions.is_empty():
			_add_actions_submenu(field_path, actions, field_value)


## Add a type's actions straight into the main menu, acting on `source`.
func _add_inline_actions(type_name: String, source: Variant) -> void:
	if type_name.is_empty():
		return
	var actions := _schema.actions_for_type(type_name)
	if actions.is_empty():
		return
	_doc_menu.add_separator()
	for action in actions:
		_doc_menu.add_item(_action_label(action), CUSTOM_ACTION_BASE + _register_entry(action, source))


## Add a `label` sub-menu to the main menu holding `actions`, each acting on `source`.
func _add_actions_submenu(label: String, actions: Array, source: Variant) -> void:
	var submenu := _make_submenu()
	for action in actions:
		submenu.add_item(_action_label(action), CUSTOM_ACTION_BASE + _register_entry(action, source))
	_doc_menu.add_submenu_node_item(label, submenu)


## Offer an "Unknown Type" sub-menu on an untyped string: one sub-menu per known
## scalar type (UserId, RoomId, …), each holding that type's actions resolved
## against `value`, so the string can be searched for as if it were that type.
func _add_unknown_type_menu(value: Variant) -> void:
	if _schema == null:
		return
	var root := _make_submenu()
	for type_name in _schema.scalar_types():
		var actions := _schema.actions_for_type(type_name)
		if actions.is_empty():
			continue
		var type_menu := _make_submenu()
		for action in actions:
			type_menu.add_item(_action_label(action), CUSTOM_ACTION_BASE + _register_entry(action, value))
		root.add_submenu_node_item(type_name, type_menu)
	if root.get_item_count() == 0:
		return  # No usable scalar types; leave the menu unchanged (root is freed on next open).
	_doc_menu.add_separator()
	_doc_menu.add_submenu_node_item("Unknown Type", root)


## Create a themed sub-menu wired to the shared action handler and tracked for
## cleanup. Not yet parented; add it via add_submenu_node_item on its owner.
func _make_submenu() -> PopupMenu:
	var submenu := PopupMenu.new()
	submenu.theme = AppTheme.shared()
	submenu.id_pressed.connect(_on_doc_action)
	_custom_submenus.append(submenu)
	return submenu


## Record an action + its source value, returning its index in the flat registry.
func _register_entry(action: Dictionary, source: Variant) -> int:
	_menu_action_entries.append({"action": action, "source": source})
	return _menu_action_entries.size() - 1


func _action_label(action: Dictionary) -> String:
	return str(action.get("label", action.get("id", "Action")))


## Drop the previous open's action registry and free its dynamic sub-menus.
func _clear_custom_menus() -> void:
	_menu_action_entries.clear()
	for submenu in _custom_submenus:
		if is_instance_valid(submenu):
			submenu.queue_free()
	_custom_submenus.clear()


func _on_doc_action(id: int) -> void:
	if _menu_doc_index < 0:
		return
	if id >= CUSTOM_ACTION_BASE:
		_trigger_custom_action(id - CUSTOM_ACTION_BASE)
		return
	match id:
		DocAction.EXPAND_RECURSIVE:
			_set_collapsed_recursive(_menu_item, false)
		DocAction.COLLAPSE_RECURSIVE:
			_set_collapsed_recursive(_menu_item, true)
		DocAction.EDIT:
			edit_requested.emit(_menu_doc_index)
		DocAction.VIEW:
			view_requested.emit(_menu_doc_index)
		DocAction.INSERT:
			insert_requested.emit()
		DocAction.COPY_NAME:
			DisplayServer.clipboard_set(_meta_name(_menu_item))
		DocAction.COPY_PATH:
			DisplayServer.clipboard_set(_meta_path(_menu_item))
		DocAction.COPY_JSON:
			DisplayServer.clipboard_set(_meta_json(_menu_item))
		DocAction.DELETE:
			delete_requested.emit(_menu_doc_index)


## Resolve a registered action's filter template against its recorded source value
## and ask the owner to open a new query tab on the action's target collection.
func _trigger_custom_action(index: int) -> void:
	if index < 0 or index >= _menu_action_entries.size():
		return
	var entry: Dictionary = _menu_action_entries[index]
	var action: Dictionary = entry["action"]
	var template: Variant = action.get("filter", {})
	var filter: Dictionary = template if template is Dictionary else {}
	var resolved := DatabaseSchema.resolve_filter(filter, entry["source"])
	open_query_requested.emit(
		str(action.get("target_collection", _collection)),
		resolved,
		str(action.get("function", "find")),
	)


# Input handling --------------------------------------------------------------
func _on_gui_input(event: InputEvent) -> void:
	if _handle_resize_input(event):
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not (key_event.pressed and key_event.alt_pressed):
		return
	var item := get_selected()
	if item == null:
		return
	if key_event.keycode == KEY_RIGHT:
		_set_collapsed_recursive(item, false)
		accept_event()
	elif key_event.keycode == KEY_LEFT:
		_collapse_or_select_parent(item)
		accept_event()


## Intercept mouse events for column-boundary dragging. Returns true when the
## event was consumed (so the keyboard handler is skipped). The drag begins on a
## left-click within RESIZE_GRAB of a header boundary, runs while the button is
## held, and updates the cursor to a horizontal-resize arrow on hover.
func _handle_resize_input(event: InputEvent) -> bool:
	if not are_column_titles_visible() or columns <= 1:
		return false

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return false
		if mb.pressed:
			var col := _column_boundary_at(mb.position)
			if col >= 0:
				_resizing_col = col
				_resize_start_x = mb.position.x
				_resize_start_width = get_column_width(col)
				accept_event()
				return true
		elif _resizing_col >= 0:
			_resizing_col = -1
			accept_event()
			return true
		return false

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _resizing_col >= 0:
			var delta := mm.position.x - _resize_start_x
			var new_width := maxi(MIN_COL_WIDTH, _resize_start_width + int(delta))
			set_column_expand(_resizing_col, false)
			set_column_custom_minimum_width(_resizing_col, new_width)
			accept_event()
			return true
		# Not dragging: show a resize cursor when hovering a boundary.
		mouse_default_cursor_shape = (
			CURSOR_HSIZE if _column_boundary_at(mm.position) >= 0 else CURSOR_ARROW
		)
		return false

	return false


## Return the column whose right edge is within RESIZE_GRAB pixels of `pos`, but
## only while the cursor is over the header row. Returns -1 otherwise. The last
## column's boundary is ignored (resizing it has no neighbour to give space to).
func _column_boundary_at(pos: Vector2) -> int:
	if pos.y < 0.0 or pos.y > _title_height():
		return -1
	var panel := get_theme_stylebox("panel")
	var x := panel.get_content_margin(SIDE_LEFT) - get_scroll().x
	for col in columns - 1:
		x += get_column_width(col)
		if absf(pos.x - x) <= RESIZE_GRAB:
			return col
	return -1


## Height of the clickable header row, or 0 when titles are hidden.
func _title_height() -> float:
	if not are_column_titles_visible():
		return 0.0
	var sb := get_theme_stylebox("title_button_normal")
	var font := get_theme_font("title_button_font")
	var fs := get_theme_font_size("title_button_font_size")
	return font.get_height(fs) + sb.get_minimum_size().y


func _on_item_activated() -> void:
	# Double-click (or Enter) on an object/array row toggles it non-recursively.
	var item := get_selected()
	if item != null and item.get_child_count() > 0:
		item.set_collapsed(not item.is_collapsed())


func _collapse_or_select_parent(item: TreeItem) -> void:
	# Alt+Left collapses an expanded object; on an already-collapsed object (or a
	# leaf) it walks the selection up to the parent row instead, so repeated
	# presses climb the tree a level at a time before collapsing it.
	if item.get_child_count() > 0 and not item.is_collapsed():
		_set_collapsed_recursive(item, true)
		return
	var parent := item.get_parent()
	if parent != null and parent != get_root():
		parent.select(0)
		scroll_to_item(parent)


func _set_collapsed_recursive(item: TreeItem, collapsed: bool) -> void:
	item.set_collapsed(collapsed)
	var child := item.get_first_child()
	while child != null:
		_set_collapsed_recursive(child, collapsed)
		child = child.get_next()


# Metadata helpers ------------------------------------------------------------
func _doc_index_from_item(item: TreeItem) -> int:
	# Climb to the top-level ancestor (whose parent is the hidden root), which
	# carries the document index in its metadata.
	var root := get_root()
	var cur := item
	while cur != null and cur.get_parent() != root:
		cur = cur.get_parent()
	if cur == null:
		return -1
	var meta: Variant = cur.get_metadata(0)
	if meta is Dictionary:
		return int(meta.get("doc_index", -1))
	return -1


func _meta_name(item: TreeItem) -> String:
	var meta: Variant = item.get_metadata(0)
	if meta is Dictionary:
		return str(meta.get("name", meta.get("key", "")))
	return ""


func _meta_json(item: TreeItem) -> String:
	var meta: Variant = item.get_metadata(0)
	if meta is Dictionary and meta.has("value"):
		return JSON.stringify(meta["value"], "  ")
	return ""


func _meta_path(item: TreeItem) -> String:
	# Build a dotted path from the document root down to the selected field,
	# e.g. "address.city" or "roles[0]". The document item itself contributes
	# nothing (its key is empty).
	var root := get_root()
	var parts: Array[String] = []
	var cur := item
	while cur != null and cur.get_parent() != root:
		var meta: Variant = cur.get_metadata(0)
		if meta is Dictionary:
			parts.push_front(str(meta.get("key", "")))
		cur = cur.get_parent()

	var path := ""
	for p in parts:
		if p.begins_with("["):
			path += p
		elif path.is_empty():
			path = p
		else:
			path += "." + p
	return path


# Extended JSON helpers -------------------------------------------------------
## Recognise an Extended JSON / BSON type wrapper and return a
## { "type": String, "text": String } preview for it, or {} when `value` is a
## plain object. This keeps the tree/table views from drilling into BSON
## wrappers ({"$oid": …}, {"$numberInt": …}, …); they show the underlying scalar
## with its real type instead. The number wrappers carry numeric flag so the
## colouring can match plain numbers.
func _ejson_scalar(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var dict: Dictionary = value

	# Single-key scalar wrappers.
	if dict.size() == 1:
		if dict.has("$oid"):
			return {"type": "ObjectId", "text": str(dict["$oid"])}
		if dict.has("$numberInt"):
			return {"type": "Int32", "text": str(dict["$numberInt"]), "numeric": true}
		if dict.has("$numberLong"):
			return {"type": "Int64", "text": str(dict["$numberLong"]), "numeric": true}
		if dict.has("$numberDouble"):
			return {"type": "Double", "text": str(dict["$numberDouble"]), "numeric": true}
		if dict.has("$numberDecimal"):
			return {"type": "Decimal128", "text": str(dict["$numberDecimal"]), "numeric": true}
		if dict.has("$date"):
			return {"type": "Date", "text": _format_date(value)}
		if dict.has("$symbol"):
			return {"type": "Symbol", "text": str(dict["$symbol"])}
		if dict.has("$timestamp"):
			return {"type": "Timestamp", "text": _format_timestamp(dict["$timestamp"])}
		if dict.has("$regularExpression"):
			return {"type": "Regex", "text": _format_regex(dict["$regularExpression"])}
		if dict.has("$binary"):
			return {"type": "Binary", "text": _format_binary(dict["$binary"])}
		if dict.has("$undefined"):
			return {"type": "Undefined", "text": "undefined"}
		if dict.has("$minKey"):
			return {"type": "MinKey", "text": "MinKey"}
		if dict.has("$maxKey"):
			return {"type": "MaxKey", "text": "MaxKey"}

	# Multi-key wrappers.
	if dict.has("$ref") and dict.has("$id"):
		return {"type": "DBRef", "text": "%s(%s)" % [str(dict["$ref"]), _scalar_text(dict["$id"])]}
	if dict.has("$code"):
		return {"type": "JavaScript", "text": str(dict["$code"])}

	return {}


## Extract the milliseconds from an Extended JSON $date value (canonical
## {"$numberLong"}, relaxed number, or ISO-8601 string), or null.
func _ejson_date_ms(value: Variant) -> Variant:
	if not (value is Dictionary):
		return null
	var dict: Dictionary = value
	if not dict.has("$date"):
		return null
	var inner: Variant = dict["$date"]
	if inner is Dictionary and (inner as Dictionary).has("$numberLong"):
		return int((inner as Dictionary)["$numberLong"])
	if inner is float or inner is int:
		return int(inner)
	if inner is String:
		return int(Time.get_unix_time_from_datetime_string(inner) * 1000.0)
	return null


## Format an Extended JSON date as a human-readable UTC string.
func _format_date(value: Variant) -> String:
	var ms: Variant = _ejson_date_ms(value)
	if ms == null:
		return ""
	return Time.get_datetime_string_from_unix_time(int(ms) / 1000, true) + " UTC"


func _format_timestamp(value: Variant) -> String:
	if value is Dictionary:
		return "%s:%s" % [_scalar_text(value.get("t", 0)), _scalar_text(value.get("i", 0))]
	return str(value)


func _format_regex(value: Variant) -> String:
	if value is Dictionary:
		return "/%s/%s" % [str(value.get("pattern", "")), str(value.get("options", ""))]
	return str(value)


func _format_binary(value: Variant) -> String:
	if value is Dictionary:
		return "Binary(0x%s)" % str(value.get("subType", "00"))
	return str(value)


## Render a possibly-wrapped scalar (e.g. a $numberInt nested in a $timestamp or
## $id) to plain text.
func _scalar_text(value: Variant) -> String:
	var scalar := _ejson_scalar(value)
	return scalar["text"] if not scalar.is_empty() else str(value)


# Value formatting ------------------------------------------------------------
func _preview(value: Variant) -> String:
	var scalar := _ejson_scalar(value)
	if not scalar.is_empty():
		return scalar["text"]
	if value is Dictionary:
		return "{%d fields}" % value.size()
	if value is Array:
		return "[%d elements]" % value.size()
	if value is String:
		return value
	if value is bool:
		return "true" if value else "false"
	return str(value)


func _type_name(value: Variant) -> String:
	var scalar := _ejson_scalar(value)
	if not scalar.is_empty():
		return scalar["type"]
	if value is Dictionary:
		return "Object"
	if value is Array:
		return "Array"
	if value is bool:
		return "Boolean"
	if value is int:
		return "Int32"
	if value is float:
		return "Double"
	if value is String:
		return "String"
	return "Null"


func _value_color(value: Variant) -> Color:
	var scalar := _ejson_scalar(value)
	if not scalar.is_empty():
		return AppTheme.ACCENT if scalar.get("numeric", false) else AppTheme.TEXT_BRIGHT
	if value is String:
		return AppTheme.ACCENT_GREEN
	if value is bool or value is int or value is float:
		return AppTheme.ACCENT
	return AppTheme.TEXT
