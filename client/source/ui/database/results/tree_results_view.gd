class_name TreeResultsView
extends DocResultsView

## Robo3T-style tree: one expandable row per document, then nested key/value/type
## rows for every field. The first document of the page starts expanded.

## When set, top-level rows are rendered as activity-log entries: the Key column
## shows source/action/target, the Value column shows the result or error, and
## failed actions get an error background. Nested field rows are unaffected.
var _log_mode := false


## Toggle activity-log rendering for top-level rows. Called by the ResultsView
## owner (only the Activity Log tab enables it).
func set_log_mode(enabled: bool) -> void:
	_log_mode = enabled


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
	var field_type := _resolve_type(path, value)
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
