class_name ConnectionDialog
extends Window

## Add/Edit connection dialog with tabbed settings: Connection / Authentication.
## It gathers a config Dictionary and emits `saved`/`updated`; the backend
## consumes the Authentication fields when it opens the connection.

signal saved(config: Dictionary)
signal updated(index: int, config: Dictionary)

const MECHANISMS := ["SCRAM-SHA-256", "SCRAM-SHA-1", "MONGODB-CR"]

@onready var _host_edit: LineEdit = %HostEdit
@onready var _port_edit: LineEdit = %PortEdit
@onready var _auth_check: CheckBox = %AuthCheck
@onready var _auth_db_edit: LineEdit = %AuthDbEdit
@onready var _user_edit: LineEdit = %UserEdit
@onready var _pass_edit: LineEdit = %PassEdit
@onready var _mech_option: OptionButton = %MechOption
@onready var _db_option: OptionButton = %DbOption
@onready var _fetch_db_btn: Button = %FetchDbBtn
@onready var _url_edit: LineEdit = %UrlEdit
@onready var _uri_label: Label = %UriLabel
@onready var _status: Label = %Status
@onready var _test_btn: Button = %TestBtn
@onready var _save_btn: Button = %SaveBtn
@onready var _cancel_btn: Button = %CancelBtn

var _auth_controls: Array[Control] = []
var _edit_index := -1  # >= 0 when editing an existing connection


func _ready() -> void:
	for mech in MECHANISMS:
		_mech_option.add_item(mech)

	_auth_controls = [_auth_db_edit, _user_edit, _pass_edit, _mech_option]

	# Keep the URI preview in sync with every field that shapes the URL.
	for field in [_host_edit, _port_edit, _user_edit, _pass_edit, _auth_db_edit]:
		field.text_changed.connect(_update_url_preview)
	_mech_option.item_selected.connect(_update_url_preview)
	_db_option.item_selected.connect(_update_url_preview)

	_apply_style()

	_set_enabled(_auth_controls, false)
	_update_url_preview()


# Section toggles (wired in connection_dialog.tscn) ---------------------------
func _on_auth_toggled(on: bool) -> void:
	_set_enabled(_auth_controls, on)
	_update_url_preview()


func _apply_style() -> void:
	_status.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_uri_label.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_save_btn.add_theme_color_override("font_color", AppTheme.ACCENT)


# Public API ------------------------------------------------------------------
func open_new() -> void:
	_reset()
	_edit_index = -1
	title = "New Connection"
	UiScale.popup_centered(self, Vector2i(540, 460))


func open_edit(index: int, config: Dictionary) -> void:
	_reset()
	_edit_index = index
	title = "Edit Connection"
	var hostport: String = config.get("host", "")
	if hostport.contains(":"):
		var parts := hostport.split(":")
		_host_edit.text = parts[0]
		_port_edit.text = parts[1]
	else:
		_host_edit.text = hostport
	_set_database(config.get("database", ""))
	var auth: Dictionary = config.get("auth", {})
	_auth_check.button_pressed = auth.get("enabled", false)
	_auth_db_edit.text = auth.get("database", "admin")
	_user_edit.text = auth.get("username", "")
	_pass_edit.text = auth.get("password", "")
	_mech_option.selected = maxi(0, MECHANISMS.find(auth.get("mechanism", "")))
	_set_enabled(_auth_controls, _auth_check.button_pressed)
	_update_url_preview()
	UiScale.popup_centered(self, Vector2i(540, 460))


# Helpers ---------------------------------------------------------------------
func _set_enabled(controls: Array, on: bool) -> void:
	for c in controls:
		if c is LineEdit:
			c.editable = on
		elif c is OptionButton:
			c.disabled = not on
		c.modulate = Color(1, 1, 1, 1.0 if on else 0.45)


func _reset() -> void:
	_host_edit.text = ""
	_port_edit.text = "27017"
	_auth_check.button_pressed = false
	_auth_db_edit.text = "admin"
	_user_edit.text = ""
	_pass_edit.text = ""
	_mech_option.selected = 0
	_set_database("")
	_status.text = ""
	_set_enabled(_auth_controls, false)
	_update_url_preview()


