class_name ProjectTab
extends Control

## One open Debris project: an optional Mongo database and an optional Rocket.Chat
## API unified in a single tab. A VSCode-style row of view icons across the top of
## the sidebar swaps it between the project's views — Collections when a DB is
## attached, Endpoints and Users when an API is attached — while a shared center
## strip (WorkspaceCenter) holds both query and endpoint tabs. configure(doc)
## builds only the parts the project has attached. The layout is assembled in code;
## the leaf sidebars/center are instanced scenes.

signal status_changed(text: String)
## Emitted when an unattached source's activity-bar icon is clicked, asking the
## host to attach that source ("mongo" | "api") to this project.
signal attach_requested(source: String)
## Emitted when a source panel's edit button is pressed, asking the host to open
## the connection/API editor for that source ("mongo" | "api").
signal edit_source_requested(source: String)
## Emitted when the project's document became dirty on its own (e.g. a user was
## added/removed in the Users panel), so the host can refresh the tab's title.
signal dirty_changed()
## Emitted when a change to the project document should be saved to its file right
## away (a query was favorited/unfavorited). Only fired for a project that already
## has a file — the host saves it in place without prompting.
signal save_requested()

const COLLECTION_SIDEBAR_SCENE := preload("res://source/ui/sidebar/collection_sidebar.tscn")
const ENDPOINT_SIDEBAR_SCENE := preload("res://source/ui/workspace/endpoint_sidebar.tscn")
const USERS_PANEL_SCENE := preload("res://source/ui/workspace/users_panel.tscn")
const RCMODELS_SIDEBAR_SCENE := preload("res://source/ui/workspace/rc_models_sidebar.tscn")
const CENTER_SCENE := preload("res://source/ui/project/workspace_center.tscn")

const ICON_COLLECTIONS := preload("res://source/ui/icons/database.svg")
const ICON_ENDPOINTS := preload("res://source/ui/icons/api.svg")
const ICON_USERS := preload("res://source/ui/icons/users.svg")
const ICON_MODELS := preload("res://source/ui/icons/models.svg")

const VIEW_COLLECTIONS := "collections"
const VIEW_ENDPOINTS := "endpoints"
const VIEW_USERS := "users"
const VIEW_MODELS := "models"

# Default sidebar width matches the old database tab (split_offset 360, 180 floor),
# which is the width the sidebar reference was taken from.
const SIDEBAR_MIN_WIDTH := 180
const SIDEBAR_SPLIT_OFFSET := 360

var _doc: WorkspaceDoc = null
var _session: WorkspaceSession = null

# The .debris-workspace sidecar: open tabs + the offline endpoint cache. Loaded
# on setup, rewritten automatically whenever the tabs/params change (see
# persist_state). Its tab list is re-captured from the center at each save; the
# endpoint cache is maintained here as live fetches land. _restored guards against
# overwriting the sidecar before its saved tabs have been reopened.
var _state: WorkspaceState = null
var _restored := false

# Shared recent/favorite query store: recents live in the sidecar (_state),
# favorites in the project document (_doc). Handed to the center so every query tab
# records into it and can browse it. Built in _setup once both stores exist.
var _history: QueryHistory = null

var _activity: ActivityBar
var _stack: MarginContainer
var _center: WorkspaceCenter
var _collection_sidebar: CollectionSidebar = null
var _endpoint_sidebar: EndpointSidebar = null
var _users_panel: UsersPanel = null
var _models_sidebar: RcModelsSidebar = null
# view id -> sidebar Control, so a view selection can show exactly one.
var _views: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_layout()
	if _doc != null:
		_setup()


## Bind this tab to a project document. Safe to call before the node is in the
## tree; the children are built once the tab is ready.
func configure(doc: WorkspaceDoc) -> void:
	_doc = doc
	if is_node_ready():
		_setup()


func doc() -> WorkspaceDoc:
	return _doc


func tab_title() -> String:
	if _doc == null or _doc.name.is_empty():
		return "(project)"
	return _doc.name


