class_name ResultsView
extends VBoxContainer

## Displays a set of documents in one of three modes, mirroring Robo3T:
##   - Tree: expandable key/value/type per document
##   - Table: one row per document, columns = union of top-level fields
##   - Text: pretty-printed JSON
## Call set_documents() to feed data; the active view rebuilds on demand.

enum ViewMode { TREE, TABLE, TEXT }
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

const DEFAULT_LIMIT := 50
const TABLE_COLUMN_MIN_WIDTH := 160

var _documents: Array = []
var _mode: ViewMode = ViewMode.TREE
var _offset := 0
var _limit := DEFAULT_LIMIT

var _count_label: Label
var _page_label: Label
var _offset_field: LineEdit
var _limit_field: LineEdit
var _prev_btn: Button
var _next_btn: Button
var _view_host: Control
var _tree_view: Tree
var _table_view: Tree
var _text_view: CodeEdit
var _mode_buttons: Array[Button] = []

var _doc_menu: PopupMenu
var _doc_dialog: DocumentDialog
var _menu_doc_index := -1
var _menu_item: TreeItem
var _menu_tree: Tree


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
	_tree_view.select_mode = Tree.SELECT_ROW
	_tree_view.allow_rmb_select = true
	_tree_view.item_mouse_selected.connect(_on_doc_mouse_selected.bind(_tree_view))
	_tree_view.gui_input.connect(_on_tree_gui_input.bind(_tree_view))
	_tree_view.item_activated.connect(_on_tree_item_activated.bind(_tree_view))
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
	_table_view.select_mode = Tree.SELECT_ROW
	_table_view.allow_rmb_select = true
	_table_view.item_mouse_selected.connect(_on_doc_mouse_selected.bind(_table_view))
	_table_view.gui_input.connect(_on_tree_gui_input.bind(_table_view))
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
	_update_pager()


## Opens the document editor in insert mode (used by the sidebar's
## "Insert Document…" action via the workspace).
func request_insert() -> void:
	_doc_dialog.open_insert()


func set_documents(documents: Array) -> void:
	_documents = documents
	_offset = 0
	_refresh_page()


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

	row.add_child(_build_pager())

	return panel


func _build_pager() -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	box.add_child(_make_dim_label("Offset"))
	_offset_field = _make_num_field("0")
	_offset_field.tooltip_text = "First document to show (0-based)"
	_offset_field.text_submitted.connect(_apply_offset_field)
	_offset_field.focus_exited.connect(_apply_offset_field)
	box.add_child(_offset_field)

	box.add_child(_make_dim_label("Limit"))
	_limit_field = _make_num_field(str(DEFAULT_LIMIT))
	_limit_field.tooltip_text = "Max documents per page"
	_limit_field.text_submitted.connect(_apply_limit_field)
	_limit_field.focus_exited.connect(_apply_limit_field)
	box.add_child(_limit_field)

	_prev_btn = Button.new()
	_prev_btn.text = "<"
	_prev_btn.focus_mode = Control.FOCUS_NONE
	_prev_btn.tooltip_text = "Previous page"
	_prev_btn.pressed.connect(func() -> void: _set_offset(_offset - _limit))
	box.add_child(_prev_btn)

	_page_label = Label.new()
	_page_label.text = "0-0"
	_page_label.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.custom_minimum_size = Vector2(72, 0)
	box.add_child(_page_label)

	_next_btn = Button.new()
	_next_btn.text = ">"
	_next_btn.focus_mode = Control.FOCUS_NONE
	_next_btn.tooltip_text = "Next page"
	_next_btn.pressed.connect(func() -> void: _set_offset(_offset + _limit))
	box.add_child(_next_btn)

	return box


func _make_dim_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	return label


func _make_num_field(value: String) -> LineEdit:
	var field := LineEdit.new()
	field.text = value
	field.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	field.custom_minimum_size = Vector2(56, 0)
	return field


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
			_text_view.text = JSON.stringify(_page_documents(), "  ")


