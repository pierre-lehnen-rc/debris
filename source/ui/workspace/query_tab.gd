class_name QueryTab
extends VBoxContainer

## A single query workspace: a code editor on top, results below, split
## vertically. "Run" currently loads mock documents for the target collection;
## later it will execute the editor's query against a live connection.

var connection_name := ""
var database_name := ""
var collection_name := ""

var _query_edit: CodeEdit
var _results: ResultsView


func configure(conn: String, database: String, collection: String) -> void:
	connection_name = conn
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
	add_theme_constant_override("separation", 0)
	add_child(_build_toolbar())

	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 140
	add_child(split)

	_query_edit = CodeEdit.new()
	_query_edit.custom_minimum_size = Vector2(0, 90)
	_query_edit.gutters_draw_line_numbers = true
	_query_edit.placeholder_text = "db.getCollection(\"...\").find({})"
	if not collection_name.is_empty():
		_query_edit.text = "db.getCollection(\"%s\").find({})" % collection_name
	split.add_child(_query_edit)

	_results = ResultsView.new()
	split.add_child(_results)

	_run()


func _build_toolbar() -> Control:
	var panel := PanelContainer.new()
	var sb := AppTheme._flat(AppTheme.BG_DARK, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	var run_btn := Button.new()
	run_btn.text = "Run"
	run_btn.focus_mode = Control.FOCUS_NONE
	run_btn.add_theme_color_override("font_color", AppTheme.ACCENT_GREEN)
	run_btn.tooltip_text = "Run query (loads mock data for now)"
	run_btn.pressed.connect(_run)
	row.add_child(run_btn)

	var target := Label.new()
	target.text = "%s  ›  %s  ›  %s" % [connection_name, database_name, collection_name]
	target.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(target)

	return panel


func _run() -> void:
	if collection_name.is_empty():
		_results.set_documents([])
		return
	_results.set_documents(MockData.documents_for(collection_name))
