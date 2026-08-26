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
## Bubbled up from the results view when a custom type action wants to open a new
## query tab on another collection with a pre-defined filter.
signal open_query_requested(collection: String, filter: Dictionary, function: String)
## Emitted when persistable state changes (a query was run, or the collection was
## retargeted), so the project can save the .debris-workspace sidecar.
signal state_changed()

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
## Operation to pre-select when the tab first opens (set via configure()).
var _initial_function := "find"
## Filter to seed the editor with when the tab first opens (set via configure()),
## e.g. from a custom type action. Empty means a blank "{}" filter.
var _initial_filter: Dictionary = {}
## Set by configure_restore() to reopen a saved tab: the editors are seeded from
## the persisted text verbatim and the query is NOT auto-run (results aren't
## saved, and restoring shouldn't fire requests). "" leaves the normal path.
var _restore_state: Dictionary = {}
## Schema driving custom types/actions in the results view.
var _schema: DatabaseSchema = null
## Shared per-project store of recent/favorite queries; set via set_history(). The
## history button browses and re-applies this collection's past queries, and each
## successful Run records one. Null in isolation (e.g. tests that don't wire it).
var _history: QueryHistory = null
## Lazily-created dropdown shown by the history button.
var _history_popup: QueryHistoryPopup = null
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
@onready var _history_btn: Button = %HistoryBtn
@onready var _query_edit: CodeEdit = %QueryEdit
@onready var _options_edit: CodeEdit = %OptionsEdit
@onready var _results: ResultsView = %Results


func configure(
	connection: Dictionary,
	database: String,
	collection: String,
	function: String = "find",
	initial_filter: Dictionary = {},
) -> void:
	connection_config = connection
	connection_name = connection.get("name", "")
	database_name = database
	collection_name = collection
	_initial_function = function
	_initial_filter = initial_filter


## Reopen a saved query tab (from the .debris-workspace sidecar). Binds the
## project's connection/database and stashes the persisted target + editor text
## for _ready to seed; the query is seeded but not run. `state` is a dict from
## to_state(). Call before the node enters the tree.
func configure_restore(connection: Dictionary, database: String, state: Dictionary) -> void:
	connection_config = connection
	connection_name = connection.get("name", "")
	database_name = database
	collection_name = String(state.get("collection", ""))
	_initial_function = String(state.get("function", "find"))
	_restore_state = state


## Snapshot this tab for the sidecar: its target and the current editor text, but
## never the results. Restored verbatim by configure_restore().
func to_state() -> Dictionary:
	return {
		"kind": "query",
		"database": database_name,
		"collection": _collection_edit.text,
		"function": FUNCTIONS[_func_option.selected] if _func_option.selected >= 0 else "find",
		"filter": _query_edit.text,
		"options": _options_edit.text,
		"options_visible": _options_btn.button_pressed,
	}


## Bind the shared query-history store (recents + favorites) this tab records into
## and its history button browses. Safe to call before or after _ready.
func set_history(history: QueryHistory) -> void:
	_history = history


## Set the schema used to resolve custom types/actions and push it to the results
## view (once this node is ready).
func set_schema(schema: DatabaseSchema) -> void:
	_schema = schema
	if is_node_ready():
		_results.set_type_context(_schema, collection_name)


## Exposes the results view so callers (e.g. the sidebar's "Insert Document…"
## action) can drive document actions on this tab.
func results() -> ResultsView:
	return _results


## Re-run the current query (from a keyboard shortcut). Public entry point mirroring
## the "Run" button, so the host can trigger it for the active tab.
func run_query() -> void:
	_run()


## Relay a results-view request to open a new query tab (custom type action).
func _on_results_open_query_requested(
	collection: String, filter: Dictionary, function: String
) -> void:
	open_query_requested.emit(collection, filter, function)


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
	var initial_index: int = maxi(FUNCTIONS.find(_initial_function), 0)
	_func_option.select(initial_index)
	_on_function_selected(initial_index)  # Sync pager visibility to the operation.

	_results.open_query_requested.connect(_on_results_open_query_requested)

	_target_label.text = "%s  ›  %s  ›" % [connection_name, database_name]
	_collection_edit.text = collection_name

	# Reopened from the sidecar: seed the editors from the persisted text verbatim
	# and stop — restoring must not re-run the query (results aren't saved, and a
	# restore shouldn't fire a request). The user re-runs with Run/F5.
	if not _restore_state.is_empty():
		_query_edit.text = String(_restore_state.get("filter", ""))
		_options_edit.text = String(_restore_state.get("options", ""))
		if bool(_restore_state.get("options_visible", false)):
			_options_btn.button_pressed = true
			_options_edit.visible = true
		return

	# Seed the filter editor whenever a filter was supplied — including a cross-tab
	# handoff that opens a blank-collection tab (a schema search action without a
	# target collection), so the filter survives until the user names the collection.
	if not _initial_filter.is_empty():
		# Indented so a generated filter (e.g. from a "List by" action) reads clearly
		# in the editor rather than as one long line.
		_query_edit.text = JSON.stringify(_initial_filter, "  ")
	if not collection_name.is_empty():
		if _initial_filter.is_empty():
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
	_run_btn.tooltip_text = "Run (F5)"
	_target_label.add_theme_color_override("font_color", AppTheme.TEXT_DIM)


## Show/hide the secondary options editor when the "Options" button is toggled.
func _on_options_toggled(on: bool) -> void:
	_options_edit.visible = on


## Open the recent/favorite query dropdown for the collection currently targeted in
## the field (so it reflects an as-yet-unrun retarget), anchored under the button.
func _on_history_pressed() -> void:
	if _history == null:
		return
	if _history_popup == null:
		_history_popup = QueryHistoryPopup.new()
		_history_popup.apply_requested.connect(apply_entry)
		add_child(_history_popup)
	_history_popup.configure(_history, _collection_edit.text.strip_edges())
	_history_popup.open_under(_history_btn)


## Snapshot the current editor contents as a saved-query entry (the shape recorded
## as a recent and stored as a favorite). Filter/options are the raw editor text so
## field order and formatting survive, mirroring how tabs persist to the sidecar.
func _current_entry() -> Dictionary:
	return {
		"function": _active_function,
		"filter": _query_edit.text,
		"options": _options_edit.text if _options_edit.visible else "",
		"options_visible": _options_edit.visible,
		"run_at": Time.get_datetime_string_from_system(true),
	}


## Load a saved query (from the history dropdown) into the editors without running
## it — consistent with tab restore; the user presses Run/F5 to execute.
func apply_entry(entry: Dictionary) -> void:
	var fn := String(entry.get("function", "find"))
	var idx := FUNCTIONS.find(fn)
	if idx >= 0:
		_func_option.select(idx)
		_on_function_selected(idx)
	_query_edit.text = String(entry.get("filter", ""))
	var opts := String(entry.get("options", ""))
	var show_opts := bool(entry.get("options_visible", not opts.strip_edges().is_empty()))
	_options_btn.button_pressed = show_opts
	_options_edit.visible = show_opts
	_options_edit.text = opts
	status_changed.emit("Loaded a saved query — press Run to execute")


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
	# The collection may have been retargeted; refresh the type context so custom
	# types/actions match the collection now being queried.
	_results.set_type_context(_schema, collection_name)
	_results.request_first_page()
	# Record this run in the collection's recent-query history (deduped/capped in the
	# store); QueryHistory persists the sidecar via its own change signal.
	if _history != null:
		_history.record(collection_name, _current_entry())
	# A run captures a persistable query/params snapshot for the sidecar.
	state_changed.emit()


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
	state_changed.emit()


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
