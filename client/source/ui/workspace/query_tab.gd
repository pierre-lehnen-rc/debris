class_name QueryTab
extends VBoxContainer

## A single query workspace: an editable collection field plus a JSON filter
## editor on top, results below, split vertically. "Run" executes a find against
## the collection named in the field via the backend, using the JSON filter, and
## displays the results. The collection can be retargeted freely; an empty field
## means a blank tab that runs nothing until a name is entered.
## Layout lives in query_tab.tscn; configure() must be called before the node
## enters the tree so _ready() can seed the editor and target label.

signal status_changed(text: String)
## Emitted when the tab's title should change (collection retargeted), so the
## workspace can relabel the tab.
signal title_changed(title: String)
## Emitted when the user asks for a new empty tab on this same database.
signal new_tab_requested(connection: Dictionary, database: String)

var connection_config: Dictionary = {}
## Filter from the last "Run". Page navigation reuses it so paging through
## results doesn't re-parse (and possibly choke on) in-progress editor edits.
var _active_filter: Dictionary = {}
var connection_name := ""
var database_name := ""
var collection_name := ""

@onready var _toolbar: PanelContainer = %Toolbar
@onready var _run_btn: Button = %RunBtn
@onready var _target_label: Label = %TargetLabel
@onready var _collection_edit: LineEdit = %CollectionEdit
@onready var _new_tab_btn: Button = %NewTabBtn
@onready var _query_edit: CodeEdit = %QueryEdit
@onready var _results: ResultsView = %Results


func configure(connection: Dictionary, database: String, collection: String) -> void:
	connection_config = connection
	connection_name = connection.get("name", "")
	database_name = database
	collection_name = collection


## Exposes the results view so callers (e.g. the sidebar's "Insert Document…"
## action) can drive document actions on this tab.
func results() -> ResultsView:
	return _results


func tab_title() -> String:
	if collection_name.is_empty():
		return "Query"
	return "%s.%s" % [database_name, collection_name]


func _ready() -> void:
	_apply_style()

	_target_label.text = "%s  ›  %s  ›" % [connection_name, database_name]
	_collection_edit.text = collection_name
	if not collection_name.is_empty():
		_query_edit.text = "{}"

	_run_btn.pressed.connect(_run)
	_collection_edit.text_submitted.connect(func(_t: String) -> void: _run())
	_new_tab_btn.pressed.connect(
		func() -> void: new_tab_requested.emit(connection_config, database_name)
	)
	_results.page_requested.connect(_fetch_page)
	if not collection_name.is_empty():
		_run()


func _apply_style() -> void:
	var sb := AppTheme._flat(AppTheme.BG_DARK, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	_toolbar.add_theme_stylebox_override("panel", sb)
	_run_btn.add_theme_color_override("font_color", AppTheme.ACCENT_GREEN)
	_target_label.add_theme_color_override("font_color", AppTheme.TEXT_DIM)


## Parse the editor's filter and (re)load from the first page. The collection is
## read from the editable field each run, so it can be retargeted freely. The
## results view then drives subsequent pages back through _fetch_page.
func _run() -> void:
	_retarget_collection()
	if collection_name.is_empty():
		_results.show_page([])
		status_changed.emit("Enter a collection name to run a query")
		return

	var parsed: Dictionary = LaxJson.parse_string(_query_edit.text.strip_edges())
	if not parsed.get("ok", false):
		status_changed.emit("Invalid filter: %s" % parsed.get("error", "parse error"))
		return
	if not (parsed.get("value") is Dictionary):
		status_changed.emit("Invalid filter: expected an object")
		return

	_active_filter = parsed["value"]
	_results.request_first_page()


## Sync collection_name from the editable field, updating the tab title when it
## changes.
func _retarget_collection() -> void:
	var entered := _collection_edit.text.strip_edges()
	if entered == collection_name:
		return
	collection_name = entered
	title_changed.emit(tab_title())


## Fetch a single page from the backend using the pager's offset/limit and the
## last-run filter. Wired to ResultsView.page_requested.
func _fetch_page(offset: int, limit: int) -> void:
	if collection_name.is_empty():
		_results.show_page([])
		return

	_run_btn.disabled = true
	status_changed.emit("Running find on %s.%s…" % [database_name, collection_name])
	var result: Dictionary = await Backend.find(
		Backend.to_spec(connection_config),
		database_name,
		collection_name,
		_active_filter,
		limit,
		offset,
	)
	_run_btn.disabled = false

	if not result.get("ok", false):
		_results.show_page([])
		status_changed.emit("Find failed: %s" % result.get("error", "unknown error"))
		return

	var docs: Array = result.get("data") if result.get("data") is Array else []
	_results.show_page(docs)
	var first := (offset + 1) if docs.size() > 0 else 0
	var last := offset + docs.size()
	status_changed.emit("%s.%s — showing %d–%d" % [database_name, collection_name, first, last])
