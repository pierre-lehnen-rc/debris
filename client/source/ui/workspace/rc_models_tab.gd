class_name RcModelsTab
extends VBoxContainer

## A query for one @rocket.chat/models method, opened by double-clicking a function
## in the Server Models sidebar. The model and method are fixed for the tab (shown in
## the toolbar); the user supplies a JSON array of arguments and presses Run, which
## posts { target, model, method, args } to the Debris /api/rocketchat/call bridge and
## renders the returned value (canonical Extended JSON) below.
##
## The target (repository path + server URL) is read live from the workspace on every
## Run via a provider Callable (bind_target), not captured when the tab opens. _run
## guards against an empty target (e.g. a restored tab whose workspace lost its path).
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
## The Mongo collection this model reads (e.g. "rocketchat_subscription"), used to
## type result documents against the database schema. "" leaves results untyped.
var _collection := ""
## The project's database schema, when a DB is attached. Model results are
## Rocket.Chat documents either way, so a plain Rocket.Chat schema stands in when
## the project has no database of its own (see _effective_schema).
var _schema: DatabaseSchema = null
var _fallback_schema: RocketChatSchema = null
## Returns the workspace's current Server Models target as { repo_path, url }.
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
func configure(model: String, method: String, collection := "", args_text := "") -> void:
	_model = model
	_method = method
	_collection = collection
	_initial_args = args_text


## Reopen a saved models tab (from the .debris-workspace sidecar): the model/method/
## args come from `state`; the target comes live from bind_target(). Call before the
## node enters the tree.
func configure_restore(state: Dictionary) -> void:
	_restore_state = state
	_model = String(state.get("model", ""))
	_method = String(state.get("method", ""))
	_collection = String(state.get("collection", ""))
	_initial_args = String(state.get("args", ""))


## Provide the live workspace target: a Callable returning { repo_path, url }. Read
## fresh on every Run, so editing the workspace's path affects already-open tabs.
func bind_target(provider: Callable) -> void:
	_target_provider = provider


## Snapshot this tab for the sidecar: the model/method and current args (never the
## results, and not the target — that lives in the workspace document).
func to_state() -> Dictionary:
	return {
		"kind": "rcmodels",
		"model": _model,
		"method": _method,
		"collection": _collection,
		"args": _args_edit.text,
	}


func tab_title() -> String:
	return "%s.%s" % [_model, _method]


## The model this tab queries, so the center can re-resolve its collection when a
## fresh model list arrives.
func model_name() -> String:
	return _model


## Set the Mongo collection this model reads, typing result documents against it.
## Ignores an empty name so a known collection isn't cleared by a failed refresh.
func set_collection(collection: String) -> void:
	if collection.is_empty() or collection == _collection:
		return
	_collection = collection
	_apply_type_context()


## Apply the project's database schema (mirrors QueryTab/EndpointTab).
func set_schema(schema: DatabaseSchema) -> void:
	_schema = schema
	_apply_type_context()


## Enable/disable the schema's cross-query search actions on result rows. The
## center enables them when the project also has a database attached.
func set_cross_query_enabled(enabled: bool) -> void:
	if is_node_ready():
		_results.set_cross_query_enabled(enabled)


## Type result rows as documents of this model's collection. The collection is
## borrowed only for typing (owns = false): the Type column and its actions light
## up, while sorting/paging stay off, exactly as for endpoint results.
func _apply_type_context() -> void:
	if is_node_ready():
		_results.set_type_context(_effective_schema(), _collection, false)


## The schema used to type results: the project's when a database is attached,
## otherwise a stock Rocket.Chat schema — these are Rocket.Chat documents by
## definition, so their ids/types resolve even without a DB in the project.
func _effective_schema() -> DatabaseSchema:
	if _schema != null:
		return _schema
	if _fallback_schema == null:
		_fallback_schema = RocketChatSchema.new()
	return _fallback_schema


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

	_apply_type_context()
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
	# Read the target fresh from the workspace, so a repository path configured after
	# this tab was opened is picked up without reopening.
	var info: Dictionary = _target_provider.call() if _target_provider.is_valid() else {}
	var repo := String(info.get("repo_path", "")).strip_edges()
	if repo.is_empty():
		status_changed.emit("Set the Rocket.Chat Repository path in the workspace settings first")
		return

	var args_result := _parse_args()
	if not args_result.get("ok", false):
		status_changed.emit(String(args_result.get("error", "invalid args")))
		return
	var args: Array = args_result["args"]

	var target := {"repoPath": repo}
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
	_results.show_raw(value, _entity_roots(value), count)
	status_changed.emit("%s.%s — %s" % [_model, _method, _describe(value, count)])
	state_changed.emit()


## The objects in a result to type as documents of this model's collection: an
## array's document elements, a single returned document, or the documents of a
## paginated { documents, totalCount } result. Everything else is left untyped.
func _entity_roots(value: Variant) -> Array:
	if value is Array:
		return (value as Array).filter(_is_document)
	if value is Dictionary:
		var d := value as Dictionary
		# A cursor-with-count method returns its rows under `documents`.
		if d.get("documents") is Array:
			return (d["documents"] as Array).filter(_is_document)
		if _is_document(d):
			return [d]
	return []


## Whether a result value is a collection document (so the schema should type it).
## Two kinds of object are deliberately excluded: write results (UpdateResult and
## friends, identified by `acknowledged`), which are command output rather than
## stored documents, and Extended JSON scalar wrappers ({"$numberInt": …}), which
## are plain values. Strings, numbers and booleans are never documents either.
func _is_document(value: Variant) -> bool:
	if not (value is Dictionary):
		return false
	var d := value as Dictionary
	if d.has("acknowledged"):
		return false
	for key in d:
		if not String(key).begins_with("$"):
			return true
	return false


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