## Re-run the active center tab (query find or endpoint request), from a keyboard
## shortcut. No-op when no source tab is open.
func run_current_tab() -> void:
	if _center != null:
		_center.run_current()


## Close the active query/endpoint tab. Returns true when one was open to close, so
## the host can fall back to closing the whole project tab when the center is empty.
func close_current_tab() -> bool:
	return _center != null and _center.close_current_tab()


## Open a JSON scratch tab in this project's center, optionally seeded with `text`
## (a file's contents) and a display `title`. Returns the tab, or null if the center
## isn't ready.
func open_json(text := "", title := "JSON") -> JsonTab:
	if _center == null:
		return null
	return _center.open_json(text, title)


## The focused center tab when it's a JSON tab, else null (lets the host enable and
## drive File ▸ Save JSON… for the active tab).
func active_json_tab() -> JsonTab:
	return _center.active_json_tab() if _center != null else null


## Cycle the active query/endpoint tab by `delta` (+1 next, -1 previous).
func cycle_tab(delta: int) -> void:
	if _center != null:
		_center.cycle_tab(delta)


## Focus the query/endpoint tab at `index` (0-based; values past the end focus the
## last tab).
func focus_tab(index: int) -> void:
	if _center != null:
		_center.focus_tab(index)


## Switch the sidebar to the activity-bar view at `index` (0-based, display order:
## Collections, Endpoints, Users). Out-of-range indices are ignored.
func select_view(index: int) -> void:
	if _activity != null:
		_activity.select_index(index)


# Layout ----------------------------------------------------------------------
## Assemble the fixed shell: split[ sidebar column | center ], where the sidebar
## column is [ activity row (top) / sidebar stack ]. The stack and center exist up
## front; the sidebars are added by _setup per what the project has attached.
func _build_layout() -> void:
	var split := HSplitContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	split.split_offset = SIDEBAR_SPLIT_OFFSET
	add_child(split)

	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(SIDEBAR_MIN_WIDTH, 0)
	column.add_theme_constant_override("separation", 0)
	split.add_child(column)

	_activity = ActivityBar.new()
	_activity.view_selected.connect(_on_view_selected)
	column.add_child(_activity)

	# A MarginContainer (not a bare Control) so the active sidebar is stretched to
	# fill the pane; a bare Control leaves each PanelContainer sidebar at its own
	# content-minimum width, gapped on the right. It fills the column below the row.
	_stack = MarginContainer.new()
	_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_stack)

	_center = CENTER_SCENE.instantiate()
	_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center.status_changed.connect(_on_status_changed)
	# Any tab/param change auto-saves the sidecar (guarded until restore is done).
	_center.state_changed.connect(persist_state)
	split.add_child(_center)


# Setup -----------------------------------------------------------------------
func _setup() -> void:
	_load_sidecar()
	_setup_history()
	_build_collections_view()
	_build_endpoints_view()
	if _doc.has_rocketchat():
		_build_users_view()
		_build_models_view()
	_refresh_activity()
	# With an API attached, tab restore waits for the endpoint list (cache or live)
	# so endpoint tabs can be matched to their definitions; _on_endpoints_loaded
	# drives it. Without one, there are no endpoint tabs to wait on — restore now.
	if not _doc.has_rocketchat():
		_restore_tabs_once()


## Build the shared query-history store over the two backing stores and hand it to
## the center (before any tabs are opened/restored). A recents change rewrites the
## sidecar; a favorites change is routed through _on_favorites_changed.
func _setup_history() -> void:
	_history = QueryHistory.new()
	_history.setup(_state, _doc)
	_history.recents_changed.connect(persist_state)
	_history.favorites_changed.connect(_on_favorites_changed)
	_center.bind_history(_history)


## A favorite query was added/removed, so the project document is now dirty. Save it
## in place when it has a file (silent auto-save); otherwise just reflect the unsaved
## state in the tab title — it'll be written on the next explicit Save.
func _on_favorites_changed() -> void:
	if _doc != null and not _doc.file_path.is_empty():
		save_requested.emit()
	else:
		dirty_changed.emit()


