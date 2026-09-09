extends "res://dev/check_base.gd"

## Check for the Server Logs feature: the log-line parser, the tap poll (through the
## Backend mock, cursor and all), and the log tab's ingest/filter/render behaviour.
##
## The parser is the seam that keeps the feature source-agnostic — the injected tap
## emits pino NDJSON today, but a future file source will emit pino-pretty text — so
## the emphasis here is that a non-JSON line survives as a plain line and is never
## dropped or hidden by the level filter, right beside the structured pino path.
##
## Runs against the fixture mock, whose /api/rocketchat/logs serves a fixed set of
## lines (mixed levels, a section, a custom level, and one non-JSON line) and honours
## the `since` cursor.
##
## log_stream.gd / logs_tab.gd reach for the Backend/ServerManager autoloads, so they
## are load()ed at runtime, not preload()ed — a `-s` main-loop script compiles before
## the autoloads register, and a top-level preload would fail to resolve them.

const LOGS_TAB_PATH := "res://source/ui/workspace/logs_tab.tscn"
const LOG_STREAM_PATH := "res://source/data/log_stream.gd"


# Loaded at runtime (their base reaches for shared UI that can touch autoloads).
const TREE_VIEW_PATH := "res://source/ui/database/results/tree_results_view.gd"
const TABLE_VIEW_PATH := "res://source/ui/database/results/table_results_view.gd"


func _run() -> void:
	_parses_pino_records()
	_falls_back_for_non_json()
	_level_labels()
	_level_colors()
	_time_parsing()
	_server_log_message_value()
	_table_columns_from_selection()
	_table_level_column_last()
	await _table_preserves_selection()
	_state_caches_log_names()
	_doc_stores_name_sets()
	await _name_filter_widget()
	await _column_filter_default()
	await _mock_serves_logs_with_cursor()
	await _stream_polls_and_logs_transitions()
	await _stream_discovers_names()
	await _tab_renders_stream_and_filters()
	await _tab_persists_filters()
	await _restored_tab_binds_when_stream_arrives()
	await _restored_columns_show_when_lines_arrive()
	await _column_menu_opens_on_title_right_click()
	await _column_groups_split()


# Logger-name caching + discovery ---------------------------------------------
func _state_caches_log_names() -> void:
	var state: Variant = load("res://source/data/workspace_state.gd")
	var st: Variant = state.new()
	st.set_log_names("http://localhost:3000", ["API", "Cron"])
	expect_eq(st.cached_log_names("http://localhost:3000"), ["API", "Cron"], "the names cache round-trips")
	expect_eq(st.cached_log_names("http://other:3000"), [], "a different URL has no cached names")
	var restored: Variant = state.from_dict(st.to_dict())
	expect_eq(restored.cached_log_names("http://localhost:3000"), ["API", "Cron"], "and survives to_dict/from_dict")


## Sets are saved per kind in the project file, flagged default, and round-trip. The
## "names" and "columns" kinds are independent.
func _doc_stores_name_sets() -> void:
	var doc_cls: Variant = load("res://source/data/workspace_document.gd")
	var sets_cls: Variant = load("res://source/data/saved_sets.gd")
	var doc: Variant = doc_cls.new()
	var sets: Variant = sets_cls.new()
	sets.setup(doc, "names")
	sets.save("errors only", {"Default": false, "API": true})
	expect_eq((sets.list() as Array).size(), 1, "a set is saved")
	sets.set_default("errors only", true)
	expect(sets.is_default("errors only"), "and can be flagged the default")
	expect_eq(sets.default_selection(), {"Default": false, "API": true}, "default_selection returns its selection")

	# The columns kind is a separate store, unaffected by the names kind.
	var col_sets: Variant = sets_cls.new()
	col_sets.setup(doc, "columns")
	expect_eq((col_sets.list() as Array).size(), 0, "the columns kind is independent of names")

	var doc2: Variant = doc_cls.from_dict(doc.to_dict())
	var sets2: Variant = sets_cls.new()
	sets2.setup(doc2, "names")
	expect_eq(sets2.default_selection(), {"Default": false, "API": true}, "sets persist in the project file")

	sets.remove("errors only")
	expect_eq((sets.list() as Array).size(), 0, "a set can be removed")


