class_name TreeResultsView
extends DocResultsView

## Robo3T-style tree: one expandable row per document, then nested key/value/type
## rows for every field. The first document of the page starts expanded.
##
## When _log_mode is set (inherited from DocResultsView), top-level rows render as
## activity-log entries: the Key column shows source/action/target, the Value
## column shows the result or error, and failed actions get an error background.
## Nested field rows are unaffected.

# The document currently being rendered, so nested field rows can resolve a
# value-dependent (`when`) type against their siblings. Set per document in
# display() before its subtree is built.
var _current_doc: Variant = null

# Entity object references within a raw response that act as typing roots (see
# display_raw): each is typed as _collection, and its descendant fields resolve
# relative to it. Matched by identity so nested field arrays aren't mistaken for
# entities.
var _raw_entity_roots: Array = []


func _ready_view() -> void:
	set_column_title(0, "Key")
	set_column_title(1, "Value")
	set_column_title(2, "Type")
	set_column_expand_ratio(0, 2)
	set_column_expand_ratio(1, 4)
	set_column_expand_ratio(2, 1)
	for c in 3:
		set_column_clip_content(c, true)


func display(documents: Array, start_index: int) -> void:
	clear()
	if _server_log:
		_setup_server_log_columns()
	var root := create_item()
	for i in documents.size():
		var doc_index := start_index + i
		var doc: Dictionary = documents[i]
		_current_doc = doc
		var item := create_item(root)
		var label: String = str(doc.get("_id", "(document)"))
		if _server_log:
			_style_server_log_row(item, doc_index, doc)
		elif _log_mode:
			_style_log_row(item, doc_index, doc)
		else:
			item.set_text(0, "(%d) %s" % [doc_index + 1, label])
			item.set_custom_color(0, AppTheme.ACCENT)
			item.set_text(1, "{%d fields}" % doc.size())
			item.set_custom_color(1, AppTheme.TEXT_DIM)
			var doc_type := _resolve_type("", doc)
			if doc_type.is_empty():
				item.set_text(2, "Object")
			else:
				item.set_text(2, doc_type)
				item.set_custom_color(2, AppTheme.ACCENT)
		# Top-level item carries the document index plus name/value for copy actions.
		item.set_metadata(0, {"doc_index": doc_index, "key": "", "name": label, "value": doc})
		_add_dict_children(item, doc, "")
		# Expand the first document on a normal page; keep log rows collapsed — they
		# read as a flat, scannable list, expanded on demand.
		item.set_collapsed(_server_log or i != 0)


## Render an endpoint's raw response body verbatim (no array coercion), so the
## Text/Tree show exactly what came back. `entity_roots` are the objects within
## `raw` to type as _collection (see DocResultsView._collection); each is a typing
## root whose descendant fields resolve relative to it, while envelope-level rows
## (the wrapper, pagination meta) stay untyped. The top level is expanded so the
## response's shape is visible at a glance.
func display_raw(raw: Variant, entity_roots: Array) -> void:
	clear()
	_raw_entity_roots = entity_roots
	var root := create_item()
	if raw is Dictionary and _ejson_scalar(raw).is_empty():
		# A body that is itself an entity types its own fields; an envelope doesn't.
		var type_doc: Variant = raw if _is_entity_root(raw) else null
		for key in raw:
			var base := str(key) if type_doc != null else ""
			_render_raw(root, str(key), (raw as Dictionary)[key], type_doc, base)
	elif raw is Array:
		for i in (raw as Array).size():
			_render_raw(root, "[%d]" % i, (raw as Array)[i], null, "")
	elif raw != null:
		var item := create_item(root)
		item.set_text(0, "(value)")
		item.set_text(1, _preview(raw))
		item.set_custom_color(1, _value_color(raw))
		item.set_text(2, _type_name(raw))
		item.set_custom_color(2, AppTheme.TEXT_DIM)
		item.set_metadata(0, {"key": "", "name": "", "value": raw, "path": "", "type_doc": null})
	var child := root.get_first_child()
	while child != null:
		child.set_collapsed(false)
		child = child.get_next()