func has_mongo() -> bool:
	return _doc != null and _doc.has_mongo()


func has_rocketchat() -> bool:
	return _doc != null and _doc.has_rocketchat()


## Attach a Mongo database at runtime (from the connection picker): replace the
## Collections attach-placeholder with the real sidebar and switch to it. No-op if a
## database is already attached (a project holds at most one).
func attach_mongo(connection: Dictionary, database: String) -> void:
	if has_mongo():
		return
	_doc.set_mongo(connection, database)
	_remove_view(VIEW_COLLECTIONS)
	_build_collections_view()
	_refresh_activity(VIEW_COLLECTIONS)
	# An endpoint tab opened before the DB existed now gets the cross-query action.
	_center.set_cross_query_enabled(true)


## Attach a Rocket.Chat API at runtime (from the workspace picker): replace the
## Endpoints attach-placeholder with the real sidebar, add the Users view, and
## switch to Endpoints. No-op if an API is already attached.
func attach_rocketchat(config: Dictionary) -> void:
	if has_rocketchat():
		return
	_doc.set_rocketchat(
		String(config.get("url", "")), config.get("users", []), String(config.get("meteor_dir", ""))
	)
	_remove_view(VIEW_ENDPOINTS)
	_build_endpoints_view()
	_build_users_view()
	_build_models_view()
	_refresh_activity(VIEW_ENDPOINTS)


## Apply an edited Mongo connection (from the connection editor) and reload the
## collection sidebar against it. The browsed database follows the connection's
## default database when set, otherwise the currently-bound one is kept.
func update_mongo_connection(connection: Dictionary) -> void:
	if not has_mongo():
		return
	var database := String(connection.get("database", ""))
	if database.is_empty():
		database = _doc.mongo_database()
	_doc.set_mongo(connection, database)
	_center.bind_mongo(connection, database)
	if _collection_sidebar != null:
		_collection_sidebar.configure(connection, database)


## Apply an edited API URL (from the workspace editor): keep the existing users
## (they're managed by the Users panel), rebuild the session, and reload the
## endpoint/users panels. Endpoint tabs already open keep their original session
## until reopened.
func update_rocketchat(config: Dictionary) -> void:
	if not has_rocketchat():
		return
	var old_meteor := _doc.rocketchat_meteor_dir()
	var users: Array = _doc.rocketchat.get("users", [])
	_doc.set_rocketchat(String(config.get("url", "")), users, String(config.get("meteor_dir", "")))
	_set_session(_doc.rocketchat_config())
	if _endpoint_sidebar != null:
		# Re-seed the cache for the (possibly new) URL — cached_endpoints returns []
		# when the URL changed, so a stale catalog isn't shown for a different server.
		_endpoint_sidebar.set_cache(_state.cached_endpoints(_rocketchat_url()))
		_endpoint_sidebar.configure(_doc.rocketchat_config())
	if _users_panel != null:
		_users_panel.configure(_session)
	if _models_sidebar != null:
		_models_sidebar.set_configured(not _doc.rocketchat_meteor_dir().is_empty())
	# Reinstall the Server Models bridge only when the meteor dir actually changed
	# (a new URL reaches the same installed endpoint, so it needs no reinstall).
	if _doc.rocketchat_meteor_dir() != old_meteor and not _doc.rocketchat_meteor_dir().is_empty():
		_install_models_bridge()


