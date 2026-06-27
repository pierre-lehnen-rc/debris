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

@onready var _toolbar: PanelContainer = %Toolbar
@onready var _send_btn: Button = %SendBtn
@onready var _method_label: Label = %MethodLabel
@onready var _path_label: Label = %PathLabel
@onready var _summary_label: Label = %SummaryLabel
@onready var _params_grid: GridContainer = %ParamsGrid
@onready var _no_params: Label = %NoParams
@onready var _results: ResultsView = %Results

var _workspace: Dictionary = {}
var _endpoint: ApiEndpoint = null
## Form values captured at the last "Send"; page navigation reuses them so paging
## doesn't pick up half-typed edits.
var _active_args: Dictionary = {}
## param name -> input Control (LineEdit or CheckBox).
var _inputs: Dictionary = {}


## Bind this tab to a workspace + endpoint. Call before the node enters the tree.
func configure(workspace: Dictionary, endpoint: ApiEndpoint) -> void:
	_workspace = workspace
	_endpoint = endpoint


func endpoint() -> ApiEndpoint:
	return _endpoint


func results() -> ResultsView:
	return _results


func tab_title() -> String:
	return _endpoint.label() if _endpoint != null else "(endpoint)"


func _ready() -> void:
	_apply_style()
	if _endpoint == null:
		return

	_method_label.text = _endpoint.method
	_path_label.text = _endpoint.path
	_summary_label.text = _endpoint.summary
	_results.set_pagination_enabled(_endpoint.paginated)
	_results.set_item_noun(_endpoint.noun())
	_build_form()
	# Run once on open so the tab shows data immediately, like a query tab.
	_send()


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

	var params := _endpoint.form_params()
	_no_params.visible = params.is_empty()
	_params_grid.visible = not params.is_empty()

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


func _make_input(param: Dictionary) -> Control:
	var type: String = param.get("type", "string")
	if type == "bool":
		var check := CheckBox.new()
		check.button_pressed = bool(param.get("default", false))
		return check

	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.placeholder_text = param.get("description", "")
	if param.has("default"):
		edit.text = str(param["default"])
	# Pressing Enter in any field sends the request.
	edit.text_submitted.connect(func(_t: String) -> void: _send())
	return edit


## Read the current form values into a request args Dictionary. Empty text fields
## are omitted so optional params don't get sent blank; booleans are always sent.
func _gather() -> Dictionary:
	var args: Dictionary = {}
	for p in _endpoint.form_params():
		var name: String = p.get("name", "")
		var type: String = p.get("type", "string")
		var input: Control = _inputs.get(name)
		if input == null:
			continue
		if input is CheckBox:
			args[name] = (input as CheckBox).button_pressed
		else:
			var text: String = (input as LineEdit).text.strip_edges()
			if text.is_empty():
				continue
			args[name] = int(text) if type == "int" else text
	return args


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
		_workspace, _http_method(_endpoint.method), path, query, body
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