## The CheckFilter widget: select all/none, catch-all, and apply_selection.
func _name_filter_widget() -> void:
	var nf: Variant = load("res://source/ui/workspace/check_filter.gd").new()
	root.add_child(nf)
	nf.setup("Names", [{"key": "Default", "label": "Auto-display new names", "tooltip": ""}], "Default")
	await create_timer(0.05).timeout
	nf.set_items(["API", "Cron"])
	expect(nf.allows("API"), "every item is shown by default")
	expect(nf.allows("Unlisted"), "an unlisted item follows the catch-all (shown)")

	nf._set_all(false)
	expect(not nf.allows("API"), "select none hides listed items")
	expect(nf.allows("Unlisted"), "but leaves the catch-all on, so unlisted items still show")
	nf._selection["Default"] = false
	expect(not nf.allows("Unlisted"), "turning the catch-all off hides unlisted items")

	nf.apply_selection({"Default": true, "API": false})
	expect(not nf.allows("API"), "apply_selection turns API off")
	expect(nf.allows("Cron"), "leaves Cron on (follows the set's catch-all)")
	expect(nf.allows("Unlisted"), "and unlisted items follow the set's catch-all (on)")
	nf.queue_free()


## The Columns filter's fresh default: envelope columns shown, auto-display off, so a
## non-default (or newly-discovered) attribute stays hidden.
func _column_filter_default() -> void:
	var cf: Variant = load("res://source/ui/workspace/check_filter.gd").new()
	root.add_child(cf)
	cf.setup("Columns", [
		{"key": "Default", "label": "auto", "checked": false, "tooltip": ""},
		{"key": "(other)", "label": "other", "checked": true, "tooltip": ""},
	], "Default")
	await create_timer(0.05).timeout
	cf.set_default_selection({"time": true, "msg": true, "section": true, "Default": false, "(other)": true})
	cf.set_items(["time", "msg", "method"])
	expect(cf.value("time") and cf.value("msg"), "envelope columns are shown by default")
	expect(not cf.value("method"), "a non-default column is hidden (auto-display off)")
	expect(not cf.value("Default"), "auto-display new columns defaults off")
	expect(cf.value("(other)"), "the (other) column shows by default")
	cf.add_item("url")
	expect(not cf.value("url"), "a newly-discovered column stays hidden while auto-display is off")
	cf.add_item("section")
	expect(cf.value("section"), "but a discovered envelope column shows per the template")
	cf.queue_free()


func _stream_discovers_names() -> void:
	var stream: Variant = _make_stream("/tmp/rc")
	stream.seed_known_names(["Cached"])
	var announced: Array = []
	stream.names_discovered.connect(func(names: Array) -> void: announced.append_array(names))
	stream._streaming = true
	await stream._poll()
	var known: Array = stream.known_names()
	expect(known.has("Cached"), "seeded (cached) names are known up front")
	expect(known.has("API"), "names from the lines are discovered")
	expect(announced.has("API"), "a newly-seen name is announced")
	expect(not announced.has("Cached"), "an already-known name is not re-announced")
	stream.queue_free()


# Tree/Table server-log rendering ---------------------------------------------
func _level_labels() -> void:
	expect_eq(LogEntry.level_label(10), "trace", "10 is trace")
	expect_eq(LogEntry.level_label(20), "debug", "20 is debug")
	expect_eq(LogEntry.level_label(30), "info", "30 is info")
	expect_eq(LogEntry.level_label(35), "info", "Rocket.Chat's 35 reads as info")
	expect_eq(LogEntry.level_label(40), "warn", "40 is warn")
	expect_eq(LogEntry.level_label(50), "error", "50 is error")
	expect_eq(LogEntry.level_label(51), "startup", "Rocket.Chat's 51 is startup")
	expect_eq(LogEntry.level_label(60), "fatal", "60 is fatal")


## The Level column's severity colours: error and fatal are reds, warn amber, and each
## band is distinct so the colour alone tells the severity apart (startup checked first).
func _level_colors() -> void:
	var error := LogEntry.level_color(50)
	var fatal := LogEntry.level_color(60)
	var warn := LogEntry.level_color(40)
	var info := LogEntry.level_color(30)
	var startup := LogEntry.level_color(51)
	expect(error.r > 0.6 and error.r > error.g and error.r > error.b, "error is a red")
	expect(fatal.r > 0.6 and fatal.r > fatal.g and fatal.r > fatal.b, "fatal is a red")
	expect(fatal != error, "fatal and error are distinguishable")
	expect(warn != error and info != warn, "warn and info differ from their neighbours")
	expect(startup != error and startup != info, "startup keeps its own colour")