## Render one value of a raw response. `type_doc` is the entity object this value
## lives in (null at envelope level) and `type_path` the value's dotted path within
## it, so its custom type resolves via the schema. Entering an entity object (one of
## _raw_entity_roots) restarts the typing root; nested containers keep it, matching
## how the DB rules address fields relative to their document.
func _render_raw(
	parent: TreeItem, key: String, value: Variant, type_doc: Variant, type_path: String
) -> void:
	if value is Dictionary and _is_entity_root(value):
		type_doc = value
		type_path = ""
	var item := create_item(parent)
	item.set_text(0, key)
	item.set_custom_color(0, AppTheme.TEXT)
	var field_type := _resolve_type(type_path, type_doc) if type_doc != null else ""
	if field_type.is_empty():
		item.set_text(2, _type_name(value))
		item.set_custom_color(2, AppTheme.TEXT_DIM)
	else:
		item.set_text(2, field_type)
		item.set_custom_color(2, AppTheme.ACCENT)
	item.set_metadata(0, {"key": key, "name": key, "value": value, "path": type_path, "type_doc": type_doc})

	if value is Dictionary and _ejson_scalar(value).is_empty():
		item.set_text(1, "{%d fields}" % (value as Dictionary).size())
		item.set_custom_color(1, AppTheme.TEXT_DIM)
		for k in value:
			var child_path := str(k) if type_path.is_empty() else type_path + "." + str(k)
			_render_raw(item, str(k), (value as Dictionary)[k], type_doc, child_path)
		item.set_collapsed(true)
	elif value is Array:
		item.set_text(1, "[%d elements]" % (value as Array).size())
		item.set_custom_color(1, AppTheme.TEXT_DIM)
		for i in (value as Array).size():
			# Array elements share their array's field path (rules address arrays
			# whole, e.g. "mentions._id"), but an element that is itself an entity
			# restarts its own typing root at the top of this function.
			_render_raw(item, "[%d]" % i, (value as Array)[i], type_doc, type_path)
		item.set_collapsed(true)
	else:
		item.set_text(1, _preview(value))
		item.set_custom_color(1, _value_color(value))


## Whether `value` is one of the raw response's entity typing roots (by identity,
## so a field that merely equals an entity isn't confused for one).
func _is_entity_root(value: Variant) -> bool:
	for root in _raw_entity_roots:
		if is_same(root, value):
			return true
	return false


## Render a top-level row as an activity-log entry: Key shows source/action/target,
## Value shows the result (or the error for a failed action), Type shows the
## duration, and failures get a red-tinted background across all columns. Nested
## field rows keep the default key/value/type rendering.
## Fields given their own top-level column, so the Message's dynamic-attributes
## fallback doesn't repeat them. Order matches the SERVER_LOG_COLUMNS layout.
const SERVER_LOG_KEY_FIELDS := ["time", "level", "name"]
## The server-log tree's columns, in display order. Each value gets its own column so
## it can be coloured independently (a single Tree cell can't be multi-coloured). The
## Message column expands; the rest are fixed, so the tree scrolls horizontally when
## the pane is narrower than their total. Level sits last so its colour-coded severity
## reads as a trailing status flag.
const SERVER_LOG_COLUMNS := [
	{"title": "Key", "width": 200},
	{"title": "Time", "width": 230},
	{"title": "Name", "width": 150},
	{"title": "Message", "width": 400, "expand": true},
	{"title": "Level", "width": 80},
]
## Column indices into SERVER_LOG_COLUMNS, by role.
const SERVER_LOG_COL_INDEX := 0
const SERVER_LOG_COL_TIME := 1
const SERVER_LOG_COL_NAME := 2
const SERVER_LOG_COL_MSG := 3
const SERVER_LOG_COL_LEVEL := 4


