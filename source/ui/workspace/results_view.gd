class_name ResultsView
extends VBoxContainer

## Displays a set of documents in one of three modes, mirroring Robo3T:
##   - Tree: expandable key/value/type per document
##   - Table: one row per document, columns = union of top-level fields
##   - Text: pretty-printed JSON
## Call set_documents() to feed data; the active view rebuilds on demand.

enum ViewMode { TREE, TABLE, TEXT }
enum DocAction { VIEW, EDIT, INSERT, DELETE }

var _documents: Array = []
var _mode: ViewMode = ViewMode.TREE

var _count_label: Label
var _view_host: Control
var _tree_view: Tree
var _table_view: Tree
var _text_view: CodeEdit
var _mode_buttons: Array[Button] = []

var _doc_menu: PopupMenu
var _doc_dialog: DocumentDialog
var _menu_doc_index := -1


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	add_child(_build_header())

	_view_host = Control.new()
	_view_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_view_host)

	_tree_view = Tree.new()
	_full_rect(_tree_view)
	_tree_view.hide_root = true
	_tree_view.allow_rmb_select = true
	_tree_view.item_mouse_selected.connect(_on_doc_mouse_selected.bind(_tree_view))
	_tree_view.columns = 3
	_tree_view.set_column_title(0, "Key")
	_tree_view.set_column_title(1, "Value")
	_tree_view.set_column_title(2, "Type")
	_tree_view.column_titles_visible = true
	_tree_view.set_column_expand_ratio(0, 2)
	_tree_view.set_column_expand_ratio(1, 4)
	_tree_view.set_column_expand_ratio(2, 1)
	_view_host.add_child(_tree_view)

	_table_view = Tree.new()
	_full_rect(_table_view)
	_table_view.hide_root = true
	_table_view.allow_rmb_select = true
	_table_view.item_mouse_selected.connect(_on_doc_mouse_selected.bind(_table_view))
	_table_view.column_titles_visible = true
	_view_host.add_child(_table_view)

	_text_view = CodeEdit.new()
	_full_rect(_text_view)
	_text_view.editable = false
	_text_view.gutters_draw_line_numbers = true
	_view_host.add_child(_text_view)

	_doc_menu = PopupMenu.new()
	_doc_menu.theme = AppTheme.shared()
	_doc_menu.id_pressed.connect(_on_doc_action)
	add_child(_doc_menu)

	_doc_dialog = DocumentDialog.new()
	_doc_dialog.inserted.connect(_on_document_inserted)
	_doc_dialog.updated.connect(_on_document_updated)
	add_child(_doc_dialog)

	_set_mode(ViewMode.TREE)


## Opens the document editor in insert mode (used by the sidebar's
## "Insert Document…" action via the workspace).
func request_insert() -> void:
	_doc_dialog.open_insert()


func set_documents(documents: Array) -> void:
	_documents = documents
	_update_count()
	_rebuild()


func _update_count() -> void:
	var n := _documents.size()
	_count_label.text = "%d document%s" % [n, "" if n == 1 else "s"]


