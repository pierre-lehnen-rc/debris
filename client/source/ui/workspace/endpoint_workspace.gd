class_name EndpointWorkspace
extends Control

## Central area of a workspace tab: a TabContainer holding one EndpointTab per
## opened endpoint. Activating an endpoint that's already open just focuses its
## tab (no duplicates); each tab carries a close button. A welcome overlay shows
## while nothing is open. Mirrors the Mongo DatabaseWorkspace.

signal status_changed(text: String)

const ENDPOINT_TAB_SCENE := preload("res://source/ui/workspace/endpoint_tab.tscn")

@onready var _tabs: TabContainer = %Tabs
@onready var _welcome: Control = %Welcome
@onready var _welcome_title: Label = %WelcomeTitle
@onready var _welcome_hint: Label = %WelcomeHint

var _tab_counter := 0
var _workspace: Dictionary = {}


func _ready() -> void:
	var bar := _tabs.get_tab_bar()
	bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ALWAYS
	bar.tab_close_pressed.connect(_on_tab_close_pressed)

	_welcome_title.add_theme_color_override("font_color", AppTheme.TEXT_BRIGHT)
	_welcome_hint.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_update_welcome()


## The workspace these endpoint tabs run against.
func configure(workspace: Dictionary) -> void:
	_workspace = workspace


func open_endpoint(endpoint: ApiEndpoint) -> EndpointTab:
	# Focus an existing tab for this endpoint instead of stacking a duplicate.
	var existing := _find_tab(endpoint)
	if existing != null:
		_tabs.current_tab = _tabs.get_tab_idx_from_control(existing)
		return existing

	var tab: EndpointTab = ENDPOINT_TAB_SCENE.instantiate()
	tab.configure(_workspace, endpoint)
	tab.status_changed.connect(func(text: String) -> void: status_changed.emit(text))
	tab.name = "ep_%d" % _tab_counter
	_tab_counter += 1

	_tabs.add_child(tab)
	var index := _tabs.get_tab_idx_from_control(tab)
	_tabs.set_tab_title(index, tab.tab_title())
	_tabs.set_tab_tooltip(index, endpoint.summary)
	_tabs.current_tab = index
	_update_welcome()
	return tab


## The open tab for `endpoint` (matched by id), or null.
func _find_tab(endpoint: ApiEndpoint) -> EndpointTab:
	for child in _tabs.get_children():
		var tab := child as EndpointTab
		if tab != null and tab.endpoint() != null and tab.endpoint().id == endpoint.id:
			return tab
	return null


func _on_tab_close_pressed(tab_index: int) -> void:
	var control := _tabs.get_tab_control(tab_index)
	if control == null:
		return
	_tabs.remove_child(control)
	control.queue_free()
	_update_welcome()


func _update_welcome() -> void:
	_welcome.visible = _tabs.get_tab_count() == 0