## Configure the tree for server-log rows: one column per log field (see
## SERVER_LOG_COLUMNS). Idempotent — called on each display().
func _setup_server_log_columns() -> void:
	columns = SERVER_LOG_COLUMNS.size()
	for c in SERVER_LOG_COLUMNS.size():
		var spec: Dictionary = SERVER_LOG_COLUMNS[c]
		set_column_title(c, str(spec["title"]))
		set_column_custom_minimum_width(c, int(spec["width"]))
		set_column_expand(c, bool(spec.get("expand", false)))
		set_column_clip_content(c, true)


## Insert newly-arrived log entries (newest first) at the top of the tree in place,
## leaving every existing row — its expanded state, its selection — untouched, then
## renumber the index column. Requires the tree to already hold a server-log page.
func insert_server_log_rows(new_docs: Array) -> void:
	var root := get_root()
	if root == null:
		return
	for i in new_docs.size():
		var doc: Dictionary = new_docs[i]
		_current_doc = doc
		var item := create_item(root, i)  # index i from the top, keeping new_docs' order
		_style_server_log_row(item, i, doc)
		item.set_metadata(0, {"doc_index": i, "key": "", "name": "", "value": doc})
		_add_dict_children(item, doc, "")
		item.set_collapsed(true)
	_renumber_server_log_rows()


## Renumber the top-level rows' index column ("(1)" newest, downward). Only the index
## text changes, so expansion and selection are preserved.
func _renumber_server_log_rows() -> void:
	var root := get_root()
	if root == null:
		return
	var index := 0
	var row := root.get_first_child()
	while row != null:
		row.set_text(0, "(%d)" % (index + 1))
		index += 1
		row = row.get_next()


## Drop rows past `cap` from the bottom (the oldest), keeping the retained tail bounded.
func trim_server_log_rows(cap: int) -> void:
	var root := get_root()
	if root == null:
		return
	var rows := root.get_children()
	for i in range(cap, rows.size()):
		rows[i].free()


## Render a server-log entry's top-level row across its columns: index, time, level
## (coloured by severity), name, and the message (msg, or a JSON of the dynamic
## attributes). Nested field rows still expand below. Error/fatal rows are backed.
func _style_server_log_row(item: TreeItem, doc_index: int, entry: Dictionary) -> void:
	item.set_text(SERVER_LOG_COL_INDEX, "(%d)" % (doc_index + 1))
	item.set_custom_color(SERVER_LOG_COL_INDEX, AppTheme.TEXT_DIM)
	if entry.has("time"):
		item.set_text(SERVER_LOG_COL_TIME, str(entry["time"]))
		item.set_custom_color(SERVER_LOG_COL_TIME, AppTheme.TEXT_DIM)
	if entry.has("name"):
		item.set_text(SERVER_LOG_COL_NAME, str(entry["name"]))
		item.set_custom_color(SERVER_LOG_COL_NAME, AppTheme.ACCENT)
	item.set_text(SERVER_LOG_COL_MSG, server_log_value(entry))
	item.set_custom_color(SERVER_LOG_COL_MSG, AppTheme.TEXT if entry.has("msg") else AppTheme.TEXT_DIM)
	var level := _server_log_level(entry)
	if entry.has("level"):
		item.set_text(SERVER_LOG_COL_LEVEL, LogEntry.level_label(level))
		item.set_custom_color(SERVER_LOG_COL_LEVEL, LogEntry.level_color(level))

	if level >= 50:  # error / fatal
		for c in SERVER_LOG_COLUMNS.size():
			item.set_custom_bg_color(c, AppTheme.BG_ERROR)


## A server-log field row (child of a log entry): the field key in the (wide) Key
## column and its value under the Message column, nested objects/arrays expanding
## below. No type column — a log record's fields aren't schema-typed.
func _add_server_log_field(parent: TreeItem, key: String, value: Variant) -> void:
	var msg_col := SERVER_LOG_COL_MSG
	var item := create_item(parent)
	item.set_text(0, key)
	item.set_custom_color(0, AppTheme.TEXT)
	item.set_metadata(0, {"key": key, "name": key, "value": value})
	if value is Dictionary and _ejson_scalar(value).is_empty():
		item.set_text(msg_col, "{%d fields}" % value.size())
		item.set_custom_color(msg_col, AppTheme.TEXT_DIM)
		for k in value:
			_add_server_log_field(item, str(k), value[k])
		item.set_collapsed(true)
	elif value is Array:
		item.set_text(msg_col, "[%d elements]" % value.size())
		item.set_custom_color(msg_col, AppTheme.TEXT_DIM)
		for i in value.size():
			_add_server_log_field(item, "[%d]" % i, value[i])
		item.set_collapsed(true)
	else:
		item.set_text(msg_col, _preview(value))
		item.set_custom_color(msg_col, _value_color(value))


