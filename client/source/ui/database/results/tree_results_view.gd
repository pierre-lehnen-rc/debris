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
	var root := create_item()
	for i in documents.size():
		var doc_index := start_index + i
		var doc: Dictionary = documents[i]
		_current_doc = doc
		var item := create_item(root)
		var label: String = str(doc.get("_id", "(document)"))
		if _log_mode:
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
		item.set_collapsed(i != 0)  # expand the first document on the page


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
	if raw is Dictionary:
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
