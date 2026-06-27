class_name DatabaseWorkspace
extends Control

## Central area: a TabContainer holding one QueryTab per opened collection.
## Each double-click opens a fresh tab (duplicates are allowed) and every tab
## carries a close button. A welcome overlay shows when no tabs are open.

signal status_changed(text: String)

const QUERY_TAB_SCENE := preload("res://source/ui/database/query_tab.tscn")

@onready var _tabs: TabContainer = %Tabs
@onready var _welcome: Control = %Welcome
@onready var _welcome_title: Label = %WelcomeTitle
@onready var _welcome_hint: Label = %WelcomeHint
@onready var _new_tab_btn: Button = %NewTabBtn

var _tab_counter := 0
# Connection + database this workspace is bound to, so the "+" button (which
# lives in the tab strip, outside any single query tab) can open new tabs.
var _bound_connection: Dictionary = {}
var _bound_database := ""


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
	tab.title_changed.connect(_on_tab_title_changed.bind(tab))
	tab.name = "tab_%d" % _tab_counter
	_tab_counter += 1

	# Remember the database so the strip's "+" button can open further tabs.
	_bound_connection = connection
	_bound_database = database

	# Opening a real collection replaces the active blank scratch tab (if any);
	# opening a blank tab (e.g. the "+" button) always adds a fresh one.
	var replaced := _current_empty_tab() if not collection.is_empty() else null

	_tabs.add_child(tab)
	if replaced != null:
		var slot := _tabs.get_tab_idx_from_control(replaced)
		_tabs.remove_child(replaced)
		replaced.queue_free()
		_tabs.move_child(tab, slot)

	var index := _tabs.get_tab_idx_from_control(tab)
	_tabs.set_tab_title(index, tab.tab_title())
	_tabs.current_tab = index
	_update_welcome()
	return tab


## The currently selected tab if it's a blank scratch tab, else null.
func _current_empty_tab() -> QueryTab:
	if _tabs.get_tab_count() == 0:
		return null
	var current := _tabs.get_current_tab_control() as QueryTab
	if current != null and current.is_empty():
		return current
	return null


func _on_tab_title_changed(title: String, tab: QueryTab) -> void:
	var index := _tabs.get_tab_idx_from_control(tab)
	if index != -1:
		_tabs.set_tab_title(index, title)


## Wired in database_workspace.tscn from the "+" button in the tab strip. Opens a fresh
## empty tab on the database this workspace is bound to.
func _on_new_tab_pressed() -> void:
	if _bound_database.is_empty():
		return
	open_collection(_bound_connection, _bound_database, "")


func _on_tab_close_pressed(tab_index: int) -> void:
	var control := _tabs.get_tab_control(tab_index)
	if control == null:
		return
	_tabs.remove_child(control)
	control.queue_free()
	_update_welcome()


func _update_welcome() -> void:
	_welcome.visible = _tabs.get_tab_count() == 0
