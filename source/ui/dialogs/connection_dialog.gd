class_name ConnectionDialog
extends Window

## Add/Edit connection dialog, modeled on Robo3T's tabbed connection settings:
## Connection / Authentication / SSH / SSL / Advanced. It only gathers a config
## Dictionary and emits `saved`; actually connecting to Mongo comes later.

signal saved(config: Dictionary)

const MECHANISMS := ["SCRAM-SHA-256", "SCRAM-SHA-1", "MONGODB-CR"]

var _name_edit: LineEdit
var _host_edit: LineEdit
var _port_edit: LineEdit
var _auth_check: CheckBox
var _auth_db_edit: LineEdit
var _user_edit: LineEdit
var _pass_edit: LineEdit
var _mech_option: OptionButton
var _ssh_check: CheckBox
var _ssh_host_edit: LineEdit
var _ssh_user_edit: LineEdit
var _ssl_check: CheckBox
var _ssl_ca_edit: LineEdit
var _default_db_edit: LineEdit
var _timeout_edit: LineEdit
var _status: Label

var _auth_controls: Array[Control] = []
var _ssh_controls: Array[Control] = []
var _ssl_controls: Array[Control] = []


func _ready() -> void:
	visible = false  # stays hidden until open_new()/open_edit() pops it up
	title = "Connection Settings"
	theme = AppTheme.shared()
	min_size = Vector2i(480, 420)
	exclusive = true
	transient = true
	close_requested.connect(_on_cancel)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(_build_connection_tab())
	tabs.add_child(_build_auth_tab())
	tabs.add_child(_build_ssh_tab())
	tabs.add_child(_build_ssl_tab())
	tabs.add_child(_build_advanced_tab())
	col.add_child(tabs)

	col.add_child(_build_buttons())

	_set_enabled(_auth_controls, false)
	_set_enabled(_ssh_controls, false)
	_set_enabled(_ssl_controls, false)


# Public API ------------------------------------------------------------------
func open_new() -> void:
	_reset()
	popup_centered(Vector2i(540, 460))


func open_edit(config: Dictionary) -> void:
	_reset()
	_name_edit.text = config.get("name", "")
	var hostport: String = config.get("host", "")
	if hostport.contains(":"):
		var parts := hostport.split(":")
		_host_edit.text = parts[0]
		_port_edit.text = parts[1]
	else:
		_host_edit.text = hostport
	popup_centered(Vector2i(540, 460))


# Tab builders ----------------------------------------------------------------
func _build_connection_tab() -> Control:
	var tab := _make_tab("Connection")

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "New Connection"
	_add_row(tab, "Name", _name_edit)

	var address := HBoxContainer.new()
	_host_edit = LineEdit.new()
	_host_edit.placeholder_text = "localhost"
	_host_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address.add_child(_host_edit)
	var colon := Label.new()
	colon.text = ":"
	address.add_child(colon)
	_port_edit = LineEdit.new()
	_port_edit.text = "27017"
	_port_edit.custom_minimum_size = Vector2(72, 0)
	address.add_child(_port_edit)
	_add_row(tab, "Address", address)

	return tab


func _build_auth_tab() -> Control:
	var tab := _make_tab("Authentication")

	_auth_check = CheckBox.new()
	_auth_check.text = "Perform authentication"
	_auth_check.toggled.connect(func(on: bool) -> void: _set_enabled(_auth_controls, on))
	tab.add_child(_auth_check)

	var grid := _make_grid()
	tab.add_child(grid)

	_auth_db_edit = LineEdit.new()
	_auth_db_edit.text = "admin"
	_add_grid_row(grid, "Database", _auth_db_edit)

	_user_edit = LineEdit.new()
	_add_grid_row(grid, "User Name", _user_edit)

	_pass_edit = LineEdit.new()
	_pass_edit.secret = true
	_add_grid_row(grid, "Password", _pass_edit)

	_mech_option = OptionButton.new()
	for mech in MECHANISMS:
		_mech_option.add_item(mech)
	_add_grid_row(grid, "Auth Mechanism", _mech_option)

	_auth_controls = [_auth_db_edit, _user_edit, _pass_edit, _mech_option]
	return tab


func _build_ssh_tab() -> Control:
	var tab := _make_tab("SSH")

	_ssh_check = CheckBox.new()
	_ssh_check.text = "Use SSH tunnel"
	_ssh_check.toggled.connect(func(on: bool) -> void: _set_enabled(_ssh_controls, on))
	tab.add_child(_ssh_check)

	var grid := _make_grid()
	tab.add_child(grid)

	_ssh_host_edit = LineEdit.new()
	_ssh_host_edit.placeholder_text = "ssh.example.com:22"
	_add_grid_row(grid, "SSH Address", _ssh_host_edit)

	_ssh_user_edit = LineEdit.new()
	_add_grid_row(grid, "SSH User", _ssh_user_edit)

	_ssh_controls = [_ssh_host_edit, _ssh_user_edit]
	return tab


func _build_ssl_tab() -> Control:
	var tab := _make_tab("SSL")

	_ssl_check = CheckBox.new()
	_ssl_check.text = "Use SSL/TLS protocol"
	_ssl_check.toggled.connect(func(on: bool) -> void: _set_enabled(_ssl_controls, on))
	tab.add_child(_ssl_check)

	var grid := _make_grid()
	tab.add_child(grid)

	_ssl_ca_edit = LineEdit.new()
	_ssl_ca_edit.placeholder_text = "Path to CA certificate"
	_add_grid_row(grid, "CA File", _ssl_ca_edit)

	_ssl_controls = [_ssl_ca_edit]
	return tab


func _build_advanced_tab() -> Control:
	var tab := _make_tab("Advanced")

	var grid := _make_grid()
	tab.add_child(grid)

	_default_db_edit = LineEdit.new()
	_default_db_edit.placeholder_text = "(show all databases)"
	_add_grid_row(grid, "Default Database", _default_db_edit)

	_timeout_edit = LineEdit.new()
	_timeout_edit.text = "30"
	_add_grid_row(grid, "Timeout (s)", _timeout_edit)

	return tab


func _build_buttons() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var test_btn := Button.new()
	test_btn.text = "Test"
	test_btn.pressed.connect(_on_test)
	row.add_child(test_btn)

	_status = Label.new()
	_status.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_status)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.add_theme_color_override("font_color", AppTheme.ACCENT)
	save_btn.pressed.connect(_on_save)
	row.add_child(save_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_on_cancel)
	row.add_child(cancel_btn)

	return row


# Helpers ---------------------------------------------------------------------
func _make_tab(tab_name: String) -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.name = tab_name
	tab.add_theme_constant_override("separation", 10)
	return tab


func _make_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	return grid


func _add_row(parent: VBoxContainer, label_text: String, control: Control) -> void:
	var grid := _make_grid()
	parent.add_child(grid)
	_add_grid_row(grid, label_text, control)


func _add_grid_row(grid: GridContainer, label_text: String, control: Control) -> void:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(120, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(lbl)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)


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
			"mechanism": MECHANISMS[_mech_option.selected],
		},
	}


func _on_test() -> void:
	if _host_edit.text.strip_edges().is_empty():
		_status.text = "Enter a host to test."
		return
	_status.text = "Testing not available yet (no driver)."


func _on_save() -> void:
	if _host_edit.text.strip_edges().is_empty():
		_status.text = "A host is required."
		return
	saved.emit(_gather())
	hide()


func _on_cancel() -> void:
	hide()
