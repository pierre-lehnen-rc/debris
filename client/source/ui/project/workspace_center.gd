class_name WorkspaceCenter
extends Control

## The shared center of a project tab: a single TabContainer holding Mongo query
## tabs, Rocket.Chat endpoint tabs, and JSON scratch tabs side by side, so the
## browsers can interact within one workspace. Each tab kind is distinguished by a
## per-tab type icon. A welcome overlay shows while nothing is open. Merges the
## former DatabaseWorkspace and EndpointWorkspace; there is no "+" new-tab button
## and opening a collection always adds a fresh tab (no blank-tab reuse).

signal status_changed(text: String)
## Emitted when the set of open tabs or their persistable state changes (tab
## opened/closed/retargeted, or a query/request run), so the project can save the
## .debris-workspace sidecar. Not emitted during a restore (see restore_tabs).
signal state_changed()

const QUERY_TAB_SCENE := preload("res://source/ui/database/query_tab.tscn")
const ENDPOINT_TAB_SCENE := preload("res://source/ui/workspace/endpoint_tab.tscn")
const JSON_TAB_SCENE := preload("res://source/ui/database/json_tab.tscn")
const RCMODELS_TAB_SCENE := preload("res://source/ui/workspace/rc_models_tab.tscn")
const ICON_QUERY := preload("res://source/ui/icons/collection.svg")
const ICON_ENDPOINT := preload("res://source/ui/icons/api.svg")
const ICON_JSON := preload("res://source/ui/icons/json.svg")
const ICON_RCMODELS := preload("res://source/ui/icons/models.svg")

@onready var _tabs: TabContainer = %Tabs
@onready var _welcome: Control = %Welcome
@onready var _welcome_title: Label = %WelcomeTitle
@onready var _welcome_hint: Label = %WelcomeHint

var _tab_counter := 0
# True while restore_tabs is reopening saved tabs, so the tabs it creates don't
# each trigger a sidecar write (the caller persists once, after).
var _restoring := false
# The Mongo binding query tabs open against (set when a DB is attached).
var _bound_connection: Dictionary = {}
var _bound_database := ""
# Schema threaded into each query tab so its results view resolves custom types.
var _schema: DatabaseSchema = null
# The Rocket.Chat session endpoint tabs run against (set when an API is attached).
var _session: WorkspaceSession = null
# The Server Models console's target: the RC server URL and the local Rocket.Chat
# repository path, bound when an API is attached, passed to new/restored models tabs.
var _rc_url := ""
var _rc_repo_path := ""
# model name -> the Mongo collection it reads, from the bridge install. Lets a
# models tab type its results with the schema rules of that collection.
var _rc_collections: Dictionary = {}
# Shared per-project recent/favorite query store, handed to every query tab.
var _history: QueryHistory = null


func _ready() -> void:
	var bar := _tabs.get_tab_bar()
	bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ALWAYS
	bar.tab_close_pressed.connect(_on_tab_close_pressed)

	_welcome_title.add_theme_color_override("font_color", AppTheme.TEXT_BRIGHT)
	_welcome_hint.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_update_welcome()


## Bind the Mongo database that query tabs open against.
func bind_mongo(connection: Dictionary, database: String) -> void:
	_bound_connection = connection
	_bound_database = database


## Bind the Rocket.Chat session that endpoint tabs run against.
func bind_session(session: WorkspaceSession) -> void:
	_session = session


## Bind the Server Models target: the workspace's RC server URL and the local
## Rocket.Chat repository path. Models tabs read these instead of asking per tab.
func bind_rocketchat_target(url: String, repo_path: String) -> void:
	_rc_url = url
	_rc_repo_path = repo_path


