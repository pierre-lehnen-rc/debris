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

@onready var _editor: CodeEdit = %Editor
@onready var _status: Label = %Status
@onready var _primary_btn: Button = %PrimaryBtn
@onready var _validate_btn: Button = %ValidateBtn
@onready var _cancel_btn: Button = %CancelBtn


func _ready() -> void:
	_apply_style()


func _apply_style() -> void:
	_status.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_primary_btn.add_theme_color_override("font_color", AppTheme.ACCENT_GREEN)


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
	UiScale.popup_centered(self, Vector2i(560, 460))
	_editor.grab_focus()


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
