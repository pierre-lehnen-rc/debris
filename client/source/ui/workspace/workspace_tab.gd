class_name WorkspaceTab
extends Control

## One Rocket.Chat workspace tab, scoped to a single configured workspace. Lays
## out the endpoint sidebar next to the endpoint explorer, mirroring the Mongo
## DatabaseTab. The sidebar lists known REST endpoints; activating one opens it in
## a tab in the explorer, where a param form drives a (currently mock) request and
## the results show in the shared tree/table/text view. Layout in workspace_tab.tscn.

signal status_changed(text: String)

@onready var _sidebar: EndpointSidebar = %EndpointSidebar
@onready var _explorer: EndpointWorkspace = %EndpointWorkspace
@onready var _users_panel: UsersPanel = %UsersPanel

var _workspace: Dictionary = {}
## Shared, in-RAM state (users + acquired tokens) for this workspace tab; the
## users panel and every endpoint tab reference the same instance.
var _session: WorkspaceSession = null


func _ready() -> void:
	if not _workspace.is_empty():
		_setup()


## Bind this tab to a workspace config. Safe to call before the node is in the
## tree; the children are configured once the tab is ready.
func configure(workspace: Dictionary) -> void:
	_workspace = workspace
	if is_node_ready():
		_setup()


func _setup() -> void:
	_session = WorkspaceSession.new(_workspace)
	_sidebar.configure(_workspace)
	_explorer.configure(_session)
	_users_panel.configure(_session)


func workspace() -> Dictionary:
	return _workspace


func tab_title() -> String:
	var ws_name := String(_workspace.get("name", ""))
	return ws_name if not ws_name.is_empty() else "(workspace)"


# Wired in workspace_tab.tscn -------------------------------------------------
func _on_endpoint_activated(endpoint: ApiEndpoint) -> void:
	_explorer.open_endpoint(endpoint)
	status_changed.emit("Opened %s" % endpoint.label())


func _on_status_changed(text: String) -> void:
	status_changed.emit(text)
