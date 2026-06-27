class_name WorkspaceTab
extends Control

## One Rocket.Chat workspace tab, scoped to a single configured workspace. For
## now it's a placeholder landing page showing the workspace's identity; the
## tailored API-client tools (REST explorer, admin helpers, …) will be added
## here later. Layout lives in workspace_tab.tscn.

signal status_changed(text: String)

@onready var _title: Label = %Title
@onready var _url: Label = %Url
@onready var _hint: Label = %Hint

var _workspace: Dictionary = {}


func _ready() -> void:
	_title.add_theme_color_override("font_color", AppTheme.TEXT_BRIGHT)
	_url.add_theme_color_override("font_color", AppTheme.TEXT)
	_hint.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	if not _workspace.is_empty():
		_refresh()


## Bind this tab to a workspace config. Safe to call before the node is in the
## tree; the labels are filled in once the node is ready.
func configure(workspace: Dictionary) -> void:
	_workspace = workspace
	if is_node_ready():
		_refresh()


func workspace() -> Dictionary:
	return _workspace


func tab_title() -> String:
	var ws_name := String(_workspace.get("name", ""))
	return ws_name if not ws_name.is_empty() else "(workspace)"


func _refresh() -> void:
	_title.text = String(_workspace.get("name", "(workspace)"))
	_url.text = String(_workspace.get("url", ""))