func _time_parsing() -> void:
	expect_eq(LogEntry.time_of_day_seconds("2026-09-01T16:22:05.500Z"), 16 * 3600 + 22 * 60 + 5.5, "an ISO timestamp gives its time of day")
	expect_eq(LogEntry.time_of_day_seconds("16:22"), 16 * 3600.0 + 22 * 60.0, "a bare HH:MM parses")
	expect_eq(LogEntry.time_of_day_seconds(""), -1.0, "empty is unbounded")
	expect_eq(LogEntry.time_of_day_seconds("garbage"), -1.0, "an unparseable value is unbounded")


func _server_log_message_value() -> void:
	var tree: Variant = load(TREE_VIEW_PATH)
	# The Message column shows msg when present, else the dynamic (non-column) attributes as JSON.
	expect_eq(tree.server_log_value({"time": "t", "level": 30, "msg": "hello"}), "hello", "msg is the message when present")
	expect_eq(
		tree.server_log_value({"time": "t", "level": 30, "name": "Cron", "jobId": 7}),
		'{"jobId":7}',
		"without msg, the message is the dynamic attributes as JSON",
	)


func _table_columns_from_selection() -> void:
	var table: Variant = load(TABLE_VIEW_PATH).new()
	var docs := [
		{"time": "t1", "level": 30, "name": "API", "method": "GET", "msg": "a"},
		{"time": "t2", "level": 30, "name": "Cron", "msg": "b"},
	]
	# Show time+level, hide method, and leave name/msg to auto-display (on): the
	# visible columns come in preferred order, then msg, then the rest sorted. `level` is
	# excluded here — it's appended last (after "(other)") by _display_server_log.
	table.set_server_log_columns({"Default": true, "(other)": false, "time": true, "level": true, "method": false})
	var cols: Array = table._visible_columns(docs)
	expect_eq(cols, ["time", "name", "msg"], "visible columns are ordered; level and a hidden one (method) are excluded")
	expect(table._level_column_visible(docs), "level is visible (shown by its switch)")

	# Turn auto-display off: only explicitly-shown columns remain (still without level).
	table.set_server_log_columns({"Default": false, "time": true, "level": true})
	expect_eq(table._visible_columns(docs), ["time"], "with auto-display off, only shown columns appear")
	expect(table._level_column_visible(docs), "level stays visible via its own switch")

	# Hide level: the trailing column drops out.
	table.set_server_log_columns({"Default": false, "time": true, "level": false})
	expect(not table._level_column_visible(docs), "a hidden level switch drops the trailing column")
	table.free()


## Level renders as the very last column — after "(other)" — so its colour-coded
## severity reads as a trailing flag.
func _table_level_column_last() -> void:
	var table: Variant = load(TABLE_VIEW_PATH).new()
	root.add_child(table)
	table._server_log = true
	var docs := [{"time": "t1", "level": 30, "name": "API", "method": "GET", "msg": "a"}]
	table.set_server_log_columns({"Default": true, "(other)": true, "level": true})
	table.display(docs, 0)
	var last: int = table.columns - 1
	expect_eq(table.get_column_title(last), "level", "level is the last column")
	expect_eq(table.get_column_title(last - 1), "(other)", "\"(other)\" sits just before level")
	table.queue_free()


## The Table keeps its selected row across the rebuild a column toggle causes.
func _table_preserves_selection() -> void:
	var table: Variant = load(TABLE_VIEW_PATH).new()
	root.add_child(table)
	table._server_log = true
	table.set_server_log_columns({"Default": true, "(other)": false})
	var docs := [
		{"time": "t1", "level": 30, "name": "A", "msg": "one"},
		{"time": "t2", "level": 40, "name": "B", "msg": "two"},
	]
	table.display(docs, 0)
	var second: Variant = table.get_root().get_first_child().get_next()
	table.set_selected(second, 0)
	var selected_before: Variant = table.get_selected().get_metadata(0).get("value")

	# Toggle a column off — the table rebuilds.
	table.set_server_log_columns({"Default": true, "(other)": false, "level": false})
	table.display(docs, 0)
	expect(table.get_selected() != null, "a selected row survives a column-toggle rebuild")
	if table.get_selected() != null:
		expect_eq(table.get_selected().get_metadata(0).get("value"), selected_before, "and it's the same row")
	table.queue_free()


