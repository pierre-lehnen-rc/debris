class_name WorkspaceDialog
extends Window

## Add/Edit dialog for a Rocket.Chat workspace, modeled on the Mongo connection
## dialog. It only gathers a config Dictionary (name, server URL and Personal
## Access Token credentials) and emits `saved` / `updated`; actually talking to
## the workspace's REST API comes later.

signal saved(config: Dictionary)
signal updated(index: int, config: Dictionary)

@onready var _name_edit: LineEdit = %NameEdit
@onready var _url_edit: LineEdit = %UrlEdit
@onready var _user_id_edit: LineEdit = %UserIdEdit
@onready var _token_edit: LineEdit = %TokenEdit
@onready var _status: Label = %Status
@onready var _save_btn: Button = %SaveBtn
@onready var _cancel_btn: Button = %CancelBtn

var _edit_index := -1  # >= 0 when editing an existing workspace


func _ready() -> void:
	_status.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_save_btn.add_theme_color_override("font_color", AppTheme.ACCENT)


# Public API ------------------------------------------------------------------
func open_new() -> void:
	_reset()
	_edit_index = -1
	title = "New Workspace"
	popup_centered(Vector2i(480, 280))


func open_edit(index: int, config: Dictionary) -> void:
	_reset()
	_edit_index = index
	title = "Edit Workspace"
	_name_edit.text = config.get("name", "")
	_url_edit.text = config.get("url", "")
	_user_id_edit.text = config.get("user_id", "")
	_token_edit.text = config.get("token", "")
	popup_centered(Vector2i(480, 280))


# Helpers ---------------------------------------------------------------------
func _reset() -> void:
	_name_edit.text = ""
	_url_edit.text = ""
	_user_id_edit.text = ""
	_token_edit.text = ""
	_status.text = ""


func _gather() -> Dictionary:
	var url := _url_edit.text.strip_edges()
	var display_name := _name_edit.text.strip_edges()
	if display_name.is_empty():
		display_name = url
	return {
		"name": display_name,
		"url": url,
		"user_id": _user_id_edit.text.strip_edges(),
		"token": _token_edit.text,
	}


# Actions ---------------------------------------------------------------------
func _on_save() -> void:
	if _url_edit.text.strip_edges().is_empty():
		_status.text = "A server URL is required."
		return
	if _edit_index >= 0:
		updated.emit(_edit_index, _gather())
	else:
		saved.emit(_gather())
	hide()


func _on_cancel() -> void:
	hide()
