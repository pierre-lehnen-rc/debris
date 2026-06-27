class_name TreeResultsView
extends DocResultsView

## Robo3T-style tree: one expandable row per document, then nested key/value/type
## rows for every field. The first document of the page starts expanded.


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
		item.set_text(0, "(%d) %s" % [doc_index + 1, label])
		item.set_custom_color(0, AppTheme.ACCENT)
		item.set_text(1, "{%d fields}" % doc.size())
		item.set_custom_color(1, AppTheme.TEXT_DIM)
		item.set_text(2, "Object")
		# Top-level item carries the document index plus name/value for copy actions.
		item.set_metadata(0, {"doc_index": doc_index, "key": "", "name": label, "value": doc})
		_add_dict_children(item, doc)
		item.set_collapsed(i != 0)  # expand the first document on the page


func _add_dict_children(parent: TreeItem, dict: Dictionary) -> void:
	for key in dict:
		_add_value_item(parent, str(key), dict[key])


func _add_value_item(parent: TreeItem, key: String, value: Variant) -> void:
	var item := create_item(parent)
	item.set_text(0, key)
	item.set_custom_color(0, AppTheme.TEXT)
	item.set_text(2, _type_name(value))
	item.set_custom_color(2, AppTheme.TEXT_DIM)
	item.set_metadata(0, {"key": key, "name": key, "value": value})

	if value is Dictionary and _ejson_scalar(value).is_empty():
		item.set_text(1, "{%d fields}" % value.size())
		item.set_custom_color(1, AppTheme.TEXT_DIM)
		_add_dict_children(item, value)
		item.set_collapsed(true)
	elif value is Array:
		item.set_text(1, "[%d elements]" % value.size())
		item.set_custom_color(1, AppTheme.TEXT_DIM)
		for i in value.size():
			_add_value_item(item, "[%d]" % i, value[i])
		item.set_collapsed(true)
	else:
		item.set_text(1, _preview(value))
		item.set_custom_color(1, _value_color(value))
