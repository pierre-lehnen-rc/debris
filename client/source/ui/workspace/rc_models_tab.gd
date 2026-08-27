class_name RcModelsTab
extends VBoxContainer

## A console for calling @rocket.chat/models methods on a running Rocket.Chat dev
## server, through the Debris server's /api/rocketchat/call bridge. The user names
## a model and method and supplies a JSON array of arguments; Run sends
## { target, model, method, args } to Backend.rocketchat_call and renders the
## returned value (canonical Extended JSON) in the results view below, exactly as
## query/endpoint tabs do. The bridge is installed into the RC server on first call.
##
## Like the other center tabs, layout lives in the .tscn and configure()/
## configure_restore() must be called before the node enters the tree so _ready()
## can seed the fields. Results are never persisted — a restore re-seeds the inputs
## and waits for the user to press Run (no auto-send), matching endpoint tabs.

signal status_changed(text: String)
## Emitted when the tab's title should change (it adopts "Model.method" after a
## run), so the workspace center can relabel the tab.
signal title_changed(title: String)
## Emitted when persistable state changes (a field edited, or a call run), so the
## project can save the .debris-workspace sidecar.
signal state_changed()
## Bubbled up from the results view when "View JSON in New Tab" is chosen on a
## nested object/array, asking the owner to open a JSON tab seeded with `text`.
signal open_json_requested(text: String)

## Field values to seed when the tab first opens (set via configure()/restore).
var _initial: Dictionary = {}
## The tab's display title: "Models" until a call names it "Model.method".
var _title := "Models"
## Set by configure_restore() to reopen a saved tab from the sidecar.
var _restore_state: Dictionary = {}

@onready var _toolbar: PanelContainer = %Toolbar
@onready var _run_btn: Button = %RunBtn
@onready var _title_label: Label = %TitleLabel
@onready var _meteor_edit: LineEdit = %MeteorEdit
@onready var _url_edit: LineEdit = %UrlEdit
@onready var _model_edit: LineEdit = %ModelEdit
@onready var _method_edit: LineEdit = %MethodEdit
@onready var _args_edit: CodeEdit = %ArgsEdit
@onready var _results: ResultsView = %Results


## Open a fresh models tab, optionally pre-filling the RC server URL and Meteor
## directory (the project supplies the URL it already knows). Call before the node
## enters the tree.
func configure(meteor_dir := "", url := "", model := "", method := "", args_text := "") -> void:
	_initial = {
		"meteor_dir": meteor_dir,
		"url": url,
		"model": model,
		"method": method,
		"args": args_text,
	}


## Reopen a saved models tab (from the .debris-workspace sidecar). `state` is a dict
## from to_state(). Call before the node enters the tree.
func configure_restore(state: Dictionary) -> void:
	_restore_state = state
	_initial = {
		"meteor_dir": String(state.get("meteor_dir", "")),
		"url": String(state.get("url", "")),
		"model": String(state.get("model", "")),
		"method": String(state.get("method", "")),
		"args": String(state.get("args", "")),
	}
	var title := String(state.get("title", "Models"))
	_title = title if not title.is_empty() else "Models"


## Snapshot this tab for the sidecar: the inputs (never the results). The Meteor
## path is a local machine path, which is why it rides in the per-user sidecar
## rather than the shared project document.
func to_state() -> Dictionary:
	return {
		"kind": "rcmodels",
		"meteor_dir": _meteor_edit.text,
		"url": _url_edit.text,
		"model": _model_edit.text,
		"method": _method_edit.text,
		"args": _args_edit.text,
		"title": _title,
	}


func tab_title() -> String:
	return _title


## Public entry point mirroring the Run button, so the host can trigger it for the
## active tab (F5).
func run() -> void:
	_run()


## Exposes the results view (mirrors QueryTab/EndpointTab/JsonTab).
func results() -> ResultsView:
	return _results


