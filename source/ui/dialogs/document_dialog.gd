class_name DocumentDialog
extends Window

## JSON document editor, modeled on Robo3T's insert/edit document windows.
## Three modes: INSERT (blank template), EDIT (existing doc), VIEW (read-only).
## It only validates and emits the text; persistence is handled by the caller.

signal inserted(text: String)
signal updated(index: int, text: String)

enum DocMode { INSERT, EDIT, VIEW }

const TEMPLATE := "{\n    \n}"

var _mode: DocMode = DocMode.INSERT
var _edit_index := -1
var _editor: CodeEdit
var _status: Label
var _primary_btn: Button


func _ready() -> void:
	visible = false
	theme = AppTheme.shared()
	min_size = Vector2i(420, 300)
	exclusive = true
	transient = true
	close_requested.connect(hide)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	_editor = CodeEdit.new()
	_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor.gutters_draw_line_numbers = true
	col.add_child(_editor)

	col.add_child(_build_buttons())


# Public API ------------------------------------------------------------------
func open_insert() -> void:
	_mode = DocMode.INSERT
	_edit_index = -1
	title = "Insert Document"
	_editor.editable = true
	_editor.text = TEMPLATE
	_status.text = ""
	_primary_btn.visible = true
	_primary_btn.text = "Insert"
	_popup()


func open_edit(index: int, text: String) -> void:
	_mode = DocMode.EDIT
	_edit_index = index
	title = "Edit Document"
	_editor.editable = true
	_editor.text = text
	_status.text = ""
	_primary_btn.visible = true
	_primary_btn.text = "Save"
	_popup()


func open_view(text: String) -> void:
	_mode = DocMode.VIEW
	title = "View Document"
	_editor.editable = false
	_editor.text = text
	_status.text = "Read-only"
	_primary_btn.visible = false
	_popup()


# Internals -------------------------------------------------------------------
func _popup() -> void:
	popup_centered(Vector2i(560, 460))
	_editor.grab_focus()


func _build_buttons() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var validate_btn := Button.new()
	validate_btn.text = "Validate"
	validate_btn.pressed.connect(func() -> void: _validate())
	row.add_child(validate_btn)

	_status = Label.new()
	_status.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_status)

	_primary_btn = Button.new()
	_primary_btn.text = "Insert"
	_primary_btn.add_theme_color_override("font_color", AppTheme.ACCENT_GREEN)
	_primary_btn.pressed.connect(_on_primary)
	row.add_child(_primary_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Close"
	cancel_btn.pressed.connect(hide)
	row.add_child(cancel_btn)

	return row


func _validate() -> bool:
	var json := JSON.new()
	var err := json.parse(_editor.text)
	if err != OK:
		_status.text = "Line %d: %s" % [json.get_error_line(), json.get_error_message()]
		_status.add_theme_color_override("font_color", Color("#e06c75"))
		return false
	if not (json.data is Dictionary):
		_status.text = "Document must be a JSON object."
		_status.add_theme_color_override("font_color", Color("#e06c75"))
		return false
	_status.text = "Valid"
	_status.add_theme_color_override("font_color", AppTheme.ACCENT_GREEN)
	return true


func _on_primary() -> void:
	if not _validate():
		return
	if _mode == DocMode.EDIT:
		updated.emit(_edit_index, _editor.text)
	else:
		inserted.emit(_editor.text)
	hide()
