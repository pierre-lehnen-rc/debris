class_name ResultsView
extends VBoxContainer

## Displays a set of documents in one of three modes, mirroring Robo3T:
##   - Tree: expandable key/value/type per document   (TreeResultsView)
##   - Table: one row per document, union of fields    (TableResultsView)
##   - Text: pretty-printed JSON                        (TextResultsView)
## This node owns the document array, pagination and the edit dialog; the active
## sub-view (instanced in results_view.tscn under ViewHost) only renders the
## current page and reports edit/view/insert/delete back through signals.

enum ViewMode { TREE, TABLE, TEXT }

const DEFAULT_LIMIT := 50
const DOCUMENT_DIALOG_SCENE := preload("res://source/ui/dialogs/document_dialog.tscn")

var _documents: Array = []
var _mode: ViewMode = ViewMode.TREE
var _offset := 0
var _limit := DEFAULT_LIMIT

@onready var _header: PanelContainer = %Header
@onready var _count_label: Label = %CountLabel
@onready var _offset_label: Label = %OffsetLabel
@onready var _limit_label: Label = %LimitLabel
@onready var _page_label: Label = %PageLabel
@onready var _offset_field: LineEdit = %OffsetField
@onready var _limit_field: LineEdit = %LimitField
@onready var _prev_btn: Button = %PrevBtn
@onready var _next_btn: Button = %NextBtn
@onready var _tree_view: TreeResultsView = %TreeView
@onready var _table_view: TableResultsView = %TableView
@onready var _text_view: TextResultsView = %TextView
@onready var _mode_buttons: Array[Button] = [%TreeBtn, %TableBtn, %TextBtn]

var _doc_dialog: DocumentDialog


func _ready() -> void:
	_apply_style()

	for i in _mode_buttons.size():
		var mode_value: ViewMode = i as ViewMode
		_mode_buttons[i].pressed.connect(func() -> void: _set_mode(mode_value))

	_offset_field.text_submitted.connect(_apply_offset_field)
	_offset_field.focus_exited.connect(_apply_offset_field)
	_limit_field.text_submitted.connect(_apply_limit_field)
	_limit_field.focus_exited.connect(_apply_limit_field)
	_prev_btn.pressed.connect(func() -> void: _set_offset(_offset - _limit))
	_next_btn.pressed.connect(func() -> void: _set_offset(_offset + _limit))

	for view: DocResultsView in [_tree_view, _table_view]:
		view.edit_requested.connect(_on_edit_requested)
		view.view_requested.connect(_on_view_requested)
		view.insert_requested.connect(request_insert)
		view.delete_requested.connect(_on_delete_requested)

	_doc_dialog = DOCUMENT_DIALOG_SCENE.instantiate()
	_doc_dialog.inserted.connect(_on_document_inserted)
	_doc_dialog.updated.connect(_on_document_updated)
	add_child(_doc_dialog)

	_set_mode(ViewMode.TREE)
	_update_pager()


func _apply_style() -> void:
	var sb := AppTheme._flat(AppTheme.BG_DARKEST, 0)
	sb.content_margin_left = 6
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	_header.add_theme_stylebox_override("panel", sb)
	for label in [_count_label, _offset_label, _limit_label, _page_label]:
		label.add_theme_color_override("font_color", AppTheme.TEXT_DIM)


## Opens the document editor in insert mode (used by the sidebar's
## "Insert Document…" action via the workspace, and the views' context menus).
func request_insert() -> void:
	_doc_dialog.open_insert()


func set_documents(documents: Array) -> void:
	_documents = documents
	_offset = 0
	_refresh_page()


func _update_count() -> void:
	var n := _documents.size()
	_count_label.text = "%d document%s" % [n, "" if n == 1 else "s"]


func _set_mode(mode: ViewMode) -> void:
	_mode = mode
	for i in _mode_buttons.size():
		_mode_buttons[i].button_pressed = (i == mode)
	_tree_view.visible = mode == ViewMode.TREE
	_table_view.visible = mode == ViewMode.TABLE
	_text_view.visible = mode == ViewMode.TEXT
	_rebuild()


func _rebuild() -> void:
	var page := _page_documents()
	var start := _page_bounds().x
	match _mode:
		ViewMode.TREE:
			_tree_view.display(page, start)
		ViewMode.TABLE:
			_table_view.display(page, start)
		ViewMode.TEXT:
			_text_view.display(page)


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


# Document actions (relayed from the active view) -----------------------------
func _on_edit_requested(doc_index: int) -> void:
	if doc_index < 0 or doc_index >= _documents.size():
		return
	_doc_dialog.open_edit(doc_index, JSON.stringify(_documents[doc_index], "  "))


func _on_view_requested(doc_index: int) -> void:
	if doc_index < 0 or doc_index >= _documents.size():
		return
	_doc_dialog.open_view(JSON.stringify(_documents[doc_index], "  "))


func _on_delete_requested(doc_index: int) -> void:
	if doc_index < 0 or doc_index >= _documents.size():
		return
	_documents.remove_at(doc_index)
	_refresh_page()


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