# Parser ----------------------------------------------------------------------
func _parses_pino_records() -> void:
	var e := LogEntry.parse(7, '{"level":50,"time":"2026-09-01T12:00:03.300Z","name":"Rooms","section":"sync","msg":"boom"}')
	expect_eq(e["seq"], 7, "the sequence number is carried through")
	expect(e["structured"], "a pino record parses as structured")
	expect_eq(e["level"], 50, "the numeric level is read for the filter")
	# The doc shown in the results view is the record itself, verbatim.
	var doc: Dictionary = e["doc"]
	expect_eq(doc.get("name"), "Rooms", "the record is shown as-is (logger name)")
	expect_eq(doc.get("msg"), "boom", "and its message")
	expect_eq(doc.get("section"), "sync", "and its section")


func _falls_back_for_non_json() -> void:
	# The line a file source of pino-pretty text (or a plain banner) would produce.
	var plain := LogEntry.parse(1, "==> Rocket.Chat is ready")
	expect(not plain["structured"], "a non-JSON line is not treated as structured")
	expect_eq((plain["doc"] as Dictionary).get("msg"), "==> Rocket.Chat is ready", "its raw text becomes the doc's msg")
	expect_eq(plain["level"], 0, "and it carries no level, so the level filter can't hide it")

	# JSON that isn't a pino record (no numeric level) is still shown as its object.
	var not_a_record := LogEntry.parse(2, '{"hello":"world"}')
	expect(not not_a_record["structured"], "JSON without a numeric level is not a log record")
	expect_eq((not_a_record["doc"] as Dictionary).get("hello"), "world", "but is shown as the object it is")


# Poll + cursor ---------------------------------------------------------------
func _mock_serves_logs_with_cursor() -> void:
	var target := {"repoPath": "/tmp/rc", "url": "http://localhost:3000"}
	var first: Dictionary = await backend.rocketchat_logs(target, 0)
	expect(first.get("ok", false), "a logs poll succeeds against an injected bridge")
	var data: Dictionary = first.get("data", {})
	expect_eq(data.get("seq", 0), 5, "the high-water sequence is reported")
	expect_eq((data.get("entries", []) as Array).size(), 5, "since 0 returns the whole buffer")

	# Polling from the high-water mark returns nothing new — the cursor advanced.
	var second: Dictionary = await backend.rocketchat_logs(target, 5)
	expect_eq(((second.get("data", {}) as Dictionary).get("entries", []) as Array).size(), 0,
		"since the high-water mark returns no repeats")

	# Watching the tail is not an action — it must stay out of the Activity Log.
	activity_log.clear()
	await backend.rocketchat_logs(target, 0)
	expect_eq(activity_log.entries().size(), 0, "a logs poll records nothing")


# Stream engine ---------------------------------------------------------------
## Drive the shared stream through polls (mock-backed, skipping the ServerManager
## connect step) and check the cursor plus the transition-based Activity Log: a clean
## tail records nothing, a failure records once (and only once), so a 404 is surfaced
## without a per-poll flood.
func _stream_polls_and_logs_transitions() -> void:
	var stream: Variant = _make_stream("/tmp/rc")
	activity_log.clear()
	stream._streaming = true
	await stream._poll()
	expect_eq((stream.buffer() as Array).size(), 5, "one poll fills the shared buffer")
	expect_eq(stream._since, 5, "the stream advances its cursor to the high-water mark")
	expect_eq(activity_log.entries().size(), 0, "a healthy tail records no Activity Log noise")

	# A second poll from the advanced cursor adds nothing.
	await stream._poll()
	expect_eq((stream.buffer() as Array).size(), 5, "polling from the cursor adds no repeats")
	stream.queue_free()

	# A failing poll (nothing injected — the mock errors, as a 404 would) is logged.
	var broken: Variant = _make_stream("/tmp/not-injected")
	activity_log.clear()
	var reach_events: Array = []
	broken.reachability_changed.connect(func(ok: bool) -> void: reach_events.append(ok))
	broken._streaming = true
	await broken._poll()
	expect_eq(activity_log.entries().size(), 1, "a poll failure is recorded to the Activity Log")
	var failure: Dictionary = activity_log.entries()[0]
	expect(not failure.get("ok", true), "and marked as a failure")
	expect(failure.get("quiet", false), "quietly — a background poll must not pop an error dialog")
	expect_eq(reach_events, [false], "a reach flip to unreachable is announced (for the status footers)")
	# The same failure again must not re-log or re-announce — only a change of state does.
	await broken._poll()
	expect_eq(activity_log.entries().size(), 1, "a repeated identical failure is not re-logged")
	expect_eq(reach_events.size(), 1, "and not re-announced")
	broken.queue_free()