func _build_header() -> Control:
	var panel := PanelContainer.new()
	var sb := AppTheme._flat(AppTheme.BG_DARKEST, 0)
	sb.content_margin_left = 6
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	panel.add_child(row)

	for entry in [["Tree", ViewMode.TREE], ["Table", ViewMode.TABLE], ["Text", ViewMode.TEXT]]:
		var btn := Button.new()
		btn.text = entry[0]
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		var mode_value: ViewMode = entry[1]
		btn.pressed.connect(func() -> void: _set_mode(mode_value))
		row.add_child(btn)
		_mode_buttons.append(btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_count_label = Label.new()
	_count_label.text = "0 documents"
	_count_label.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	row.add_child(_count_label)

	return panel


func _full_rect(node: Control) -> void:
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _set_mode(mode: ViewMode) -> void:
	_mode = mode
	for i in _mode_buttons.size():
		_mode_buttons[i].button_pressed = (i == mode)
	_tree_view.visible = mode == ViewMode.TREE
	_table_view.visible = mode == ViewMode.TABLE
	_text_view.visible = mode == ViewMode.TEXT
	_rebuild()


func _rebuild() -> void:
	match _mode:
		ViewMode.TREE:
			_rebuild_tree()
		ViewMode.TABLE:
			_rebuild_table()
		ViewMode.TEXT:
			_text_view.text = JSON.stringify(_documents, "  ")


# Tree view -------------------------------------------------------------------
func _rebuild_tree() -> void:
	_tree_view.clear()
	var root := _tree_view.create_item()
	for i in _documents.size():
		var doc: Dictionary = _documents[i]
		var item := _tree_view.create_item(root)
		var label: String = str(doc.get("_id", "(document)"))
		item.set_text(0, "(%d) %s" % [i + 1, label])
		item.set_custom_color(0, AppTheme.ACCENT)
		item.set_text(2, "Object")
		item.set_metadata(0, i)  # top-level item -> document index
		_add_dict_children(item, doc)
		item.set_collapsed(i != 0)


func _add_dict_children(parent: TreeItem, dict: Dictionary) -> void:
	for key in dict:
		_add_value_item(parent, str(key), dict[key])


func _add_value_item(parent: TreeItem, key: String, value: Variant) -> void:
	var item := _tree_view.create_item(parent)
	item.set_text(0, key)
	item.set_custom_color(0, AppTheme.TEXT)
	item.set_text(2, _type_name(value))
	item.set_custom_color(2, AppTheme.TEXT_DIM)

	if value is Dictionary:
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


# Table view ------------------------------------------------------------------
func _rebuild_table() -> void:
	_table_view.clear()
	var columns := _collect_columns()
	_table_view.columns = max(1, columns.size())
	for c in columns.size():
		_table_view.set_column_title(c, columns[c])
		_table_view.set_column_expand(c, true)

	var root := _table_view.create_item()
	for i in _documents.size():
		var doc: Dictionary = _documents[i]
		var row := _table_view.create_item(root)
		row.set_metadata(0, i)  # row -> document index
		for c in columns.size():
			var key: String = columns[c]
			if doc.has(key):
				row.set_text(c, _preview(doc[key]))
				row.set_custom_color(c, _value_color(doc[key]))
			else:
				row.set_text(c, "")


func _collect_columns() -> Array:
	var columns: Array = []
	for doc in _documents:
		for key in doc:
			if not columns.has(key):
				columns.append(key)
	return columns


# Value formatting ------------------------------------------------------------
func _preview(value: Variant) -> String:
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
	if value is String:
		return AppTheme.ACCENT_GREEN
	if value is bool or value is int or value is float:
		return AppTheme.ACCENT
	return AppTheme.TEXT


# Document actions ------------------------------------------------------------
func _on_doc_mouse_selected(_pos: Vector2, mouse_button_index: int, tree: Tree) -> void:
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return
	var item := tree.get_selected()
	if item == null:
		return
	_menu_doc_index = _doc_index_from_item(item, tree)
	if _menu_doc_index < 0:
		return
	_doc_menu.clear()
	_doc_menu.add_item("View Document", DocAction.VIEW)
	_doc_menu.add_item("Edit Document…", DocAction.EDIT)
	_doc_menu.add_item("Insert Document…", DocAction.INSERT)
	_doc_menu.add_separator()
	_doc_menu.add_item("Delete Document", DocAction.DELETE)
	_doc_menu.reset_size()
	_doc_menu.position = Vector2i(tree.get_global_mouse_position())
	_doc_menu.popup()


func _doc_index_from_item(item: TreeItem, tree: Tree) -> int:
	# Climb to the top-level ancestor (whose parent is the hidden root), which
	# carries the document index in its metadata.
	var root := tree.get_root()
	var cur := item
	while cur != null and cur.get_parent() != root:
		cur = cur.get_parent()
	if cur == null:
		return -1
	var meta: Variant = cur.get_metadata(0)
	return int(meta) if meta != null else -1


func _on_doc_action(id: int) -> void:
	if _menu_doc_index < 0 or _menu_doc_index >= _documents.size():
		return
	match id:
		DocAction.VIEW:
			_doc_dialog.open_view(JSON.stringify(_documents[_menu_doc_index], "  "))
		DocAction.EDIT:
			_doc_dialog.open_edit(_menu_doc_index, JSON.stringify(_documents[_menu_doc_index], "  "))
		DocAction.INSERT:
			_doc_dialog.open_insert()
		DocAction.DELETE:
			_documents.remove_at(_menu_doc_index)
			_update_count()
			_rebuild()


func _on_document_inserted(text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_documents.append(parsed)
		_update_count()
		_rebuild()


func _on_document_updated(index: int, text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary and index >= 0 and index < _documents.size():
		_documents[index] = parsed
		_rebuild()
