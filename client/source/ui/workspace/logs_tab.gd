class_name LogsTab
extends Control

## One view onto the project's shared server-log tail (LogStream), rendered through
## the same Tree/Table/Text results view the query, models, and endpoint tabs use, in
## its read-only server-log mode (log-shaped rows; see ResultsView.set_server_log_mode).
## Several may be open at once,
## each with its own client-side controls (text/level filters, clear); those
## act on what this view shows, not on the source. Start/stop is a source control and
## lives in the Server Logs sidebar panel.
##
## Transient: it holds no state worth persisting (the stream is live, the filters are
## per-view), so it isn't captured into the .debris-workspace sidecar.

const RESULTS_SCENE := preload("res://source/ui/database/results_view.tscn")

## The default Columns selection when no set is flagged default: the old grouped
## layout — the envelope fields + msg get columns, new/other attributes don't (they
## fall into the "(other)" JSON column), and auto-display-new is off.
const COLUMN_DEFAULT := {
	"time": true, "level": true, "name": true, "section": true, "pid": true, "hostname": true,
	"msg": true, "Default": false, "(other)": true,
}

# Untyped (not `: LogStream`) on purpose: LogStream reaches for autoloads, and typing
# against it would drag this view into that dependency. Methods are resolved dynamically.
var _stream = null

## Emitted when a persistable filter changes, so the project re-saves the sidecar.
signal state_changed()

var _text_filter := ""
# Level label -> whether entries at that level are shown. A level whose label isn't
# in the map defaults to shown.
var _allowed_levels: Dictionary = {}
# Time-of-day window in seconds since midnight; -1 means the bound is unset.
var _time_start := -1.0
var _time_end := -1.0

# The project's shared saved-set stores (names + columns), handed to the filters.
var _name_sets: SavedSets = null
var _column_sets: SavedSets = null

var _filter_edit: LineEdit = null
var _level_menu: MenuButton = null
var _name_filter: CheckFilter = null
var _column_filter: CheckFilter = null
var _start_edit: LineEdit = null
var _end_edit: LineEdit = null
var _results: ResultsView = null
# Saved filter state to apply once the UI is built and the name filter populated
# (set by configure_restore before the tab is bound). Empty for a fresh tab.
var _pending_state: Dictionary = {}


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()
	_refresh()


func tab_title() -> String:
	return "Server Logs"


## Reopen from a sidecar snapshot: the saved filters are applied once the stream is
## bound (the name filter needs the stream's known names first). Call before binding.
func configure_restore(state: Dictionary) -> void:
	_pending_state = state


## The persistable state of this view: its filters (not the live buffer, nor pause).
func to_state() -> Dictionary:
	return {
		"kind": "logs",
		"text": _filter_edit.text if _filter_edit != null else "",
		"levels": _allowed_levels.duplicate(),
		"names": _name_filter.selection() if _name_filter != null else {},
		"columns": _column_filter.selection() if _column_filter != null else {},
		"time_start": _start_edit.text if _start_edit != null else "",
		"time_end": _end_edit.text if _end_edit != null else "",
	}


## Apply a saved filter state to the (already-built, name-populated) UI.
func _apply_state(state: Dictionary) -> void:
	var text := str(state.get("text", ""))
	_filter_edit.text = text
	_text_filter = text.strip_edges().to_lower()

	var levels: Dictionary = state.get("levels", {}) if state.get("levels") is Dictionary else {}
	var level_popup := _level_menu.get_popup()
	for i in LogEntry.LEVEL_FILTER_LABELS.size():
		var label: String = LogEntry.LEVEL_FILTER_LABELS[i]
		var on := bool(levels.get(label, true))
		_allowed_levels[label] = on
		level_popup.set_item_checked(level_popup.get_item_index(i), on)

	var names: Dictionary = state.get("names", {}) if state.get("names") is Dictionary else {}
	if not names.is_empty():
		_name_filter.apply_selection(names)
	var columns: Dictionary = state.get("columns", {}) if state.get("columns") is Dictionary else {}
	if not columns.is_empty():
		# The saved selection is this tab's own layout, so let it — not the generic
		# COLUMN_DEFAULT — govern columns discovered after restore (a restored tab binds
		# before any line arrives, so every column is "discovered" later). Envelope
		# fields still fall back to COLUMN_DEFAULT for anything the save didn't record.
		var template := COLUMN_DEFAULT.duplicate()
		template.merge(columns, true)
		_column_filter.set_default_selection(template)
		_column_filter.apply_selection(columns)

	_start_edit.text = str(state.get("time_start", ""))
	_end_edit.text = str(state.get("time_end", ""))
	_time_start = _time_bound(_start_edit.text)
	_time_end = _time_bound(_end_edit.text)