# Tab integration -------------------------------------------------------------
## A tab feeds the shared stream's backlog to the results view and applies its
## client-side filters. The `_visible_docs()` list is what the results view shows;
## the point is that the level filter narrows structured lines while never hiding
## the level-less non-JSON line (the seam a file source depends on).
func _tab_renders_stream_and_filters() -> void:
	var stream: Variant = _make_stream("/tmp/rc")
	stream._streaming = true
	await stream._poll()

	var tab: Variant = load(LOGS_TAB_PATH).instantiate()
	root.add_child(tab)
	await create_timer(0.1).timeout
	tab.bind_stream(stream)

	expect_eq((tab._visible_docs() as Array).size(), 5, "with no filter, every buffered line is shown")
	var all := JSON.stringify(tab._visible_docs())
	expect(all.contains("Server started"), "a structured line is shown")
	expect(all.contains("Rocket.Chat is ready"), "the non-JSON line too")

	# Exercise each render path (default is Tree): the Table renders the selected
	# columns, and Text/Tree switch without error.
	var rv: Variant = tab.results()
	rv._set_mode(1)  # TABLE
	var expected_cols: int = (rv._table_view._visible_columns(tab._visible_docs()) as Array).size()
	if tab._column_filter.value("(other)"):
		expected_cols += 1
	if rv._table_view._level_column_visible(tab._visible_docs()):
		expected_cols += 1  # the trailing Level column
	expect_eq(rv._table_view.columns, expected_cols, "the Table renders one column per visible attribute (plus (other) and Level)")
	rv._set_mode(2)  # TEXT
	rv._set_mode(0)  # TREE

	# Tree view: each log field is its own column, coloured independently.
	var tree_view: Variant = rv._tree_view
	expect_eq(tree_view.columns, 5, "the server-log tree splits fields into columns")
	# Columns are now Key(0) Time(1) Name(2) Message(3) Level(4) — Level moved to the end.
	var error_row: Variant = _find_tree_row(tree_view, 2, "Rooms")
	expect(error_row != null, "the error entry (name Rooms) has a row")
	if error_row != null:
		expect_eq(error_row.get_text(4), "error", "the (last) level column shows the text label, not the number")
		expect_eq(error_row.get_text(3), "boom", "the message column shows msg")
		expect_eq(error_row.get_custom_color(4), LogEntry.level_color(50), "the error level is coloured red")
		# Expanded field rows: key in column 0 (spanning the empty middle), value under Message.
		var field: Variant = error_row.get_first_child()
		expect(field != null, "the error row expands to field rows")
		if field != null:
			expect(not (field.get_text(0) as String).is_empty(), "a field row's key is in the (wide) Key column")
			expect(not (field.get_text(3) as String).is_empty(), "and its value under the Message column")
			expect_eq(field.get_text(1), "", "the middle columns stay empty")

		# New lines insert in place: an expanded, selected row is left intact and the
		# new entry lands at the top, renumbered — no full rebuild, no collapse/reset.
		error_row.set_collapsed(false)
		tree_view.set_selected(error_row, 0)
		var field_count: int = error_row.get_child_count()
		rv.add_log_documents([{"level": 40, "time": "t", "name": "Fresh", "msg": "new line"}])
		expect(not error_row.is_collapsed(), "an expanded row stays expanded when a new line arrives")
		expect_eq(error_row.get_child_count(), field_count, "and keeps its field rows")
		expect(tree_view.get_selected() == error_row, "the selection is preserved")
		var top_row: Variant = tree_view.get_root().get_first_child()
		expect_eq(top_row.get_text(2), "Fresh", "the new entry is inserted at the top")
		expect_eq(top_row.get_text(0), "(1)", "and the rows are renumbered from the top")

	# Text filter: only matching lines survive.
	tab._text_filter = "boom"
	tab._refresh()
	var filtered := JSON.stringify(tab._visible_docs())
	expect(filtered.contains("boom"), "the text filter keeps matching lines")
	expect(not filtered.contains("Server started"), "and drops non-matching ones")

	# Level filter (multi-select): show only "error". Other structured levels drop,
	# but the level-less non-JSON line stays — hiding it would blind a file source
	# that has no levels at all.
	tab._text_filter = ""
	for lbl in LogEntry.LEVEL_FILTER_LABELS:
		tab._allowed_levels[lbl] = (lbl == "error")
	tab._refresh()
	var lvl := JSON.stringify(tab._visible_docs())
	expect(lvl.contains("boom"), "an error line shows when only error is selected")
	expect(not lvl.contains("Server started"), "an info line is filtered out")
	expect(lvl.contains("Rocket.Chat is ready"), "a level-less line is never hidden by the level filter")

	# Name filter: the loggers' names are loaded into the filter, all shown.
	for lbl in LogEntry.LEVEL_FILTER_LABELS:
		tab._allowed_levels[lbl] = true
	var nf: Variant = tab._name_filter
	expect(nf.selection().has("Rooms"), "the Names filter is seeded from the discovered names")
	expect(nf.selection().has("Default"), "and carries the Default catch-all")

	# Hiding a logger name drops its lines; others stay.
	nf._selection["Rooms"] = false
	tab._refresh()
	var names := JSON.stringify(tab._visible_docs())
	expect(not names.contains("boom"), "hiding a logger name drops its lines")
	expect(names.contains("Server started"), "other loggers still show")

	# The Default catch-all governs lines with no listed name (the non-JSON line).
	nf._selection["Rooms"] = true
	nf._selection["Default"] = false
	tab._refresh()
	names = JSON.stringify(tab._visible_docs())
	expect(not names.contains("Rocket.Chat is ready"), "hiding Default drops lines with no listed name")
	expect(names.contains("Server started"), "named loggers still show")

	# A newly-discovered name joins the filter.
	nf._selection["Default"] = true
	tab._on_names_discovered(["BrandNew"])
	expect(nf.selection().has("BrandNew"), "a new name is added to the filter")

	# Time-of-day window: keep only entries between 12:00:02 and 12:00:03.5.
	tab._time_start = LogEntry.time_of_day_seconds("12:00:02")
	tab._time_end = LogEntry.time_of_day_seconds("12:00:03.500")
	tab._refresh()
	var timed := JSON.stringify(tab._visible_docs())
	expect(timed.contains("3 pending"), "an entry inside the window shows (12:00:02.200)")
	expect(timed.contains("boom"), "and another (12:00:03.300)")
	expect(not timed.contains("Server started"), "an entry before the window is hidden (12:00:01.123)")
	expect(not timed.contains("GET /api/info"), "an entry after the window is hidden (12:00:04.400)")
	expect(not timed.contains("Rocket.Chat is ready"), "a line with no time is hidden while a window is active")

	tab.queue_free()
	stream.queue_free()


