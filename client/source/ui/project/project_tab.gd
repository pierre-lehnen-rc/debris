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
	var views: Array = []

	if _doc.has_mongo():
		var connection := _doc.mongo_connection()
		var database := _doc.mongo_database()
		_collection_sidebar = COLLECTION_SIDEBAR_SCENE.instantiate()
		_add_sidebar(VIEW_COLLECTIONS, _collection_sidebar)
		_collection_sidebar.collection_activated.connect(_on_collection_activated)
		_collection_sidebar.insert_document_requested.connect(_on_insert_document_requested)
		_collection_sidebar.list_indexes_requested.connect(_on_list_indexes_requested)
		_collection_sidebar.schema_changed.connect(_on_schema_changed)
		_collection_sidebar.status_changed.connect(_on_status_changed)
		_center.bind_mongo(connection, database)
		_collection_sidebar.configure(connection, database)
		views.append({"id": VIEW_COLLECTIONS, "icon": ICON_COLLECTIONS, "tooltip": "Collections"})

	if _doc.has_rocketchat():
		var config := _doc.rocketchat_config()
		_session = WorkspaceSession.new(config)
		_center.bind_session(_session)

		_endpoint_sidebar = ENDPOINT_SIDEBAR_SCENE.instantiate()
		_add_sidebar(VIEW_ENDPOINTS, _endpoint_sidebar)
		_endpoint_sidebar.endpoint_activated.connect(_on_endpoint_activated)
		_endpoint_sidebar.status_changed.connect(_on_status_changed)
		_endpoint_sidebar.configure(config)
		views.append({"id": VIEW_ENDPOINTS, "icon": ICON_ENDPOINTS, "tooltip": "Endpoints"})

		_users_panel = USERS_PANEL_SCENE.instantiate()
		_add_sidebar(VIEW_USERS, _users_panel)
		_users_panel.status_changed.connect(_on_status_changed)
		_users_panel.configure(_session)
		views.append({"id": VIEW_USERS, "icon": ICON_USERS, "tooltip": "Users"})

	_activity.set_views(views)


## Add a sidebar to the swappable stack, hidden until its view is selected. The
## MarginContainer stretches whichever child is visible to fill the pane, so the
## sidebars need no anchor/size setup of their own.
func _add_sidebar(view: String, node: Control) -> void:
	_stack.add_child(node)
	node.visible = false
	_views[view] = node


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
