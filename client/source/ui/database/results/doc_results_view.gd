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
## Emitted when the "Sort by this field" action is chosen on a scalar attribute,
## asking the owner (QueryTab) to fold `field` into the query's sort options with
## `direction` (1 ascending, -1 descending).
signal sort_requested(field: String, direction: int)

enum DocAction {
	EXPAND_RECURSIVE,
	COLLAPSE_RECURSIVE,
	EDIT,
	VIEW,
	INSERT,
	COPY_NAME,
	COPY_PATH,
	COPY_JSON,
	# Date values offer a "Copy Value" sub-menu with these three formats instead of
	# a single Copy Value.
	COPY_DATE_STRING,  # the rendered UTC string
	COPY_DATE_UNIX,  # milliseconds since the Unix epoch
	COPY_DATE_EJSON,  # canonical Extended JSON, for pasting into a date query
	DELETE,
	SORT_ASC,  # fold this attribute into the query's sort options, ascending
	SORT_DESC,  # …descending
}

## Custom type actions are added to the context menu with ids offset by this base
## so they never collide with the fixed DocAction ids.
const CUSTOM_ACTION_BASE := 1000
## Copy-value menu items (Copy _id, and the per-attribute Copy) are offset by this
## larger base, above any custom-action id, into a separate copy-text registry.
const COPY_ENTRY_BASE := 100000

var _doc_menu: PopupMenu
var _menu_doc_index := -1
var _menu_item: TreeItem

## When set, top-level rows render as activity-log entries (see the tree view) and
## the context menu drops the Insert/Edit actions, since log entries aren't
## editable documents. Delete stays available.
var _log_mode := false

## When set (endpoint results), the view renders a raw response body rather than a
## page of documents: rows aren't editable documents, so the context menu drops
## Edit/Insert/Delete, and typed actions resolve against the per-row entity object
## carried in metadata ("type_doc") instead of climbing to a top-level document.
var _raw_mode := false

## When set (endpoint results in a project that also has a database attached),
## string values offer the schema's "Unknown Type" search actions even though this
## view has no collection of its own — the cross-browser handoff.
var _cross_query := false

# Schema-driven custom types/actions ------------------------------------------
## Schema resolving custom types for the collection currently displayed, and the
## collection name itself. Set via set_type_context(); null/"" disables the feature.
var _schema: DatabaseSchema = null
var _collection := ""
## Whether this view owns `_collection` as its own queryable collection (the DB
## side) versus borrowing it only to type endpoint response rows (the API side).
## Type display works either way; a borrowed collection offers the schema's
## DB-targeting actions only when cross-querying is enabled (a database is bound).
var _owns_collection := true
## Flat registry of the custom actions currently offered by the open context menu.
## Each entry is { "action": Dictionary, "source": Variant }; a menu item's id is
## CUSTOM_ACTION_BASE + its index here, so items in the main menu and any dynamic
## sub-menus share one id-space and one handler.
var _menu_action_entries: Array = []
## Sub-menu PopupMenus built for the current open (one per typed attribute), freed
## before the next open.
var _custom_submenus: Array = []
## Precomputed clipboard text for the open menu's copy items (Copy _id, per-attribute
## Copy); a menu item's id is COPY_ENTRY_BASE + its index here. Cleared each open.
var _menu_copy_entries: Array = []

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
## `owns` is false when `collection` is borrowed only to type endpoint rows (the
## API side), which keeps type display on but gates the DB-targeting actions on
## cross-querying being enabled.
func set_type_context(schema: DatabaseSchema, collection: String, owns := true) -> void:
	_schema = schema
	_collection = collection
	_owns_collection = owns


## Toggle activity-log rendering. The Activity Log tab enables it via ResultsView;
## subclasses read _log_mode when rendering rows and the base uses it to hide the
## Insert/Edit context-menu actions.
func set_log_mode(enabled: bool) -> void:
	_log_mode = enabled


## Toggle raw-response rendering (endpoint results). Drives the context menu to
## drop document mutations and resolve typed actions per row (see _raw_mode).
func set_raw_mode(enabled: bool) -> void:
	_raw_mode = enabled


## Allow the schema's cross-query search actions on this view's string values even
## when it has no collection of its own (endpoint results). Set by the workspace
## center on an endpoint results view when the project also has a DB.
func set_cross_query_enabled(enabled: bool) -> void:
	_cross_query = enabled


