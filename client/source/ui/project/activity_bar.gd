class_name ActivityBar
extends PanelContainer

## A compact horizontal row of view-toggle icons across the top of a project tab's
## sidebar (VSCode-style views, placed along the top to spare horizontal space). It
## holds one toggle button per available sidebar view; selecting one emits
## `view_selected` so the project tab can swap the sidebar below it. The available
## views are supplied by the tab from what the project has attached — a DB adds
## Collections, an API adds Endpoints and Users. Built entirely in code (no scene).

signal view_selected(view: String)

const BUTTON_SIZE := 34
const ICON_MAX := 20
const META_VIEW := "view"

var _group := ButtonGroup.new()
var _box: HBoxContainer


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_FILL
	var sb := AppTheme._flat(AppTheme.BG_DARKEST, 0)
	sb.border_width_bottom = 1
	sb.border_color = AppTheme.BORDER
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	add_theme_stylebox_override("panel", sb)
	_box = HBoxContainer.new()
	_box.add_theme_constant_override("separation", 2)
	add_child(_box)


## Rebuild the bar from an ordered list of { id: String, icon: Texture2D,
## tooltip: String } entries and select the first, which emits view_selected.
func set_views(views: Array) -> void:
	if _box == null:
		return
	for child in _box.get_children():
		child.queue_free()
	for v in views:
		_box.add_child(_make_button(v))
	if not views.is_empty():
		# Setting button_pressed programmatically emits `toggled`, which fires
		# view_selected for the initial view.
		var first := _box.get_child(0) as Button
		first.button_pressed = true


func _make_button(v: Dictionary) -> Button:
	var btn := Button.new()
	btn.toggle_mode = true
	btn.button_group = _group
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
	btn.icon = v.get("icon")
	btn.expand_icon = true
	btn.add_theme_constant_override("icon_max_width", ICON_MAX)
	btn.tooltip_text = String(v.get("tooltip", ""))
	btn.set_meta(META_VIEW, String(v.get("id", "")))
	btn.toggled.connect(_on_toggled.bind(btn))
	return btn


## A toggle changed. In a ButtonGroup exactly one button is pressed, so ignore the
## un-press of the previously selected one and act only on the new selection.
func _on_toggled(pressed: bool, btn: Button) -> void:
	if pressed:
		view_selected.emit(String(btn.get_meta(META_VIEW)))
