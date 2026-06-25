class_name TableResultsView
extends DocResultsView

## Grid view: one row per document, columns = union of top-level field names in
## the page. Columns hold a minimum width and clip overflow so collections with
## many fields scroll horizontally rather than squeezing cells unreadably narrow.

const TABLE_COLUMN_MIN_WIDTH := 160


func display(documents: Array, start_index: int) -> void:
	clear()
	var cols := _collect_columns(documents)
	columns = maxi(1, cols.size())
	for c in cols.size():
		set_column_title(c, cols[c])
		set_column_expand(c, true)
		set_column_custom_minimum_width(c, TABLE_COLUMN_MIN_WIDTH)
		set_column_clip_content(c, true)

	var root := create_item()
	for i in documents.size():
		var doc_index := start_index + i
		var doc: Dictionary = documents[i]
		var row := create_item(root)
		row.set_metadata(0, {
			"doc_index": doc_index, "key": "", "name": str(doc.get("_id", "")), "value": doc,
		})
		for c in cols.size():
			var key: String = cols[c]
			if doc.has(key):
				row.set_text(c, _preview(doc[key]))
				row.set_custom_color(c, _value_color(doc[key]))
			else:
				row.set_text(c, "")


func _collect_columns(docs: Array) -> Array:
	var cols: Array = []
	for doc in docs:
		for key in doc:
			if not cols.has(key):
				cols.append(key)
	return cols