func _ready() -> void:
	_apply_style()
	# Model results, like endpoint responses, carry no schema and aren't paginated.
	_results.set_raw_mode(true)
	_results.set_pagination_enabled(false)
	_results.set_item_noun("result")
	_results.open_json_requested.connect(func(text: String) -> void: open_json_requested.emit(text))

	_meteor_edit.text = String(_initial.get("meteor_dir", ""))
	_url_edit.text = String(_initial.get("url", ""))
	_model_edit.text = String(_initial.get("model", ""))
	_method_edit.text = String(_initial.get("method", ""))
	_args_edit.text = String(_initial.get("args", ""))
	_title_label.text = _title
	# Enter in any of the single-line fields runs the call, like the query editors.
	var fields: Array[LineEdit] = [_meteor_edit, _url_edit, _model_edit, _method_edit]
	for field in fields:
		field.text_submitted.connect(func(_t: String) -> void: _run())

	status_changed.emit("Enter a model, method and JSON args, then Run (F5)")


func _apply_style() -> void:
	var sb := AppTheme._flat(AppTheme.BG_DARK, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	_toolbar.add_theme_stylebox_override("panel", sb)
	_run_btn.add_theme_color_override("font_color", AppTheme.ACCENT_GREEN)
	_run_btn.tooltip_text = "Call the model method (F5)"
	_title_label.add_theme_color_override("font_color", AppTheme.TEXT_DIM)


## Send { target, model, method, args } to the bridge and render the result. The
## args editor is parsed leniently (LaxJson — the same JSON5-flavoured parser the
## query editors use) and must yield a JSON array; an empty editor means no args.
func _run() -> void:
	var meteor := _meteor_edit.text.strip_edges()
	var model := _model_edit.text.strip_edges()
	var method := _method_edit.text.strip_edges()
	if meteor.is_empty():
		status_changed.emit("Set the Meteor app directory (…/Rocket.Chat/apps/meteor)")
		return
	if model.is_empty() or method.is_empty():
		status_changed.emit("Enter both a model (e.g. Users) and a method")
		return

	var args_result := _parse_args()
	if not args_result.get("ok", false):
		status_changed.emit(String(args_result.get("error", "invalid args")))
		return
	var args: Array = args_result["args"]

	var target := {"meteorDir": meteor}
	var url := _url_edit.text.strip_edges()
	if not url.is_empty():
		target["url"] = url

	_run_btn.disabled = true
	status_changed.emit("%s.%s…" % [model, method])
	var result: Dictionary = await Backend.rocketchat_call(target, model, method, args)
	_run_btn.disabled = false

	if not result.get("ok", false):
		# Still show the error body (if any) so the message is inspectable.
		_results.show_raw(result.get("data"), [], 0)
		status_changed.emit("%s.%s failed: %s" % [model, method, result.get("error", "request failed")])
		state_changed.emit()
		return

	# The bridge wraps the return value as { result: <value> }; unwrap it, but fall
	# back to the whole body if the shape is ever different.
	var data: Variant = result.get("data")
	var value: Variant = data.get("result") if (data is Dictionary and (data as Dictionary).has("result")) else data
	var count := (value as Array).size() if value is Array else 0
	_results.show_raw(value, [], count)
	_set_title("%s.%s" % [model, method])
	status_changed.emit("%s.%s — %s" % [model, method, _describe(value, count)])
	state_changed.emit()


## Parse the args editor into an Array. Empty input is no args ([]); anything that
## isn't a JSON array is an error.
func _parse_args() -> Dictionary:
	var text := _args_edit.text.strip_edges()
	if text.is_empty():
		return {"ok": true, "args": []}
	var parsed: Dictionary = LaxJson.parse_string(text)
	if not parsed.get("ok", false):
		return {"ok": false, "error": "Invalid args JSON: %s" % parsed.get("error", "parse error")}
	var value: Variant = parsed["value"]
	if not (value is Array):
		return {"ok": false, "error": "Args must be a JSON array (e.g. [\"rocket.cat\"])"}
	return {"ok": true, "args": value}


## Human-readable result summary for the status line.
func _describe(value: Variant, count: int) -> String:
	if value is Array:
		return "%d result%s" % [count, "" if count == 1 else "s"]
	if value == null:
		return "no result"
	return "1 result"


## Adopt "Model.method" as the tab title after a run, announcing the change so the
## center relabels the tab. No-op when unchanged or blank.
func _set_title(title: String) -> void:
	if title.is_empty() or title == _title:
		return
	_title = title
	_title_label.text = _title
	title_changed.emit(_title)
