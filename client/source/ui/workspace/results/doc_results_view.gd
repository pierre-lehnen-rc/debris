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

var _doc_menu: PopupMenu
var _menu_doc_index := -1
var _menu_item: TreeItem


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
	_doc_menu.add_item("Edit Document…", DocAction.EDIT)
	_doc_menu.add_item("View Document", DocAction.VIEW)
	_doc_menu.add_item("Insert Document…", DocAction.INSERT)
	_doc_menu.add_separator()
	if not is_document:
		_doc_menu.add_item("Copy Name", DocAction.COPY_NAME)
		_doc_menu.add_item("Copy Path", DocAction.COPY_PATH)
	# "Copy JSON" for containers (objects/arrays); "Copy Value" for scalars.
	_doc_menu.add_item("Copy JSON" if has_children else "Copy Value", DocAction.COPY_JSON)
	_doc_menu.add_separator()
	_doc_menu.add_item("Delete Document", DocAction.DELETE)
	_doc_menu.reset_size()
	_doc_menu.position = Vector2i(get_global_mouse_position())
	_doc_menu.popup()


func _on_doc_action(id: int) -> void:
	if _menu_doc_index < 0:
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


# Keyboard navigation ---------------------------------------------------------
func _on_gui_input(event: InputEvent) -> void:
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
## Recognise an Extended JSON date wrapper and return its Unix time in
## milliseconds, or null when `value` is not a date. Handles the canonical form
## ({ "$date": { "$numberLong": "ms" } }) the server emits, the relaxed numeric
## form and the relaxed ISO-8601 string form.
func _ejson_date_ms(value: Variant) -> Variant:
	if not (value is Dictionary):
		return null
	var dict: Dictionary = value
	if dict.size() != 1 or not dict.has("$date"):
		return null
	var inner: Variant = dict["$date"]
	if inner is Dictionary and (inner as Dictionary).has("$numberLong"):
		return int((inner as Dictionary)["$numberLong"])
	if inner is float or inner is int:
		return int(inner)
	if inner is String:
		return int(Time.get_unix_time_from_datetime_string(inner) * 1000.0)
	return null


func _is_date(value: Variant) -> bool:
	return _ejson_date_ms(value) != null


## Format an Extended JSON date as a human-readable UTC string.
func _format_date(value: Variant) -> String:
	var ms: Variant = _ejson_date_ms(value)
	if ms == null:
		return ""
	return Time.get_datetime_string_from_unix_time(int(ms) / 1000, true) + " UTC"


# Value formatting ------------------------------------------------------------
func _preview(value: Variant) -> String:
	if _is_date(value):
		return _format_date(value)
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
	if _is_date(value):
		return "Date"
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
	if _is_date(value):
		return AppTheme.ACCENT
	if value is String:
		return AppTheme.ACCENT_GREEN
	if value is bool or value is int or value is float:
		return AppTheme.ACCENT
	return AppTheme.TEXT