# View building ---------------------------------------------------------------
## The Collections view: the real collection sidebar when a DB is attached, else an
## attach placeholder inviting the user to attach one.
func _build_collections_view() -> void:
	if not _doc.has_mongo():
		_add_view(VIEW_COLLECTIONS, _make_attach_placeholder(
			"mongo", "No database in this project.", "Attach Database…"
		))
		return
	var connection := _doc.mongo_connection()
	var database := _doc.mongo_database()
	_collection_sidebar = COLLECTION_SIDEBAR_SCENE.instantiate()
	_add_view(VIEW_COLLECTIONS, _collection_sidebar)
	_collection_sidebar.collection_activated.connect(_on_collection_activated)
	_collection_sidebar.insert_document_requested.connect(_on_insert_document_requested)
	_collection_sidebar.list_indexes_requested.connect(_on_list_indexes_requested)
	_collection_sidebar.schema_changed.connect(_on_schema_changed)
	_collection_sidebar.status_changed.connect(_on_status_changed)
	_collection_sidebar.edit_requested.connect(func() -> void: edit_source_requested.emit("mongo"))
	_center.bind_mongo(connection, database)
	_collection_sidebar.configure(connection, database)


## The Endpoints view: the real endpoint sidebar when an API is attached, else an
## attach placeholder.
func _build_endpoints_view() -> void:
	if not _doc.has_rocketchat():
		_add_view(VIEW_ENDPOINTS, _make_attach_placeholder(
			"api", "No workspace in this project.", "Attach Workspace…"
		))
		return
	_ensure_session()
	_endpoint_sidebar = ENDPOINT_SIDEBAR_SCENE.instantiate()
	_add_view(VIEW_ENDPOINTS, _endpoint_sidebar)
	_endpoint_sidebar.endpoint_activated.connect(_on_endpoint_activated)
	_endpoint_sidebar.status_changed.connect(_on_status_changed)
	_endpoint_sidebar.edit_requested.connect(func() -> void: edit_source_requested.emit("api"))
	# Seed the offline cache and listen for load results before configuring, so the
	# synchronous "cache" emit (when a cache exists) is caught and drives restore.
	_endpoint_sidebar.endpoints_loaded.connect(_on_endpoints_loaded)
	_endpoint_sidebar.set_cache(_state.cached_endpoints(_rocketchat_url()))
	_endpoint_sidebar.configure(_doc.rocketchat_config())


func _build_users_view() -> void:
	_ensure_session()
	_users_panel = USERS_PANEL_SCENE.instantiate()
	_add_view(VIEW_USERS, _users_panel)
	_users_panel.status_changed.connect(_on_status_changed)
	_users_panel.configure(_session)


## The Models view: a launcher for the server-models console. Present whenever an
## API is attached (the console targets that Rocket.Chat server).
func _build_models_view() -> void:
	_models_sidebar = RCMODELS_SIDEBAR_SCENE.instantiate()
	_add_view(VIEW_MODELS, _models_sidebar)
	_models_sidebar.function_activated.connect(_on_model_function_activated)
	_models_sidebar.refresh_requested.connect(_on_models_refresh)
	_models_sidebar.functions_requested.connect(_on_model_functions_requested)
	_models_sidebar.edit_requested.connect(func() -> void: edit_source_requested.emit("api"))
	_models_sidebar.set_configured(not _doc.rocketchat_meteor_dir().is_empty())
	# Inject the bridge on startup so the endpoint is ready before the first query.
	_install_models_bridge()


## Create the shared Rocket.Chat session once, binding it to the center.
func _ensure_session() -> void:
	if _session == null:
		_set_session(_doc.rocketchat_config())


## Build a fresh session for `config`, bind it to the center, and observe it so
## user changes made in the Users panel are persisted to the project file.
func _set_session(config: Dictionary) -> void:
	_session = WorkspaceSession.new(config)
	_session.changed.connect(_on_session_changed)
	_center.bind_session(_session)
	# The Server Models console targets the Debris bridge, not the RC REST session,
	# so give the center the server URL + local meteor dir it needs directly.
	_center.bind_rocketchat_target(String(config.get("url", "")), String(config.get("meteor_dir", "")))


## The session changed (a user was added/removed/edited, or logged in/out). Persist
## the user list to the project; login-acquired tokens are stripped by the doc, so
## login/logout make no persistable change and don't dirty the project.
func _on_session_changed() -> void:
	if _doc.sync_rocketchat_users(_session.users()):
		dirty_changed.emit()