# Actions ---------------------------------------------------------------------
func _gather() -> Dictionary:
	var host := _host_edit.text.strip_edges()
	var port := _port_edit.text.strip_edges()
	return {
		# No separate name field — a connection lives in its project, so identify it
		# by its address for the few places that show a label.
		"name": "%s:%s" % [host, port],
		"host": "%s:%s" % [host, port],
		"connected": false,
		"databases": [],
		"database": _selected_database(),
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


## Refresh the read-only connection-URI preview from the current field values.
## Accepts (and ignores) the argument the various field signals emit.
func _update_url_preview(_changed: Variant = null) -> void:
	if _url_edit != null:
		_url_edit.text = _mongo_url()


## Build a standard mongodb:// URI from the current fields, mirroring what the
## backend spec (Backend.to_spec) would connect with: host:port, an optional
## auth prefix + authSource/authMechanism, an optional default database path, and
## directConnection. The password is masked so the URI can stay on screen safely.
func _mongo_url() -> String:
	var host := _host_edit.text.strip_edges()
	if host.is_empty():
		host = "localhost"
	var port := _port_edit.text.strip_edges()
	if port.is_empty():
		port = "27017"

	var auth_on := _auth_check.button_pressed and not _user_edit.text.strip_edges().is_empty()
	var creds := ""
	if auth_on:
		creds = _user_edit.text.strip_edges().uri_encode()
		if not _pass_edit.text.is_empty():
			creds += ":****"
		creds += "@"

	var url := "mongodb://%s%s:%s" % [creds, host, port]

	var db := _selected_database()
	if not db.is_empty():
		url += "/" + db.uri_encode()

	var params: Array[String] = ["directConnection=true"]
	if auth_on:
		var auth_db := _auth_db_edit.text.strip_edges()
		if auth_db.is_empty():
			auth_db = "admin"
		params.append("authSource=" + auth_db.uri_encode())
		params.append("authMechanism=" + MECHANISMS[_mech_option.selected])
	url += "?" + "&".join(params)
	return url


# Database select -------------------------------------------------------------
## The chosen database name, or "" when none is selected.
func _selected_database() -> String:
	if _db_option.selected < 0:
		return ""
	return _db_option.get_item_text(_db_option.selected)


## Set the selected database, keeping it as the sole option until Fetch lists more.
func _set_database(db: String) -> void:
	_db_option.clear()
	if not db.is_empty():
		_db_option.add_item(db)
		_db_option.select(0)


## Populate the dropdown from a fetched name list, preserving the current choice
## (added on top even if the server didn't return it).
func _populate_databases(names: Array) -> void:
	var current := _selected_database()
	_db_option.clear()
	if not current.is_empty() and not (current in names):
		_db_option.add_item(current)
	for db_name in names:
		_db_option.add_item(String(db_name))
	for i in _db_option.item_count:
		if _db_option.get_item_text(i) == current:
			_db_option.select(i)
			break
	if _db_option.selected < 0 and _db_option.item_count > 0:
		_db_option.select(0)
	_update_url_preview()


## List database names from the connection's current fields, filling the dropdown.
func _on_fetch_databases() -> void:
	if _host_edit.text.strip_edges().is_empty():
		_status.text = "Enter a host to list databases."
		return
	_status.text = "Fetching databases…"
	_fetch_db_btn.disabled = true
	var result: Dictionary = await Backend.list_databases(_spec_from_fields())
	_fetch_db_btn.disabled = false
	if not result.get("ok", false):
		# The failure is already surfaced by the error popup (via the activity log);
		# don't echo a (possibly long) message here, which would grow the window.
		_status.text = ""
		return
	var names := _database_names(result.get("data"))
	_populate_databases(names)
	_status.text = "Found %d database%s" % [names.size(), "" if names.size() == 1 else "s"]


## Extract database names from a list-databases response. Mongo's listDatabases
## returns { databases: [ { name, … } ] }; a plain array (of strings or
## { name: … } objects) is also accepted defensively.
func _database_names(data: Variant) -> Array:
	var names: Array = []
	var list: Variant = data
	if data is Dictionary and (data as Dictionary).get("databases") is Array:
		list = (data as Dictionary)["databases"]
	if list is Array:
		for entry in list:
			if entry is String:
				names.append(entry)
			elif entry is Dictionary:
				var n := String((entry as Dictionary).get("name", ""))
				if not n.is_empty():
					names.append(n)
	return names


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