## The custom type name for the value at `field_path` in the current collection, or
## "" when no schema/collection/rule applies. field_path == "" is the document.
## `doc` is the whole document the field lives in — the schema needs it to judge a
## value-dependent (`when`) rule, e.g. a media-call actor's id whose type follows
## its sibling `type`. Pass the document itself when resolving the document type.
func _resolve_type(field_path: String, doc: Variant) -> String:
	if _schema == null or _collection.is_empty():
		return ""
	return _schema.type_for(_collection, field_path, doc)


## The whole document a `TreeItem` belongs to: climb to its top-level ancestor
## (whose parent is the hidden root) and read the `value` its metadata carries.
## Returns null when there is no such ancestor or metadata.
func _doc_from_item(item: TreeItem) -> Variant:
	var root := get_root()
	var cur := item
	while cur != null and cur.get_parent() != root:
		cur = cur.get_parent()
	if cur == null:
		return null
	var meta: Variant = cur.get_metadata(0)
	if meta is Dictionary:
		return (meta as Dictionary).get("value")
	return null


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
	# Free the previous open's dynamic sub-menus up front, so any built below (a
	# date's Copy Value sub-menu, the custom-action sub-menus) survive this open.
	_clear_custom_menus()
	# Raw responses (endpoints) have no editable documents, so there's no doc index
	# to resolve or require; document mutations are dropped from the menu below.
	_menu_doc_index = -1 if _raw_mode else _doc_index_from_item(item)
	if not _raw_mode and _menu_doc_index < 0:
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
	# Document mutations only apply to editable document pages, not raw responses
	# or activity-log entries.
	if not _raw_mode:
		if not _log_mode:
			_doc_menu.add_item("Edit Document…", DocAction.EDIT)
		_doc_menu.add_item("View Document", DocAction.VIEW)
		if not _log_mode:
			_doc_menu.add_item("Insert Document…", DocAction.INSERT)
		_doc_menu.add_separator()
	if not is_document:
		_doc_menu.add_item("Copy Name", DocAction.COPY_NAME)
		_doc_menu.add_item("Copy Path", DocAction.COPY_PATH)
	var value: Variant = (item.get_metadata(0) as Dictionary).get("value") if item.get_metadata(0) is Dictionary else null
	if _ejson_date_ms(value) != null:
		# A date offers three copy formats: the rendered string, the raw Unix
		# milliseconds, and canonical Extended JSON for pasting into a date query.
		var submenu := _make_submenu()
		submenu.add_item("Date String", DocAction.COPY_DATE_STRING)
		submenu.add_item("Unix Timestamp (ms)", DocAction.COPY_DATE_UNIX)
		submenu.add_item("Extended JSON (for queries)", DocAction.COPY_DATE_EJSON)
		_doc_menu.add_submenu_node_item("Copy Value", submenu)
	else:
		# "Copy JSON" for containers (objects/arrays); "Copy Value" for scalars.
		_doc_menu.add_item("Copy JSON" if has_children else "Copy Value", DocAction.COPY_JSON)
	# Any object carrying an id (a document or a nested object attribute) offers a
	# quick "Copy _id" right next to Copy JSON.
	var id_key := _id_key_of(value)
	if not id_key.is_empty():
		_doc_menu.add_item(
			"Copy %s" % id_key,
			COPY_ENTRY_BASE + _register_copy(_copy_text_for((value as Dictionary)[id_key])),
		)
	# Scalar attributes of this view's own DB collection can be folded into the
	# query's sort options (ascending/descending). Objects, arrays, whole documents
	# and borrowed/raw rows don't qualify.
	if _can_sort(is_document, value):
		var sort_menu := _make_submenu()
		sort_menu.add_item("Ascending", DocAction.SORT_ASC)
		sort_menu.add_item("Descending", DocAction.SORT_DESC)
		_doc_menu.add_separator()
		_doc_menu.add_submenu_node_item("Sort by this field", sort_menu)
	if not _raw_mode:
		_doc_menu.add_separator()
		_doc_menu.add_item("Delete Document", DocAction.DELETE)
	_add_custom_actions(item, is_document)
	UiScale.prepare(_doc_menu)
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
	# The dynamic sub-menu registry is already cleared per open in
	# _on_doc_mouse_selected, so this only appends.
	if _schema == null:
		return
	# The DB side owns its collection, so its rows always offer the schema's
	# actions. Endpoint results only borrow a collection to type their fields, so
	# their DB-targeting actions (and the "Unknown Type" handoff on plain strings)
	# appear only when a database is attached (_cross_query) — the type display in
	# the Type column, driven separately by _resolve_type, is unaffected either way.
	if not _cross_query and not (_owns_collection and not _collection.is_empty()):
		return
	var meta: Variant = item.get_metadata(0)
	if not (meta is Dictionary):
		return
	var value: Variant = (meta as Dictionary).get("value")
	# A document row (DB page) expands into a sub-menu per typed attribute.
	if is_document and not _raw_mode:
		_add_object_type_menus(value, "")
		return
	# The document the field's type resolves against: in raw mode the entity object
	# carried per-row ("type_doc", null for envelope-level rows); otherwise the
	# whole document reached by climbing to the top-level row.
	var doc: Variant = (meta as Dictionary).get("type_doc") if _raw_mode else _doc_from_item(item)
	# Prefer the index-free path stored in metadata (so array elements resolve to
	# their parent's field path, e.g. "mentions._id"); fall back to the bracketed
	# path only if it's absent (DB rows only).
	var field_path: String = str((meta as Dictionary).get("path", ""))
	if field_path.is_empty() and not _raw_mode:
		field_path = _meta_path(item)
	# A nested object lists its own typed attributes too (plus its own type's inline
	# actions), so queries can be built from them just like on a top-level document.
	if doc != null and value is Dictionary and _ejson_scalar(value).is_empty():
		_add_object_type_menus(doc, field_path)
		return
	var type_name := _resolve_type(field_path, doc) if doc != null else ""
	if not type_name.is_empty():
		_add_inline_actions(type_name, value)
	elif value is String:
		# An untyped string: let the user reinterpret it as any known id type
		# and search other collections by that value.
		_add_unknown_type_menu(value)


