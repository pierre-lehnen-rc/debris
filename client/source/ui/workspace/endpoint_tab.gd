class_name EndpointTab
extends VBoxContainer

## A single endpoint workspace: a parameter form on top (built dynamically from
## the endpoint's params) and a results view below, split vertically. "Send"
## issues the request against the workspace's live REST API (via the RocketChat
## client) using the form values and displays the response. Query params go in the
## URL, body params in a JSON body, and ":id"/"{id}" path placeholders are filled
## from matching fields. Paginated endpoints drive the results pager; single or
## bounded endpoints hide it. Layout lives in endpoint_tab.tscn; configure() must
## be called before the node enters the tree so _ready() can build the form.

signal status_changed(text: String)
## Bubbled up from the results view when a cross-query search action (the schema's
## "Unknown Type" menu on a result value) asks to open a query tab on the DB.
signal open_query_requested(collection: String, filter: Dictionary, function: String)

@onready var _toolbar: PanelContainer = %Toolbar
@onready var _send_btn: Button = %SendBtn
@onready var _method_label: Label = %MethodLabel
@onready var _path_label: Label = %PathLabel
@onready var _summary_label: Label = %SummaryLabel
@onready var _params_grid: GridContainer = %ParamsGrid
@onready var _no_params: Label = %NoParams
@onready var _results: ResultsView = %Results

var _session: WorkspaceSession = null
var _endpoint: ApiEndpoint = null
## Form values captured at the last "Send"; page navigation reuses them so paging
## doesn't pick up half-typed edits.
var _active_args: Dictionary = {}
## param name -> input Control (LineEdit or CheckBox).
var _inputs: Dictionary = {}
## Dropdown for choosing which session user to send as. Item metadata holds the
## session user id, or -1 for the anonymous "(none)" entry.
var _user_select: OptionButton = null


## Bind this tab to a session + endpoint. Call before the node enters the tree.
func configure(session: WorkspaceSession, endpoint: ApiEndpoint) -> void:
	_session = session
	_endpoint = endpoint


func endpoint() -> ApiEndpoint:
	return _endpoint


func results() -> ResultsView:
	return _results


## Enable/disable the cross-query search actions on this tab's result rows. The
## workspace center enables it when the project also has a database attached.
func set_cross_query_enabled(enabled: bool) -> void:
	_results.set_cross_query_enabled(enabled)


## Apply the attached database's schema so result string values can be searched via
## the schema's "Unknown Type" actions. Endpoint results have no collection of their
## own, so an empty collection is passed.
func set_schema(schema: DatabaseSchema) -> void:
	if is_node_ready():
		_results.set_type_context(schema, "")


func tab_title() -> String:
	return _endpoint.label() if _endpoint != null else "(endpoint)"


func _ready() -> void:
	_apply_style()
	# Relay a results-view cross-query request up to the workspace center.
	_results.open_query_requested.connect(
		func(collection: String, filter: Dictionary, function: String) -> void:
			open_query_requested.emit(collection, filter, function)
	)
	if _endpoint == null:
		return

	_method_label.text = _endpoint.method
	_path_label.text = _endpoint.path
	_summary_label.text = _endpoint.summary
	_results.set_pagination_enabled(_endpoint.paginated)
	_results.set_item_noun(_endpoint.noun())
	_build_form()
	# Keep the user picker in step with the session's live user/token list.
	if _session != null:
		_session.changed.connect(_refresh_user_options)
	# Don't auto-run: wait for the user to press Send so opening a tab (which may
	# be a mutating POST/PUT/DELETE) never fires a request on its own.
	status_changed.emit("%s %s — press Send to run" % [_endpoint.method, _endpoint.path])