# Pagination ------------------------------------------------------------------
## Largest valid offset: the first document is always reachable, so this is the
## index of the last document (or 0 when empty).
func _max_offset() -> int:
	return maxi(0, _documents.size() - 1)


func _page_bounds() -> Vector2i:
	var start := clampi(_offset, 0, _documents.size())
	var end := mini(start + _limit, _documents.size())
	return Vector2i(start, end)


func _page_documents() -> Array:
	var b := _page_bounds()
	return _documents.slice(b.x, b.y)


## Clamp the offset (the document set may have shrunk), then refresh counts,
## the pager controls and the active view together.
func _refresh_page() -> void:
	_update_count()
	_set_offset(_offset)


func _set_offset(offset: int) -> void:
	_offset = clampi(offset, 0, _max_offset())
	_update_pager()
	_rebuild()


func _apply_offset_field(_text: String = "") -> void:
	_set_offset(int(_offset_field.text))


func _apply_limit_field(_text: String = "") -> void:
	_limit = maxi(1, int(_limit_field.text))
	_set_offset(_offset)


func _update_pager() -> void:
	var b := _page_bounds()
	_page_label.text = "0-0" if _documents.is_empty() else "%d-%d" % [b.x + 1, b.y]
	_offset_field.text = str(_offset)
	_limit_field.text = str(_limit)
	_prev_btn.disabled = _offset <= 0
	_next_btn.disabled = b.y >= _documents.size()


# Tree view -------------------------------------------------------------------
func _rebuild_tree() -> void:
	_tree_view.clear()
	var root := _tree_view.create_item()
	var bounds := _page_bounds()
	for i in range(bounds.x, bounds.y):
		var doc: Dictionary = _documents[i]
		var item := _tree_view.create_item(root)
		var label: String = str(doc.get("_id", "(document)"))
		item.set_text(0, "(%d) %s" % [i + 1, label])
		item.set_custom_color(0, AppTheme.ACCENT)
		item.set_text(1, "{%d fields}" % doc.size())
		item.set_custom_color(1, AppTheme.TEXT_DIM)
		item.set_text(2, "Object")
		# Top-level item carries the document index plus name/value for copy actions.
		item.set_metadata(0, {"doc_index": i, "key": "", "name": label, "value": doc})
		_add_dict_children(item, doc)
		item.set_collapsed(i != bounds.x)  # expand the first document on the page


func _add_dict_children(parent: TreeItem, dict: Dictionary) -> void:
	for key in dict:
		_add_value_item(parent, str(key), dict[key])


func _add_value_item(parent: TreeItem, key: String, value: Variant) -> void:
	var item := _tree_view.create_item(parent)
	item.set_text(0, key)
	item.set_custom_color(0, AppTheme.TEXT)
	item.set_text(2, _type_name(value))
	item.set_custom_color(2, AppTheme.TEXT_DIM)
	item.set_metadata(0, {"key": key, "name": key, "value": value})

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
	var bounds := _page_bounds()
	var columns := _collect_columns(_page_documents())
	_table_view.columns = max(1, columns.size())
	for c in columns.size():
		_table_view.set_column_title(c, columns[c])
		# Expand to share width when there are few columns, but hold a minimum so
		# that many columns overflow into a horizontal scrollbar instead of being
		# squeezed unreadably narrow. Clip long cell text rather than wrapping.
		_table_view.set_column_expand(c, true)
		_table_view.set_column_custom_minimum_width(c, TABLE_COLUMN_MIN_WIDTH)
		_table_view.set_column_clip_content(c, true)

	var root := _table_view.create_item()
	for i in range(bounds.x, bounds.y):
		var doc: Dictionary = _documents[i]
		var row := _table_view.create_item(root)
		row.set_metadata(0, {
			"doc_index": i, "key": "", "name": str(doc.get("_id", "")), "value": doc,
		})
		for c in columns.size():
			var key: String = columns[c]
			if doc.has(key):
				row.set_text(c, _preview(doc[key]))
				row.set_custom_color(c, _value_color(doc[key]))
			else:
				row.set_text(c, "")