## An object's type actions: its own type inline, then a sub-menu per typed
## attribute. `doc` is the document the object lives in and `base` its dotted path
## within it ("" when the object is the whole document). Only attributes at or under
## `base` are listed, each labelled relative to the object (so a nested "u" object
## shows "_id ›", not "u._id ›"). Types resolve against `doc`, so a value-dependent
## field (e.g. an actor's id) offers the actions matching this document's data.
func _add_object_type_menus(doc: Variant, base: String) -> void:
	if not (doc is Dictionary):
		return
	var own_value: Variant = doc if base.is_empty() else DatabaseSchema.value_at_path(doc, base)
	_add_inline_actions(_resolve_type(base, doc), own_value)
	var prefix := "" if base.is_empty() else base + "."
	for entry in _schema.typed_fields(_collection):
		var field_path: String = entry["field"]
		if not prefix.is_empty() and not field_path.begins_with(prefix):
			continue
		var field_value: Variant = DatabaseSchema.value_at_path(doc, field_path)
		if field_value == null:
			continue
		# A path that dug through arrays but found nothing yields an empty list — no
		# values to search by, so skip the attribute entirely.
		if field_value is Array and (field_value as Array).is_empty():
			continue
		var field_type := _resolve_type(field_path, doc)
		if field_type.is_empty():
			continue
		var actions := _schema.actions_for_type(field_type)
		if not actions.is_empty():
			_add_actions_submenu(field_path.substr(prefix.length()), actions, field_value)


## Add a type's actions straight into the main menu, acting on `source`.
func _add_inline_actions(type_name: String, source: Variant) -> void:
	if type_name.is_empty():
		return
	var actions := _schema.actions_for_type(type_name)
	if actions.is_empty():
		return
	_doc_menu.add_separator()
	_add_grouped_actions(_doc_menu, actions, source)


## Add a `label` sub-menu to the main menu holding `actions`, each acting on `source`.
## The attribute's own value can also be copied straight from the sub-menu.
func _add_actions_submenu(label: String, actions: Array, source: Variant) -> void:
	var submenu := _make_submenu()
	submenu.add_item("Copy", COPY_ENTRY_BASE + _register_copy(_copy_text_for(source)))
	submenu.add_separator()
	_add_grouped_actions(submenu, actions, source)
	_doc_menu.add_submenu_node_item(label, submenu)


## Add `actions` into `menu`, grouping the auto-generated cross-collection
## "List <collection>" actions by their target collection: a collection reached
## through several typed fields collapses into one "List <collection>" sub-menu
## with a "by <field>" item each, while a collection with a single field stays a
## flat item. Manual actions (those without a target collection/field) render flat
## in place. `source` is the value every action resolves its filter against.
func _add_grouped_actions(menu: PopupMenu, actions: Array, source: Variant) -> void:
	var order: Array = []  # target collections in first-seen order.
	var groups: Dictionary = {}
	for action in actions:
		var collection := str(action.get("target_collection", ""))
		var field := str(action.get("field", ""))
		if collection.is_empty() or field.is_empty():
			menu.add_item(_action_label(action), CUSTOM_ACTION_BASE + _register_entry(action, source))
			continue
		if not groups.has(collection):
			groups[collection] = []
			order.append(collection)
		(groups[collection] as Array).append(action)
	for collection in order:
		var group: Array = groups[collection]
		if group.size() == 1:
			_add_grouped_leaf(menu, group[0], _action_label(group[0]), source)
			continue
		var submenu := _make_submenu()
		for action in group:
			_add_grouped_leaf(submenu, action, "by %s" % str((action as Dictionary).get("field", "")), source)
		var title := str((group[0] as Dictionary).get("group_label", _action_label(group[0])))
		menu.add_submenu_node_item(title, submenu)


