class_name QueryTab
extends VBoxContainer

## A single query workspace: a JSON filter editor on top, results below, split
## vertically. "Run" executes a find against the configured collection via the
## backend, using the JSON filter from the editor, and displays the results.
## Layout lives in query_tab.tscn; configure() must be called before the node
## enters the tree so _ready() can seed the editor and target label.

signal status_changed(text: String)

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

	_target_label.text = "%s  ›  %s  ›  %s" % [connection_name, database_name, collection_name]
	if not collection_name.is_empty():
		_query_edit.text = "{}"

	_run_btn.pressed.connect(_run)
	_results.page_requested.connect(_fetch_page)
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


## Parse the editor's filter and (re)load from the first page. The results view
## then drives subsequent pages back through _fetch_page via page_requested.
func _run() -> void:
	if collection_name.is_empty():
		_results.show_page([])
		return

	var filter_variant: Variant = _parse_filter()
	if filter_variant == null:
		status_changed.emit("Invalid filter: expected a JSON object")
		return

	_active_filter = filter_variant
	_results.request_first_page()


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


## Parse the query editor as a JSON filter object. Returns {} for an empty
## query, or null when the text is not a valid JSON object (so the caller can
## report the error).
func _parse_filter() -> Variant:
	var text := _query_edit.text.strip_edges()
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return null
