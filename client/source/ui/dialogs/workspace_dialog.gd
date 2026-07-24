class_name WorkspaceDialog
extends Window

## Add/Edit dialog for a Rocket.Chat workspace: just the server URL. Users are
## managed (and persisted) in the workspace's Users panel, so the config this emits
## carries only { url }. Emits `saved` (new) / `updated` (edit); the host applies
## it to the active project.

signal saved(config: Dictionary)
signal updated(index: int, config: Dictionary)

@onready var _url_edit: LineEdit = %UrlEdit
@onready var _status: Label = %Status
@onready var _save_btn: Button = %SaveBtn

var _edit_index := -1  # >= 0 when editing an existing workspace


func _ready() -> void:
	_status.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_save_btn.add_theme_color_override("font_color", AppTheme.ACCENT)


# Public API ------------------------------------------------------------------
func open_new() -> void:
	_reset()
	_edit_index = -1
	title = "New Workspace"
	popup_centered(Vector2i(560, 180))


func open_edit(index: int, config: Dictionary) -> void:
	_reset()
	_edit_index = index
	title = "Edit Workspace"
	_url_edit.text = config.get("url", "")
	popup_centered(Vector2i(560, 180))


# Helpers ---------------------------------------------------------------------
func _reset() -> void:
	_url_edit.text = ""
	_status.text = ""


func _gather() -> Dictionary:
	# Users live in the project (managed by the Users panel), not in this dialog.
	return {"url": _url_edit.text.strip_edges()}


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
