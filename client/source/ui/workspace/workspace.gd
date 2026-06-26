class_name Workspace
extends Control

## Central area: a TabContainer holding one QueryTab per opened collection.
## Each double-click opens a fresh tab (duplicates are allowed) and every tab
## carries a close button. A welcome overlay shows when no tabs are open.

signal status_changed(text: String)

const QUERY_TAB_SCENE := preload("res://source/ui/workspace/query_tab.tscn")

@onready var _tabs: TabContainer = %Tabs
@onready var _welcome: Control = %Welcome
@onready var _welcome_title: Label = %WelcomeTitle
@onready var _welcome_hint: Label = %WelcomeHint

var _tab_counter := 0


func _ready() -> void:
	# Welcome lives outside the tab strip so it never gets a close button; it is
	# shown only while no collection tabs are open.
	var bar := _tabs.get_tab_bar()
	bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ALWAYS
	bar.tab_close_pressed.connect(_on_tab_close_pressed)

	_welcome_title.add_theme_color_override("font_color", AppTheme.TEXT_BRIGHT)
	_welcome_hint.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_update_welcome()


func open_collection(connection: Dictionary, database: String, collection: String) -> QueryTab:
	var tab: QueryTab = QUERY_TAB_SCENE.instantiate()
	tab.configure(connection, database, collection)
	# Connect before add_child so the tab's initial _run() status is captured.
	tab.status_changed.connect(func(text: String) -> void: status_changed.emit(text))
	tab.name = "tab_%d" % _tab_counter
	_tab_counter += 1
	_tabs.add_child(tab)
	var index := _tabs.get_tab_count() - 1
	_tabs.set_tab_title(index, tab.tab_title())
	_tabs.current_tab = index
	_update_welcome()
	return tab


func _on_tab_close_pressed(tab_index: int) -> void:
	var control := _tabs.get_tab_control(tab_index)
	if control == null:
		return
	_tabs.remove_child(control)
	control.queue_free()
	_update_welcome()


func _update_welcome() -> void:
	_welcome.visible = _tabs.get_tab_count() == 0
