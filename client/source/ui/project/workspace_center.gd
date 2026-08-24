class_name WorkspaceCenter
extends Control

## The shared center of a project tab: a single TabContainer holding both Mongo
## query tabs and Rocket.Chat endpoint tabs side by side, so the two browsers can
## interact within one workspace. Query and endpoint tabs are distinguished by a
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
const ICON_QUERY := preload("res://source/ui/icons/collection.svg")
const ICON_ENDPOINT := preload("res://source/ui/icons/api.svg")

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


## Toggle the cross-query search actions on every open endpoint tab. Called when a
## database is attached after some endpoint tabs are already open.
func set_cross_query_enabled(enabled: bool) -> void:
	for child in _tabs.get_children():
		if child is EndpointTab:
			(child as EndpointTab).set_cross_query_enabled(enabled)


## Set the active schema and push it to every open query tab, and to endpoint tabs
## so their result values can be searched via the schema's cross-query actions.
func set_schema(schema: DatabaseSchema) -> void:
	_schema = schema
	for child in _tabs.get_children():
		if child is QueryTab:
			(child as QueryTab).set_schema(schema)
		elif child is EndpointTab:
			(child as EndpointTab).set_schema(schema)


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
	# Connect before add_child so the tab's initial _run() status is captured.
	tab.status_changed.connect(func(text: String) -> void: status_changed.emit(text))
	tab.title_changed.connect(_on_tab_title_changed.bind(tab))
	tab.open_query_requested.connect(_on_open_query_requested)
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


func _on_tab_title_changed(title: String, tab: QueryTab) -> void:
	var index := _tabs.get_tab_idx_from_control(tab)
	if index != -1:
		_tabs.set_tab_title(index, title)


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
## / EndpointTab.to_state). Results are never included.
func capture_tabs() -> Array:
	var out: Array = []
	for child in _tabs.get_children():
		if child is QueryTab:
			out.append((child as QueryTab).to_state())
		elif child is EndpointTab:
			out.append((child as EndpointTab).to_state())
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
	tab.status_changed.connect(func(text: String) -> void: status_changed.emit(text))
	tab.title_changed.connect(_on_tab_title_changed.bind(tab))
	tab.open_query_requested.connect(_on_open_query_requested)
	tab.state_changed.connect(_emit_state_changed)
	tab.name = "q_%d" % _tab_counter
	_tab_counter += 1
	_tabs.add_child(tab)
	var index := _tabs.get_tab_idx_from_control(tab)
	_tabs.set_tab_title(index, tab.tab_title())
	_tabs.set_tab_icon(index, ICON_QUERY)
