class_name WorkspaceDialog
extends Window

## Add/Edit dialog for a Rocket.Chat workspace, modeled on the Mongo connection
## dialog. It gathers a config Dictionary (name, server URL and a list of users,
## each a { name, user_id, token } Personal Access Token credential) and emits
## `saved` / `updated`. A workspace can hold several users; the endpoint tab picks
## which one to send a given request as.

signal saved(config: Dictionary)
signal updated(index: int, config: Dictionary)

@onready var _name_edit: LineEdit = %NameEdit
@onready var _url_edit: LineEdit = %UrlEdit
@onready var _users_list: VBoxContainer = %UsersList
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
	_add_user_row()
	popup_centered(Vector2i(560, 420))


func open_edit(index: int, config: Dictionary) -> void:
	_reset()
	_edit_index = index
	title = "Edit Workspace"
	_name_edit.text = config.get("name", "")
	_url_edit.text = config.get("url", "")
	var users: Variant = config.get("users", [])
	if users is Array and not (users as Array).is_empty():
		for user in users:
			_add_user_row(user)
	else:
		_add_user_row()
	popup_centered(Vector2i(560, 420))


# Helpers ---------------------------------------------------------------------
func _reset() -> void:
	_name_edit.text = ""
	_url_edit.text = ""
	_status.text = ""
	for child in _users_list.get_children():
		child.queue_free()


## Build one user row (label + user id + secret token + remove button). The row's
## LineEdits are stored in its metadata so _gather can read them back.
func _add_user_row(user: Dictionary = {}) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var name_edit := LineEdit.new()
	name_edit.custom_minimum_size = Vector2(110, 0)
	name_edit.placeholder_text = "Label"
	name_edit.text = user.get("name", "")

	var user_id_edit := LineEdit.new()
	user_id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	user_id_edit.placeholder_text = "User ID"
	user_id_edit.text = user.get("user_id", "")

	var token_edit := LineEdit.new()
	token_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	token_edit.placeholder_text = "Access Token"
	token_edit.secret = true
	token_edit.text = user.get("token", "")

	var remove_btn := Button.new()
	remove_btn.text = "✕"
	remove_btn.tooltip_text = "Remove this user"
	remove_btn.focus_mode = Control.FOCUS_NONE
	remove_btn.pressed.connect(func() -> void: row.queue_free())

	row.add_child(name_edit)
	row.add_child(user_id_edit)
	row.add_child(token_edit)
	row.add_child(remove_btn)
	row.set_meta("fields", [name_edit, user_id_edit, token_edit])
	_users_list.add_child(row)


## Collect the non-empty user rows. A row with neither a user id nor a token is
## treated as blank and dropped; an unnamed user is labelled by its user id.
func _gather_users() -> Array:
	var users: Array = []
	for row in _users_list.get_children():
		if not row.has_meta("fields"):
			continue
		var fields: Array = row.get_meta("fields")
		var label: String = (fields[0] as LineEdit).text.strip_edges()
		var user_id: String = (fields[1] as LineEdit).text.strip_edges()
		var token: String = (fields[2] as LineEdit).text
		if user_id.is_empty() and token.strip_edges().is_empty():
			continue
		users.append({
			"name": label if not label.is_empty() else user_id,
			"user_id": user_id,
			"token": token,
		})
	return users


func _gather() -> Dictionary:
	var url := _url_edit.text.strip_edges()
	var display_name := _name_edit.text.strip_edges()
	if display_name.is_empty():
		display_name = url
	return {
		"name": display_name,
		"url": url,
		"users": _gather_users(),
	}


# Actions ---------------------------------------------------------------------
func _on_add_user() -> void:
	_add_user_row()


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
