class_name TableResultsView
extends DocResultsView

## Grid view: one row per document, columns = union of top-level field names in
## the page. Columns hold a minimum width and clip overflow so collections with
## many fields scroll horizontally rather than squeezing cells unreadably narrow.
##
## In server-log mode the columns are driven by the Columns filter's selection (an
## attribute is a column when its switch is on, or when it's new and "auto-display new
## columns" is on), in a preferred order, with an optional "(other)" column collecting
## every hidden attribute as one JSON object. The selected table row is preserved
## across the rebuild that a column toggle (or a new poll) causes.

const TABLE_COLUMN_MIN_WIDTH := 160
## Wider minimum for the msg / "(other)" columns, whose content (a message, or a JSON
## object of inline fields) needs room to read.
const TABLE_WIDE_COLUMN_MIN_WIDTH := 360
## Preferred left-to-right order for the columns that exist; `msg` follows them and any
## other visible fields follow sorted. The "(other)" column, if shown, comes after those,
## and `level` sits at the very end (its colour-coded severity reads as a trailing flag).
const PREFERRED_ORDER := ["time", "level", "name", "section", "pid", "hostname"]
const OTHER_COLUMN := "(other)"
## Special keys in the column selection that aren't attribute columns.
const CATCH_ALL_KEY := "Default"

## The Columns filter's selection: { attribute -> shown }, plus CATCH_ALL_KEY (auto-
## display new attributes) and OTHER_COLUMN (show the JSON-of-hidden column).
var _col_selection: Dictionary = {}

## Emitted when a column title is right-clicked in server-log mode, carrying the cursor's
## absolute screen position — the log tab opens its Columns filter there (there's no
## toolbar button for it).
signal log_column_menu_requested(at_position: Vector2)


func _ready_view() -> void:
	column_title_clicked.connect(_on_column_title_clicked)


## Right-clicking a column title opens the Columns filter (server-log mode only); a
## left-click is left to the Tree's normal title behaviour.
func _on_column_title_clicked(_column: int, mouse_button_index: int) -> void:
	if _server_log and mouse_button_index == MOUSE_BUTTON_RIGHT:
		log_column_menu_requested.emit(DisplayServer.mouse_get_position())


## Set the column selection driving the server-log table layout (see the log tab).
func set_server_log_columns(selection: Dictionary) -> void:
	_col_selection = selection


func display(documents: Array, start_index: int) -> void:
	if _server_log:
		_display_server_log(documents, start_index)
		return

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


## Server-log layout: one column per selected (shown) attribute, plus the "(other)"
## JSON column when its toggle is on. The selected row is restored after the rebuild.
func _display_server_log(documents: Array, start_index: int) -> void:
	var selected_value: Variant = _selected_value()
	clear()

	var visible := _visible_columns(documents)
	var visible_set := {}
	for k in visible:
		visible_set[k] = true
	var titles := visible.duplicate()
	if bool(_col_selection.get(OTHER_COLUMN, false)):
		titles.append(OTHER_COLUMN)
	# Level goes last, after "(other)", so its colour-coded severity reads as a trailing
	# flag. It's kept in visible_set so the "(other)" JSON column doesn't repeat it.
	var level_visible := _level_column_visible(documents)
	if level_visible:
		visible_set["level"] = true
		titles.append("level")
	columns = maxi(1, titles.size())
	# The last column expands to fill spare width (no trailing gap) — but when Level is
	# last it stays narrow, so the column before it fills instead.
	var expand_col := titles.size() - 1
	if level_visible and titles.size() >= 2:
		expand_col = titles.size() - 2
	for c in titles.size():
		var title: String = titles[c]
		var wide := title == OTHER_COLUMN or title == "msg"
		set_column_title(c, title)
		set_column_custom_minimum_width(c, TABLE_WIDE_COLUMN_MIN_WIDTH if wide else TABLE_COLUMN_MIN_WIDTH)
		set_column_expand(c, c == expand_col)
		set_column_clip_content(c, true)

	var root := create_item()
	for i in documents.size():
		var doc: Dictionary = documents[i]
		var row := create_item(root)
		row.set_metadata(0, {"doc_index": start_index + i, "key": "", "name": "", "value": doc})
		for c in titles.size():
			var title: String = titles[c]
			if title == OTHER_COLUMN:
				var other := {}
				for key in doc:
					if not visible_set.has(key):
						other[key] = doc[key]
				row.set_text(c, JSON.stringify(other) if not other.is_empty() else "")
				row.set_custom_color(c, AppTheme.TEXT_DIM)
			elif title == "level" and doc.has("level"):
				row.set_text(c, LogEntry.level_label(int(doc["level"])))
				row.set_custom_color(c, LogEntry.level_color(int(doc["level"])))
			elif doc.has(title):
				row.set_text(c, _preview(doc[title]))
				row.set_custom_color(c, _value_color(doc[title]))
			else:
				row.set_text(c, "")

	_restore_selection(selected_value)


## The attribute columns to show, in preferred order: every union key whose switch is
## on (or, when unlisted, follows the auto-display catch-all). `level` is left out — it's
## appended last by the caller (see _display_server_log / _level_column_visible).
func _visible_columns(documents: Array) -> Array:
	var catch_all := bool(_col_selection.get(CATCH_ALL_KEY, true))
	var seen := {}
	for doc in documents:
		if doc is Dictionary:
			for key in doc:
				seen[key] = true
	var visible := {}
	for key in seen:
		if bool(_col_selection.get(key, catch_all)):
			visible[key] = true
	var ordered: Array = []
	for field in PREFERRED_ORDER:
		if field == "level":
			continue  # placed last, after "(other)"
		if visible.has(field):
			ordered.append(field)
	if visible.has("msg"):
		ordered.append("msg")
	var rest: Array = []
	for key in visible:
		if not PREFERRED_ORDER.has(key) and key != "msg":
			rest.append(key)
	rest.sort()
	ordered.append_array(rest)
	return ordered


## Whether the trailing Level column should show: some doc carries `level` and its switch
## is on (or, unlisted, follows the auto-display catch-all). Mirrors _visible_columns'
## rule for the one field it deliberately leaves out.
func _level_column_visible(documents: Array) -> bool:
	var present := false
	for doc in documents:
		if doc is Dictionary and doc.has("level"):
			present = true
			break
	if not present:
		return false
	var catch_all := bool(_col_selection.get(CATCH_ALL_KEY, true))
	return bool(_col_selection.get("level", catch_all))


## The `value` (the doc) of the currently-selected row, or null.
func _selected_value() -> Variant:
	var sel := get_selected()
	if sel == null:
		return null
	var meta: Variant = sel.get_metadata(0)
	return meta.get("value") if meta is Dictionary else null


## Re-select the row whose doc matches `value` (best-effort, single selection).
func _restore_selection(value: Variant) -> void:
	if value == null:
		return
	var root := get_root()
	if root == null:
		return
	var row := root.get_first_child()
	while row != null:
		var meta: Variant = row.get_metadata(0)
		if meta is Dictionary and meta.get("value") == value:
			set_selected(row, 0)
			return
		row = row.get_next()


func _collect_columns(docs: Array) -> Array:
	var cols: Array = []
	for doc in docs:
		for key in doc:
			if not cols.has(key):
				cols.append(key)
	return cols