## A placeholder panel shown in the sidebar for an unattached source: a message and
## a button that asks the host to attach that source.
func _make_attach_placeholder(source: String, message: String, button_text: String) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", AppTheme._flat(AppTheme.BG_DARKEST, 0))

	var center := CenterContainer.new()
	panel.add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	box.add_child(label)

	var btn := Button.new()
	btn.text = button_text
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(func() -> void: attach_requested.emit(source))
	box.add_child(btn)
	return panel


## Rebuild the activity bar: Collections and Endpoints are always shown; Users
## appears once an API is attached. `select_view` optionally picks the active view.
func _refresh_activity(select_view: String = "") -> void:
	var views: Array = [
		{"id": VIEW_COLLECTIONS, "icon": ICON_COLLECTIONS, "tooltip": "Collections"},
		{"id": VIEW_ENDPOINTS, "icon": ICON_ENDPOINTS, "tooltip": "Endpoints"},
	]
	if _doc.has_rocketchat():
		views.append({"id": VIEW_USERS, "icon": ICON_USERS, "tooltip": "Users"})
		views.append({"id": VIEW_MODELS, "icon": ICON_MODELS, "tooltip": "Server Models"})
	_activity.set_views(views, select_view)


## Add a view (sidebar or attach placeholder) to the swappable stack, hidden until
## selected. The MarginContainer stretches whichever child is visible to fill the
## pane, so the views need no anchor/size setup of their own.
func _add_view(view: String, node: Control) -> void:
	_stack.add_child(node)
	node.visible = false
	_views[view] = node


## Remove and free a view from the stack (e.g. an attach placeholder being replaced
## by the real sidebar).
func _remove_view(view: String) -> void:
	if not _views.has(view):
		return
	var node: Control = _views[view]
	_stack.remove_child(node)
	node.queue_free()
	_views.erase(view)


# Sidebar view switching ------------------------------------------------------
func _on_view_selected(view: String) -> void:
	for id in _views:
		(_views[id] as Control).visible = (id == view)


# Sidebar signal handlers -----------------------------------------------------
func _on_collection_activated(connection: Dictionary, database: String, collection: String) -> void:
	_center.open_collection(connection, database, collection)
	status_changed.emit("Opened %s.%s" % [database, collection])


func _on_insert_document_requested(connection: Dictionary, database: String, collection: String) -> void:
	var tab := _center.open_collection(connection, database, collection)
	tab.results().request_insert()
	status_changed.emit("Insert document into %s.%s" % [database, collection])


func _on_list_indexes_requested(connection: Dictionary, database: String, collection: String) -> void:
	_center.open_collection(connection, database, collection, "listIndexes")
	status_changed.emit("List indexes of %s.%s" % [database, collection])


func _on_schema_changed(schema: DatabaseSchema) -> void:
	_center.set_schema(schema)


func _on_endpoint_activated(endpoint: ApiEndpoint) -> void:
	_center.open_endpoint(endpoint)
	status_changed.emit("Opened %s" % endpoint.label())


func _on_model_function_activated(model: String, method: String) -> void:
	# Double-clicking a function opens (or focuses) a query for model.method. The tab
	# reads the workspace's server URL + meteor dir live; the user presses Run.
	_center.open_rcmodels(model, method)
	status_changed.emit("Opened %s.%s" % [model, method])


## Manual "Refresh" on the Server Models sidebar: reinstall the bridge endpoint.
func _on_models_refresh() -> void:
	_install_models_bridge()


## A model was expanded in the sidebar: fetch its methods (from model-typings) and
## hand them back to fill in as child leaves.
func _on_model_functions_requested(model: String) -> void:
	if not has_rocketchat() or _doc.rocketchat_meteor_dir().is_empty():
		return
	var target := {"meteorDir": _doc.rocketchat_meteor_dir(), "url": _rocketchat_url()}
	var result: Dictionary = await Backend.rocketchat_model_methods(target, model)
	if _models_sidebar == null:
		return
	var methods: Array = []
	if result.get("ok", false):
		var data: Dictionary = result.get("data", {}) if result.get("data") is Dictionary else {}
		methods = data.get("methods", [])
	else:
		status_changed.emit("Couldn't load %s functions: %s" % [model, result.get("error", "error")])
	_models_sidebar.set_model_functions(model, methods)


