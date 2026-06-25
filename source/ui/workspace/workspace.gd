class_name Workspace
extends Control

## Central area: a TabContainer holding one QueryTab per opened collection.
## Opening the same collection twice just refocuses the existing tab.

var _tabs: TabContainer
var _open_targets: Array[String] = []


func _ready() -> void:
	_tabs = TabContainer.new()
	_tabs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tabs.tabs_rearrange_group = 0
	_tabs.add_child(_build_welcome())
	add_child(_tabs)


func open_collection(conn: String, database: String, collection: String) -> void:
	var target := "%s/%s/%s" % [conn, database, collection]
	var existing := _open_targets.find(target)
	if existing != -1:
		# +1 because the welcome tab occupies index 0.
		_tabs.current_tab = existing + 1
		return

	var tab := QueryTab.new()
	tab.configure(conn, database, collection)
	tab.name = "tab_%d" % _open_targets.size()
	_tabs.add_child(tab)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, tab.tab_title())
	_tabs.current_tab = _tabs.get_tab_count() - 1
	_open_targets.append(target)


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