## Add one action leaf into `menu` under `label`. An object-type "List by" action
## (pick_fields) becomes a checkable attribute-picker sub-menu; any other action is
## a plain item that runs immediately.
func _add_grouped_leaf(menu: PopupMenu, action: Dictionary, label: String, source: Variant) -> void:
	if action.get("pick_fields", false):
		_add_object_list_picker(menu, label, action, source)
	else:
		menu.add_item(label, CUSTOM_ACTION_BASE + _register_entry(action, source))


## A checkable sub-menu letting the user choose which of the object's attributes to
## query by. Each scalar attribute is a toggle (the type's identity, key_fields, is
## checked by default), and a final "List <collection>" item runs a find on the
## chosen attributes as dot-notation equality (order-insensitive, unlike matching
## the whole embedded object). The menu stays open while toggling.
func _add_object_list_picker(menu: PopupMenu, label: String, action: Dictionary, source: Variant) -> void:
	if not (source is Dictionary):
		return
	var keys := _scalar_keys(source)
	if keys.is_empty():
		return
	var defaults: Dictionary = {}
	for k in action.get("key_fields", []):
		defaults[str(k)] = true
	var picker := PopupMenu.new()
	picker.theme = AppTheme.shared()
	picker.hide_on_checkable_item_selection = false
	_custom_submenus.append(picker)
	for i in keys.size():
		picker.add_check_item(str(keys[i]), i + 1)
		picker.set_item_checked(i, defaults.has(str(keys[i])))
	picker.add_separator()
	picker.add_item(str(action.get("group_label", "List")), 0)  # id 0 = run
	picker.id_pressed.connect(_on_picker_pressed.bind(
		picker, keys, str(action.get("field", "")),
		source, str(action.get("target_collection", _collection)),
		str(action.get("function", "find")),
	))
	menu.add_submenu_node_item(label, picker)


## Handle a click in an attribute picker (id 0 runs the query; any other id toggles
## that attribute's checkbox and keeps the menu open).
func _on_picker_pressed(
	id: int, picker: PopupMenu, keys: Array, field: String,
	source: Variant, target: String, function: String
) -> void:
	if id != 0:
		var idx := picker.get_item_index(id)
		picker.set_item_checked(idx, not picker.is_item_checked(idx))
		return
	var filter: Dictionary = {}
	for i in keys.size():
		if picker.is_item_checked(picker.get_item_index(i + 1)):
			filter["%s.%s" % [field, str(keys[i])]] = (source as Dictionary)[keys[i]]
	open_query_requested.emit(target, filter, function)


## An object's scalar attribute names (in the object's own order) — the candidates
## for an attribute-picker query. Nested objects and arrays are skipped: matching
## them reintroduces the order-sensitive whole-object equality this avoids.
func _scalar_keys(obj: Variant) -> Array:
	var out: Array = []
	if not (obj is Dictionary):
		return out
	for k in obj:
		var v: Variant = (obj as Dictionary)[k]
		if (v is Dictionary and _ejson_scalar(v).is_empty()) or v is Array:
			continue
		out.append(k)
	return out


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
		_add_grouped_actions(type_menu, actions, value)
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
	_menu_copy_entries.clear()
	for submenu in _custom_submenus:
		if is_instance_valid(submenu):
			submenu.queue_free()
	_custom_submenus.clear()


func _on_doc_action(id: int) -> void:
	# Custom type actions, expand/collapse and copy don't need a document index (and
	# raw responses have none); only the document mutations below require one.
	if id >= COPY_ENTRY_BASE:
		var ci := id - COPY_ENTRY_BASE
		if ci >= 0 and ci < _menu_copy_entries.size():
			DisplayServer.clipboard_set(str(_menu_copy_entries[ci]))
		return
	if id >= CUSTOM_ACTION_BASE:
		_trigger_custom_action(id - CUSTOM_ACTION_BASE)
		return
	if _menu_doc_index < 0 and id in [DocAction.EDIT, DocAction.VIEW, DocAction.DELETE]:
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
			DisplayServer.clipboard_set(_meta_copy_text(_menu_item))
		DocAction.COPY_DATE_STRING:
			DisplayServer.clipboard_set(_scalar_text(_menu_value()))
		DocAction.COPY_DATE_UNIX:
			var ms: Variant = _ejson_date_ms(_menu_value())
			DisplayServer.clipboard_set(str(ms) if ms != null else "")
		DocAction.COPY_DATE_EJSON:
			DisplayServer.clipboard_set(JSON.stringify(_menu_value(), "  "))
		DocAction.DELETE:
			delete_requested.emit(_menu_doc_index)
		DocAction.SORT_ASC:
			_emit_sort(1)
		DocAction.SORT_DESC:
			_emit_sort(-1)


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