func _collect_columns(docs: Array) -> Array:
	var columns: Array = []
	for doc in docs:
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
	_menu_item = item
	_menu_tree = tree
	_menu_doc_index = _doc_index_from_item(item, tree)
	if _menu_doc_index < 0:
		return

	var is_document := item.get_parent() == tree.get_root()
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
	_doc_menu.position = Vector2i(tree.get_global_mouse_position())
	_doc_menu.popup()


func _on_tree_gui_input(event: InputEvent, tree: Tree) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not (key_event.pressed and key_event.alt_pressed):
		return
	var item := tree.get_selected()
	if item == null:
		return
	if key_event.keycode == KEY_RIGHT:
		_set_collapsed_recursive(item, false)
		tree.accept_event()
	elif key_event.keycode == KEY_LEFT:
		_collapse_or_select_parent(item, tree)
		tree.accept_event()


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
	if meta is Dictionary:
		return int(meta.get("doc_index", -1))
	return -1


func _on_doc_action(id: int) -> void:
	if _menu_doc_index < 0 or _menu_doc_index >= _documents.size():
		return
	match id:
		DocAction.EXPAND_RECURSIVE:
			_set_collapsed_recursive(_menu_item, false)
		DocAction.COLLAPSE_RECURSIVE:
			_set_collapsed_recursive(_menu_item, true)
		DocAction.EDIT:
			_doc_dialog.open_edit(_menu_doc_index, JSON.stringify(_documents[_menu_doc_index], "  "))
		DocAction.VIEW:
			_doc_dialog.open_view(JSON.stringify(_documents[_menu_doc_index], "  "))
		DocAction.INSERT:
			_doc_dialog.open_insert()
		DocAction.COPY_NAME:
			DisplayServer.clipboard_set(_meta_name(_menu_item))
		DocAction.COPY_PATH:
			DisplayServer.clipboard_set(_meta_path(_menu_item, _menu_tree))
		DocAction.COPY_JSON:
			DisplayServer.clipboard_set(_meta_json(_menu_item))
		DocAction.DELETE:
			_documents.remove_at(_menu_doc_index)
			_refresh_page()


func _on_tree_item_activated(tree: Tree) -> void:
	# Double-click (or Enter) on an object/array row toggles it non-recursively.
	var item := tree.get_selected()
	if item != null and item.get_child_count() > 0:
		item.set_collapsed(not item.is_collapsed())


func _collapse_or_select_parent(item: TreeItem, tree: Tree) -> void:
	# Alt+Left collapses an expanded object; on an already-collapsed object (or a
	# leaf) it walks the selection up to the parent row instead, so repeated
	# presses climb the tree a level at a time before collapsing it.
	if item.get_child_count() > 0 and not item.is_collapsed():
		_set_collapsed_recursive(item, true)
		return
	var parent := item.get_parent()
	if parent != null and parent != tree.get_root():
		parent.select(0)
		tree.scroll_to_item(parent)


func _set_collapsed_recursive(item: TreeItem, collapsed: bool) -> void:
	item.set_collapsed(collapsed)
	var child := item.get_first_child()
	while child != null:
		_set_collapsed_recursive(child, collapsed)
		child = child.get_next()


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


func _meta_path(item: TreeItem, tree: Tree) -> String:
	# Build a dotted path from the document root down to the selected field,
	# e.g. "address.city" or "roles[0]". The document item itself contributes
	# nothing (its key is empty).
	var root := tree.get_root()
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


func _on_document_inserted(text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_documents.append(parsed)
		_update_count()
		# Jump to the last page so the newly inserted document is visible.
		_set_offset(((_documents.size() - 1) / _limit) * _limit)


func _on_document_updated(index: int, text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary and index >= 0 and index < _documents.size():
		_documents[index] = parsed
		_rebuild()