## Attach to the project's shared tail: render its current backlog, then follow it.
## `stream` is a LogStream (untyped for the isolated-compile reason above).
func bind_stream(stream) -> void:
	_stream = stream
	stream.entries_added.connect(_on_stream_changed)
	stream.cleared.connect(_refresh)
	stream.names_discovered.connect(_on_names_discovered)
	_name_filter.set_items(stream.known_names())
	_column_filter.set_items(_column_keys_in(_buffer()))
	if not _pending_state.is_empty():
		_apply_state(_pending_state)
		_pending_state = {}
	else:
		# A fresh tab starts from the project's default sets, if any are flagged.
		if _name_sets != null and not _name_sets.default_selection().is_empty():
			_name_filter.apply_selection(_name_sets.default_selection())
		if _column_sets != null and not _column_sets.default_selection().is_empty():
			_column_filter.apply_selection(_column_sets.default_selection())
	_push_columns()
	_refresh()


## Hand the filters the project's shared saved-set stores. Call before bind_stream.
func set_filter_sets(name_sets: SavedSets, column_sets: SavedSets) -> void:
	_name_sets = name_sets
	_column_sets = column_sets
	if _name_filter != null:
		_name_filter.bind_sets(name_sets)
	if _column_filter != null:
		_column_filter.bind_sets(column_sets)


## New logger names appeared: add them to the Names filter, then re-render.
func _on_names_discovered(new_names: Array) -> void:
	for name in new_names:
		_name_filter.add_item(str(name))
	_refresh()


func _on_name_filter_changed() -> void:
	_refresh()
	state_changed.emit()


## The Columns filter changed: push the new visible-column spec to the table and
## persist. (The Columns filter never hides rows, only columns, so no re-filtering.)
func _on_column_filter_changed() -> void:
	_push_columns()
	state_changed.emit()


## Open the Columns filter at the cursor — wired to a right-click on a Table column
## title (the filter has no toolbar button of its own).
func _open_column_menu(at_position: Vector2) -> void:
	if _column_filter != null:
		_column_filter.open_at(at_position)


## Give the results view the current column selection so the Table renders it.
func _push_columns() -> void:
	if _results != null and _column_filter != null:
		_results.set_server_log_columns(_column_filter.selection())


## The union of attribute keys across the given log docs (for the Columns filter).
func _column_keys_in(docs: Array) -> Array:
	var keys: Dictionary = {}
	for entry in docs:
		var doc: Dictionary = entry.get("doc", {}) if entry.get("doc") is Dictionary else {}
		for key in doc:
			keys[key] = true
	return keys.keys()


## The fixed envelope columns — the ones a pino record structurally always carries.
## The "Default" group is exactly these (that actually exist as columns): membership is
## by identity, NOT by "happens to be on every shown line" — a non-envelope attribute
## that's universal only because the log is filtered is Current, not Default. This
## doubles as the group's left-to-right order.
const DEFAULT_COLUMNS := ["time", "level", "name", "pid", "hostname", "msg"]


## Classify the known column keys for the Columns filter's Default / Current / Extra
## tree:
##   Default — the fixed envelope columns (DEFAULT_COLUMNS) that exist,
##   Current — any other attribute on some line currently shown in the table
##             (`_visible_docs`, i.e. after the row filters),
##   Extra   — every other known attribute (on no shown line: only on filtered-out
##             lines, or seen earlier and since scrolled/trimmed away).
func _column_groups() -> Dictionary:
	var is_default: Dictionary = {}
	for k in DEFAULT_COLUMNS:
		is_default[k] = true
	var shown_keys: Dictionary = {}
	for doc in _visible_docs():
		if doc is Dictionary:
			for k in doc:
				shown_keys[str(k)] = true

	var default_g: Array = []
	var current_g: Array = []
	var extra_g: Array = []
	for key in _column_filter.item_keys():
		var k := str(key)
		if is_default.has(k):
			default_g.append(k)
		elif shown_keys.has(k):
			current_g.append(k)
		else:
			extra_g.append(k)
	return {
		"Default": _ordered_default(default_g),
		"Current": _ordered_columns(current_g),
		"Extra": _ordered_columns(extra_g),
	}