## Bind the server's model list ({ name, collection } entries, from the bridge
## install) so models tabs can type their results against the collection each model
## reads. Open tabs pick up a newly-resolved collection too.
func bind_rocketchat_models(models: Array) -> void:
	_rc_collections = {}
	for entry in models:
		if entry is Dictionary:
			var name := String((entry as Dictionary).get("name", ""))
			if not name.is_empty():
				_rc_collections[name] = String((entry as Dictionary).get("collection", ""))
	for child in _tabs.get_children():
		if child is RcModelsTab:
			var tab := child as RcModelsTab
			tab.set_collection(String(_rc_collections.get(tab.model_name(), "")))


## The current Server Models target, as { repo_path, url }. Handed to models tabs
## as a Callable so their Run reads the up-to-date workspace config, not a snapshot.
func _rc_target() -> Dictionary:
	return {"repo_path": _rc_repo_path, "url": _rc_url}


## Bind the shared query-history store handed to every query tab (recents +
## favorites). Set before tabs are opened/restored so each tab records into it.
func bind_history(history: QueryHistory) -> void:
	_history = history


## Toggle the cross-query search actions on every open endpoint tab. Called when a
## database is attached after some endpoint tabs are already open.
func set_cross_query_enabled(enabled: bool) -> void:
	for child in _tabs.get_children():
		if child is EndpointTab:
			(child as EndpointTab).set_cross_query_enabled(enabled)
		elif child is RcModelsTab:
			(child as RcModelsTab).set_cross_query_enabled(enabled)


## Set the active schema and push it to every open query tab, and to endpoint tabs
## so their result values can be searched via the schema's cross-query actions.
func set_schema(schema: DatabaseSchema) -> void:
	_schema = schema
	for child in _tabs.get_children():
		if child is QueryTab:
			(child as QueryTab).set_schema(schema)
		elif child is EndpointTab:
			(child as EndpointTab).set_schema(schema)
		elif child is RcModelsTab:
			(child as RcModelsTab).set_schema(schema)


# Mongo query tabs ------------------------------------------------------------
func open_collection(
	connection: Dictionary,
	database: String,
	collection: String,
	function: String = "find",
	initial_filter: Dictionary = {},
) -> QueryTab:
	var tab: QueryTab = QUERY_TAB_SCENE.instantiate()
	tab.configure(connection, database, collection, function, initial_filter)
	tab.set_schema(_schema)
	tab.set_history(_history)
	# Connect before add_child so the tab's initial _run() status is captured.
	tab.status_changed.connect(func(text: String) -> void: status_changed.emit(text))
	tab.title_changed.connect(_on_tab_title_changed.bind(tab))
	tab.open_query_requested.connect(_on_open_query_requested)
	tab.open_json_requested.connect(_on_open_json_requested)
	tab.state_changed.connect(_emit_state_changed)
	tab.name = "q_%d" % _tab_counter
	_tab_counter += 1

	_bound_connection = connection
	_bound_database = database

	_tabs.add_child(tab)
	var index := _tabs.get_tab_idx_from_control(tab)
	_tabs.set_tab_title(index, tab.tab_title())
	_tabs.set_tab_icon(index, ICON_QUERY)
	_tabs.current_tab = index
	_update_welcome()
	_emit_state_changed()
	return tab


## A results view asked to open a new query tab (e.g. a custom type action).
func _on_open_query_requested(collection: String, filter: Dictionary, function: String) -> void:
	open_collection(_bound_connection, _bound_database, collection, function, filter)


## A results view (any tab kind) asked to open its selected object/string in a new
## JSON tab.
func _on_open_json_requested(text: String) -> void:
	open_json(text)


func _on_tab_title_changed(title: String, tab: Control) -> void:
	var index := _tabs.get_tab_idx_from_control(tab)
	if index != -1:
		_tabs.set_tab_title(index, title)


