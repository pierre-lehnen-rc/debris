class_name Workspace
extends Control

## Central area: a TabContainer holding one QueryTab per opened collection.
## Each double-click opens a fresh tab (duplicates are allowed) and every tab
## carries a close button. A welcome overlay shows when no tabs are open.

var _tabs: TabContainer
var _welcome: Control
var _tab_counter := 0


func _ready() -> void:
	_tabs = TabContainer.new()
	_tabs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tabs.tabs_rearrange_group = 0
	var bar := _tabs.get_tab_bar()
	bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ALWAYS
	bar.tab_close_pressed.connect(_on_tab_close_pressed)
	add_child(_tabs)

	# Welcome lives outside the tab strip so it never gets a close button; it is
	# shown only while no collection tabs are open.
	_welcome = _build_welcome()
	_welcome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_welcome)
	_update_welcome()


func open_collection(conn: String, database: String, collection: String) -> QueryTab:
	var tab := QueryTab.new()
	tab.configure(conn, database, collection)
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


func _build_welcome() -> Control:
	var center := CenterContainer.new()
	center.name = "Welcome"

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)

	var title := Label.new()
	title.text = "Quetzalcoatl"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", AppTheme.TEXT_BRIGHT)
	box.add_child(title)

	var hint := Label.new()
	hint.text = "Double-click a collection in the sidebar to open a query tab."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	box.add_child(hint)

	return center
