class_name WorkspaceDialog
extends Window

## Add/Edit dialog for a Rocket.Chat workspace, modeled on the Mongo connection
## dialog. It gathers a config Dictionary (name, server URL and a list of users,
## each a { name, user_id, token } Personal Access Token credential) and emits
## `saved` / `updated`. A workspace can hold several users; the endpoint tab picks
## which one to send a given request as.

signal saved(config: Dictionary)
signal updated(index: int, config: Dictionary)

## Auth-mode dropdown ids, per user row.
const AUTH_TOKEN := 0
const AUTH_PASSWORD := 1

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
	popup_centered(Vector2i(680, 440))


func open_edit(index: int, config: Dictionary) -> void:
	_reset()
	_edit_index = index
	title = "Edit Workspace"
	_url_edit.text = config.get("url", "")
	var users: Variant = config.get("users", [])
	if users is Array and not (users as Array).is_empty():
		for user in users:
			_add_user_row(user)
	else:
		_add_user_row()
	popup_centered(Vector2i(680, 440))


# Helpers ---------------------------------------------------------------------
func _reset() -> void:
	_url_edit.text = ""
	_status.text = ""
	for child in _users_list.get_children():
		child.queue_free()


## Build one user row: User ID + Username/Email (always present) + auth-mode
## dropdown + the matching secret field (Access Token or Password) + remove button.
## The row's controls are stored in its metadata so _gather can read them back.
func _add_user_row(user: Dictionary = {}) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var user_id_edit := LineEdit.new()
	user_id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	user_id_edit.placeholder_text = "User ID"
	user_id_edit.text = user.get("user_id", "")

	var username_edit := LineEdit.new()
	username_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	username_edit.placeholder_text = "Username or Email"
	username_edit.text = user.get("username", "")

	var mode := OptionButton.new()
	mode.add_item("Access Token", AUTH_TOKEN)
	mode.add_item("Password", AUTH_PASSWORD)

	var secret := LineEdit.new()
	secret.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	secret.secret = true

	var remove_btn := Button.new()
	remove_btn.text = "✕"
	remove_btn.tooltip_text = "Remove this user"
	remove_btn.focus_mode = Control.FOCUS_NONE
	remove_btn.pressed.connect(func() -> void: row.queue_free())

	row.add_child(user_id_edit)
	row.add_child(username_edit)
	row.add_child(mode)
	row.add_child(secret)
	row.add_child(remove_btn)
	row.set_meta("controls", {
		"user_id": user_id_edit, "username": username_edit, "mode": mode, "secret": secret,
	})

	var is_password: bool = String(user.get("auth", "")) == "password"
	mode.select(AUTH_PASSWORD if is_password else AUTH_TOKEN)
	secret.text = user.get("password", "") if is_password else user.get("token", "")
	_apply_mode(mode, secret)
	mode.item_selected.connect(func(_i: int) -> void: _apply_mode(mode, secret))

	_users_list.add_child(row)


## Relabel the secret field to match the chosen auth mode; it stays masked either
## way (an access token or a password).
func _apply_mode(mode: OptionButton, secret: LineEdit) -> void:
	secret.placeholder_text = "Password" if mode.get_selected_id() == AUTH_PASSWORD else "Access Token"


## Collect the non-empty user rows. A row with no user id, username or secret is
## treated as empty and dropped.
func _gather_users() -> Array:
	var users: Array = []
	for row in _users_list.get_children():
		if not row.has_meta("controls"):
			continue
		var c: Dictionary = row.get_meta("controls")
		var user_id: String = (c["user_id"] as LineEdit).text.strip_edges()
		var username: String = (c["username"] as LineEdit).text.strip_edges()
		var secret: String = (c["secret"] as LineEdit).text
		if user_id.is_empty() and username.is_empty() and secret.strip_edges().is_empty():
			continue
		var entry := {"user_id": user_id, "username": username}
		if (c["mode"] as OptionButton).get_selected_id() == AUTH_PASSWORD:
			entry["auth"] = "password"
			entry["password"] = secret
		else:
			entry["auth"] = "token"
			entry["token"] = secret
		users.append(entry)
	return users


func _gather() -> Dictionary:
	# No separate name field — the workspace lives in its project. The project name
	# is used as its display name (see WorkspaceDoc.rocketchat_config).
	return {
		"url": _url_edit.text.strip_edges(),
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