# JSON scratch tabs -----------------------------------------------------------
## Open a JSON tab, optionally seeded with `text` (a file's contents) and a display
## `title`. JSON tabs are self-contained — they need no DB/API — but live here as
## peers of the query/endpoint tabs so they share the tab strip and sidecar.
func open_json(text := "", title := "JSON") -> JsonTab:
	var tab: JsonTab = JSON_TAB_SCENE.instantiate()
	tab.configure(text, title)
	# Connect before add_child so the tab's initial _show() status is captured.
	tab.status_changed.connect(func(t: String) -> void: status_changed.emit(t))
	tab.title_changed.connect(_on_tab_title_changed.bind(tab))
	tab.open_json_requested.connect(_on_open_json_requested)
	tab.state_changed.connect(_emit_state_changed)
	tab.name = "j_%d" % _tab_counter
	_tab_counter += 1

	_tabs.add_child(tab)
	var index := _tabs.get_tab_idx_from_control(tab)
	_tabs.set_tab_title(index, tab.tab_title())
	_tabs.set_tab_icon(index, ICON_JSON)
	_tabs.current_tab = index
	_update_welcome()
	_emit_state_changed()
	return tab


## The focused tab when it's a JSON tab, else null. Lets the host enable/drive
## File ▸ Save JSON… for the active tab.
func active_json_tab() -> JsonTab:
	return _tabs.get_current_tab_control() as JsonTab


# Rocket.Chat model tabs ------------------------------------------------------
## Open a models console tab, optionally pre-filling the RC server URL (the project
## already knows it) and repository path. Self-contained like a JSON tab — it
## targets the Debris server's bridge, not the bound Mongo DB or endpoint session.
func open_rcmodels(model: String, method: String, collection := "", signature := "") -> RcModelsTab:
	# Always a fresh tab (like query tabs): the same function is often run side by
	# side with different arguments, so duplicates are wanted, not deduplicated.
	var tab: RcModelsTab = RCMODELS_TAB_SCENE.instantiate()
	if collection.is_empty():
		collection = String(_rc_collections.get(model, ""))
	tab.configure(model, method, collection, signature)
	tab.bind_target(_rc_target)
	tab.set_history(_history)
	# Connect before add_child so the tab's initial status is captured.
	tab.status_changed.connect(func(text: String) -> void: status_changed.emit(text))
	tab.open_json_requested.connect(_on_open_json_requested)
	# A schema type action on a result opens a sibling query tab on the DB.
	tab.open_query_requested.connect(_on_open_query_requested)
	tab.state_changed.connect(_emit_state_changed)
	tab.name = "m_%d" % _tab_counter
	_tab_counter += 1

	_tabs.add_child(tab)
	# After add_child, so the tab is ready to apply them to its results view.
	tab.set_schema(_schema)
	tab.set_cross_query_enabled(not _bound_database.is_empty())
	var index := _tabs.get_tab_idx_from_control(tab)
	_tabs.set_tab_title(index, tab.tab_title())
	_tabs.set_tab_icon(index, ICON_RCMODELS)
	_tabs.current_tab = index
	_update_welcome()
	_emit_state_changed()
	return tab


# Rocket.Chat endpoint tabs ---------------------------------------------------
## Open (or focus) a tab for `endpoint`. When `restore_state` is non-empty the tab
## is reopened from the sidecar with its saved user/params (never auto-sending).
func open_endpoint(endpoint: ApiEndpoint, restore_state: Dictionary = {}) -> EndpointTab:
	# Focus an existing tab for this endpoint instead of stacking a duplicate.
	var existing := _find_endpoint_tab(endpoint)
	if existing != null:
		_tabs.current_tab = _tabs.get_tab_idx_from_control(existing)
		return existing

	var tab: EndpointTab = ENDPOINT_TAB_SCENE.instantiate()
	if restore_state.is_empty():
		tab.configure(_session, endpoint)
	else:
		tab.configure_restore(_session, endpoint, restore_state)
	tab.status_changed.connect(func(text: String) -> void: status_changed.emit(text))
	# A cross-query search action on a result opens a sibling query tab on the DB.
	tab.open_query_requested.connect(_on_open_query_requested)
	tab.open_json_requested.connect(_on_open_json_requested)
	tab.state_changed.connect(_emit_state_changed)
	tab.name = "e_%d" % _tab_counter
	_tab_counter += 1

	_tabs.add_child(tab)
	# Offer the cross-query search actions only when this project also has a
	# database, and give the new tab the current schema to resolve them.
	tab.set_cross_query_enabled(not _bound_database.is_empty())
	tab.set_schema(_schema)
	var index := _tabs.get_tab_idx_from_control(tab)
	_tabs.set_tab_title(index, tab.tab_title())
	_tabs.set_tab_icon(index, ICON_ENDPOINT)
	_tabs.set_tab_tooltip(index, endpoint.summary)
	_tabs.current_tab = index
	_update_welcome()
	_emit_state_changed()
	return tab