## Order the Default group by the fixed envelope order.
func _ordered_default(keys: Array) -> Array:
	var ordered: Array = []
	for field in DEFAULT_COLUMNS:
		if keys.has(field):
			ordered.append(field)
	return ordered


## Order a Current/Extra group alphabetically (these hold only non-envelope attributes).
func _ordered_columns(keys: Array) -> Array:
	var sorted := keys.duplicate()
	sorted.sort()
	return sorted


## Whether the shared stream has been bound yet. False for a tab restored before the
## stream exists; WorkspaceCenter.bind_log_stream binds it once the stream arrives.
func has_stream() -> bool:
	return _stream != null


## Whether the shared saved-set stores have been handed over yet (see set_filter_sets).
func has_filter_sets() -> bool:
	return _name_sets != null


## Exposes the results view, matching the other tabs (for driving its view mode).
func results() -> ResultsView:
	return _results


func _on_stream_changed(new_entries: Array) -> void:
	# Insert just the new lines (newest first) at the top, rather than re-rendering
	# the whole page — so a row the user expanded or selected, and their scroll, are
	# left undisturbed while the tail keeps flowing.
	# New attributes may bring new columns to offer in the Columns filter. When any is
	# new, re-push the selection: the table's copy was taken when the tab bound (for a
	# restored tab, before any line arrived, so it held only the special keys), and a
	# newly-added column has to reach it or it stays hidden behind the catch-all.
	var columns_grew := false
	for key in _column_keys_in(new_entries):
		if _column_filter.add_item(str(key)):
			columns_grew = true
	if columns_grew:
		_push_columns()
	var new_docs: Array = []
	for i in range(new_entries.size() - 1, -1, -1):
		var entry: Dictionary = new_entries[i]
		if _passes(entry):
			new_docs.append(entry.get("doc", {}))
	if not new_docs.is_empty():
		_results.add_log_documents(new_docs)


# UI --------------------------------------------------------------------------
func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	var toolbar := PanelContainer.new()
	toolbar.add_theme_stylebox_override("panel", AppTheme._flat(AppTheme.BG_DARK, 0))
	column.add_child(toolbar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 6)
	pad.add_child(row)
	toolbar.add_child(pad)

	_filter_edit = LineEdit.new()
	_filter_edit.placeholder_text = "Filter lines…"
	_filter_edit.clear_button_enabled = true
	_filter_edit.custom_minimum_size = Vector2(200, 0)
	_filter_edit.text_changed.connect(_on_filter_changed)
	row.add_child(_filter_edit)

	# Level filter: a multi-select of the levels to show. All on by default.
	_level_menu = MenuButton.new()
	_level_menu.text = "Levels"
	_level_menu.focus_mode = Control.FOCUS_NONE
	var level_popup := _level_menu.get_popup()
	level_popup.hide_on_checkable_item_selection = false
	for i in LogEntry.LEVEL_FILTER_LABELS.size():
		var label: String = LogEntry.LEVEL_FILTER_LABELS[i]
		level_popup.add_check_item(label, i)
		level_popup.set_item_checked(i, true)
		_allowed_levels[label] = true
	level_popup.id_pressed.connect(_on_level_toggled)
	row.add_child(_level_menu)

	# Name filter: a multi-select of the loggers' names with saved sets, filled from
	# the stream's known names in bind_stream(). "Auto-display new names" governs
	# lines whose logger name isn't listed (new/unseen).
	_name_filter = CheckFilter.new()
	_name_filter.changed.connect(_on_name_filter_changed)
	row.add_child(_name_filter)
	_name_filter.setup("Names", [{
		"key": "Default", "label": "Auto-display new names",
		"tooltip": "Show log lines whose logger name isn't listed below (new or unseen names)",
	}], "Default")

	# Column filter (Table view): which attributes get their own column. "Auto-display
	# new columns" governs newly-seen attributes; "(other)" adds a column of the rest.
	# It has no toolbar button — it's opened by right-clicking a Table column title (see
	# _open_column_menu) — so it lives hidden in the tree purely to host its popup.
	_column_filter = CheckFilter.new()
	_column_filter.visible = false
	_column_filter.changed.connect(_on_column_filter_changed)
	add_child(_column_filter)
	_column_filter.setup("Columns", [
		{
			"key": "Default", "label": "Auto-display new columns", "checked": false,
			"tooltip": "Give newly-seen attributes their own column",
		},
		{
			"key": "(other)", "label": "Show \"(other)\" column", "checked": true,
			"tooltip": "A column with every hidden attribute as one JSON object",
		},
	], "Default")
	_column_filter.set_default_selection(COLUMN_DEFAULT)
	# Group the column list into Default / Current / Extra (see _column_groups).
	_column_filter.set_grouping(["Default", "Current", "Extra"], _column_groups)

	# Time-of-day range filter (start/end). Empty bounds are unset.
	var time_label := Label.new()
	time_label.text = "Time"
	time_label.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	row.add_child(time_label)
	_start_edit = _make_time_field("from (HH:MM:SS)")
	row.add_child(_start_edit)
	_end_edit = _make_time_field("to (HH:MM:SS)")
	row.add_child(_end_edit)

	# The shared results view, in server-log mode: the lines are read-only records
	# shown in Tree/Table/Text, with log-shaped rows (see ResultsView.set_server_log_mode).
	# No pagination — the buffer is the page.
	_results = RESULTS_SCENE.instantiate()
	_results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_results)
	_results.set_server_log_mode(true)
	_results.set_pagination_enabled(false)
	_results.set_item_noun("line")
	# The Columns filter opens from a right-click on a Table column title, not a button.
	_results.log_column_menu_requested.connect(_open_column_menu)