## A tab's filters survive a to_state()/configure_restore() round-trip, so the tab
## reopens with the same filters from the sidecar.
func _tab_persists_filters() -> void:
	var stream: Variant = _make_stream("/tmp/rc")
	stream._streaming = true
	await stream._poll()  # discover the loggers' names

	var tab: Variant = load(LOGS_TAB_PATH).instantiate()
	root.add_child(tab)
	await create_timer(0.1).timeout
	tab.bind_stream(stream)
	tab._filter_edit.text = "boom"
	tab._text_filter = "boom"
	tab._allowed_levels["info"] = false
	tab._name_filter._selection["Rooms"] = false
	tab._start_edit.text = "12:00:02"
	tab._end_edit.text = "12:00:03.500"
	var state: Dictionary = tab.to_state()
	expect_eq(state.get("kind"), "logs", "the tab captures as a logs tab")

	var restored: Variant = load(LOGS_TAB_PATH).instantiate()
	restored.configure_restore(state)
	root.add_child(restored)
	await create_timer(0.1).timeout
	restored.bind_stream(stream)
	expect_eq(restored._filter_edit.text, "boom", "the text filter is restored")
	expect_eq(restored._text_filter, "boom", "and applied")
	expect(not bool(restored._allowed_levels.get("info", true)), "the level selection is restored")
	expect(not bool(restored._name_filter.selection().get("Rooms", true)), "the name selection is restored")
	expect_eq(restored._start_edit.text, "12:00:02", "the time bounds are restored")
	expect(restored._time_start > 0.0, "and parsed")

	tab.queue_free()
	restored.queue_free()
	stream.queue_free()