# Sort by attribute -----------------------------------------------------------
## Whether the "Sort by this field" action applies to the selected row: only a
## scalar attribute (not an object, array, or whole document) of this view's own DB
## collection. Borrowed (endpoint) and raw rows have no query options to sort.
func _can_sort(is_document: bool, value: Variant) -> bool:
	if is_document or _raw_mode or not _owns_collection or _collection.is_empty():
		return false
	if value is Array:
		return false
	# A real nested object isn't sortable; an EJSON scalar wrapper (ObjectId, date,
	# number) is a scalar and is.
	if value is Dictionary and _ejson_scalar(value).is_empty():
		return false
	return true


## Ask the owner to fold the selected attribute into the sort, at `direction`
## (1 ascending, -1 descending).
func _emit_sort(direction: int) -> void:
	if _menu_item == null:
		return
	var field := _sort_field_for(_menu_item)
	if not field.is_empty():
		sort_requested.emit(field, direction)


## The dotted, index-free field path of `item` for use as a Mongo sort key. Prefers
## the metadata "path" (already index-free); falls back to the built path with any
## array-index segments stripped ("roles[0]" -> "roles").
func _sort_field_for(item: TreeItem) -> String:
	var meta: Variant = item.get_metadata(0)
	var path := str((meta as Dictionary).get("path", "")) if meta is Dictionary else ""
	if path.is_empty():
		path = _meta_path(item)
	return _strip_indices(path)


## Remove any "[…]" segments from a dotted path, so an array-element path collapses
## to its field ("a[0].b" -> "a.b").
func _strip_indices(path: String) -> String:
	var out := ""
	var depth := 0
	for c in path:
		if c == "[":
			depth += 1
		elif c == "]":
			depth = maxi(0, depth - 1)
		elif depth == 0:
			out += c
	return out


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


## The value carried by the row whose context menu is open (for the copy actions).
func _menu_value() -> Variant:
	if _menu_item == null:
		return null
	var meta: Variant = _menu_item.get_metadata(0)
	return (meta as Dictionary).get("value") if meta is Dictionary else null


func _meta_name(item: TreeItem) -> String:
	var meta: Variant = item.get_metadata(0)
	if meta is Dictionary:
		return str(meta.get("name", meta.get("key", "")))
	return ""


## Clipboard text for the Copy JSON / Copy Value action. Containers (objects and
## arrays) copy as pretty JSON; a scalar copies its plain value with no surrounding
## quotes — a string as its raw text, an EJSON wrapper as its underlying scalar
## (e.g. an ObjectId's hex) — matching what the Value column shows.
func _meta_copy_text(item: TreeItem) -> String:
	var meta: Variant = item.get_metadata(0)
	if not (meta is Dictionary) or not (meta as Dictionary).has("value"):
		return ""
	return _copy_text_for((meta as Dictionary)["value"])


## Clipboard text for a value: containers (objects/arrays) as pretty JSON, scalars
## as their plain value with no surrounding quotes (an EJSON wrapper as its
## underlying scalar, e.g. an ObjectId's hex or a date's rendered string).
func _copy_text_for(value: Variant) -> String:
	if (value is Dictionary and _ejson_scalar(value).is_empty()) or value is Array:
		return JSON.stringify(value, "  ")
	return _scalar_text(value)


## Record clipboard text for a copy menu item, returning its index in the registry
## (a menu item's id is COPY_ENTRY_BASE + this).
func _register_copy(text: String) -> int:
	_menu_copy_entries.append(text)
	return _menu_copy_entries.size() - 1


## The id attribute of an object value ("_id" preferred, else "id"), or "" when the
## value isn't a plain object or has neither. EJSON wrappers (e.g. an ObjectId) are
## scalars, not objects, so they don't qualify.
func _id_key_of(value: Variant) -> String:
	if value is Dictionary and _ejson_scalar(value).is_empty():
		if (value as Dictionary).has("_id"):
			return "_id"
		if (value as Dictionary).has("id"):
			return "id"
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