## Inject (or refresh) the Server Models bridge into the workspace's Rocket.Chat
## server. A no-op without a meteor dir. Its own Activity Log entry is recorded by
## Backend. Fire-and-forget: the status line reflects the outcome.
func _install_models_bridge() -> void:
	if not has_rocketchat() or _doc.rocketchat_meteor_dir().is_empty():
		return
	var target := {"meteorDir": _doc.rocketchat_meteor_dir(), "url": _rocketchat_url()}
	status_changed.emit("Installing Server Models bridge…")
	var result: Dictionary = await Backend.rocketchat_install(target)
	if result.get("ok", false):
		# The install response carries the server's model list for the sidebar tree.
		var data: Dictionary = result.get("data", {}) if result.get("data") is Dictionary else {}
		if _models_sidebar != null:
			_models_sidebar.set_models(data.get("models", []))
		status_changed.emit("Server Models bridge ready")
	else:
		status_changed.emit("Server Models install failed: %s" % result.get("error", "unknown error"))


func _on_status_changed(text: String) -> void:
	status_changed.emit(text)


# Sidecar (.debris-workspace) persistence -------------------------------------
## Load the project's session sidecar (open tabs + endpoint cache), if one exists
## next to the project file. A missing sidecar is normal (Untitled, or a project
## saved before this feature); a present-but-unreadable one is reported but
## non-fatal. Always leaves _state non-null.
func _load_sidecar() -> void:
	_state = WorkspaceState.new()
	if _doc == null or _doc.file_path.is_empty():
		return
	var result := WorkspaceStateFile.load(WorkspaceStateFile.path_for(_doc.file_path))
	if result.get("ok", false):
		_state = result["state"]
	elif String(result.get("error", "")) != "absent":
		status_changed.emit("Couldn't read workspace state: %s" % result.get("error", ""))


## The endpoint list is available (from cache, live, or the built-in catalog):
## restore the saved tabs the first time, and refresh the offline cache whenever a
## live fetch lands (never caching the built-in fallback).
func _on_endpoints_loaded(endpoints: Array, source: String) -> void:
	_restore_tabs_once()
	if source == "live":
		_state.set_endpoint_cache(
			_rocketchat_url(), endpoints, Time.get_datetime_string_from_system(true)
		)
		persist_state()


## Reopen the saved tabs exactly once per project open. Endpoint tabs are matched
## to their definitions by id from the current endpoint list.
func _restore_tabs_once() -> void:
	if _restored:
		return
	_restored = true
	var by_id: Dictionary = {}
	if _endpoint_sidebar != null:
		for e in _endpoint_sidebar.endpoints():
			by_id[(e as ApiEndpoint).id] = e
	_center.restore_tabs(_state.tabs, _state.active_tab, by_id)


## Write the sidecar: the current open tabs (captured fresh from the center) plus
## the maintained endpoint cache. No-op for an unsaved project (no path to write
## next to) or before the saved tabs have been restored (so we never clobber them).
## Called on every tab/param change and after the project is saved.
func persist_state() -> void:
	if _doc == null or _doc.file_path.is_empty() or not _restored:
		return
	_state.tabs = _center.capture_tabs()
	_state.active_tab = _center.active_tab_index()
	var result := WorkspaceStateFile.save(_state, WorkspaceStateFile.path_for(_doc.file_path))
	if not result.get("ok", false):
		status_changed.emit("Couldn't save workspace state: %s" % result.get("error", ""))


## The project's Rocket.Chat URL, or "" when no API is attached.
func _rocketchat_url() -> String:
	return String(_doc.rocketchat.get("url", "")) if _doc != null else ""