## A logs tab restored before the stream exists (a cached endpoint list drives restore
## while the endpoints view builds, before the logs view) is bound when the stream
## finally arrives — otherwise it would never show a line. Regression test.
func _restored_tab_binds_when_stream_arrives() -> void:
	var center: Variant = load("res://source/ui/project/workspace_center.tscn").instantiate()
	root.add_child(center)
	await create_timer(0.05).timeout  # let _ready wire the tab bar

	# Restore a logs tab with no stream bound yet.
	center.restore_tabs([{"kind": "logs"}], 0, {})
	var tab: Variant = _find_logs_tab(center)
	expect(tab != null, "the logs tab is restored")
	if tab != null:
		expect(not tab.has_stream(), "restored before the stream, it is unbound")
		var stream: Variant = load(LOG_STREAM_PATH).new()
		root.add_child(stream)
		center.bind_log_stream(stream)
		expect(tab.has_stream(), "binding the stream wires the restored tab so it can show lines")
		stream.queue_free()
	center.queue_free()


## A logs tab restored before any line arrives (empty buffer at bind, as when a cached
## endpoint list drives restore before the first poll) must still show its saved default
## columns once lines flow in. Binding copies the column selection into the table while
## no attribute column exists yet, so a later-discovered column has to be re-pushed —
## otherwise it stays hidden behind the "auto-display new columns" catch-all even though
## its checkbox reads on. Regression test.
func _restored_columns_show_when_lines_arrive() -> void:
	var state := {
		"kind": "logs",
		"columns": {
			"time": true, "level": true, "name": true, "msg": true,
			"Default": false, "(other)": true,
		},
	}
	var stream: Variant = _make_stream("/tmp/rc")  # not polled: empty buffer, like restore
	var tab: Variant = load(LOGS_TAB_PATH).instantiate()
	tab.configure_restore(state)
	root.add_child(tab)
	await create_timer(0.1).timeout
	tab.bind_stream(stream)

	var table: Variant = tab.results()._table_view
	expect(not (table._col_selection as Dictionary).has("time"),
		"no attribute column exists at bind (empty buffer), only the specials")

	# Lines arrive after restore: the columns are discovered and the selection re-pushed.
	var entries := [
		LogEntry.parse(1, '{"level":30,"time":"2026-09-02T10:00:00.000Z","name":"API","method":"GET","msg":"up"}'),
	]
	tab._on_stream_changed(entries)

	expect(bool(table._col_selection.get("time", false)),
		"a discovered default column is re-pushed to the table")
	var cols: Array = table._visible_columns([entries[0].get("doc")])
	expect(cols.has("time") and cols.has("msg"), "so the saved default columns render")
	expect(not cols.has("method"), "while a non-default column stays hidden (auto-display off)")

	tab.queue_free()
	stream.queue_free()