## The open tab for `endpoint` (matched by id), or null.
func _find_endpoint_tab(endpoint: ApiEndpoint) -> EndpointTab:
	for child in _tabs.get_children():
		var tab := child as EndpointTab
		if tab != null and tab.endpoint() != null and tab.endpoint().id == endpoint.id:
			return tab
	return null


# Shared ----------------------------------------------------------------------
## Re-run the active center tab (from a keyboard shortcut): a query tab's find or an
## endpoint tab's request. No-op when nothing is open.
func run_current() -> void:
	var control := _tabs.get_current_tab_control()
	if control is QueryTab:
		(control as QueryTab).run_query()
	elif control is EndpointTab:
		(control as EndpointTab).send_request()
	elif control is JsonTab:
		(control as JsonTab).show_json()
	elif control is RcModelsTab:
		(control as RcModelsTab).run()


## Close the active source tab. Returns true when one was open to close, so the host
## can fall back to closing the whole project tab when the center is empty.
func close_current_tab() -> bool:
	if _tabs.get_tab_count() == 0:
		return false
	_on_tab_close_pressed(_tabs.current_tab)
	return true


## Move the active source-tab selection by `delta` (+1 next, -1 previous), wrapping
## around the ends. No-op with fewer than two tabs.
func cycle_tab(delta: int) -> void:
	var count := _tabs.get_tab_count()
	if count <= 1:
		return
	_tabs.current_tab = (_tabs.current_tab + delta + count) % count


## Focus the source tab at `index` (0-based); values past the end focus the last tab.
func focus_tab(index: int) -> void:
	var count := _tabs.get_tab_count()
	if count == 0:
		return
	_tabs.current_tab = clampi(index, 0, count - 1)


func _on_tab_close_pressed(tab_index: int) -> void:
	var control := _tabs.get_tab_control(tab_index)
	if control == null:
		return
	_tabs.remove_child(control)
	control.queue_free()
	_update_welcome()
	_emit_state_changed()


func _update_welcome() -> void:
	_welcome.visible = _tabs.get_tab_count() == 0


# Persistence (sidecar) -------------------------------------------------------
## Relay a tab/state change to the project, unless a restore is in progress (the
## restore caller persists once when it finishes, so tabs it opens stay quiet).
func _emit_state_changed() -> void:
	if not _restoring:
		state_changed.emit()


## The index of the focused tab (0 when none), for the sidecar's active_tab.
func active_tab_index() -> int:
	return maxi(_tabs.current_tab, 0)


## Snapshot every open tab, in tab order, as sidecar dicts (see QueryTab.to_state
## / EndpointTab.to_state / JsonTab.to_state). Results are never included.
func capture_tabs() -> Array:
	var out: Array = []
	for child in _tabs.get_children():
		if child is QueryTab:
			out.append((child as QueryTab).to_state())
		elif child is EndpointTab:
			out.append((child as EndpointTab).to_state())
		elif child is JsonTab:
			out.append((child as JsonTab).to_state())
		elif child is RcModelsTab:
			out.append((child as RcModelsTab).to_state())
	return out