func _on_filter_changed(text: String) -> void:
	_text_filter = text.strip_edges().to_lower()
	_refresh()
	state_changed.emit()


func _on_level_toggled(id: int) -> void:
	var popup := _level_menu.get_popup()
	var idx := popup.get_item_index(id)
	var checked := not popup.is_item_checked(idx)
	popup.set_item_checked(idx, checked)
	_allowed_levels[LogEntry.LEVEL_FILTER_LABELS[id]] = checked
	_refresh()
	state_changed.emit()


## A narrow time-of-day input for the range filter.
func _make_time_field(placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(120, 0)
	edit.tooltip_text = "Time of day (HH:MM or HH:MM:SS). Leave empty for no bound."
	edit.text_changed.connect(_on_time_changed)
	return edit


func _on_time_changed(_text: String) -> void:
	_time_start = _time_bound(_start_edit.text)
	_time_end = _time_bound(_end_edit.text)
	_refresh()
	state_changed.emit()


## Parse a time-field's text into seconds since midnight, or -1 when empty/unparseable.
func _time_bound(text: String) -> float:
	if text.strip_edges().is_empty():
		return -1.0
	return LogEntry.time_of_day_seconds(text)


# Rendering -------------------------------------------------------------------
## Re-render the shown page: the filtered backlog, newest first, as a raw array.
func _refresh() -> void:
	if _results == null:
		return
	_results.show_page(_visible_docs())


## The docs to show: every buffered line passing the filters, its display `doc`,
## newest first (so the latest line is at the top without scrolling).
func _visible_docs() -> Array:
	var docs: Array = []
	for entry in _buffer():
		if _passes(entry):
			docs.append(entry.get("doc", {}))
	docs.reverse()
	return docs


## A line is shown when its text matches the filter and, for a level-carrying line,
## its level is at or above the floor. Level-less lines (a non-JSON source, or an
## unparsed line) are never hidden by the level filter — only by the text filter.
func _passes(entry: Dictionary) -> bool:
	if not _text_filter.is_empty() and not str(entry.get("raw", "")).to_lower().contains(_text_filter):
		return false
	if bool(entry.get("structured", false)):
		var label := LogEntry.level_label(int(entry.get("level", 0)))
		if not bool(_allowed_levels.get(label, true)):
			return false
	# Name filter (a listed name uses its own switch; anything else follows Default).
	var doc: Dictionary = entry.get("doc", {}) if entry.get("doc") is Dictionary else {}
	if not _name_filter.allows(str(doc.get("name", ""))):
		return false
	# Time-of-day window: while a bound is set, a line outside it — or with no time to
	# place — is hidden.
	if _time_start >= 0.0 or _time_end >= 0.0:
		var t := LogEntry.time_of_day_seconds(str(doc.get("time", "")))
		if t < 0.0:
			return false
		if _time_start >= 0.0 and t < _time_start:
			return false
		if _time_end >= 0.0 and t > _time_end:
			return false
	return true


func _buffer() -> Array:
	return _stream.buffer() if _stream != null else []
