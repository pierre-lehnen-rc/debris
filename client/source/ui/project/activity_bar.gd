class_name ActivityBar
extends PanelContainer

## A compact horizontal row of view-toggle icons across the top of a project tab's
## sidebar (VSCode-style views, placed along the top to spare horizontal space). It
## holds one toggle button per view; selecting one emits `view_selected` so the
## project tab can swap the sidebar below it. The tab always shows Collections and
## Endpoints (their panels host an attach button until the source is attached) and
## adds Users once an API is attached. Built entirely in code (no scene).

signal view_selected(view: String)

const BUTTON_SIZE := 34
const ICON_MAX := 20
const META_VIEW := "view"

var _group := ButtonGroup.new()
var _box: HBoxContainer
## The id of the currently selected view, so a rebuild (after attaching a source)
## can keep the user on the same view instead of snapping back to the first.
var _current_view := ""


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
## tooltip: String } entries. Selection order of preference: `select_id` when
## given and present, else the previously-selected view when it still exists, else
## the first view. Selecting a button emits view_selected.
func set_views(views: Array, select_id: String = "") -> void:
	if _box == null:
		return
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	for v in views:
		_box.add_child(_make_button(v))
	if views.is_empty():
		return

	var target := select_id
	if not _has_view(views, target):
		target = _current_view if _has_view(views, _current_view) else String(views[0]["id"])
	for btn in _box.get_children():
		if String((btn as Button).get_meta(META_VIEW)) == target:
			# Setting button_pressed programmatically emits `toggled`, which fires
			# view_selected for the target view.
			(btn as Button).button_pressed = true
			break


## Programmatically select the view at `index` (0-based, in display order) as if its
## button were clicked — driving the same view_selected path. Out-of-range indices
## (e.g. the Users view on a DB-only project) are ignored. Used by view shortcuts.
func select_index(index: int) -> void:
	if _box == null:
		return
	var buttons := _box.get_children()
	if index < 0 or index >= buttons.size():
		return
	(buttons[index] as Button).button_pressed = true


func _has_view(views: Array, id: String) -> bool:
	if id.is_empty():
		return false
	for v in views:
		if String((v as Dictionary).get("id", "")) == id:
			return true
	return false


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
		_current_view = String(btn.get_meta(META_VIEW))
		view_selected.emit(_current_view)
