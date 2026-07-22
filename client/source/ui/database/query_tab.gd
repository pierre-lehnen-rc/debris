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
## database workspace can relabel the tab.
signal title_changed(title: String)

## Collection operations offered by the function dropdown. Only "find" paginates
## and yields a stream of documents; the rest return a single/bounded result.
const FUNCTIONS := ["find", "countDocuments", "explain", "listIndexes", "findOne"]

var connection_config: Dictionary = {}
## Filter from the last "Run". Page navigation reuses it so paging through
## results doesn't re-parse (and possibly choke on) in-progress editor edits.
var _active_filter: Dictionary = {}
## Extra find options (projection, sort) from the last "Run", captured alongside
## the filter so paging reuses them too.
var _active_options: Dictionary = {}
## Operation from the last "Run" (one of FUNCTIONS), so paging reuses it.
var _active_function := "find"
var connection_name := ""
var database_name := ""
var collection_name := ""
## Set once the user runs a query, so a tab that produced results is never
## treated as a blank scratch tab even after the fields are cleared.
var _has_run := false

@onready var _toolbar: PanelContainer = %Toolbar
@onready var _run_btn: Button = %RunBtn
@onready var _target_label: Label = %TargetLabel
@onready var _collection_edit: LineEdit = %CollectionEdit
@onready var _func_option: OptionButton = %FuncOption
@onready var _options_btn: Button = %OptionsBtn
@onready var _query_edit: CodeEdit = %QueryEdit
@onready var _options_edit: CodeEdit = %OptionsEdit
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


## True when this is a blank scratch tab — no collection targeted, no meaningful
## filter typed, and no query ever run — so opening a real collection can replace
## it instead of stacking a new tab.
func is_empty() -> bool:
	if _has_run:
		return false
	if not _collection_edit.text.strip_edges().is_empty():
		return false
	var filter := _query_edit.text.replace(" ", "").replace("\t", "").replace("\n", "")
	return filter.is_empty() or filter == "{}"


func _ready() -> void:
	_apply_style()

	for fn in FUNCTIONS:
		_func_option.add_item(fn)
	_func_option.select(0)

	_target_label.text = "%s  ›  %s  ›" % [connection_name, database_name]
	_collection_edit.text = collection_name
	if not collection_name.is_empty():
		_query_edit.text = "{}"
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


## Show/hide the secondary options editor when the "Options" button is toggled.
func _on_options_toggled(on: bool) -> void:
	_options_edit.visible = on


## Update the pager visibility when the operation changes: only find streams
## pages; the others return a single/bounded result.
func _on_function_selected(index: int) -> void:
	var fn: String = FUNCTIONS[index] if index >= 0 and index < FUNCTIONS.size() else "find"
	_results.set_pagination_enabled(fn == "find")


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

	var options: Variant = _parse_options()
	if options == null:
		return  # _parse_options already reported the error

	_active_filter = parsed["value"]
	_active_options = options
	_active_function = FUNCTIONS[_func_option.selected] if _func_option.selected >= 0 else "find"
	_has_run = true
	_results.request_first_page()


## Parse the options editor (projection/sort) into a Dictionary. Returns an empty
## Dictionary when the editor is hidden or blank, or null when the JSON is invalid
## (after emitting a status message).
func _parse_options() -> Variant:
	if not _options_edit.visible:
		return {}
	var text := _options_edit.text.strip_edges()
	if text.is_empty():
		return {}
	var parsed: Dictionary = LaxJson.parse_string(text)
	if not parsed.get("ok", false):
		status_changed.emit("Invalid options: %s" % parsed.get("error", "parse error"))
		return null
	if not (parsed.get("value") is Dictionary):
		status_changed.emit("Invalid options: expected an object")
		return null
	return parsed["value"]


## Sync collection_name from the editable field, updating the tab title when it
## changes.
func _retarget_collection() -> void:
	var entered := _collection_edit.text.strip_edges()
	if entered == collection_name:
		return
	collection_name = entered
	title_changed.emit(tab_title())


## Fetch a single page (or bounded result) from the backend, dispatching to the
## operation captured at the last Run. Only find uses the pager's offset/limit;
## the others ignore them. Wired to ResultsView.page_requested.
func _fetch_page(offset: int, limit: int) -> void:
	if collection_name.is_empty():
		_results.show_page([])
		return

	var spec := Backend.to_spec(connection_config)
	_run_btn.disabled = true
	status_changed.emit("Running %s on %s.%s…" % [_active_function, database_name, collection_name])

	var result: Dictionary
	match _active_function:
		"findOne":
			result = await Backend.find_one(spec, database_name, collection_name, _active_filter, _active_options)
		"countDocuments":
			result = await Backend.count(spec, database_name, collection_name, _active_filter)
		"explain":
			result = await Backend.explain(spec, database_name, collection_name, _active_filter, _active_options)
		"listIndexes":
			result = await Backend.list_indexes(spec, database_name, collection_name)
		_:
			result = await Backend.find(spec, database_name, collection_name, _active_filter, limit, offset, _active_options)
	_run_btn.disabled = false

	if not result.get("ok", false):
		_results.show_page([])
		status_changed.emit("%s failed: %s" % [_active_function, result.get("error", "unknown error")])
		return

	var rows := _rows_from(result.get("data"))
	_results.show_page(rows)
	if _active_function == "find":
		var first := (offset + 1) if rows.size() > 0 else 0
		var last := offset + rows.size()
		status_changed.emit("%s.%s — showing %d–%d" % [database_name, collection_name, first, last])
	else:
		status_changed.emit("%s.%s — %s returned %d row%s" % [
			database_name, collection_name, _active_function,
			rows.size(), "" if rows.size() == 1 else "s",
		])


## Normalise a response payload into the rows the results view shows: arrays pass
## through (find, listIndexes), a single object becomes one row (findOne, count,
## explain), and null/other becomes no rows (e.g. findOne with no match).
func _rows_from(data: Variant) -> Array:
	if data is Array:
		return data
	if data is Dictionary:
		return [data]
	return []