func _apply_style() -> void:
	var sb := AppTheme._flat(AppTheme.BG_DARK, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	_toolbar.add_theme_stylebox_override("panel", sb)
	_send_btn.add_theme_color_override("font_color", AppTheme.ACCENT_GREEN)
	_method_label.add_theme_color_override("font_color", AppTheme.ACCENT)
	_path_label.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_summary_label.add_theme_color_override("font_color", AppTheme.TEXT_DIM)


# Form ------------------------------------------------------------------------
## Build a label + input row per user-facing param. Pagination params are handled
## by the results pager and excluded by ApiEndpoint.form_params().
func _build_form() -> void:
	for child in _params_grid.get_children():
		child.queue_free()
	_inputs.clear()
	_user_select = null

	var params := _endpoint.form_params()
	_no_params.visible = params.is_empty()
	_params_grid.visible = true  # always at least the User row

	_build_user_row()

	for p in params:
		var name: String = p.get("name", "")
		var required: bool = p.get("required", false)

		var label := Label.new()
		label.text = "%s%s" % [name, " *" if required else ""]
		label.custom_minimum_size = Vector2(120, 0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
		_params_grid.add_child(label)

		var input := _make_input(p)
		_inputs[name] = input
		_params_grid.add_child(input)


## Add the "User" selector as the first form row: an anonymous "(none)" entry
## followed by each session user. Defaults to the first user so opening a tab
## keeps the previous "always authenticated" behaviour.
func _build_user_row() -> void:
	var label := Label.new()
	label.text = "User"
	label.custom_minimum_size = Vector2(120, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_params_grid.add_child(label)

	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_user_select = opt
	_params_grid.add_child(opt)
	_populate_user_options(-2)  # -2: no prior selection, so default to first user


## The id of the currently selected session user, or -1 for "(none)".
func _selected_user_id() -> int:
	if _user_select == null or _user_select.selected < 0:
		return -1
	var meta: Variant = _user_select.get_item_metadata(_user_select.selected)
	return int(meta) if meta != null else -1


## (Re)fill the picker from the session's live user list, keeping the previously
## selected user when it still exists. Called on session changes (login/logout,
## user added/removed) so every open tab stays in sync.
func _refresh_user_options() -> void:
	if _user_select != null:
		_populate_user_options(_selected_user_id())


## Rebuild the option items. `keep_id` is the user id to reselect if still present
## (-1 keeps "(none)", -2 means default to the first user).
func _populate_user_options(keep_id: int) -> void:
	var opt := _user_select
	opt.clear()
	opt.add_item("(none)")
	opt.set_item_metadata(0, -1)
	var users: Array = _session.users() if _session != null else []
	var keep_position := -1
	for i in users.size():
		var user: Dictionary = users[i]
		opt.add_item(_user_label(user))
		opt.set_item_metadata(opt.item_count - 1, user["id"])
		if user["id"] == keep_id:
			keep_position = opt.item_count - 1
	if keep_position >= 0:
		opt.select(keep_position)
	elif keep_id == -2 and users.size() > 0:
		opt.select(1)  # default to the first user
	else:
		opt.select(0)  # (none)


## Label a user in the picker: their derived label, with a hint when a password
## user is not logged in (so it's clear the request will go out unauthenticated).
func _user_label(user: Dictionary) -> String:
	var label := WorkspaceSession.display_label(user)
	if not _session.has_token(user["id"]):
		label += " (no token)"
	return label


## Pick an input widget matched to the param's schema: a checkbox for bools, a
## dropdown for enums, a calendar picker for date/date-time fields, a spin box
## for integers, and a plain text field otherwise.
func _make_input(param: Dictionary) -> Control:
	var type: String = param.get("type", "string")
	var format: String = str(param.get("format", ""))
	var choices: Array = param["enum"] if param.get("enum") is Array else []

	if type == "bool":
		var check := CheckBox.new()
		check.button_pressed = bool(param.get("default", false))
		return check

	if not choices.is_empty():
		return _make_enum(param, choices)

	if format == "date" or format == "date-time":
		var picker := DatePicker.create(format == "date-time", param.get("description", ""))
		if param.has("default"):
			picker.set_value(str(param["default"]))
		picker.submitted.connect(_send)
		return picker

	if type == "int":
		return _make_int(param)

	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.placeholder_text = param.get("description", "")
	if param.has("default"):
		edit.text = str(param["default"])
	# Pressing Enter in any field sends the request.
	edit.text_submitted.connect(func(_t: String) -> void: _send())
	return edit


## A dropdown for an enum param. Optional enums get a leading blank entry (null
## metadata) so they can be left unset; the chosen value is stored as item
## metadata to preserve its original type.
func _make_enum(param: Dictionary, choices: Array) -> OptionButton:
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not bool(param.get("required", false)):
		opt.add_item("")
		opt.set_item_metadata(opt.item_count - 1, null)
	var default_val: Variant = param.get("default")
	for choice in choices:
		opt.add_item(str(choice))
		opt.set_item_metadata(opt.item_count - 1, choice)
		if default_val != null and choice == default_val:
			opt.select(opt.item_count - 1)
	return opt


func _make_int(param: Dictionary) -> SpinBox:
	var spin := SpinBox.new()
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.step = 1
	# Don't clamp to the schema bounds — they're hints, not hard limits.
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.min_value = float(param.get("minimum", 0))
	spin.max_value = float(param.get("maximum", 1_000_000))
	if param.has("default"):
		spin.value = float(param["default"])
	# Pressing Enter in the inner field sends the request.
	spin.get_line_edit().text_submitted.connect(func(_t: String) -> void: _send())
	return spin


## Read the current form values into a request args Dictionary. Blank text/date
## fields and unset dropdowns are omitted so optional params don't get sent
## empty; checkboxes, dropdowns with a value and spin boxes are always sent.
func _gather() -> Dictionary:
	var args: Dictionary = {}
	for p in _endpoint.form_params():
		var name: String = p.get("name", "")
		var input: Control = _inputs.get(name)
		if input == null:
			continue
		var value: Variant = _value_of(input)
		if value == null:
			continue
		args[name] = value
	return args


## Pull the current value from one input widget. Returns null when the field is
## blank/unset so _gather can omit it.
func _value_of(input: Control) -> Variant:
	if input is CheckBox:
		return (input as CheckBox).button_pressed
	if input is OptionButton:
		var opt := input as OptionButton
		return opt.get_item_metadata(opt.selected) if opt.selected >= 0 else null
	if input is SpinBox:
		return int((input as SpinBox).value)
	if input is DatePicker:
		var iso := (input as DatePicker).get_value()
		return null if iso.is_empty() else iso
	if input is LineEdit:
		var text := (input as LineEdit).text.strip_edges()
		return null if text.is_empty() else text
	return null


# Requests --------------------------------------------------------------------
## Capture form values and (re)load from the first page. The results view then
## drives subsequent pages back through _fetch_page.
func _send() -> void:
	_active_args = _gather()
	_results.request_first_page()


## Fetch one page (or the single/bounded result) from the live API. Wired to
## ResultsView.page_requested.
func _fetch_page(offset: int, limit: int) -> void:
	if _endpoint == null:
		_results.show_page([])
		return

	# Distribute the captured args across the path, query string and JSON body.
	var path := _endpoint.path
	var query: Dictionary = {}
	var body: Dictionary = {}
	var locations := _param_locations()
	for name in _active_args:
		var value: Variant = _active_args[name]
		if path.contains(":" + name):
			path = path.replace(":" + name, str(value).uri_encode())
		elif path.contains("{" + name + "}"):
			path = path.replace("{" + name + "}", str(value).uri_encode())
		elif locations.get(name, "query") == "body":
			body[name] = value
		else:
			query[name] = value
	if _endpoint.paginated:
		query[_endpoint.offset_param] = offset
		query[_endpoint.count_param] = limit

	_send_btn.disabled = true
	status_changed.emit("%s %s…" % [_endpoint.method, path])
	var result: Dictionary = await RocketChat.request(
		_effective_workspace(), _http_method(_endpoint.method), path, query, body
	)
	_send_btn.disabled = false

	var raw: Variant = result.get("data")
	# Transport failure, or a 200 with { success: false }.
	if not result.get("ok", false) or (raw is Dictionary and raw.get("success") == false):
		var message: String = result.get("error", "request failed")
		if raw is Dictionary and raw.get("error") is String:
			message = raw["error"]
		_results.show_page([raw] if raw is Dictionary else [])
		status_changed.emit("%s failed: %s" % [_endpoint.id, message])
		return

	var data := _extract(raw)
	_results.show_page(data)
	var total := int(raw["total"]) if (raw is Dictionary and raw.has("total")) else data.size()
	if _endpoint.paginated:
		var first := (offset + 1) if data.size() > 0 else 0
		var last := offset + data.size()
		status_changed.emit("%s — %d–%d of %d" % [_endpoint.id, first, last, total])
	else:
		status_changed.emit("%s — %d %s%s" % [
			_endpoint.id, data.size(), _endpoint.noun(), "" if data.size() == 1 else "s",
		])


## The workspace to send this tab's request as: the session resolves the picked
## user's credentials (empty when the user has no token, so no auth header goes
## out; empty too for the anonymous "(none)" choice).
func _effective_workspace() -> Dictionary:
	if _session == null:
		return {}
	return _session.effective_workspace(_selected_user_id())


## Map each declared param name to where it belongs in the request ("query" or
## "body"), so _fetch_page can route the captured values.
func _param_locations() -> Dictionary:
	var out: Dictionary = {}
	for p in _endpoint.params:
		out[p.get("name", "")] = p.get("in", "query")
	return out


func _http_method(method: String) -> int:
	match method.to_upper():
		"POST":
			return HTTPClient.METHOD_POST
		"PUT":
			return HTTPClient.METHOD_PUT
		"DELETE":
			return HTTPClient.METHOD_DELETE
		"PATCH":
			return HTTPClient.METHOD_PATCH
		_:
			return HTTPClient.METHOD_GET


## Pull the rows to display out of a response body. Uses the endpoint's inferred
## result_key: an array becomes the rows, a single object becomes one row. With no
## usable key, the whole response object is shown as a single row.
func _extract(raw: Variant) -> Array:
	if raw is Array:
		return raw
	if not (raw is Dictionary):
		return [] if raw == null else [{"value": raw}]

	var dict: Dictionary = raw
	var key := _endpoint.result_key
	if key != "" and dict.has(key):
		var payload: Variant = dict[key]
		if payload is Array:
			return payload
		if payload is Dictionary:
			return [payload]
		return [{key: payload}]
	return [dict]