## The Message text for a server-log row: the `msg` attribute if present, else a JSON
## string of the entry's dynamic attributes (everything not in its own column).
static func server_log_value(entry: Dictionary) -> String:
	if entry.has("msg"):
		return str(entry["msg"])
	var dynamic := entry.duplicate()
	for field in SERVER_LOG_KEY_FIELDS:
		dynamic.erase(field)
	return JSON.stringify(dynamic)


## The numeric pino level of an entry, or 0 when it carries none.
static func _server_log_level(entry: Dictionary) -> int:
	var value: Variant = entry.get("level")
	return int(value) if (value is int or value is float) else 0


func _style_log_row(item: TreeItem, doc_index: int, entry: Dictionary) -> void:
	var ok: bool = entry.get("ok", false)
	var source: String = str(entry.get("source", ""))
	var action: String = str(entry.get("action", ""))
	var target: String = str(entry.get("target", ""))

	var key := "(%d) %s · %s" % [doc_index + 1, source, action]
	if not target.is_empty():
		key += " · %s" % target
	item.set_text(0, key)
	item.set_custom_color(0, AppTheme.ERROR if not ok else AppTheme.ACCENT)

	var value: String = str(entry.get("error", "")) if not ok else str(entry.get("result", ""))
	item.set_text(1, value)
	item.set_custom_color(1, AppTheme.ERROR if not ok else AppTheme.TEXT_BRIGHT)

	item.set_text(2, "%d ms" % int(entry.get("ms", 0)))
	item.set_custom_color(2, AppTheme.TEXT_DIM)

	if not ok:
		for c in 3:
			item.set_custom_bg_color(c, AppTheme.BG_ERROR)


## Add a dict's fields as child rows. `prefix` is the dotted path of `parent`
## within the document ("" at the document root), so each field can compute its
## own path for custom-type resolution.
func _add_dict_children(parent: TreeItem, dict: Dictionary, prefix: String) -> void:
	for key in dict:
		var child_path: String = str(key) if prefix.is_empty() else prefix + "." + str(key)
		_add_value_item(parent, str(key), dict[key], child_path)


func _add_value_item(parent: TreeItem, key: String, value: Variant, path: String) -> void:
	if _server_log:
		_add_server_log_field(parent, key, value)
		return
	var item := create_item(parent)
	item.set_text(0, key)
	item.set_custom_color(0, AppTheme.TEXT)
	var field_type := _resolve_type(path, _current_doc)
	if field_type.is_empty():
		item.set_text(2, _type_name(value))
		item.set_custom_color(2, AppTheme.TEXT_DIM)
	else:
		item.set_text(2, field_type)
		item.set_custom_color(2, AppTheme.ACCENT)
	item.set_metadata(0, {"key": key, "name": key, "value": value, "path": path})

	if value is Dictionary and _ejson_scalar(value).is_empty():
		item.set_text(1, "{%d fields}" % value.size())
		item.set_custom_color(1, AppTheme.TEXT_DIM)
		_add_dict_children(item, value, path)
		item.set_collapsed(true)
	elif value is Array:
		item.set_text(1, "[%d elements]" % value.size())
		item.set_custom_color(1, AppTheme.TEXT_DIM)
		for i in value.size():
			_add_value_item(item, "[%d]" % i, value[i], path)
		item.set_collapsed(true)
	else:
		item.set_text(1, _preview(value))
		item.set_custom_color(1, _value_color(value))
