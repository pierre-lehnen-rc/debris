class_name ResultsView
extends VBoxContainer

## Displays a set of documents in one of three modes, mirroring Robo3T:
##   - Tree: expandable key/value/type per document   (TreeResultsView)
##   - Table: one row per document, union of fields    (TableResultsView)
##   - Text: pretty-printed JSON                        (TextResultsView)
## This node owns the current page of documents, the pager and the edit dialog.
## Pagination is server-side: the pager controls (offset/limit, prev/next) emit
## `page_requested`, and the owner (QueryTab) re-runs the find with skip/limit
## and hands back the page via `show_page`. The total document count is unknown,
## so the UI only ever shows how many rows are currently displayed.

## Emitted whenever the user changes the page (offset or limit). The owner is
## expected to fetch that slice from the backend and call show_page().
signal page_requested(offset: int, limit: int)

enum ViewMode { TREE, TABLE, TEXT }

const DEFAULT_LIMIT := 50

## The current page of documents (not the whole result set).
var _documents: Array = []
var _mode: ViewMode = ViewMode.TREE
var _offset := 0
var _limit := DEFAULT_LIMIT
## Singular noun used in the count label ("3 documents", "3 channels", …).
var _item_noun := "document"

@onready var _header: PanelContainer = %Header
@onready var _pager: HBoxContainer = %Pager
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
@onready var _doc_dialog: DocumentDialog = $DocumentDialog


func _ready() -> void:
	_apply_style()
	_set_mode(ViewMode.TREE)
	_update_pager()


# Pager buttons (wired in results_view.tscn) ----------------------------------
func _on_prev_pressed() -> void:
	_set_offset(_offset - _limit)


func _on_next_pressed() -> void:
	_set_offset(_offset + _limit)


func _apply_style() -> void:
	var sb := AppTheme._flat(AppTheme.BG_DARKEST, 0)
	sb.content_margin_left = 6
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	_header.add_theme_stylebox_override("panel", sb)
	for label in [_count_label, _offset_label, _limit_label, _page_label]:
		label.add_theme_color_override("font_color", AppTheme.TEXT_DIM)


## Show or hide the offset/limit/prev/next pager. Endpoints that don't paginate
## (single-object or bounded lists) hide it; the count label still updates.
func set_pagination_enabled(enabled: bool) -> void:
	_pager.visible = enabled


## Set the singular noun shown in the count label (e.g. "channel"). Pluralised
## automatically. Used by the endpoint explorer to label non-document results.
func set_item_noun(noun: String) -> void:
	_item_noun = noun if not noun.is_empty() else "document"
	_update_count()


## Render the tree view's top-level rows as activity-log entries (Key =
## source/action/target, Value = result/error, failures highlighted). Only the
## tree view changes; the table and text views are unaffected.
func set_log_mode(enabled: bool) -> void:
	_tree_view.set_log_mode(enabled)


## Opens the document editor in insert mode (used by the sidebar's
## "Insert Document…" action via the database workspace, and the views' context menus).
func request_insert() -> void:
	_doc_dialog.open_insert()


## Reset to the first page and ask the owner to fetch it. Used when a fresh
## query is run.
func request_first_page() -> void:
	_offset = 0
	page_requested.emit(_offset, _limit)


## Display a page fetched from the backend at the current offset/limit. The
## array is exactly the rows to show; the total result size stays unknown.
func show_page(documents: Array) -> void:
	_documents = documents
	_update_count()
	_update_pager()
	_rebuild()


func _update_count() -> void:
	var n := _documents.size()
	_count_label.text = "%d %s%s" % [n, _item_noun, "" if n == 1 else "s"]


func _set_mode(mode: ViewMode) -> void:
	_mode = mode
	for i in _mode_buttons.size():
		_mode_buttons[i].button_pressed = (i == mode)
	_tree_view.visible = mode == ViewMode.TREE
	_table_view.visible = mode == ViewMode.TABLE
	_text_view.visible = mode == ViewMode.TEXT
	_rebuild()


func _rebuild() -> void:
	# The sub-views number rows by absolute index, so the page's first document
	# sits at _offset.
	match _mode:
		ViewMode.TREE:
			_tree_view.display(_documents, _offset)
		ViewMode.TABLE:
			_table_view.display(_documents, _offset)
		ViewMode.TEXT:
			_text_view.display(_documents)


# Pagination (server-side) ----------------------------------------------------
## Move to a new offset and request that page. No-op (beyond syncing the field)
## when the offset is unchanged, so a stray focus-out doesn't trigger a refetch.
func _set_offset(offset: int) -> void:
	var clamped := maxi(0, offset)
	if clamped == _offset:
		_offset_field.text = str(_offset)
		return
	_offset = clamped
	page_requested.emit(_offset, _limit)


func _apply_offset_field(_text: String = "") -> void:
	_set_offset(int(_offset_field.text))


func _apply_limit_field(_text: String = "") -> void:
	var new_limit := maxi(1, int(_limit_field.text))
	if new_limit == _limit:
		_limit_field.text = str(_limit)
		return
	_limit = new_limit
	# Changing the page size restarts from the first page.
	_offset = 0
	page_requested.emit(_offset, _limit)


func _update_pager() -> void:
	var n := _documents.size()
	_page_label.text = "0-0" if n == 0 else "%d-%d" % [_offset + 1, _offset + n]
	_offset_field.text = str(_offset)
	_limit_field.text = str(_limit)
	_prev_btn.disabled = _offset <= 0
	# A short page means there's nothing more to fetch.
	_next_btn.disabled = n < _limit


# Document actions (relayed from the active view) -----------------------------
# Sub-views report absolute indices (offset + row); convert to page-relative
# before touching the current page array.
func _on_edit_requested(doc_index: int) -> void:
	var local := doc_index - _offset
	if local < 0 or local >= _documents.size():
		return
	_doc_dialog.open_edit(local, JSON.stringify(_documents[local], "  "))


func _on_view_requested(doc_index: int) -> void:
	var local := doc_index - _offset
	if local < 0 or local >= _documents.size():
		return
	_doc_dialog.open_view(JSON.stringify(_documents[local], "  "))


func _on_delete_requested(doc_index: int) -> void:
	var local := doc_index - _offset
	if local < 0 or local >= _documents.size():
		return
	_documents.remove_at(local)
	_update_count()
	_update_pager()
	_rebuild()


func _on_document_inserted(text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_documents.append(parsed)
		_update_count()
		_update_pager()
		_rebuild()


# _on_document_updated receives the page-relative index passed to open_edit().
func _on_document_updated(index: int, text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary and index >= 0 and index < _documents.size():
		_documents[index] = parsed
		_rebuild()
