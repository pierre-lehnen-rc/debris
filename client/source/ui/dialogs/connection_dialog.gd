class_name ConnectionDialog
extends Window

## Add/Edit connection dialog, modeled on Robo3T's tabbed connection settings:
## Connection / Authentication / SSH / SSL / Advanced. It only gathers a config
## Dictionary and emits `saved`; actually connecting to Mongo comes later.

signal saved(config: Dictionary)
signal updated(index: int, config: Dictionary)

const MECHANISMS := ["SCRAM-SHA-256", "SCRAM-SHA-1", "MONGODB-CR"]

@onready var _name_edit: LineEdit = %NameEdit
@onready var _host_edit: LineEdit = %HostEdit
@onready var _port_edit: LineEdit = %PortEdit
@onready var _auth_check: CheckBox = %AuthCheck
@onready var _auth_db_edit: LineEdit = %AuthDbEdit
@onready var _user_edit: LineEdit = %UserEdit
@onready var _pass_edit: LineEdit = %PassEdit
@onready var _mech_option: OptionButton = %MechOption
@onready var _ssh_check: CheckBox = %SshCheck
@onready var _ssh_host_edit: LineEdit = %SshHostEdit
@onready var _ssh_user_edit: LineEdit = %SshUserEdit
@onready var _ssl_check: CheckBox = %SslCheck
@onready var _ssl_ca_edit: LineEdit = %SslCaEdit
@onready var _default_db_edit: LineEdit = %DefaultDbEdit
@onready var _timeout_edit: LineEdit = %TimeoutEdit
@onready var _status: Label = %Status
@onready var _test_btn: Button = %TestBtn
@onready var _save_btn: Button = %SaveBtn
@onready var _cancel_btn: Button = %CancelBtn

var _auth_controls: Array[Control] = []
var _ssh_controls: Array[Control] = []
var _ssl_controls: Array[Control] = []
var _edit_index := -1  # >= 0 when editing an existing connection


func _ready() -> void:
	for mech in MECHANISMS:
		_mech_option.add_item(mech)

	_auth_controls = [_auth_db_edit, _user_edit, _pass_edit, _mech_option]
	_ssh_controls = [_ssh_host_edit, _ssh_user_edit]
	_ssl_controls = [_ssl_ca_edit]

	_apply_style()

	_set_enabled(_auth_controls, false)
	_set_enabled(_ssh_controls, false)
	_set_enabled(_ssl_controls, false)


# Section toggles (wired in connection_dialog.tscn) ---------------------------
func _on_auth_toggled(on: bool) -> void:
	_set_enabled(_auth_controls, on)


func _on_ssh_toggled(on: bool) -> void:
	_set_enabled(_ssh_controls, on)


func _on_ssl_toggled(on: bool) -> void:
	_set_enabled(_ssl_controls, on)


func _apply_style() -> void:
	_status.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_save_btn.add_theme_color_override("font_color", AppTheme.ACCENT)


# Public API ------------------------------------------------------------------
func open_new() -> void:
	_reset()
	_edit_index = -1
	title = "New Connection"
	popup_centered(Vector2i(540, 460))


func open_edit(index: int, config: Dictionary) -> void:
	_reset()
	_edit_index = index
	title = "Edit Connection"
	_name_edit.text = config.get("name", "")
	var hostport: String = config.get("host", "")
	if hostport.contains(":"):
		var parts := hostport.split(":")
		_host_edit.text = parts[0]
		_port_edit.text = parts[1]
	else:
		_host_edit.text = hostport
	popup_centered(Vector2i(540, 460))


# Helpers ---------------------------------------------------------------------
func _set_enabled(controls: Array, on: bool) -> void:
	for c in controls:
		if c is LineEdit:
			c.editable = on
		elif c is OptionButton:
			c.disabled = not on
		c.modulate = Color(1, 1, 1, 1.0 if on else 0.45)


func _reset() -> void:
	_name_edit.text = ""
	_host_edit.text = ""
	_port_edit.text = "27017"
	_auth_check.button_pressed = false
	_auth_db_edit.text = "admin"
	_user_edit.text = ""
	_pass_edit.text = ""
	_mech_option.selected = 0
	_ssh_check.button_pressed = false
	_ssh_host_edit.text = ""
	_ssh_user_edit.text = ""
	_ssl_check.button_pressed = false
	_ssl_ca_edit.text = ""
	_status.text = ""
	_set_enabled(_auth_controls, false)
	_set_enabled(_ssh_controls, false)
	_set_enabled(_ssl_controls, false)


# Actions ---------------------------------------------------------------------
func _gather() -> Dictionary:
	var host := _host_edit.text.strip_edges()
	var port := _port_edit.text.strip_edges()
	var display_name := _name_edit.text.strip_edges()
	if display_name.is_empty():
		display_name = host
	return {
		"name": display_name,
		"host": "%s:%s" % [host, port],
		"connected": false,
		"databases": [],
		"auth": {
			"enabled": _auth_check.button_pressed,
			"database": _auth_db_edit.text,
			"username": _user_edit.text,
			"password": _pass_edit.text,
			"mechanism": MECHANISMS[_mech_option.selected],
		},
	}


## Build the server connection spec directly from the current field values
## (used by Test, before the config is saved).
func _spec_from_fields() -> Dictionary:
	var port := _port_edit.text.strip_edges().to_int()
	if port == 0:
		port = 27017
	var spec := {
		"host": _host_edit.text.strip_edges(),
		"port": port,
		"directConnection": true,
	}
	if _auth_check.button_pressed:
		spec["username"] = _user_edit.text
		spec["password"] = _pass_edit.text
		spec["authSource"] = _auth_db_edit.text
		spec["authMechanism"] = MECHANISMS[_mech_option.selected]
	return spec


func _on_test() -> void:
	if _host_edit.text.strip_edges().is_empty():
		_status.text = "Enter a host to test."
		return
	_status.text = "Testing…"
	_test_btn.disabled = true
	var result: Dictionary = await Backend.ping(_spec_from_fields())
	_test_btn.disabled = false
	if result.get("ok", false):
		_status.text = "Connection successful."
	else:
		_status.text = "Failed: %s" % result.get("error", "unknown error")


func _on_save() -> void:
	if _host_edit.text.strip_edges().is_empty():
		_status.text = "A host is required."
		return
	if _edit_index >= 0:
		updated.emit(_edit_index, _gather())
	else:
		saved.emit(_gather())
	hide()


func _on_cancel() -> void:
	hide()