## The Columns filter has no toolbar button — it opens from a right-click on a Table
## column title. Check the signal path end to end: the table relays only a right-click,
## the results view bubbles it, and the tab pops the (hidden) filter's popup.
func _column_menu_opens_on_title_right_click() -> void:
	var stream: Variant = _make_stream("/tmp/rc")
	stream._streaming = true
	await stream._poll()
	var tab: Variant = load(LOGS_TAB_PATH).instantiate()
	root.add_child(tab)
	await create_timer(0.1).timeout
	tab.bind_stream(stream)

	# The Columns filter lives hidden in the tree (no toolbar button of its own).
	expect(not tab._column_filter.is_visible_in_tree(), "the Columns filter has no visible toolbar button")

	var table: Variant = tab.results()._table_view
	var opened: Array = []
	tab.results().log_column_menu_requested.connect(func(_p: Vector2) -> void: opened.append(true))
	# A left-click on a title is left alone; a right-click requests the columns menu.
	table._on_column_title_clicked(0, MOUSE_BUTTON_LEFT)
	expect(opened.is_empty(), "a left-click on a column title does not open the menu")
	table._on_column_title_clicked(0, MOUSE_BUTTON_RIGHT)
	expect_eq(opened.size(), 1, "a right-click on a column title requests the columns menu")

	tab.queue_free()
	stream.queue_free()


## The Columns filter groups its known columns into Default / Current / Extra. Default is
## the FIXED envelope whitelist (time/level/name/pid/hostname/msg) that exist — by
## identity, never "happens to be on every shown line". Current = any other attribute on
## a shown line; Extra = every other known attribute (only on filtered-out lines, etc.).
func _column_groups_split() -> void:
	var stream: Variant = _make_stream("/tmp/rc")
	stream._streaming = true
	await stream._poll()
	var tab: Variant = load(LOGS_TAB_PATH).instantiate()
	root.add_child(tab)
	await create_timer(0.1).timeout
	tab.bind_stream(stream)

	# All five mock lines shown. Default is the fixed envelope columns that exist here
	# (time/level/name/msg — no pid/hostname in the fixtures), in their fixed order.
	var g0: Dictionary = tab._column_groups()
	expect_eq(g0["Default"], ["time", "level", "name", "msg"], "Default = the fixed envelope columns that exist")
	expect_eq(g0["Current"], ["section"], "a non-envelope attribute on a shown line is Current")
	expect((g0["Extra"] as Array).is_empty(), "nothing is Extra while section's line shows")

	# Show ONLY the Rooms line: `section` is now on every shown line — yet it stays Current,
	# never promoted to Default, because being universal here is just a filter artefact.
	for n in ["Meteor", "Migrations", "API", "Default"]:
		tab._name_filter._selection[n] = false
	tab._name_filter._selection["Rooms"] = true
	tab._refresh()
	var g_only: Dictionary = tab._column_groups()
	expect((g_only["Current"] as Array).has("section"), "section on every shown line is still Current…")
	expect(not (g_only["Default"] as Array).has("section"), "…a non-envelope attribute never enters Default")
	expect_eq(g_only["Default"], ["time", "level", "name", "msg"], "the fixed Default group is unaffected by filters")

	# Hide the Rooms logger — the only line with `section`. It's now on no shown line, so
	# it drops to Extra, but stays a known column (not forgotten).
	for n in ["Meteor", "Migrations", "API", "Default"]:
		tab._name_filter._selection[n] = true
	tab._name_filter._selection["Rooms"] = false
	tab._refresh()
	var g1: Dictionary = tab._column_groups()
	expect((g1["Extra"] as Array).has("section"), "an attribute only on a hidden line is Extra")
	expect(not (g1["Current"] as Array).has("section"), "and no longer Current")
	expect(tab._column_filter.item_keys().has("section"), "the hidden-only attribute stays a known column")

	tab.queue_free()
	stream.queue_free()


func _find_logs_tab(center: Variant) -> Variant:
	for child in center._tabs.get_children():
		if child.has_method("has_stream"):
			return child
	return null


## Find the first top-level tree row whose `column` text equals `text`, or null.
func _find_tree_row(tree: Variant, column: int, text: String) -> Variant:
	var row: Variant = tree.get_root().get_first_child()
	while row != null:
		if row.get_text(column) == text:
			return row
		row = row.get_next()
	return null


## A LogStream in the tree, targeting `repo` (use a "not-injected" path to make the
## mock error). Loaded at runtime — see the note at the top of the file.
func _make_stream(repo: String) -> Variant:
	var stream: Variant = load(LOG_STREAM_PATH).new()
	root.add_child(stream)
	stream.bind_target(func() -> Dictionary: return {"repo_path": repo, "url": "http://localhost:3000"})
	return stream
