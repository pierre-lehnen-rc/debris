class_name QueryTab
extends VBoxContainer

## A single query workspace: a code editor on top, results below, split
## vertically. "Run" currently loads mock documents for the target collection;
## later it will execute the editor's query against a live connection.
## Layout lives in query_tab.tscn; configure() must be called before the node
## enters the tree so _ready() can seed the editor and target label.

var connection_name := ""
var database_name := ""
var collection_name := ""

@onready var _toolbar: PanelContainer = %Toolbar
@onready var _run_btn: Button = %RunBtn
@onready var _target_label: Label = %TargetLabel
@onready var _query_edit: CodeEdit = %QueryEdit
@onready var _results: ResultsView = %Results


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
	_apply_style()

	_target_label.text = "%s  ›  %s  ›  %s" % [connection_name, database_name, collection_name]
	if not collection_name.is_empty():
		_query_edit.text = "db.getCollection(\"%s\").find({})" % collection_name

	_run_btn.pressed.connect(_run)
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


func _run() -> void:
	if collection_name.is_empty():
		_results.set_documents([])
		return
	_results.set_documents(MockData.documents_for(collection_name))
