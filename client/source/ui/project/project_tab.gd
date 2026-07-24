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

const COLLECTION_SIDEBAR_SCENE := preload("res://source/ui/sidebar/collection_sidebar.tscn")
const ENDPOINT_SIDEBAR_SCENE := preload("res://source/ui/workspace/endpoint_sidebar.tscn")
const USERS_PANEL_SCENE := preload("res://source/ui/workspace/users_panel.tscn")
const CENTER_SCENE := preload("res://source/ui/project/workspace_center.tscn")

const ICON_COLLECTIONS := preload("res://source/ui/icons/database.svg")
const ICON_ENDPOINTS := preload("res://source/ui/icons/api.svg")
const ICON_USERS := preload("res://source/ui/icons/users.svg")

const VIEW_COLLECTIONS := "collections"
const VIEW_ENDPOINTS := "endpoints"
const VIEW_USERS := "users"

# Default sidebar width matches the old database tab (split_offset 360, 180 floor),
# which is the width the sidebar reference was taken from.
const SIDEBAR_MIN_WIDTH := 180
const SIDEBAR_SPLIT_OFFSET := 360

var _doc: WorkspaceDoc = null
var _session: WorkspaceSession = null

var _activity: ActivityBar
var _stack: MarginContainer
var _center: WorkspaceCenter
var _collection_sidebar: CollectionSidebar = null
var _endpoint_sidebar: EndpointSidebar = null
var _users_panel: UsersPanel = null
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
	split.add_child(_center)


# Setup -----------------------------------------------------------------------
func _setup() -> void:
	_build_collections_view()
	_build_endpoints_view()
	if _doc.has_rocketchat():
		_build_users_view()
	_refresh_activity()


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
	_doc.set_rocketchat(String(config.get("url", "")), config.get("users", []))
	_remove_view(VIEW_ENDPOINTS)
	_build_endpoints_view()
	_build_users_view()
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


## Apply an edited API config (from the workspace editor): rebuild the session and
## reload the endpoint/users panels against it. Endpoint tabs already open keep
## their original session until reopened.
func update_rocketchat(config: Dictionary) -> void:
	if not has_rocketchat():
		return
	_doc.set_rocketchat(String(config.get("url", "")), config.get("users", []))
	_session = WorkspaceSession.new(_doc.rocketchat_config())
	_center.bind_session(_session)
	if _endpoint_sidebar != null:
		_endpoint_sidebar.configure(_doc.rocketchat_config())
	if _users_panel != null:
		_users_panel.configure(_session)


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
			"api", "No API in this project.", "Attach API…"
		))
		return
	_ensure_session()
	_endpoint_sidebar = ENDPOINT_SIDEBAR_SCENE.instantiate()
	_add_view(VIEW_ENDPOINTS, _endpoint_sidebar)
	_endpoint_sidebar.endpoint_activated.connect(_on_endpoint_activated)
	_endpoint_sidebar.status_changed.connect(_on_status_changed)
	_endpoint_sidebar.edit_requested.connect(func() -> void: edit_source_requested.emit("api"))
	_endpoint_sidebar.configure(_doc.rocketchat_config())


func _build_users_view() -> void:
	_ensure_session()
	_users_panel = USERS_PANEL_SCENE.instantiate()
	_add_view(VIEW_USERS, _users_panel)
	_users_panel.status_changed.connect(_on_status_changed)
	_users_panel.configure(_session)


## Create the shared Rocket.Chat session once, binding it to the center.
func _ensure_session() -> void:
	if _session == null:
		_session = WorkspaceSession.new(_doc.rocketchat_config())
		_center.bind_session(_session)


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


func _on_status_changed(text: String) -> void:
	status_changed.emit(text)
