class_name SessionUserDialog
extends Window

## Small dialog for adding a user to an open workspace tab's Users panel. The user
## exists only for that session (never written to the workspace config). User ID
## and Username/Email are always configurable; the auth mode chooses the secret —
## an Access Token (token auth) or a Password (password auth). Emits `submitted`.

signal submitted(entry: Dictionary)

const AUTH_TOKEN := 0
const AUTH_PASSWORD := 1

@onready var _mode: OptionButton = %ModeOption
@onready var _user_id_edit: LineEdit = %UserIdEdit
@onready var _username_edit: LineEdit = %UsernameEdit
@onready var _secret_label: Label = %SecretLabel
@onready var _secret_edit: LineEdit = %SecretEdit
@onready var _status: Label = %Status
@onready var _add_btn: Button = %AddBtn


func _ready() -> void:
	_status.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_add_btn.add_theme_color_override("font_color", AppTheme.ACCENT)
	_mode.clear()
	_mode.add_item("Access Token", AUTH_TOKEN)
	_mode.add_item("Password", AUTH_PASSWORD)
	_mode.item_selected.connect(func(_i: int) -> void: _apply_mode())


func open() -> void:
	_user_id_edit.text = ""
	_username_edit.text = ""
	_secret_edit.text = ""
	_status.text = ""
	_mode.select(AUTH_TOKEN)
	_apply_mode()
	popup_centered(Vector2i(460, 280))
	_user_id_edit.grab_focus()


func _apply_mode() -> void:
	_secret_label.text = "Password" if _mode.get_selected_id() == AUTH_PASSWORD else "Access Token"


func _on_add() -> void:
	var user_id := _user_id_edit.text.strip_edges()
	var username := _username_edit.text.strip_edges()
	var secret := _secret_edit.text
	if user_id.is_empty() and username.is_empty() and secret.strip_edges().is_empty():
		_status.text = "Enter this user's credentials."
		return
	var entry := {"user_id": user_id, "username": username}
	if _mode.get_selected_id() == AUTH_PASSWORD:
		entry["auth"] = "password"
		entry["password"] = secret
	else:
		entry["auth"] = "token"
		entry["token"] = secret
	submitted.emit(entry)
	hide()


func _on_cancel() -> void:
	hide()
