class_name RcModelsTab
extends VBoxContainer

## A query for one @rocket.chat/models method, opened by double-clicking a function
## in the Server Models sidebar. The model and method are fixed for the tab (shown in
## the toolbar); the user supplies a JSON array of arguments and presses Run, which
## posts { target, model, method, args } to the Debris /api/rocketchat/call bridge and
## renders the returned value (canonical Extended JSON) below.
##
## The target (meteor dir + server URL) is read live from the workspace on every Run
## via a provider Callable (bind_target), not captured when the tab opens. _run guards
## against an empty target (e.g. a restored tab whose workspace lost its meteor dir).
##
## Layout lives in the .tscn; configure()/configure_restore() must be called before
## the node enters the tree so _ready() can seed the args editor. Results are never
## persisted; a restore re-seeds the inputs and waits for the user to press Run.

signal status_changed(text: String)
## Emitted when persistable state changes (args edited, or a call run), so the project
## can save the .debris-workspace sidecar.
signal state_changed()
## Bubbled up from the results view when "View JSON in New Tab" is chosen on a nested
## object/array, asking the owner to open a JSON tab seeded with `text`.
signal open_json_requested(text: String)

## The model and method this tab queries (set via configure/restore; fixed after).
var _model := ""
var _method := ""
## Returns the workspace's current Server Models target as { meteor_dir, url }.
## Set by bind_target(); called fresh on every Run so config changes take effect.
var _target_provider: Callable = Callable()
## Args editor text to seed when the tab first opens.
var _initial_args := ""
## Set by configure_restore() to reopen a saved tab from the sidecar.
var _restore_state: Dictionary = {}

@onready var _toolbar: PanelContainer = %Toolbar
@onready var _run_btn: Button = %RunBtn
@onready var _title_label: Label = %TitleLabel
@onready var _args_edit: CodeEdit = %ArgsEdit
@onready var _results: ResultsView = %Results


## Open a tab for `model`.`method`, optionally pre-filling the args editor. Call
## before the node enters the tree; pair with bind_target() for the live target.
func configure(model: String, method: String, args_text := "") -> void:
	_model = model
	_method = method
	_initial_args = args_text


## Reopen a saved models tab (from the .debris-workspace sidecar): the model/method/
## args come from `state`; the target comes live from bind_target(). Call before the
## node enters the tree.
func configure_restore(state: Dictionary) -> void:
	_restore_state = state
	_model = String(state.get("model", ""))
	_method = String(state.get("method", ""))
	_initial_args = String(state.get("args", ""))


## Provide the live workspace target: a Callable returning { meteor_dir, url }. Read
## fresh on every Run, so editing the workspace's meteor dir affects already-open tabs.
func bind_target(provider: Callable) -> void:
	_target_provider = provider


## Snapshot this tab for the sidecar: the model/method and current args (never the
## results, and not the target — that lives in the workspace document).
func to_state() -> Dictionary:
	return {
		"kind": "rcmodels",
		"model": _model,
		"method": _method,
		"args": _args_edit.text,
	}


func tab_title() -> String:
	return "%s.%s" % [_model, _method]


## Public entry point mirroring the Run button (F5).
func run() -> void:
	_run()


## Exposes the results view (mirrors QueryTab/EndpointTab/JsonTab).
func results() -> ResultsView:
	return _results


func _ready() -> void:
	_apply_style()
	# Model results, like endpoint responses, carry no schema and aren't paginated —
	# but they're very often an array (any cursor method), so keep the Table mode
	# available.
	_results.set_raw_mode(true, true)
	_results.set_pagination_enabled(false)
	_results.set_item_noun("result")
	_results.open_json_requested.connect(func(text: String) -> void: open_json_requested.emit(text))

	_args_edit.text = _initial_args
	_title_label.text = tab_title()
	status_changed.emit("Enter JSON args, then Run (F5)")


func _apply_style() -> void:
	var sb := AppTheme._flat(AppTheme.BG_DARK, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	_toolbar.add_theme_stylebox_override("panel", sb)
	_run_btn.add_theme_color_override("font_color", AppTheme.ACCENT_GREEN)
	_run_btn.tooltip_text = "Call the model method (F5)"
	_title_label.add_theme_color_override("font_color", AppTheme.TEXT_BRIGHT)


## Send { target, model, method, args } to the bridge and render the result. The
## args editor is parsed leniently (LaxJson — the same JSON5-flavoured parser the
## query editors use) and must yield a JSON array; an empty editor means no args.
func _run() -> void:
	# Read the target fresh from the workspace, so a meteor dir configured after this
	# tab was opened is picked up without reopening.
	var info: Dictionary = _target_provider.call() if _target_provider.is_valid() else {}
	var meteor := String(info.get("meteor_dir", "")).strip_edges()
	if meteor.is_empty():
		status_changed.emit("Configure a Meteor directory in the workspace settings first")
		return

	var args_result := _parse_args()
	if not args_result.get("ok", false):
		status_changed.emit(String(args_result.get("error", "invalid args")))
		return
	var args: Array = args_result["args"]

	var target := {"meteorDir": meteor}
	var url := String(info.get("url", "")).strip_edges()
	if not url.is_empty():
		target["url"] = url

	_run_btn.disabled = true
	status_changed.emit("%s.%s…" % [_model, _method])
	var result: Dictionary = await Backend.rocketchat_call(target, _model, _method, args)
	_run_btn.disabled = false

	if not result.get("ok", false):
		# Still show the error body (if any) so the message is inspectable.
		_results.show_raw(result.get("data"), [], 0)
		status_changed.emit("%s.%s failed: %s" % [_model, _method, result.get("error", "request failed")])
		state_changed.emit()
		return

	# The bridge wraps the return value as { result: <value> }; unwrap it, but fall
	# back to the whole body if the shape is ever different.
	var data: Variant = result.get("data")
	var value: Variant = data.get("result") if (data is Dictionary and (data as Dictionary).has("result")) else data
	var count := (value as Array).size() if value is Array else 0
	_results.show_raw(value, [], count)
	status_changed.emit("%s.%s — %s" % [_model, _method, _describe(value, count)])
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