## Reopen tabs from a sidecar snapshot, in order, then focus `active`. Query tabs
## reuse the bound Mongo connection/database; endpoint tabs are matched to an
## ApiEndpoint by id via `endpoints_by_id` (skipped when the id is unknown, e.g. a
## catalog that no longer has it). State-change signals are suppressed throughout.
func restore_tabs(states: Array, active: int, endpoints_by_id: Dictionary) -> void:
	_restoring = true
	for st in states:
		if not (st is Dictionary):
			continue
		var state := st as Dictionary
		match String(state.get("kind", "")):
			"query":
				_restore_query_tab(state)
			"endpoint":
				var ep: ApiEndpoint = endpoints_by_id.get(String(state.get("endpoint_id", "")))
				if ep != null:
					open_endpoint(ep, state)
			"json":
				_restore_json_tab(state)
			"rcmodels":
				_restore_rcmodels_tab(state)
	_restoring = false
	var count := _tabs.get_tab_count()
	if count > 0:
		_tabs.current_tab = clampi(active, 0, count - 1)
	_update_welcome()


## Reopen one saved query tab against the bound Mongo connection/database.
func _restore_query_tab(state: Dictionary) -> void:
	var tab: QueryTab = QUERY_TAB_SCENE.instantiate()
	var database := String(state.get("database", _bound_database))
	tab.configure_restore(_bound_connection, database, state)
	tab.set_schema(_schema)
	tab.set_history(_history)
	tab.status_changed.connect(func(text: String) -> void: status_changed.emit(text))
	tab.title_changed.connect(_on_tab_title_changed.bind(tab))
	tab.open_query_requested.connect(_on_open_query_requested)
	tab.open_json_requested.connect(_on_open_json_requested)
	tab.state_changed.connect(_emit_state_changed)
	tab.name = "q_%d" % _tab_counter
	_tab_counter += 1
	_tabs.add_child(tab)
	var index := _tabs.get_tab_idx_from_control(tab)
	_tabs.set_tab_title(index, tab.tab_title())
	_tabs.set_tab_icon(index, ICON_QUERY)


## Reopen one saved JSON tab from the sidecar: its text and title are seeded and the
## value is re-parsed on open (results aren't stored, but reproducing them from the
## text is local and free).
func _restore_json_tab(state: Dictionary) -> void:
	var tab: JsonTab = JSON_TAB_SCENE.instantiate()
	tab.configure_restore(state)
	tab.status_changed.connect(func(text: String) -> void: status_changed.emit(text))
	tab.title_changed.connect(_on_tab_title_changed.bind(tab))
	tab.open_json_requested.connect(_on_open_json_requested)
	tab.state_changed.connect(_emit_state_changed)
	tab.name = "j_%d" % _tab_counter
	_tab_counter += 1
	_tabs.add_child(tab)
	var index := _tabs.get_tab_idx_from_control(tab)
	_tabs.set_tab_title(index, tab.tab_title())
	_tabs.set_tab_icon(index, ICON_JSON)


## Reopen one saved models console tab from the sidecar: its inputs are re-seeded;
## it does not auto-run (the user presses Run), consistent with the other tabs.
func _restore_rcmodels_tab(state: Dictionary) -> void:
	var tab: RcModelsTab = RCMODELS_TAB_SCENE.instantiate()
	tab.configure_restore(state)
	tab.bind_target(_rc_target)
	tab.set_history(_history)
	tab.status_changed.connect(func(text: String) -> void: status_changed.emit(text))
	tab.open_json_requested.connect(_on_open_json_requested)
	# A schema type action on a result opens a sibling query tab on the DB.
	tab.open_query_requested.connect(_on_open_query_requested)
	tab.state_changed.connect(_emit_state_changed)
	tab.name = "m_%d" % _tab_counter
	_tab_counter += 1
	_tabs.add_child(tab)
	tab.set_collection(String(_rc_collections.get(tab.model_name(), "")))
	tab.set_schema(_schema)
	tab.set_cross_query_enabled(not _bound_database.is_empty())
	var index := _tabs.get_tab_idx_from_control(tab)
	_tabs.set_tab_title(index, tab.tab_title())
	_tabs.set_tab_icon(index, ICON_RCMODELS)
